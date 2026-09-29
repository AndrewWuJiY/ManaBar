import SwiftUI
import WidgetKit

// MARK: - ManaBarWidget
//
// 见 docs/草案-桌面小组件.md。
// 小组件是独立进程,拿不到 AppState,也**不能**自己拉额度(Keychain / token 刷新 / CLI 兜底都在主 App)。
// 它只做一件事:读 App Group 容器里的 quota-cache.json + widget-state.json,把结果画出来。
//
// P1 阶段:数据通路打通,视图是能看的最小实现。
// 布局定稿、共享组件抽取(ServiceTile / ProgressBar / statusColor)、URL 跳转在 P2,见草案 §3.4 / §5。

// MARK: - Entry

struct QuotaEntry: TimelineEntry {
    let date: Date
    let zh: Bool
    /// nil = 主 App 未运行 / 从未运行 → 空态。
    /// 刻意不在空态里保留旧百分比:既然选了空态而不是过期数据,就不该让用户误读为实时额度。
    let payload: Payload?

    struct Payload {
        let codex: QuotaWindow?
        let claude: QuotaWindow?
        let showCodex: Bool
        let showClaude: Bool
    }
}

// MARK: - Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: Date(), zh: true, payload: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(Self.entry(at: Date()))
    }

    /// 倒计时的推进步长。重置时间显示到分钟,3 分钟精度足够,也不会让 entry 数量失控。
    private static let countdownStep: TimeInterval = 3 * 60

    /// 生成一串数据态 entry(推进倒计时)+ 末尾一个空态 entry(心跳到期)。
    ///
    /// 两件事靠它完成:
    ///
    /// 1. **倒计时走动**。小组件里 TimelineView(.periodic) 不工作,而 Text(date:style:) 的
    ///    固有宽度在布局期不确定、会挤垮同行元素,所以重置时间用静态文本渲染。静态文本要动,
    ///    只能靠 timeline 里不同 date 的 entry 推进——每个 entry 用自己的 date 当"现在"算倒计时。
    /// 2. **空态自动翻转**。主 App 退出时没有机会通知小组件(被强杀 / 崩溃时更是如此),
    ///    而 timeline 不会自己重算。所以把"该翻空态的时刻"直接预埋进去:
    ///    主 App 活着 → 每 5 分钟 reload,这个时刻被不断推后,用户永远看不到空态;
    ///    主 App 停了 → 没有新的 reload,时间走到就自动翻空态,不需要任何进程配合。
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        let now = Date()
        let current = Self.entry(at: now)

        guard current.payload != nil, let state = WidgetSharedStore.load() else {
            completion(Timeline(entries: [current], policy: .atEnd))
            return
        }

        let expiry = state.heartbeatAt.addingTimeInterval(WidgetSharedStore.staleThreshold)
        guard expiry > now else {
            completion(Timeline(entries: [current], policy: .atEnd))
            return
        }

        var entries: [QuotaEntry] = []
        var tick = now
        while tick < expiry {
            entries.append(Self.entry(at: tick))
            tick.addTimeInterval(Self.countdownStep)
        }
        entries.append(QuotaEntry(date: expiry, zh: current.zh, payload: nil))

        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private static func entry(at date: Date) -> QuotaEntry {
        guard let state = WidgetSharedStore.load() else {
            // 从未运行过主 App:容器里什么都没有。与"主 App 已退出"走同一套空态,文案不区分。
            return QuotaEntry(date: date, zh: true, payload: nil)
        }

        let zh = state.language == "zh"
        guard date.timeIntervalSince(state.heartbeatAt) < WidgetSharedStore.staleThreshold else {
            return QuotaEntry(date: date, zh: zh, payload: nil)
        }

        let cache = QuotaCache.load()
        return QuotaEntry(
            date: date,
            zh: zh,
            payload: .init(
                codex: monitoredWindow(of: cache.codex),
                claude: monitoredWindow(of: cache.claude),
                showCodex: state.showCodex,
                showClaude: state.showClaude
            )
        )
    }

    /// 5h 优先、无 5h 窗口时回退周窗口——与悬浮窗同一套取值规则(见 FloatingContentView)。
    ///
    /// 必须先把 record 解包再取窗口:写成 `record?.snapshot.fiveHour ?? record?.snapshot.weekly`
    /// 时可选链末端本身已是 Optional,`??` 的右侧永远取不到,Codex 这类没有 5h 限制的服务会显示 --%。
    private static func monitoredWindow(of record: QuotaCacheRecord?) -> QuotaWindow? {
        guard let snapshot = record?.snapshot else { return nil }
        // 重置时间已过的窗口按无数据处理(见 QuotaSnapshot.displayFiveHour)。
        return snapshot.fiveHourUnlimited ? snapshot.displayWeekly() : snapshot.displayFiveHour()
    }
}

// MARK: - View
//
// medium 约 330×155pt。排版原则:**百分比是主信息,必须是视觉焦点**。
// 初版把它压到 15pt、和 11pt 的服务名挤在一行,结果整块内容缩在中间一条,
// 上下大片留白——看着"空"的根因不是背景太大,是内容没撑起来。
//
// 现在的层级:百分比 26pt semibold(焦点)> tile 34pt(识别)> 服务名 13pt(标签)> 倒计时 11pt(次要)。
// 进度条 9pt 高,圆角胶囊,与容器圆角呼应(Liquid Glass 的同心原则)。
// 两行用 Spacer 上下撑开而不是居中堆叠,让内容占满容器。
//
// 刻意**不**给每行加卡片背景/玻璃层:CLAUDE.md 实现约束里写明不自造大面积背景与玻璃阴影,
// 密度问题靠排版解决,不靠加装饰。见 docs/草案-桌面小组件.md §3.4。

struct ManaBarWidgetEntryView: View {
    var entry: QuotaEntry

    var body: some View {
        if let payload = entry.payload {
            rows(payload)
        } else {
            emptyState
        }
    }

    private func rows(_ payload: QuotaEntry.Payload) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            // Codex 永远排在 Claude 前(见 CLAUDE.md 实现约束)
            if payload.showCodex {
                QuotaRow(
                    logoName: "codex",
                    fallback: "C",
                    name: "Codex",
                    tint: .codexAccent,
                    window: payload.codex,
                    now: entry.date
                )
            }
            if payload.showCodex && payload.showClaude {
                Spacer(minLength: 16)
            }
            if payload.showClaude {
                QuotaRow(
                    logoName: "claude",
                    fallback: "K",
                    name: "Claude Code",
                    tint: .claudeAccent,
                    window: payload.claude,
                    now: entry.date
                )
            }
            if !payload.showCodex && !payload.showClaude {
                Text(entry.zh ? "未启用" : "No services")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// 刻意不显示任何百分比:既然选了空态而不是过期数据,就不该让用户误读为实时额度。
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 3) {
                Text(entry.zh ? "ManaBar 未运行" : "ManaBar isn\u{2019}t running")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Text(entry.zh ? "点按启动" : "Click to launch")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct QuotaRow: View {
    let logoName: String
    let fallback: String
    let name: String
    let tint: Color
    let window: QuotaWindow?
    /// 该 entry 代表的时刻,不是 Date()——倒计时按它计算才会随 timeline 推进。
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            ServiceTile(
                logoName: logoName,
                fallback: fallback,
                tint: tint,
                size: 34,
                logoSize: 21,
                cornerRadius: 10
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)

                    // 桌面小组件在用户点击桌面时会去饱和至近单色,交通灯状态色那时基本失效。
                    // 低额度两档补一个符号做冗余,不靠颜色单独传递状态。见草案 §3.5。
                    if let symbol = warningSymbol {
                        Image(systemName: symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(barColor)
                    }

                    if let reset = resetLabel {
                        Text(reset)
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary.opacity(0.8))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    Text(percentText)
                        .font(.system(size: 26, weight: .semibold))
                        .kerning(-0.5)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .layoutPriority(2)
                }

                // 进度条独占整行,右端与百分比对齐:两行等长,是这块里最强的对齐线。
                ProgressBar(value: barValue, tint: barColor, height: 9)
            }
        }
    }

    /// 紧凑重置时间,形如 "· 4h25m"。与悬浮窗同一个 compactRelativeReset(Shared/QuotaVisuals.swift)。
    ///
    /// 用静态文本而不是 Text(date:style:):后者固有宽度在布局期不确定,会在 HStack 里抢走超额宽度,
    /// 把服务名和百分比压成 0 宽、内容溢出到 tile 底下。文本的走动交给 timeline 的多个 entry。
    /// 没有 resetsAt 时整段不渲染,不留占位符。
    private var resetLabel: String? {
        guard let resetsAt = window?.resetsAt, resetsAt > now else { return nil }
        return "\u{00B7} " + compactRelativeReset(resetsAt, now: now)
    }

    private var barValue: Double {
        guard let window else { return 0 }
        return window.remainingPercent / 100
    }

    private var percentText: String {
        guard let window else { return "--%" }
        return "\(Int(window.remainingPercent.rounded()))%"
    }

    private var barColor: Color {
        statusColor(remainingPercent: window?.remainingPercent, tint: tint)
    }

    private var warningSymbol: String? {
        guard let value = window?.remainingPercent else { return nil }
        if value <= 0 { return "exclamationmark.octagon.fill" }
        if value < 20 { return "exclamationmark.triangle.fill" }
        return nil
    }
}

// MARK: - Widget

struct ManaBarWidget: Widget {
    let kind: String = WidgetSharedStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ManaBarWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "manabar://stats"))
        }
        .configurationDisplayName("ManaBar")
        .description("Codex 与 Claude Code 的剩余额度")
        // 只做 medium:两行服务各需 tile + 名称 + 进度条 + 百分比 + 重置倒计时,
        // small 放不下会退化成悬浮窗的阉割版,large 对这个数据量是浪费。见草案 §3.3。
        .supportedFamilies([.systemMedium])
    }
}
