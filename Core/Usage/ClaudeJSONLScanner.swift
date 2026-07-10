import Foundation

/// 扫 Claude 本地会话日志，把 assistant 行解析成 UsageEntry。两个扫描根：
/// 1. CLI：`~/.claude/projects/**/*.jsonl`
/// 2. 桌面 App（Cowork）：`~/Library/Application Support/Claude/local-agent-mode-sessions/<uuid>/<uuid>/<session>/.claude/projects/**/*.jsonl`
///    （未公开内部结构，按固定 3 层定向枚举；结构变化时找不到即返回空，不影响 CLI 统计。网页 / 移动端无本地日志，仍不可统计。）
/// 增量逻辑：file mtime + byte offset；同一条 message.id 跨调用只计一次（持久化到 ScanFileState.seenMessageIds）。
enum ClaudeJSONLScanner {
    struct Result: Sendable {
        var entries: [UsageEntry]
        var newState: [String: ScanFileState]
        var newSeenIds: [String]
        var filesScanned: Int
        var linesParsed: Int
    }

    nonisolated static func scan(previous: [String: ScanFileState], seenMessageIds: [String]) -> Result {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cliRoot = home.appendingPathComponent(".claude/projects", isDirectory: true)
        var files = JSONLDirectoryEnumerator.files(at: cliRoot)
        for root in appSessionProjectRoots(home: home) {
            files.append(contentsOf: JSONLDirectoryEnumerator.files(at: root))
        }

        var newState: [String: ScanFileState] = previous
        var entries: [UsageEntry] = []
        var linesParsed = 0
        // 跨文件全局去重：同一 message.id 在 sidechain / subagent 文件中会反复出现。
        var seen = Set(seenMessageIds)

        for url in files {
            let path = url.path
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0

            var state = previous[path] ?? ScanFileState(mtime: 0, offset: 0)
            // mtime 没变 & size 没变 → 跳过
            if state.mtime == mtime, state.offset == size {
                newState[path] = state
                continue
            }
            // 文件被截断：offset 回到 0 重扫（此时仍由全局 seen 兜底防重复计费）
            if state.offset > size {
                state.offset = 0
            }

            guard let read = JSONLLineReader.read(url: url, fromOffset: state.offset) else {
                newState[path] = state
                continue
            }

            // 本批次内按 id 收集 candidate，最后挑 stop_reason != nil 的；最终再与全局 seen 比对。
            var candidates: [String: ParsedAssistant] = [:]
            for line in read.lines {
                linesParsed += 1
                guard let parsed = parseAssistantLine(line) else { continue }
                if seen.contains(parsed.messageId) { continue }
                if let existing = candidates[parsed.messageId] {
                    let prefer = (parsed.stopReason != nil && existing.stopReason == nil)
                        || (parsed.outputTokens > existing.outputTokens && existing.stopReason == nil)
                    if prefer { candidates[parsed.messageId] = parsed }
                } else {
                    candidates[parsed.messageId] = parsed
                }
            }

            for (id, p) in candidates {
                seen.insert(id)
                let day = UsageDay.startOfDay(for: p.timestamp)
                let cost = Pricing.cost(
                    model: p.model,
                    input: p.inputTokens,
                    output: p.outputTokens,
                    cacheRead: p.cacheReadTokens,
                    cacheCreation: p.cacheCreationTokens
                )
                entries.append(UsageEntry(
                    app: .claude,
                    model: Pricing.normalize(model: p.model),
                    day: day,
                    timestamp: p.timestamp,
                    inputTokens: p.inputTokens,
                    outputTokens: p.outputTokens,
                    cacheReadTokens: p.cacheReadTokens,
                    cacheCreationTokens: p.cacheCreationTokens,
                    costUSD: cost
                ))
            }

            state.mtime = mtime
            state.offset = read.newOffset
            newState[path] = state
        }

        // 删除已不存在的文件 watermark
        let alive = Set(files.map { $0.path })
        for key in newState.keys where !alive.contains(key) {
            newState.removeValue(forKey: key)
        }

        // 控制全局 seen 集合大小：保留最近 20000 条
        let seenArr = Array(seen)
        let cappedSeen = seenArr.count > 20000 ? Array(seenArr.suffix(20000)) : seenArr

        return Result(entries: entries, newState: newState, newSeenIds: cappedSeen, filesScanned: files.count, linesParsed: linesParsed)
    }

    /// 枚举桌面 App 会话的 `.claude/projects` 根目录。
    /// 不从会话根整树递归：目录大（数百 MB、含大量非日志文件），且 `.claude` 是隐藏目录会被
    /// `.skipsHiddenFiles` 跳过——按观察到的固定层级 `<base>/<uuid>/<uuid>/<session>/` 逐层列目录，
    /// 再显式拼 `.claude/projects` 检查存在性，开销只有几次浅层 contentsOfDirectory。
    private nonisolated static func appSessionProjectRoots(home: URL) -> [URL] {
        let fm = FileManager.default
        let base = home.appendingPathComponent(
            "Library/Application Support/Claude/local-agent-mode-sessions", isDirectory: true)
        var roots: [URL] = []
        for l1 in subdirectories(of: base, fm) {
            for l2 in subdirectories(of: l1, fm) {
                for session in subdirectories(of: l2, fm) {
                    let projects = session.appendingPathComponent(".claude/projects", isDirectory: true)
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: projects.path, isDirectory: &isDir), isDir.boolValue {
                        roots.append(projects)
                    }
                }
            }
        }
        return roots
    }

    private nonisolated static func subdirectories(of url: URL, _ fm: FileManager) -> [URL] {
        guard let items = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return items.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        }
    }

    private struct ParsedAssistant {
        var messageId: String
        var model: String
        var timestamp: Date
        var inputTokens: Int
        var outputTokens: Int
        var cacheReadTokens: Int
        var cacheCreationTokens: Int
        var stopReason: String?
    }

    private nonisolated static func parseTimestamp(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    private nonisolated static func parseAssistantLine(_ line: String) -> ParsedAssistant? {
        guard let data = line.data(using: .utf8) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard (root["type"] as? String) == "assistant" else { return nil }
        guard let message = root["message"] as? [String: Any] else { return nil }
        guard let messageId = message["id"] as? String else { return nil }
        guard let usage = message["usage"] as? [String: Any] else { return nil }
        let outputTokens = (usage["output_tokens"] as? Int) ?? 0
        if outputTokens == 0 { return nil }
        let inputTokens = (usage["input_tokens"] as? Int) ?? 0
        let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0
        let cacheCreation = (usage["cache_creation_input_tokens"] as? Int) ?? 0
        let model = (message["model"] as? String) ?? "unknown"
        let stopReason = message["stop_reason"] as? String

        let ts: Date
        if let s = root["timestamp"] as? String, let parsed = parseTimestamp(s) {
            ts = parsed
        } else {
            ts = Date()
        }

        return ParsedAssistant(
            messageId: messageId,
            model: model,
            timestamp: ts,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheRead,
            cacheCreationTokens: cacheCreation,
            stopReason: stopReason
        )
    }
}
