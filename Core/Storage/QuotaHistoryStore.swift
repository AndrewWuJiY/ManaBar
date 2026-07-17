import Foundation

enum QuotaHistoryAccountKind: String, Sendable, Codable {
    case codexPrimary
    case codexImported
    case claudePrimary
}

/// 被记录的额度窗口类型。5H 优先;服务当前没有 5H 窗口时回退记录周额度
/// (如 2026-07 起 OpenAI 移除 Plus/Business/Pro 的 5h 限制)。
enum QuotaHistoryWindowKind: String, Sendable, Codable {
    case fiveHour
    case weekly
}

struct QuotaHistorySample: Sendable, Equatable, Codable {
    var accountKey: String
    var app: QuotaApp
    var kind: QuotaHistoryAccountKind
    var sampledAt: Date
    var remainingPercent: Int
    var resetsAt: Date?
    /// 旧数据(仅记录 5H 的时期)没有此字段,按 5H 处理。
    var window: QuotaHistoryWindowKind?

    var windowKind: QuotaHistoryWindowKind { window ?? .fiveHour }
}

struct QuotaChangeEvent: Sendable, Equatable, Codable, Identifiable {
    var id: String
    var accountKey: String
    var app: QuotaApp
    var kind: QuotaHistoryAccountKind
    var sampledAt: Date
    var beforeRemainingPercent: Int
    var afterRemainingPercent: Int
    var deltaPercent: Int
    var resetsAt: Date?
    /// 旧数据(仅记录 5H 的时期)没有此字段,按 5H 处理。
    var window: QuotaHistoryWindowKind?

    var windowKind: QuotaHistoryWindowKind { window ?? .fiveHour }
}

struct QuotaHistoryPayload: Sendable, Equatable, Codable {
    /// v2(2026-06):由「只存今天」改为按保留窗口跨天留存,供时间线按区间回看。
    static let currentVersion = 2

    var version: Int = Self.currentVersion
    var dayStart: Date = QuotaHistoryStore.todayStart()
    var lastSamples: [String: QuotaHistorySample] = [:]
    var events: [QuotaChangeEvent] = []
}

enum QuotaHistoryAccountKey {
    nonisolated static func codexPrimary(accountId: String?) -> String {
        if let id = nonEmpty(accountId) {
            return "codex:primary:\(id)"
        }
        return "codex:primary"
    }

    nonisolated static func codexImported(id: String) -> String {
        "codex:imported:\(id)"
    }

    nonisolated static func claudePrimary() -> String {
        "claude:primary"
    }

    nonisolated private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

enum QuotaHistoryStore {
    nonisolated private static let fileName = "quota-history.json"
    /// v1 旧文件名(只存当天)。升级时一次性迁移其内容。
    nonisolated private static let legacyFileName = "quota-history-today.json"
    nonisolated private static let bundleDirectory = "ManaBar"
    /// 跨天保留窗口(天)。超过的事件在 prune 时丢弃,避免文件无限增长。
    nonisolated static let retentionDays = 90

    nonisolated static func load(now: Date = Date()) -> QuotaHistoryPayload {
        if let payload = decodeFile(fileURL()), payload.version == QuotaHistoryPayload.currentVersion {
            return prune(payload, now: now)
        }
        // 迁移:旧版 v1 只存当天的 quota-history-today.json,搬进新存储。
        if let legacy = decodeFile(legacyFileURL()) {
            var migrated = QuotaHistoryPayload(dayStart: todayStart(now: now))
            migrated.lastSamples = legacy.lastSamples
            migrated.events = legacy.events
            return prune(migrated, now: now)
        }
        return QuotaHistoryPayload(dayStart: todayStart(now: now))
    }

    nonisolated private static func decodeFile(_ url: URL) -> QuotaHistoryPayload? {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(QuotaHistoryPayload.self, from: data)
        else { return nil }
        return payload
    }

    nonisolated static func save(_ payload: QuotaHistoryPayload) throws {
        let url = fileURL()
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: url, options: [.atomic])
    }

    nonisolated static func record(
        payload: QuotaHistoryPayload,
        accountKey: String,
        app: QuotaApp,
        kind: QuotaHistoryAccountKind,
        snapshot: QuotaSnapshot,
        sampledAt: Date
    ) -> QuotaHistoryPayload {
        // 5H 优先;无 5H 窗口(fiveHourUnlimited)时回退记录周额度。
        let tracked: (window: QuotaWindow, kind: QuotaHistoryWindowKind)
        if let fiveHour = snapshot.fiveHour {
            tracked = (fiveHour, .fiveHour)
        } else if let weekly = snapshot.weekly {
            tracked = (weekly, .weekly)
        } else {
            return prune(payload, now: sampledAt)
        }

        var next = prune(payload, now: sampledAt)
        let remaining = roundedPercent(tracked.window.remainingPercent)
        let previous = next.lastSamples[accountKey]

        next.lastSamples[accountKey] = QuotaHistorySample(
            accountKey: accountKey,
            app: app,
            kind: kind,
            sampledAt: sampledAt,
            remainingPercent: remaining,
            resetsAt: tracked.window.resetsAt,
            window: tracked.kind
        )

        // 无基线,或窗口类型发生切换(5H ⇄ 周):只重置基线,
        // 不把跨窗口差值当成一次额度变动记录下来。
        guard let previous, previous.windowKind == tracked.kind else {
            return next
        }
        guard previous.remainingPercent != remaining else {
            return next
        }

        let delta = remaining - previous.remainingPercent
        next.events.append(QuotaChangeEvent(
            id: eventId(accountKey: accountKey, sampledAt: sampledAt, before: previous.remainingPercent, after: remaining),
            accountKey: accountKey,
            app: app,
            kind: kind,
            sampledAt: sampledAt,
            beforeRemainingPercent: previous.remainingPercent,
            afterRemainingPercent: remaining,
            deltaPercent: delta,
            resetsAt: tracked.window.resetsAt,
            window: tracked.kind
        ))
        return next
    }

    nonisolated static func todayStart(now: Date = Date()) -> Date {
        Calendar.current.startOfDay(for: now)
    }

    nonisolated static func fileURL() -> URL {
        supportDirectory().appendingPathComponent(fileName, isDirectory: false)
    }

    nonisolated private static func legacyFileURL() -> URL {
        supportDirectory().appendingPathComponent(legacyFileName, isDirectory: false)
    }

    nonisolated private static func supportDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent(bundleDirectory, isDirectory: true)
    }

    /// 保留窗口起点(含):今天 0 点往前推 retentionDays-1 天。
    nonisolated static func retentionStart(now: Date = Date()) -> Date {
        let start = todayStart(now: now)
        return Calendar.current.date(byAdding: .day, value: -(retentionDays - 1), to: start) ?? start
    }

    nonisolated private static func prune(_ payload: QuotaHistoryPayload, now: Date) -> QuotaHistoryPayload {
        let cutoff = retentionStart(now: now)
        var next = payload
        next.version = QuotaHistoryPayload.currentVersion
        next.dayStart = todayStart(now: now)
        // 事件按保留窗口裁剪并保持时间升序。
        next.events = next.events
            .filter { $0.sampledAt >= cutoff }
            .sorted { $0.sampledAt < $1.sampledAt }
        // lastSamples 是跨天 delta 的 baseline,保留;仅丢弃超出窗口很久未更新的账号。
        next.lastSamples = next.lastSamples.filter { $0.value.sampledAt >= cutoff }
        return next
    }

    nonisolated private static func roundedPercent(_ value: Double) -> Int {
        max(0, min(100, Int(value.rounded())))
    }

    nonisolated private static func eventId(
        accountKey: String,
        sampledAt: Date,
        before: Int,
        after: Int
    ) -> String {
        "\(accountKey)|\(Int(sampledAt.timeIntervalSince1970))|\(before)|\(after)"
    }
}
