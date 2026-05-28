import Darwin
import Foundation
import os

/// 日志专用 logger。subsystem 用 bundle id 风格,category 单独成段方便在 Console.app 过滤。
/// 过滤示例:`subsystem:com.cc-bar process:CCBar category:delegated-refresh`
private let log = Logger(subsystem: "com.cc-bar", category: "delegated-refresh")

/// 当 cc-bar 自家的 OAuth refresh 拿到 `invalid_grant`(refresh_token 被服务端拒)时,
/// 直接唤起本机 `claude` CLI 跑一次 `/status`,让 CLI 用自己受信任的会话身份重新刷新
/// 并把新凭据写回 keychain / credentials.json,本进程随后重读即可恢复。
///
/// 这是参考 CodexBar 的 `ClaudeOAuthDelegatedRefreshCoordinator` 思路的精简实现:
/// 只保留"找 CLI、跑 /status、看 keychain 指纹变化"这条主路径,不做 ANSI 解析、
/// 不处理 Codex 风格的 update prompt、不维护进程注册表。
enum ClaudeDelegatedRefresh {
    enum Outcome: Sendable {
        /// 委托刷新成功,新凭据已被外部写回,调用方应重读存储。
        case refreshed
        /// 还在冷却窗口内,本次跳过。
        case skippedByCooldown
        /// 本机找不到 `claude` 二进制,无法委托。
        case cliUnavailable
        /// 跑了 CLI,但超时 / keychain 没有观察到变化。
        case noChangeObserved
        /// 启动 CLI 失败(launchFailed / openpty 失败等)。
        case attemptFailed(String)
    }

    /// 5 分钟冷却,对齐 CodexBar 实测值。避免反复唤起 CLI。
    static let cooldownInterval: TimeInterval = 5 * 60
    /// 单次 PTY 会话整体超时。我们不早退,让 claude 跑满这个窗口,确保它有充足时间
    /// 完成启动期的 auth refresh。对齐 CodexBar 的 8s。
    static let sessionTimeout: TimeInterval = 8
    /// CLI 启动后给它的初始 settle 时间。
    static let initialDelay: TimeInterval = 0.6
    /// CLI 跑完后等待 keychain 写入的兜底时间。
    static let postRunObserveWindow: TimeInterval = 2.0

    /// 协调入口。同一时刻只允许一个 in-flight 任务,所有并发调用 join 同一 future;
    /// 冷却窗口内的调用直接返回 `.skippedByCooldown`,不会真的去戳 CLI。
    nonisolated static func attempt(source: CredentialSource) async -> Outcome {
        await Coordinator.shared.attempt(source: source)
    }

    /// 后台启动委托刷新,**不等待结果**。专门给"不应阻塞 UI 的刷新调用方"用——
    /// 比如用户点了刷新按钮、cc-bar 自家 OAuth 刚抛 tokenRevoked 这种场景。
    ///
    /// 行为:
    /// - 启动后立刻返回,调用方继续走自己的失败路径(把 tokenRevoked 抛给 UI)
    /// - 后台 Coordinator 完成 PTY + 指纹观察后,如果成功 (.refreshed),会通过
    ///   `NotificationCenter` 发出 `.claudeDelegatedRefreshDidSucceed`,
    ///   AppState 收到后会自动再触发一次完整刷新,UI 自然更新到新数据。
    /// - 失败的 outcome 不发通知(下次用户再刷新或下次定时刷新还会重试)。
    nonisolated static func attemptInBackground(source: CredentialSource) {
        Task.detached(priority: .utility) {
            let outcome = await Coordinator.shared.attempt(source: source)
            if case .refreshed = outcome {
                NotificationCenter.default.post(
                    name: .claudeDelegatedRefreshDidSucceed,
                    object: nil)
            }
        }
    }

    // MARK: - Coordinator

    private actor Coordinator {
        static let shared = Coordinator()

        private var inFlight: Task<Outcome, Never>?
        private var lastAttemptAt: Date?

        func attempt(source: CredentialSource) async -> Outcome {
            log.info("attempt entered, source=\(source.rawValue, privacy: .public)")
            if let task = inFlight {
                log.info("joining in-flight task")
                return await task.value
            }
            if let last = lastAttemptAt,
               Date().timeIntervalSince(last) < ClaudeDelegatedRefresh.cooldownInterval {
                log.info("skipped by cooldown, elapsed=\(Date().timeIntervalSince(last))s")
                return .skippedByCooldown
            }
            let task = Task { () -> Outcome in
                await Self.performAttempt(source: source)
            }
            inFlight = task
            lastAttemptAt = Date()
            let outcome = await task.value
            inFlight = nil
            return outcome
        }

        private static func performAttempt(source: CredentialSource) async -> Outcome {
            guard let binary = ClaudeCLIResolver.resolve() else {
                log.warning("cli unavailable: no binary resolved")
                return .cliUnavailable
            }
            log.info("cli resolved: \(binary, privacy: .public)")
            let baselineFingerprint = ClaudeDelegatedRefresh.currentFingerprint(source: source)
            log.info("baseline fingerprint captured: \(baselineFingerprint ?? 0)")

            do {
                try await ClaudePTYTouch.run(binary: binary, timeout: ClaudeDelegatedRefresh.sessionTimeout)
                log.info("pty session finished")
            } catch let error as ClaudePTYTouch.Error {
                log.error("pty error: \(error.description, privacy: .public)")
                return .attemptFailed(error.description)
            } catch {
                log.error("pty unknown error: \(String(describing: error), privacy: .public)")
                return .attemptFailed("\(error)")
            }

            // CLI 退出后 keychain 写入可能稍有延迟,给一小段窗口轮询。
            let deadline = Date().addingTimeInterval(ClaudeDelegatedRefresh.postRunObserveWindow)
            while Date() < deadline {
                let current = ClaudeDelegatedRefresh.currentFingerprint(source: source)
                if let current, current != baselineFingerprint {
                    log.info("fingerprint changed -> refreshed; new=\(current)")
                    return .refreshed
                }
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            }
            log.warning("no fingerprint change within observe window")
            return .noChangeObserved
        }
    }

    // MARK: - Fingerprint

    /// 拿存储里凭据 JSON 的稳定指纹,用来对比"CLI 跑前 / 跑后是否被外部更新"。
    /// 失败返回 nil(此时不视作变化,避免误判)。
    nonisolated static func currentFingerprint(source: CredentialSource) -> Int? {
        switch source {
        case .file:
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/.credentials.json")
            guard let data = try? Data(contentsOf: url) else { return nil }
            return data.hashValue
        case .keychain:
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            proc.arguments = [
                "find-generic-password",
                "-s", ClaudeTokenRefresher.keychainService,
                "-w",
            ]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            do {
                try proc.run()
            } catch {
                return nil
            }
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return data.isEmpty ? nil : data.hashValue
        }
    }
}

// MARK: - CLI Resolver

enum ClaudeCLIResolver {
    /// 按优先级查找 `claude` 二进制。返回绝对路径,找不到返回 nil。
    /// - `$CLAUDE_CLI_PATH` 显式覆盖(测试 / 高级用户用)
    /// - 常见 PATH 位置
    /// - Claude Desktop 内嵌的 `claude-code/<ver>/claude.app/Contents/MacOS/claude`
    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let override = environment["CLAUDE_CLI_PATH"],
           !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        let staticCandidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
            "\(NSHomeDirectory())/.bun/bin/claude",
            "\(NSHomeDirectory())/.volta/bin/claude",
        ]
        for path in staticCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        if let fromPath = which(tool: "claude", environment: environment) {
            return fromPath
        }
        if let bundled = resolveDesktopBundledCLI() {
            return bundled
        }
        return nil
    }

    private static func which(tool: String, environment: [String: String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [tool]
        var env = environment
        // GUI 进程的 PATH 通常只有系统目录,补一些常见 node 工具链路径,提高命中率。
        let extras = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin"]
        let existing = env["PATH"] ?? ""
        env["PATH"] = (extras + existing.split(separator: ":").map(String.init))
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        proc.environment = env
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    /// 查找 Claude Desktop 内嵌的 CLI:
    /// `~/Library/Application Support/Claude/claude-code/<version>/claude.app/Contents/MacOS/claude`
    /// 版本目录可能有多个,选 mtime 最新的一个。
    private static func resolveDesktopBundledCLI() -> String? {
        let root = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Claude/claude-code")
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let candidates = entries.compactMap { dir -> (URL, Date)? in
            let bin = dir
                .appendingPathComponent("claude.app/Contents/MacOS/claude")
            guard fm.isExecutableFile(atPath: bin.path) else { return nil }
            let mtime = (try? bin.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return (bin, mtime)
        }
        return candidates.max(by: { $0.1 < $1.1 })?.0.path
    }
}

// MARK: - Probe Working Directory

/// 给 claude CLI 一个**受控、空白的工作目录**。
///
/// 为什么需要:claude CLI 启动时会扫描 `cwd` 寻找 git 仓库 / 项目结构(读 `.git/`、
/// 父目录的 `package.json` 等)。如果它继承 cc-bar 的 cwd(通常是 `$HOME` 或 `/`),
/// 就会一路扫到用户的桌面 / 文稿 / 下载,触发一堆 TCC 弹窗。
///
/// 解决:准备一个完全空的目录 `~/Library/Application Support/CCBar/ClaudeProbe/`,
/// 在里面放一个 `.claude/settings.local.json` 关掉 deep-link 注册等额外副作用,
/// 把它作为 claude 的 cwd。这样它扫描出来啥都没有,不会摸到用户数据。
enum ClaudeProbeWorkspace {
    static func prepared() -> URL {
        let directory = self.directoryURL()
        do {
            try self.materialize(at: directory)
        } catch {
            log.warning("probe workspace materialize failed: \(error.localizedDescription, privacy: .public)")
        }
        return directory
    }

    private static func directoryURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        return base
            .appendingPathComponent("CCBar", isDirectory: true)
            .appendingPathComponent("ClaudeProbe", isDirectory: true)
    }

    private static func materialize(at directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let claudeDir = directory.appendingPathComponent(".claude", isDirectory: true)
        try fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let settingsURL = claudeDir.appendingPathComponent("settings.local.json")
        // 关掉 claude 主动注册 URL handler / 自动打开浏览器之类的副作用,
        // 我们只想让它跑一下、刷个 token,不希望它产生其他系统侧效果。
        let payload: [String: String] = [
            "disableDeepLinkRegistration": "disable",
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }
}

// MARK: - Watchdog Helper Resolver

/// 找到内嵌的 `CCBarClaudeWatchdog`。
/// 发布构建里它在 `CCBar.app/Contents/Helpers/CCBarClaudeWatchdog`;
/// Debug 跑(尤其 Xcode Run)的话 bundle 里可能没有,这种情况下返回 nil,
/// 让调用方降级到直接起 claude(开发期容忍一下 TCC 弹窗)。
enum ClaudeWatchdogResolver {
    static func resolve() -> String? {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/CCBarClaudeWatchdog")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            return nil
        }
        return helperURL.path
    }
}

// MARK: - PTY Touch

/// 最小化的 PTY 启动器:
/// 1. openpty 拿一对 fd
/// 2. 子进程的 stdin/stdout/stderr 全指向 PTY 从端
/// 3. 等 `initialDelay` 让 CLI 渲染好 TUI,发 `/status\r`
/// 4. 周期发回车防止卡 prompt,跑满 timeout
/// 5. 兜底发 `/exit\r`、SIGTERM、SIGKILL 清理
///
/// 我们不需要解析输出,目的只是"让 CLI 跑一次,顺便触发它内部的 token refresh"。
///
/// 关键:如果发现内嵌的 `CCBarClaudeWatchdog`,启动 claude 时走 watchdog 套娃,
/// 这样 macOS TCC 把潜在的文件访问归到 watchdog 而不是 cc-bar 本体。
enum ClaudePTYTouch {
    enum Error: Swift.Error, CustomStringConvertible {
        case openptyFailed(Int32)
        case launchFailed(String)
        case timedOut

        var description: String {
            switch self {
            case .openptyFailed(let err):
                return "openpty failed: errno=\(err)"
            case .launchFailed(let msg):
                return "launch failed: \(msg)"
            case .timedOut:
                return "pty session timed out"
            }
        }
    }

    static func run(binary: String, timeout: TimeInterval) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Self.runBlocking(binary: binary, timeout: timeout)
        }.value
    }

    private static func runBlocking(binary: String, timeout: TimeInterval) throws {
        var primaryFD: Int32 = -1
        var secondaryFD: Int32 = -1
        var win = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primaryFD, &secondaryFD, nil, nil, &win) == 0 else {
            throw Error.openptyFailed(errno)
        }
        // 设非阻塞,让 read 不会卡死。
        _ = fcntl(primaryFD, F_SETFL, O_NONBLOCK)

        let primaryHandle = FileHandle(fileDescriptor: primaryFD, closeOnDealloc: true)
        let secondaryHandle = FileHandle(fileDescriptor: secondaryFD, closeOnDealloc: true)

        let proc = Process()
        proc.standardInput = secondaryHandle
        proc.standardOutput = secondaryHandle
        proc.standardError = secondaryHandle

        // 如果发现 watchdog,就走 watchdog 套娃启动 claude。
        // TCC 弹窗会归到 watchdog,不再污染 cc-bar 主体的权限画像。
        if let watchdog = ClaudeWatchdogResolver.resolve() {
            proc.executableURL = URL(fileURLWithPath: watchdog)
            proc.arguments = ["--", binary]
            log.info("launching via watchdog: \(watchdog, privacy: .public)")
        } else {
            proc.executableURL = URL(fileURLWithPath: binary)
            log.warning("watchdog unavailable, falling back to direct launch (DEBUG?)")
        }

        // 给 claude 一个空白可写的 cwd,避免它扫到用户的真实项目目录。
        proc.currentDirectoryURL = ClaudeProbeWorkspace.prepared()

        var env = ProcessInfo.processInfo.environment
        if (env["TERM"] ?? "").isEmpty { env["TERM"] = "xterm-256color" }
        if (env["LANG"] ?? "").isEmpty { env["LANG"] = "en_US.UTF-8" }
        env["CI"] = "0"
        // 显式 PWD 跟随 cwd,有的 CLI 会优先读 PWD 而不是 getcwd。
        env["PWD"] = proc.currentDirectoryURL?.path ?? env["PWD"] ?? NSHomeDirectory()
        proc.environment = env

        var launched = false
        defer {
            // 兜底清理:先尝试优雅退出,再 SIGTERM,再 SIGKILL。
            if launched, proc.isRunning {
                _ = Self.write(fd: primaryFD, string: "/exit\r")
                let exitDeadline = Date().addingTimeInterval(0.8)
                while proc.isRunning, Date() < exitDeadline {
                    usleep(50_000)
                }
                if proc.isRunning {
                    proc.terminate()
                    let termDeadline = Date().addingTimeInterval(1.0)
                    while proc.isRunning, Date() < termDeadline {
                        usleep(50_000)
                    }
                }
                if proc.isRunning {
                    kill(proc.processIdentifier, SIGKILL)
                }
                proc.waitUntilExit()
            }
            try? primaryHandle.close()
            try? secondaryHandle.close()
        }

        do {
            try proc.run()
            launched = true
        } catch {
            throw Error.launchFailed(error.localizedDescription)
        }

        // 初始 settle:等 CLI 渲染 TUI、做完启动期 auth 检查。Auth refresh 通常就发生在这里。
        usleep(UInt32(ClaudeDelegatedRefresh.initialDelay * 1_000_000))

        // 发 /status,触发 CLI 调一次需要 token 的命令,保险起见再促一次 refresh。
        _ = Self.write(fd: primaryFD, string: "/status\r")

        let deadline = Date().addingTimeInterval(timeout)
        var sawAnyOutput = false
        var buffer = Data()
        // CLI 渲染会请求光标位置(ESC[6n),不回它的话有些 TUI 会卡住。
        let cursorQuery = Data([0x1B, 0x5B, 0x36, 0x6E])
        var nextCursorReplyAt = Date.distantPast
        // 每隔一小段时间补一次回车,防止 TUI 卡在某些一次性 prompt 上(对齐 CodexBar)。
        var lastEnterAt = Date()
        let enterInterval: TimeInterval = 0.8

        while Date() < deadline {
            var tmp = [UInt8](repeating: 0, count: 4096)
            let n = read(primaryFD, &tmp, tmp.count)
            if n > 0 {
                sawAnyOutput = true
                buffer.append(contentsOf: tmp.prefix(Int(n)))
                if Date() >= nextCursorReplyAt,
                   buffer.range(of: cursorQuery) != nil {
                    _ = Self.write(fd: primaryFD, string: "\u{1b}[1;1R")
                    nextCursorReplyAt = Date().addingTimeInterval(1.0)
                }
                // buffer 太长就截一下,避免无限增长。
                if buffer.count > 32 * 1024 {
                    buffer = buffer.suffix(8 * 1024)
                }
                // 注意:这里 *不* 早退。banner 里随便一个词都可能命中关键字,过早早退
                // 会让 claude 还没来得及做 token refresh 就被 /exit 收尾。让它跑满超时。
            } else if n == 0 {
                break // EOF
            } else {
                let err = errno
                if err == EAGAIN || err == EWOULDBLOCK || err == EINTR {
                    // 没数据,继续 idle
                } else if err == EIO {
                    break
                } else {
                    break
                }
            }
            if Date().timeIntervalSince(lastEnterAt) >= enterInterval {
                _ = Self.write(fd: primaryFD, string: "\r")
                lastEnterAt = Date()
            }
            if !proc.isRunning { break }
            usleep(50_000)
        }

        // sawAnyOutput 为 false 通常意味着 CLI 立刻就崩了(比如 binary 不可执行或者依赖缺失)。
        if !sawAnyOutput, !proc.isRunning, proc.terminationStatus != 0 {
            throw Error.launchFailed("claude exited with status \(proc.terminationStatus) producing no output")
        }
    }

    @discardableResult
    private static func write(fd: Int32, string: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            var offset = 0
            var retries = 0
            while offset < raw.count {
                let n = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                if n > 0 {
                    offset += n
                    retries = 0
                    continue
                }
                if n == 0 { return false }
                let err = errno
                if err == EAGAIN || err == EWOULDBLOCK {
                    retries += 1
                    if retries > 100 { return false }
                    usleep(5_000)
                    continue
                }
                return false
            }
            return true
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    /// 后台委托刷新成功(claude CLI 完成 token 刷新并写回了 keychain)。
    /// AppState 监听此通知并自动再发起一次完整刷新,让 UI 拿到新数据。
    static let claudeDelegatedRefreshDidSucceed = Notification.Name("ClaudeDelegatedRefreshDidSucceed")
}
