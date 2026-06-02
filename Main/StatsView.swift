import SwiftUI
import Charts

// MARK: - StatsRange

enum StatsRange: Hashable, CaseIterable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case thisYear
    case last7
    case last30
    case all
    case custom

    var englishLabel: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "Week"
        case .thisMonth: return "Month"
        case .thisYear: return "Year"
        case .last7: return "7d"
        case .last30: return "30d"
        case .all: return "All"
        case .custom: return "Custom"
        }
    }

    var chineseLabel: String {
        switch self {
        case .today: return "今天"
        case .yesterday: return "昨天"
        case .thisWeek: return "本周"
        case .thisMonth: return "本月"
        case .thisYear: return "本年"
        case .last7: return "7 天"
        case .last30: return "30 天"
        case .all: return "全部"
        case .custom: return "自定义"
        }
    }

    private static var weekStartMondayCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        cal.firstWeekday = 2
        return cal
    }

    func bounds(now: Date = Date(), customFrom: Date, customTo: Date) -> (from: Date, to: Date) {
        let cal = Self.weekStartMondayCalendar
        let startOfToday = cal.startOfDay(for: now)
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday

        switch self {
        case .today:
            return (startOfToday, startOfTomorrow)
        case .yesterday:
            let yesterdayStart = cal.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
            return (yesterdayStart, startOfToday)
        case .thisWeek:
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            let weekStart = cal.date(from: comps) ?? startOfToday
            return (weekStart, startOfTomorrow)
        case .thisMonth:
            let comps = cal.dateComponents([.year, .month], from: now)
            let monthStart = cal.date(from: comps) ?? startOfToday
            return (monthStart, startOfTomorrow)
        case .thisYear:
            let comps = cal.dateComponents([.year], from: now)
            let yearStart = cal.date(from: comps) ?? startOfToday
            return (yearStart, startOfTomorrow)
        case .last7:
            let from = cal.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
            return (from, startOfTomorrow)
        case .last30:
            let from = cal.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
            return (from, startOfTomorrow)
        case .all:
            return (.distantPast, .distantFuture)
        case .custom:
            let from = cal.startOfDay(for: customFrom)
            let toBase = cal.startOfDay(for: customTo)
            let to = cal.date(byAdding: .day, value: 1, to: toBase) ?? toBase
            return (from, max(from, to))
        }
    }

    /// 上一个等长区间(用于 delta 对比)。`.all` / `.custom` 返回 nil(无法对比)。
    func previousBounds(now: Date = Date(), customFrom: Date, customTo: Date) -> (from: Date, to: Date)? {
        switch self {
        case .all, .custom:
            return nil
        default:
            break
        }
        let current = bounds(now: now, customFrom: customFrom, customTo: customTo)
        let length = current.to.timeIntervalSince(current.from)
        guard length > 0, length.isFinite else { return nil }
        return (current.from.addingTimeInterval(-length), current.from)
    }
}

// MARK: - Service filter (sidebar)

enum StatsServiceFilter: Hashable, CaseIterable {
    case all
    case codex
    case claude

    var englishLabel: String {
        switch self {
        case .all: return "All"
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        }
    }

    var chineseLabel: String {
        switch self {
        case .all: return "全部"
        case .codex: return "OpenAI"
        case .claude: return "Anthropic"
        }
    }

    var tint: Color? {
        switch self {
        case .all: return nil
        case .codex: return .codexAccent
        case .claude: return .claudeAccent
        }
    }
}

// MARK: - StatsView

struct StatsView: View {
    @Environment(AppState.self) private var appState
    @State private var range: StatsRange = .today
    @State private var serviceFilter: StatsServiceFilter = .all
    @State private var customFrom: Date = Calendar.current.startOfDay(
        for: Date().addingTimeInterval(-7 * 86400)
    )
    @State private var customTo: Date = Calendar.current.startOfDay(for: Date())

    var body: some View {
        // `.accessory` 菜单栏 App 在非激活态下,后台刷新产生的 @Observable 变更
        // 不会立即重绘已打开的窗口(要等鼠标事件才 flush)。用周期 TimelineView
        // 强制重算,与 PopoverRootView header 同一套做法,让用量 / 限额在后台
        // 自动刷新后及时更新,而不是要等鼠标移入。
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            statsLayout
        }
    }

    private var statsLayout: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    topBar
                    if range == .custom { customRangeRow }

                    kpiRow.padding(.top, 6)

                    dailyUsagePanel

                    HStack(alignment: .top, spacing: 12) {
                        byServicePanel
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                        currentLimitsPanel
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                    }

                    byModelPanel
                }
                .padding(20)
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            sidebarGroup(title: "Service", chinese: "服务") {
                ForEach(StatsServiceFilter.allCases, id: \.self) { item in
                    sidebarItem(
                        english: item.englishLabel,
                        chinese: item.chineseLabel,
                        tint: item.tint,
                        active: serviceFilter == item
                    ) {
                        serviceFilter = item
                    }
                }
            }

            sidebarGroup(title: "View", chinese: "视图") {
                sidebarItem(english: "Overview", chinese: "概览", icon: "rectangle.split.2x2", active: true) {}
                sidebarItem(english: "Timeline", chinese: "时间线", icon: "chart.line.uptrend.xyaxis", active: false) {}
                    .disabled(true)
                    .opacity(0.5)
                sidebarItem(english: "Breakdown", chinese: "明细", icon: "list.bullet", active: false) {}
                    .disabled(true)
                    .opacity(0.5)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func sidebarGroup<Content: View>(
        title: String,
        chinese: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(tr(title, chinese).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            content()
        }
    }

    private func sidebarItem(
        english: String,
        chinese: String,
        tint: Color? = nil,
        icon: String? = nil,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .frame(width: 13, height: 13)
                        .foregroundStyle(active ? Color.white : Color.secondary)
                } else if let tint {
                    ServiceMark(color: tint, size: 8)
                        .frame(width: 13, height: 13, alignment: .center)
                } else {
                    Color.clear.frame(width: 13, height: 13)
                }

                Text(tr(english, chinese))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(active ? Color.white : Color.primary)

                Spacer()
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(active ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: Top bar (segmented + custom)

    private var topBar: some View {
        HStack(spacing: 12) {
            Spacer()
            Picker("", selection: $range) {
                ForEach(StatsRange.allCases, id: \.self) { r in
                    Text(tr(r.englishLabel, r.chineseLabel)).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }

    private var customRangeRow: some View {
        HStack(spacing: 12) {
            DatePicker(tr("From", "起"), selection: $customFrom, displayedComponents: .date)
                .datePickerStyle(.compact)
            DatePicker(tr("To", "止"), selection: $customTo, in: customFrom..., displayedComponents: .date)
                .datePickerStyle(.compact)
            Spacer()
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }

    // MARK: KPI row

    private var kpiRow: some View {
        HStack(spacing: 12) {
            KPICard(
                english: "Total tokens",
                chinese: "总 Tokens",
                value: StatsFormatter.compactToken(currentTotalsAll.totalTokens),
                delta: deltaPercent(current: Double(currentTotalsAll.totalTokens),
                                    previous: Double(previousTotalsAll.totalTokens)),
                tint: nil
            )
            KPICard(
                english: "Total spend",
                chinese: "总花费",
                value: StatsFormatter.cost(currentTotalsAll.costUSD),
                delta: deltaPercent(current: currentTotalsAll.costUSD.doubleValue,
                                    previous: previousTotalsAll.costUSD.doubleValue),
                tint: nil
            )
            KPICard(
                english: "Codex",
                chinese: "OpenAI",
                value: StatsFormatter.cost(currentTotals(.codex).costUSD),
                delta: deltaPercent(current: currentTotals(.codex).costUSD.doubleValue,
                                    previous: previousTotals(.codex).costUSD.doubleValue),
                tint: .codexAccent
            )
            KPICard(
                english: "Claude Code",
                chinese: "Anthropic",
                value: StatsFormatter.cost(currentTotals(.claude).costUSD),
                delta: deltaPercent(current: currentTotals(.claude).costUSD.doubleValue,
                                    previous: previousTotals(.claude).costUSD.doubleValue),
                tint: .claudeAccent
            )
        }
    }

    // MARK: Daily usage panel

    private var dailyUsagePanel: some View {
        Panel(title: "Daily usage", chinese: "每日用量", right: AnyView(
            HStack(spacing: 8) {
                LegendChip(color: .codexAccent, label: "Codex")
                LegendChip(color: .claudeAccent, label: "Claude")
            }
        )) {
            VStack(spacing: 6) {
                if dailySamples.isEmpty {
                    placeholderHeight(160, message: tr("No data", "无数据"))
                } else {
                    Chart(dailySamples) { sample in
                        BarMark(
                            x: .value("Day", sample.day, unit: .day),
                            y: .value("Cost", sample.codexCost.doubleValue),
                            stacking: .standard
                        )
                        .foregroundStyle(Color.codexAccent)
                        .cornerRadius(2)

                        BarMark(
                            x: .value("Day", sample.day, unit: .day),
                            y: .value("Cost", sample.claudeCost.doubleValue),
                            stacking: .standard
                        )
                        .foregroundStyle(Color.claudeAccent)
                        .cornerRadius(2)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: max(1, dailySamples.count / 5))) { value in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day(),
                                           centered: true)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 160)
                }
            }
        }
    }

    // MARK: By service panel

    private var byServicePanel: some View {
        Panel(title: "By service", chinese: "按服务") {
            VStack(alignment: .leading, spacing: 4) {
                ByServiceRow(
                    title: "Codex",
                    subtitle: "OpenAI",
                    tint: .codexAccent,
                    value: currentTotals(.codex).costUSD,
                    totalValue: currentTotalsAll.costUSD,
                    tokens: currentTotals(.codex).totalTokens
                )
                ByServiceRow(
                    title: "Claude Code",
                    subtitle: "Anthropic",
                    tint: .claudeAccent,
                    value: currentTotals(.claude).costUSD,
                    totalValue: currentTotalsAll.costUSD,
                    tokens: currentTotals(.claude).totalTokens
                )
            }
        }
    }

    // MARK: Current limits panel

    private var currentLimitsPanel: some View {
        Panel(title: "Current limits", chinese: "当前限额") {
            VStack(spacing: 4) {
                LimitRingRow(label: "Codex 5H", window: appState.codexQuota?.fiveHour, tint: .codexAccent)
                LimitRingRow(label: "Codex WK", window: appState.codexQuota?.weekly, tint: .codexAccent)
                LimitRingRow(label: "Claude 5H", window: appState.claudeQuota?.fiveHour, tint: .claudeAccent)
                LimitRingRow(label: "Claude WK", window: appState.claudeQuota?.weekly, tint: .claudeAccent)
            }
        }
    }

    // MARK: By model panel(保留旧的按模型聚合)

    private var byModelPanel: some View {
        Panel(title: "By model", chinese: "按模型") {
            VStack(alignment: .leading, spacing: 10) {
                if serviceFilter != .claude {
                    modelGroup(title: "Codex", tint: .codexAccent, rows: modelRows(for: .codex))
                }
                if serviceFilter != .codex && serviceFilter != .claude {
                    Divider()
                }
                if serviceFilter != .codex {
                    modelGroup(title: "Claude", tint: .claudeAccent, rows: modelRows(for: .claude))
                }
            }
        }
    }

    private func modelGroup(title: String, tint: Color, rows: [ModelRow]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ServiceMark(color: tint, size: 6, cornerRadius: 1.5)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.4)
                    .foregroundStyle(.tertiary)
            }
            if rows.isEmpty {
                Text(tr("No data", "无数据"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
            } else {
                ForEach(rows) { row in
                    HStack {
                        Text(row.model)
                            .font(.system(size: 12.5))
                        Spacer()
                        Text("\(tr("in", "入")) \(StatsFormatter.compactToken(row.totals.inputWithCacheTokens))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text("\(tr("out", "出")) \(StatsFormatter.compactToken(row.totals.outputTokens))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(StatsFormatter.cost(row.totals.costUSD))
                            .font(.system(size: 12.5, weight: .semibold))
                            .monospacedDigit()
                            .frame(width: 96, alignment: .trailing)
                    }
                    .padding(.leading, 12)
                }
            }
        }
    }

    // MARK: Data helpers

    private var rangeBounds: (from: Date, to: Date) {
        range.bounds(customFrom: customFrom, customTo: customTo)
    }

    private var previousRangeBounds: (from: Date, to: Date)? {
        range.previousBounds(customFrom: customFrom, customTo: customTo)
    }

    private var filteredBuckets: [UsageBucket] {
        let (from, to) = rangeBounds
        let buckets = appState.usageService.aggregator.snapshot()
            .filter { $0.day >= from && $0.day < to }
        switch serviceFilter {
        case .all:
            return buckets
        case .codex:
            return buckets.filter { $0.app == .codex }
        case .claude:
            return buckets.filter { $0.app == .claude }
        }
    }

    private var currentTotalsAll: UsageTotals {
        var t = UsageTotals.zero
        for b in filteredBuckets { t.add(b) }
        return t
    }

    private func currentTotals(_ app: UsageApp) -> UsageTotals {
        var t = UsageTotals.zero
        for b in filteredBuckets where b.app == app { t.add(b) }
        return t
    }

    private var previousTotalsAll: UsageTotals {
        guard let bounds = previousRangeBounds else { return .zero }
        let buckets = appState.usageService.aggregator.snapshot()
            .filter { $0.day >= bounds.from && $0.day < bounds.to }
        var t = UsageTotals.zero
        for b in buckets {
            if serviceFilter == .codex && b.app != .codex { continue }
            if serviceFilter == .claude && b.app != .claude { continue }
            t.add(b)
        }
        return t
    }

    private func previousTotals(_ app: UsageApp) -> UsageTotals {
        guard let bounds = previousRangeBounds else { return .zero }
        let buckets = appState.usageService.aggregator.snapshot()
            .filter { $0.app == app && $0.day >= bounds.from && $0.day < bounds.to }
        var t = UsageTotals.zero
        for b in buckets { t.add(b) }
        return t
    }

    private func deltaPercent(current: Double, previous: Double) -> Double? {
        guard previousRangeBounds != nil else { return nil }
        guard previous > 0 else { return nil }
        return ((current - previous) / previous) * 100
    }

    private var dailySamples: [DailySample] {
        var byDay: [Date: (codex: Decimal, claude: Decimal)] = [:]
        for b in filteredBuckets {
            var pair = byDay[b.day] ?? (0, 0)
            switch b.app {
            case .codex: pair.codex += b.costUSD
            case .claude: pair.claude += b.costUSD
            }
            byDay[b.day] = pair
        }
        return byDay
            .map { DailySample(day: $0.key, codexCost: $0.value.codex, claudeCost: $0.value.claude) }
            .sorted { $0.day < $1.day }
    }

    private func modelRows(for app: UsageApp) -> [ModelRow] {
        var byModel: [String: UsageTotals] = [:]
        for b in filteredBuckets where b.app == app {
            var t = byModel[b.model] ?? .zero
            t.add(b)
            byModel[b.model] = t
        }
        return byModel
            .map { ModelRow(model: $0.key, totals: $0.value) }
            .sorted { $0.totals.costUSD > $1.totals.costUSD }
    }

    private func placeholderHeight(_ height: CGFloat, message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
}

// MARK: - Panel container

private struct Panel<Content: View>: View {
    let title: String
    let chinese: String
    var right: AnyView? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr(title, chinese))
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                if let right { right }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ccPanel(cornerRadius: 12)
    }
}

private struct LegendChip: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            ServiceMark(color: color, size: 9)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - KPI card

private struct KPICard: View {
    let english: String
    let chinese: String
    let value: String
    let delta: Double?
    let tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let tint {
                    ServiceMark(color: tint, size: 6, cornerRadius: 1.5)
                }
                Text(tr(english, chinese))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold))
                    .kerning(-0.5)
                    .monospacedDigit()
                    .foregroundStyle(tint ?? .primary)
                if let delta {
                    Text(formatDelta(delta))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(delta >= 0 ? Color.red : Color.green)
                }
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ccPanel(cornerRadius: 10)
    }

    private func formatDelta(_ value: Double) -> String {
        let arrow = value >= 0 ? "↑" : "↓"
        let abs = Swift.abs(value)
        return "\(arrow) \(String(format: "%.1f", abs))%"
    }
}

// MARK: - By service row

private struct ByServiceRow: View {
    let title: String
    let subtitle: String
    let tint: Color
    let value: Decimal
    let totalValue: Decimal
    let tokens: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                ServiceMark(color: tint, size: 8)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(StatsFormatter.cost(value))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
            ProgressBar(value: ratio, tint: tint, height: 5)
                .padding(.leading, 16)
            HStack {
                Text("\(StatsFormatter.compactToken(tokens)) Tokens")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((ratio * 100).rounded()))% \(tr("of spend", "占比"))")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 16)
        }
        .padding(.vertical, 8)
    }

    private var ratio: Double {
        guard totalValue > 0 else { return 0 }
        let n = NSDecimalNumber(decimal: value).doubleValue
        let d = NSDecimalNumber(decimal: totalValue).doubleValue
        guard d > 0 else { return 0 }
        return n / d
    }
}

// MARK: - Limit ring row

private struct LimitRingRow: View {
    let label: String
    let window: QuotaWindow?
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            ProgressRing(
                value: (window?.remainingPercent ?? 0) / 100,
                tint: ringColor,
                diameter: 32,
                stroke: 4
            ) {
                Text(percentText)
                    .font(.system(size: 9.5, weight: .semibold))
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Text(resetText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(.vertical, 7)
    }

    private var ringColor: Color {
        guard window != nil else { return .secondary }
        return statusColor(remainingPercent: window?.remainingPercent, tint: tint)
    }

    private var percentText: String {
        guard let window else { return "--" }
        return "\(Int(window.remainingPercent.rounded()))"
    }

    private var resetText: String {
        formatResetHint(window?.resetsAt)
    }
}

// MARK: - Daily / Model row models

private struct DailySample: Identifiable {
    var id: Date { day }
    let day: Date
    let codexCost: Decimal
    let claudeCost: Decimal
}

private struct ModelRow: Identifiable {
    var id: String { model }
    let model: String
    let totals: UsageTotals
}

// MARK: - Formatter

enum StatsFormatter {
    static func cost(_ value: Decimal) -> String {
        let ns = NSDecimalNumber(decimal: value)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US_POSIX")
        f.groupingSeparator = ","
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return "$\(f.string(from: ns) ?? "0.00")"
    }

    static func token(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US_POSIX")
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// 紧凑显示。中文用 万 / 亿,英文用 k / M / B。
    /// zh:  6772.37 万  /  1.23 亿  /  1,234
    /// en:  67.7M  /  248.3k  /  1,234
    @MainActor
    static func compactToken(_ value: Int) -> String {
        let v = Double(value)
        switch L10n.current {
        case .zh:
            if v >= 100_000_000 {
                return "\(trimTrailingZeros(v / 100_000_000)) 亿"
            }
            if v >= 10_000 {
                return "\(trimTrailingZeros(v / 10_000)) 万"
            }
            return token(value)
        case .en:
            if v >= 1_000_000_000 {
                return String(format: "%.2fB", v / 1_000_000_000)
            }
            if v >= 1_000_000 {
                return String(format: "%.2fM", v / 1_000_000)
            }
            if v >= 1_000 {
                return String(format: "%.1fk", v / 1_000)
            }
            return "\(value)"
        }
    }

    /// 保留两位小数,去掉末尾多余的 0(如 6772.30 → 6772.3,1234.00 → 1234)。
    private static func trimTrailingZeros(_ value: Double) -> String {
        let s = String(format: "%.2f", value)
        var trimmed = s
        if trimmed.contains(".") {
            while trimmed.hasSuffix("0") { trimmed.removeLast() }
            if trimmed.hasSuffix(".") { trimmed.removeLast() }
        }
        return trimmed
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }
}

// MARK: - Decimal helper

private extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
