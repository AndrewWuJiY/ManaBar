import Foundation

struct QuotaCacheRecord: Sendable, Equatable, Codable {
    var snapshot: QuotaSnapshot
    var source: QuotaSnapshotSource
    var updatedAt: Date
}

struct QuotaCachePayload: Sendable, Equatable, Codable {
    var version: Int = 1
    var codex: QuotaCacheRecord?
    var claude: QuotaCacheRecord?
    /// 用户导入的 Codex 账号配额缓存,key = ImportedCodexAccount.id (= chatgpt_account_id)。
    /// 字段缺失时解码为 nil,旧缓存文件兼容。
    var importedCodex: [String: QuotaCacheRecord]?
}

enum QuotaCache {
    nonisolated private static let fileName = "quota-cache.json"
    nonisolated private static let bundleDirectory = "ManaBar"

    /// App Group 容器标识,与桌面小组件(ManaBarWidget)共享额度快照。见 docs/草案-桌面小组件.md §3.2。
    /// 主 App 仍是非沙箱(app-sandbox = false),加 App Group entitlement 只为拿到共享容器路径。
    nonisolated static let appGroupID = "group.659P79368S.com.andrewwujiy.manabar"

    nonisolated static func load() -> QuotaCachePayload {
        migrateLegacyIfNeeded()
        let url = cacheFileURL()
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(QuotaCachePayload.self, from: data),
              payload.version == 1
        else {
            return QuotaCachePayload()
        }
        return payload
    }

    nonisolated static func save(_ payload: QuotaCachePayload) throws {
        let url = cacheFileURL()
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: url, options: [.atomic])
    }

    /// 优先用 App Group 共享容器(小组件要读同一份);entitlement 未配置时回退旧路径,
    /// 行为与引入小组件之前完全一致。
    nonisolated static func cacheFileURL() -> URL {
        groupCacheFileURL() ?? legacyCacheFileURL()
    }

    /// entitlement 缺失时 containerURL 返回 nil。为防某些情况下拿到一个尚未创建的路径,
    /// 再验一次目录真实存在——否则会把缓存写进小组件读不到的地方,还丢掉旧文件。
    nonisolated static func groupCacheFileURL() -> URL? {
        let fm = FileManager.default
        guard let container = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID),
              fm.fileExists(atPath: container.path)
        else {
            return nil
        }
        return container.appendingPathComponent(fileName, isDirectory: false)
    }

    nonisolated static func legacyCacheFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support
            .appendingPathComponent(bundleDirectory, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    /// App Group 可用、且容器里还没有缓存时,把 Application Support 的旧文件拷过去。
    /// 只拷不删:回滚到不带小组件的版本时旧路径仍是权威数据,不至于丢掉额度基线。
    nonisolated static func migrateLegacyIfNeeded() {
        guard let groupURL = groupCacheFileURL() else { return }
        let fm = FileManager.default
        guard !fm.fileExists(atPath: groupURL.path) else { return }
        let legacy = legacyCacheFileURL()
        guard fm.fileExists(atPath: legacy.path) else { return }
        try? fm.copyItem(at: legacy, to: groupURL)
    }
}
