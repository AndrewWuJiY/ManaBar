import Darwin
import Foundation

enum ClaudeCLIFallbackQuotaClient {
    nonisolated static func fetch(timeout: TimeInterval = 20) async -> Result<QuotaSnapshot, QuotaError> {
        // cwd / watchdog 与委托刷新保持一致:空白工作目录避免 CLI 扫描用户目录触发 TCC 弹窗。
        let workspace = await ClaudeProbeWorkspace.prepared()
        let watchdog = await ClaudeWatchdogResolver.resolve()
        return await Task.detached(priority: .utility) {
            run(timeout: timeout, workspace: workspace, watchdog: watchdog)
        }.value
    }

    nonisolated private static func run(
        timeout: TimeInterval,
        workspace: URL,
        watchdog: String?
    ) -> Result<QuotaSnapshot, QuotaError> {
        // 与委托刷新共用 ClaudeCLIResolver:GUI 进程 PATH 只有系统目录,
        // 原生安装器的 ~/.local/bin/claude 等位置必须显式查找。
        guard let binary = ClaudeCLIResolver.resolve() else {
            return .failure(.transport("claude cli not found"))
        }
        return runSession(binary: binary, workspace: workspace, watchdog: watchdog, timeout: timeout)
    }

    /// TUI 启动后多久没有新输出视为就绪;超过 `maxBootWait` 仍未安静也照发 `/usage`。
    nonisolated private static let settleInterval: TimeInterval = 1.0
    nonisolated private static let maxBootWait: TimeInterval = 8
    /// 解析成功后需输出安静这么久才收尾,等周窗口等后续行渲染完整。
    nonisolated private static let usageSettleInterval: TimeInterval = 1.0
    /// `/usage` 先画缓存值再显示 `Refreshing…` 原地更新;最多等这么久的刷新结果。
    nonisolated private static let usageRefreshWait: TimeInterval = 6
    nonisolated private static let maxOutputBytes = 4 * 1_048_576

    /// 在伪终端里驱动一次交互式 CLI:等 TUI 就绪 → 发 `/usage` → 读到额度或确认失败即收尾。
    ///
    /// 不能像早期实现那样用管道一次性写入命令:TUI 初始化前的输入会被丢弃,回车也必须是 `\r`,
    /// 否则 CLI 停在输入框里一直挂到超时。CLI 未用订阅登录时直接失败,不白等。
    nonisolated private static func runSession(
        binary: String,
        workspace: URL,
        watchdog: String?,
        timeout: TimeInterval
    ) -> Result<QuotaSnapshot, QuotaError> {
        var primaryFD: Int32 = -1
        var secondaryFD: Int32 = -1
        var win = winsize(ws_row: 50, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primaryFD, &secondaryFD, nil, nil, &win) == 0 else {
            return .failure(.transport("openpty failed: errno=\(errno)"))
        }
        _ = fcntl(primaryFD, F_SETFL, O_NONBLOCK)
        let primaryHandle = FileHandle(fileDescriptor: primaryFD, closeOnDealloc: true)
        let secondaryHandle = FileHandle(fileDescriptor: secondaryFD, closeOnDealloc: true)

        let proc = Process()
        proc.standardInput = secondaryHandle
        proc.standardOutput = secondaryHandle
        proc.standardError = secondaryHandle
        if let watchdog {
            proc.executableURL = URL(fileURLWithPath: watchdog)
            proc.arguments = ["--", binary]
        } else {
            proc.executableURL = URL(fileURLWithPath: binary)
        }
        proc.currentDirectoryURL = workspace
        var env = ProcessInfo.processInfo.environment
        if (env["TERM"] ?? "").isEmpty { env["TERM"] = "xterm-256color" }
        if (env["LANG"] ?? "").isEmpty { env["LANG"] = "en_US.UTF-8" }
        env["CI"] = "0"
        env["PWD"] = workspace.path
        proc.environment = env

        do {
            try proc.run()
        } catch {
            try? primaryHandle.close()
            try? secondaryHandle.close()
            return .failure(.transport("claude cli launch failed: \(error.localizedDescription)"))
        }
        defer {
            // 先尝试优雅退出(Esc 关掉 /usage 面板再 /exit),再 SIGTERM,最后 SIGKILL,不留孤儿进程。
            if proc.isRunning {
                _ = write(fd: primaryFD, string: "\u{1b}")
                usleep(150_000)
                _ = write(fd: primaryFD, string: "/exit\r")
                waitForExit(proc, within: 0.8)
            }
            if proc.isRunning {
                proc.terminate()
                waitForExit(proc, within: 1.0)
            }
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
            proc.waitUntilExit()
            try? primaryHandle.close()
            try? secondaryHandle.close()
        }

        let start = Date()
        let deadline = start.addingTimeInterval(timeout)
        // CLI 渲染会请求光标位置(ESC[6n),不回应的话部分 TUI 会卡住。
        let cursorQuery = Data([0x1B, 0x5B, 0x36, 0x6E])
        var nextCursorReplyAt = Date.distantPast
        var output = Data()
        var lastOutputAt = start
        var usageSentAt: Date?
        var usageParsedAt: Date?
        var trustAnswered = false
        var lastParse: Result<QuotaSnapshot, QuotaError>?
        var screen = ""

        while Date() < deadline {
            var chunk = [UInt8](repeating: 0, count: 8192)
            let n = read(primaryFD, &chunk, chunk.count)
            let now = Date()
            if n > 0 {
                output.append(contentsOf: chunk.prefix(n))
                lastOutputAt = now
                if now >= nextCursorReplyAt, output.suffix(4096).range(of: cursorQuery) != nil {
                    _ = write(fd: primaryFD, string: "\u{1b}[1;1R")
                    nextCursorReplyAt = now.addingTimeInterval(1.0)
                }
                // 屏幕需从完整输出重放,不能截断;20 秒内正常远到不了上限。
                if output.count > maxOutputBytes {
                    return .failure(.transport("claude cli output too large"))
                }
            } else if n == 0 {
                break
            } else if errno != EAGAIN, errno != EWOULDBLOCK, errno != EINTR {
                break
            }

            let text = String(decoding: output, as: UTF8.self)
            let compact = stripANSICodes(text).lowercased().filter { !$0.isWhitespace }

            // CLI 未用订阅账号登录:启动横幅显示 `API Usage Billing`(或状态栏 `Not logged in`),
            // `/usage` 只有本次会话花费、没有套餐额度,等下去没有意义。
            if compact.contains("notloggedin") || compact.contains("apiusagebilling") {
                return .failure(.tokenRevoked)
            }

            if usageSentAt == nil {
                // 首次进入陌生目录时 CLI 会问是否信任该目录,回车接受默认选项。
                if !trustAnswered,
                   compact.contains("doyoutrust") || compact.contains("yes,proceed")
                    || compact.contains("quicksafetycheck") {
                    _ = write(fd: primaryFD, string: "\r")
                    trustAnswered = true
                    lastOutputAt = now
                } else if (!output.isEmpty && now.timeIntervalSince(lastOutputAt) >= settleInterval)
                            || now.timeIntervalSince(start) >= maxBootWait {
                    _ = write(fd: primaryFD, string: "/usage\r")
                    usageSentAt = now
                }
            } else {
                if n > 0 {
                    // TUI 靠光标定位原地重绘(`Refreshing…` 后只改动变化的字符),
                    // 必须按终端语义重放成屏幕再解析,按字节流顺序读只能拿到旧值。
                    screen = TerminalScreen.render(text)
                    let parsed = parse(text: screen)
                    switch parsed {
                    case .success:
                        lastParse = parsed
                        if usageParsedAt == nil { usageParsedAt = now }
                    case .failure(.decode(let msg)) where msg.contains("missing Current session"):
                        break // 面板还没渲染出来,继续等
                    case .failure:
                        return parsed // 限流 / 认证失败 / 加载失败等明确结论
                    }
                }
                if let usageParsedAt, let lastParse,
                   now.timeIntervalSince(lastOutputAt) >= usageSettleInterval,
                   !screen.contains("Refreshing") || now.timeIntervalSince(usageParsedAt) >= usageRefreshWait {
                    return lastParse
                }
            }

            if !proc.isRunning { break }
            usleep(50_000)
        }

        if let lastParse { return lastParse }
        if !proc.isRunning {
            let parsed = parse(text: TerminalScreen.render(String(decoding: output, as: UTF8.self)))
            if case .success = parsed { return parsed }
            return .failure(.transport("claude cli exited \(proc.terminationStatus) before usage was read"))
        }
        return .failure(.transport("claude cli fallback timed out"))
    }

    nonisolated private static func waitForExit(_ proc: Process, within seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while proc.isRunning, Date() < deadline {
            usleep(50_000)
        }
    }

    @discardableResult
    nonisolated private static func write(fd: Int32, string: String) -> Bool {
        let bytes = Array(string.utf8)
        return bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) } == bytes.count
    }

    nonisolated private static func parse(text: String) -> Result<QuotaSnapshot, QuotaError> {
        let clean = stripANSICodes(text)
        let lower = clean.lowercased()
        let compact = lower.filter { !$0.isWhitespace }

        if lower.contains("rate limited") || lower.contains("rate_limit_error") || compact.contains("ratelimited") {
            return .failure(.http(429, "claude cli usage endpoint is rate limited"))
        }
        if lower.contains("authentication_error") || lower.contains("token_expired") {
            return .failure(.http(401, "claude cli authentication failed"))
        }
        if lower.contains("failed to load usage data") || compact.contains("failedtoloadusagedata") {
            return .failure(.decode("claude cli could not load usage data"))
        }

        let sessionLeft = extractPercent(after: ["Current session"], in: clean)
        let weeklyLeft = extractPercent(after: ["Current week (all models)", "Current week"], in: clean)
        let sonnetLeft = extractPercent(after: ["Current week (Sonnet only)", "Current week (Sonnet)"], in: clean)
        let opusLeft = extractPercent(after: ["Current week (Opus)"], in: clean)

        guard let sessionLeft else {
            return .failure(.decode("claude cli usage output missing Current session"))
        }

        return .success(QuotaSnapshot(
            app: .claude,
            fiveHour: makeWindow(percentLeft: sessionLeft,
                                 resetText: extractReset(after: ["Current session"], in: clean),
                                 windowSeconds: 5 * 60 * 60),
            weekly: makeWindow(percentLeft: weeklyLeft,
                               resetText: extractReset(after: ["Current week (all models)", "Current week"], in: clean),
                               windowSeconds: 7 * 24 * 60 * 60),
            weeklyOpus: makeWindow(percentLeft: opusLeft,
                                   resetText: extractReset(after: ["Current week (Opus)"], in: clean),
                                   windowSeconds: 7 * 24 * 60 * 60),
            weeklySonnet: makeWindow(percentLeft: sonnetLeft,
                                     resetText: extractReset(after: ["Current week (Sonnet only)", "Current week (Sonnet)"], in: clean),
                                     windowSeconds: 7 * 24 * 60 * 60),
            planType: nil,
            fetchedAt: Date()
        ))
    }

    nonisolated private static func makeWindow(
        percentLeft: Int?,
        resetText: String?,
        windowSeconds: Int
    ) -> QuotaWindow? {
        guard let percentLeft else { return nil }
        return QuotaWindow(
            usedPercent: max(0, min(100, 100 - Double(percentLeft))),
            resetsAt: parseResetDate(resetText),
            windowSeconds: windowSeconds
        )
    }

    nonisolated private static func extractPercent(after labels: [String], in text: String) -> Int? {
        let lines = text.components(separatedBy: .newlines)
        let normalizedLines = lines.map(normalizedForLabelSearch)
        for label in labels.map(normalizedForLabelSearch) {
            for (idx, normalizedLine) in normalizedLines.enumerated() where normalizedLine.contains(label) {
                for candidate in lines.dropFirst(idx).prefix(12) {
                    if let pct = percentFromLine(candidate) { return pct }
                }
            }
        }

        let compact = normalizedForLabelSearch(text)
        guard labels.contains(where: { compact.contains(normalizedForLabelSearch($0)) }) else { return nil }
        return allPercents(text).first
    }

    nonisolated private static func percentFromLine(_ line: String) -> Int? {
        guard !line.contains("|") else { return nil }
        let pattern = #"([0-9]{1,3}(?:\.[0-9]+)?)\p{Zs}*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let valRange = Range(match.range(at: 1), in: line),
              let rawVal = Double(line[valRange])
        else { return nil }

        let clamped = max(0, min(100, rawVal))
        let lower = line.lowercased()
        if ["used", "spent", "consumed"].contains(where: lower.contains) {
            return Int((100 - clamped).rounded())
        }
        if ["left", "remaining", "available"].contains(where: lower.contains) {
            return Int(clamped.rounded())
        }
        return nil
    }

    nonisolated private static func allPercents(_ text: String) -> [Int] {
        let normalized = text.lowercased().filter { !$0.isWhitespace }
        guard normalized.contains("currentsession") || normalized.contains("currentweek") else { return [] }
        guard normalized.contains("used") || normalized.contains("left")
            || normalized.contains("remaining") || normalized.contains("available")
        else { return [] }
        return text.components(separatedBy: .newlines).compactMap(percentFromLine)
    }

    nonisolated private static func extractReset(after labels: [String], in text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        let normalizedLines = lines.map(normalizedForLabelSearch)
        for label in labels.map(normalizedForLabelSearch) {
            for (idx, normalizedLine) in normalizedLines.enumerated() where normalizedLine.contains(label) {
                for candidate in lines.dropFirst(idx).prefix(14) {
                    if let range = candidate.range(of: "Resets", options: [.caseInsensitive]) {
                        return String(candidate[range.lowerBound...])
                            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n)"))
                    }
                }
            }
        }
        return nil
    }

    /// 解析 `/usage` 的重置文案,如 `Resets 1pm (Asia/Shanghai)`、`Resets Oct 4 at 3pm (Asia/Shanghai)`、
    /// `Resets 1:30pm`。括号里的时区优先,缺省用本机时区。
    nonisolated private static func parseResetDate(_ text: String?, now: Date = Date()) -> Date? {
        guard var raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        raw = raw.replacingOccurrences(of: #"(?i)^resets?:?\s*"#, with: "", options: .regularExpression)

        var timeZone = TimeZone.current
        // extractReset 会裁掉末尾的 `)`,右括号可有可无。
        if let range = raw.range(of: #"\([^)]+\)?"#, options: .regularExpression) {
            let identifier = raw[range].trimmingCharacters(in: CharacterSet(charactersIn: "() "))
            if let zone = TimeZone(identifier: identifier) { timeZone = zone }
            raw.removeSubrange(range)
        }
        raw = raw.replacingOccurrences(of: " at ", with: " ", options: .caseInsensitive)
        raw = raw.replacingOccurrences(of: ",", with: " ")
        // 1pm / 1 pm / 1:30pm → `1 PM` / `1:30 PM`,统一成 `a` 能解析的大写形式。
        raw = raw.replacingOccurrences(of: #"(?i)([0-9])\s*am\b"#, with: "$1 AM", options: .regularExpression)
        raw = raw.replacingOccurrences(of: #"(?i)([0-9])\s*pm\b"#, with: "$1 PM", options: .regularExpression)
        raw = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        formatter.timeZone = timeZone
        // 缺省字段用当地今天 00:00 补:用 now 会带上当前分钟;不设则落到远古年份,时区偏移非整分钟。
        formatter.defaultDate = calendar.startOfDay(for: now)

        for format in ["MMM d h:mm a", "MMM d h a", "MMM d HH:mm", "h:mm a", "h a", "HH:mm", "H:mm"] {
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: raw) else { continue }
            if format.contains("MMM") {
                var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: parsed)
                comps.year = calendar.component(.year, from: now)
                guard let date = calendar.date(from: comps) else { return nil }
                // 12 月看到 1 月的重置时间 ⇒ 跨年
                if date < now.addingTimeInterval(-24 * 60 * 60) {
                    return calendar.date(byAdding: .year, value: 1, to: date)
                }
                return date
            }
            let comps = calendar.dateComponents([.hour, .minute], from: parsed)
            guard let anchored = calendar.date(
                bySettingHour: comps.hour ?? 0,
                minute: comps.minute ?? 0,
                second: 0,
                of: now
            ) else { return nil }
            return anchored >= now ? anchored : calendar.date(byAdding: .day, value: 1, to: anchored)
        }
        return nil
    }

    nonisolated private static func stripANSICodes(_ text: String) -> String {
        let pattern = "\u{001B}\\[[0-?]*[ -/]*[@-~]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    nonisolated private static func normalizedForLabelSearch(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }
}

// MARK: - Terminal Screen

/// 极简终端屏幕重放:只实现 claude TUI 用到的光标移动 / 擦除,把字节流还原成最终屏幕文本。
/// 宽字符按 1 列处理,只影响含 CJK 的行(如路径),不影响额度面板的英文标签。
nonisolated private struct TerminalScreen {
    nonisolated static let rows = 50
    nonisolated static let cols = 120

    nonisolated static func render(_ text: String) -> String {
        var screen = TerminalScreen()
        screen.feed(Array(text.unicodeScalars))
        return screen.grid
            .map { String(String.UnicodeScalarView($0)).replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
            .joined(separator: "\n")
    }

    private var grid: [[Unicode.Scalar]] = Self.blankGrid()
    private var row = 0
    private var col = 0
    private var saved = (0, 0)

    nonisolated private static func blankGrid() -> [[Unicode.Scalar]] {
        Array(repeating: blankRow(), count: rows)
    }

    nonisolated private static func blankRow() -> [Unicode.Scalar] {
        Array(repeating: " ", count: cols)
    }

    nonisolated private mutating func lineFeed() {
        if row == Self.rows - 1 {
            grid.removeFirst()
            grid.append(Self.blankRow())
        } else {
            row += 1
        }
    }

    nonisolated private mutating func feed(_ s: [Unicode.Scalar]) {
        var i = 0
        let n = s.count
        while i < n {
            let ch = s[i]
            if ch == "\u{1B}" {
                guard i + 1 < n else { return }
                let next = s[i + 1]
                if next == "[" {
                    var j = i + 2
                    while j < n, !(0x40...0x7E).contains(s[j].value) { j += 1 }
                    guard j < n else { return }
                    csi(params: String(String.UnicodeScalarView(s[(i + 2)..<j])), final: s[j])
                    i = j + 1
                } else if next == "]" {
                    // OSC:以 BEL 或 ESC \ 结束
                    var j = i + 2
                    while j < n, s[j] != "\u{07}", !(s[j] == "\u{1B}" && j + 1 < n && s[j + 1] == "\\") { j += 1 }
                    i = j < n && s[j] == "\u{07}" ? j + 1 : j + 2
                } else if next == "7" {
                    saved = (row, col); i += 2
                } else if next == "8" {
                    (row, col) = saved; i += 2
                } else if next == "(" || next == ")" {
                    i += 3
                } else {
                    i += 2
                }
                continue
            }
            switch ch {
            case "\r": col = 0
            case "\n": lineFeed()
            case "\u{08}": col = max(0, col - 1)
            default:
                if ch.value >= 0x20, ch.value != 0x7F {
                    if col >= Self.cols {
                        col = 0
                        lineFeed()
                    }
                    grid[row][col] = ch
                    col += 1
                }
            }
            i += 1
        }
    }

    nonisolated private mutating func csi(params: String, final: Unicode.Scalar) {
        if let first = params.unicodeScalars.first, "?><=".unicodeScalars.contains(first) {
            // 私有模式里只关心切换备用屏:进出都等价于清屏。
            if ["?1049h", "?1049l", "?47h", "?47l"].contains(params + String(final)) {
                grid = Self.blankGrid(); row = 0; col = 0
            }
            return
        }
        let values = params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        let p1 = max(1, values.first ?? 1)
        switch final {
        case "A": row = max(0, row - p1)
        case "B": row = min(Self.rows - 1, row + p1)
        case "C": col = min(Self.cols - 1, col + p1)
        case "D": col = max(0, col - p1)
        case "G": col = min(Self.cols - 1, p1 - 1)
        case "H", "f":
            row = min(Self.rows - 1, max(1, values.first ?? 1) - 1)
            col = min(Self.cols - 1, max(1, values.count > 1 ? values[1] : 1) - 1)
        case "K":
            let c = min(col, Self.cols - 1)
            switch values.first ?? 0 {
            case 0: for k in c..<Self.cols { grid[row][k] = " " }
            case 1: for k in 0...c { grid[row][k] = " " }
            default: grid[row] = Self.blankRow()
            }
        case "J":
            let c = min(col, Self.cols - 1)
            switch values.first ?? 0 {
            case 0:
                for k in c..<Self.cols { grid[row][k] = " " }
                for r in (row + 1)..<Self.rows { grid[r] = Self.blankRow() }
            case 1:
                for r in 0..<row { grid[r] = Self.blankRow() }
                for k in 0...c { grid[row][k] = " " }
            default:
                grid = Self.blankGrid()
            }
        default:
            break // SGR 等不影响文本布局
        }
    }
}
