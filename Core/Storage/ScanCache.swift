import Foundation

/// 单个 JSONL 文件的扫描 watermark。
struct ScanFileState: Sendable, Equatable, Codable {
    var mtime: Double          // file modification time, epoch seconds
    var offset: UInt64         // 已扫到的字节数
    /// Codex 用：当前会话最近一次 `turn_context` 里的模型，用于给后续 token_count 打标签。
    var lastModel: String?
}

struct ScanState: Sendable, Equatable, Codable {
    /// version 管「结构变更」（字段增减导致解码不兼容时 bump）；价格变更由 pricingFingerprint 接管。
    /// v4: 引入 pricingFingerprint，价格表变化自动触发全量重扫，不再依赖手动 bump。
    static let currentVersion: Int = 4
    var version: Int = ScanState.currentVersion
    /// 写盘时记录的价格表指纹；load 时与当前 `Pricing.fingerprint` 不一致即视为缓存失效、全量重扫重算。
    var pricingFingerprint: String = ""
    var claude: [String: ScanFileState] = [:]
    var codex: [String: ScanFileState] = [:]
    /// 跨文件的 Claude message.id 去重集合（同一条 assistant 消息可能被 sidechain / subagent 在多个 jsonl 里重复引用）。
    var claudeSeenMessageIds: [String] = []
}

enum ScanCache {
    nonisolated private static let fileName = "scan-state.json"
    nonisolated private static let bundleDirectory = "ManaBar"

    nonisolated static func load() -> ScanState {
        let url = cacheFileURL()
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(ScanState.self, from: data),
              state.version == ScanState.currentVersion,
              state.pricingFingerprint == Pricing.fingerprint
        else {
            return ScanState()
        }
        return state
    }

    nonisolated static func save(_ state: ScanState) throws {
        let url = cacheFileURL()
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: [.atomic])
    }

    nonisolated static func cacheFileURL() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Caches", isDirectory: true)
        return caches
            .appendingPathComponent(bundleDirectory, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}

/// 聚合结果磁盘缓存，启动后立刻 UI 有数。
struct UsageRollupPayload: Sendable, Codable {
    /// version 管「结构变更」；价格变更由 pricingFingerprint 接管。
    /// v4: 引入 pricingFingerprint，价格表变化自动触发重算，丢弃用旧价存的桶。
    static let currentVersion: Int = 4
    var version: Int = UsageRollupPayload.currentVersion
    /// 写盘时记录的价格表指纹；load 时与当前 `Pricing.fingerprint` 不一致即丢弃，全量重扫重建。
    var pricingFingerprint: String = ""
    var buckets: [UsageBucket] = []
    var updatedAt: Date = Date()
}

enum UsageRollupCache {
    nonisolated private static let fileName = "usage-rollup.json"
    nonisolated private static let bundleDirectory = "ManaBar"

    nonisolated static func load() -> UsageRollupPayload {
        let url = cacheFileURL()
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(UsageRollupPayload.self, from: data),
              payload.version == UsageRollupPayload.currentVersion,
              payload.pricingFingerprint == Pricing.fingerprint
        else {
            return UsageRollupPayload()
        }
        return payload
    }

    nonisolated static func save(_ payload: UsageRollupPayload) throws {
        let url = cacheFileURL()
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: url, options: [.atomic])
    }

    nonisolated static func cacheFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support
            .appendingPathComponent(bundleDirectory, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}
