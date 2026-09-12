import Foundation

// MARK: - WidgetSharedState
//
// 见 docs/草案-桌面小组件.md §3.2 / §4。
// 主 App 写、桌面小组件读的共享状态。只放"小组件需要、而 quota-cache.json 里没有"的东西:
// 心跳 + 几个显示开关。额度快照本身仍走 QuotaCache,两边读同一个 App Group 容器。

struct WidgetSharedState: Codable, Sendable, Equatable {
    var version: Int = 1

    /// 主 App 最近一次证明自己活着的时间。
    /// 小组件据此决定是否翻「请启动 ManaBar」空态——主 App 退出时没有机会通知小组件
    /// (被强杀或崩溃时更是如此),所以改由小组件在 timeline 里预埋一个到期翻转的 entry。
    var heartbeatAt: Date

    /// 服务显示开关。取全局的 showCodex / showClaude,**不**跟悬浮窗的 floatingShow* 联动:
    /// 用户关掉悬浮窗的某一行,不代表也想让小组件少一行。
    var showCodex: Bool
    var showClaude: Bool

    /// "zh" / "en"。小组件进程里没有 SettingsStore,靠这个字段选词。
    var language: String
}

enum WidgetSharedStore {
    nonisolated private static let fileName = "widget-state.json"

    /// WidgetKit 的 kind,主 App reload 与 Widget 声明必须一致。
    nonisolated static let widgetKind = "ManaBarWidget"

    /// 主 App 侧心跳间隔。固定 5 分钟,不跟 quotaInterval(1~10 分钟可调)抖——
    /// 否则 10 分钟档下空态阈值会被迫拉到 20 分钟以上。
    nonisolated static let heartbeatInterval: TimeInterval = 5 * 60

    /// 心跳停多久后小组件翻空态。5 × 2 + 3 分钟宽限,可容忍一次心跳丢失。
    nonisolated static let staleThreshold: TimeInterval = 13 * 60

    nonisolated static func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: QuotaCache.appGroupID)?
            .appendingPathComponent(fileName, isDirectory: false)
    }

    nonisolated static func load() -> WidgetSharedState? {
        guard let url = fileURL(),
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(WidgetSharedState.self, from: data),
              state.version == 1
        else {
            return nil
        }
        return state
    }

    nonisolated static func save(_ state: WidgetSharedState) {
        guard let url = fileURL() else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
