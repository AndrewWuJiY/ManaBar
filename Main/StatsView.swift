import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

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
    case cursor

    var englishLabel: String {
        switch self {
        case .all: return "All"
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .cursor: return "Cursor"
        }
    }

    var chineseLabel: String {
        switch self {
        case .all: return "全部"
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .cursor: return "Cursor"
        }
    }

    var tint: Color? {
        switch self {
        case .all: return nil
        case .codex: return .codexAccent
        case .claude: return .claudeAccent
        case .cursor: return .cursorAccent
        }
    }
}

enum StatsViewMode: Hashable {
    case overview
    case timeline
    case breakdown
}

// MARK: - Breakdown sort

/// 明细表可排序列。
enum BreakdownColumn: Hashable {
    case date
    case service
    case model
    case input
    case cacheRead
    case cacheWrite
    case output
    case total
    case cost
}

// MARK: - StatsView

struct StatsView: View {
    @Environment(AppState.self) private var appState
    @State private var range: StatsRange = .today
    @State private var serviceFilter: StatsServiceFilter = .all
    @State private var viewMode: StatsViewMode = .overview
    @State private var customFrom: Date = Calendar.current.startOfDay(
        for: Date().addingTimeInterval(-7 * 86400)
    )
    @State private var customTo: Date = Calendar.current.startOfDay(for: Date())
    @State private var breakdownSortColumn: BreakdownColumn = .date
    @State private var breakdownSortAscending: Bool = false

    var body: some View {
        let settings = SettingsStore.shared
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)

            Divider()

            VStack(spacing: 0) {
                statsToolbar
                if range == .custom {
                    customRangeRow
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) { Divider() }
                }
                ScrollView {
                    mainContent
                }
            }
        }
        .onChange(of: settings.showCodex) { _, on in
            if !on, serviceFilter == .codex { serviceFilter = .all }
        }
        .onChange(of: settings.showClaude) { _, on in
            if !on, serviceFilter == .claude { serviceFilter = .all }
        }
        .onChange(of: settings.showCursor) { _, on in
            if !on, serviceFilter == .cursor { serviceFilter = .all }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch viewMode {
        case .overview:
            overviewContent
        case .timeline:
            timelineContent
        case .breakdown:
            breakdownContent
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            if visibleQuotaFilters.isEmpty {
                placeholderHeight(220, message: tr("No services enabled", "未启用任何服务"))
                    .ccPanel(cornerRadius: 12)
            } else {
                quotaSection
                if spendApps.isEmpty {
                    cursorSpendEmpty
                } else {
                    usageSection
                }
            }
        }
        .padding(20)
    }

    private var timelineContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            timelineHeader
            if showHistoryStartNote { historyStartNote }
            if timelineSections.isEmpty && !showsCursorHistoryNote {
                placeholderHeight(220, message: tr("No accounts", "暂无账号"))
                    .ccPanel(cornerRadius: 12)
            } else {
                ForEach(timelineSections) { section in
                    QuotaTimelineAccountPanel(section: section)
                }
                if showsCursorHistoryNote {
                    cursorHistoryNote
                }
            }
        }
        .padding(20)
    }

    // MARK: Breakdown

    private var breakdownContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if serviceFilter == .cursor {
                placeholderHeight(
                    220,
                    message: tr(
                        "Cursor has no local session logs",
                        "Cursor 没有本地会话日志，花费明细只来自 Codex 和 Claude Code"
                    )
                )
                .ccPanel(cornerRadius: 12)
            } else {
            localSpendNote
            VStack(alignment: .leading, spacing: 0) {
                if breakdownRows.isEmpty {
                    placeholderHeight(220, message: tr("No data", "无数据"))
                } else {
                    breakdownTable
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ccPanel(cornerRadius: 12)
            }
        }
        .padding(20)
    }

    private var breakdownTable: some View {
        VStack(spacing: 0) {
            breakdownHeaderRow
            ForEach(breakdownRows) { row in
                Divider()
                breakdownRowView(row.bucket)
            }
            Divider().overlay(Color.secondary.opacity(0.28))
            breakdownFooterRow
        }
    }

    private var breakdownHeaderRow: some View {
        HStack(spacing: 0) {
            breakdownHeader("Date", "日期", column: .date, width: 92, alignment: .leading)
            breakdownHeader("Service", "服务", column: .service, width: 90, alignment: .leading)
            breakdownHeader("Model", "模型", column: .model, width: nil, alignment: .leading)
            breakdownHeader("In", "输入", column: .input, width: 72, alignment: .trailing)
            breakdownHeader("Cache R", "缓存读", column: .cacheRead, width: 84, alignment: .trailing)
            breakdownHeader("Cache W", "缓存写", column: .cacheWrite, width: 84, alignment: .trailing)
            breakdownHeader("Out", "输出", column: .output, width: 72, alignment: .trailing)
            breakdownHeader("Total", "总计", column: .total, width: 84, alignment: .trailing)
            breakdownHeader("Cost", "花费", column: .cost, width: 92, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func breakdownHeader(
        _ english: String,
        _ chinese: String,
        column: BreakdownColumn,
        width: CGFloat?,
        alignment: Alignment
    ) -> some View {
        let trailing = alignment == .trailing
        return Button {
            if breakdownSortColumn == column {
                breakdownSortAscending.toggle()
            } else {
                breakdownSortColumn = column
                breakdownSortAscending = false
            }
        } label: {
            HStack(spacing: 3) {
                if trailing { Spacer(minLength: 0) }
                Text(tr(english, chinese))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(breakdownSortColumn == column ? Color.primary : .secondary)
                if breakdownSortColumn == column {
                    Image(systemName: breakdownSortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                if !trailing { Spacer(minLength: 0) }
            }
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
            .frame(width: width, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func breakdownRowView(_ bucket: UsageBucket) -> some View {
        HStack(spacing: 0) {
            Text(StatsFormatter.day(bucket.day))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 92, alignment: .leading)

            HStack(spacing: 5) {
                ServiceMark(color: bucket.app == .codex ? .codexAccent : .claudeAccent, size: 7)
                Text(bucket.app == .codex ? "Codex" : "Claude")
                    .font(.system(size: 11.5))
                Spacer(minLength: 0)
            }
            .frame(width: 90, alignment: .leading)

            Text(bucket.model)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            breakdownTokenCell(bucket.inputTokens, width: 72)
            breakdownTokenCell(bucket.cacheReadTokens, width: 84)
            breakdownTokenCell(bucket.cacheCreationTokens, width: 84)
            breakdownTokenCell(bucket.outputTokens, width: 72)
            breakdownTokenCell(bucket.breakdownTotalTokens, width: 84)

            let priced = Pricing.hasPrice(model: bucket.model)
            Text(priced ? StatsFormatter.cost(bucket.costUSD) : StatsFormatter.unpriced)
                .font(.system(size: 11.5, weight: priced ? .semibold : .regular, design: priced ? .monospaced : .default))
                .foregroundStyle(priced ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
                .frame(width: 92, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func breakdownTokenCell(_ value: Int, width: CGFloat) -> some View {
        Text(StatsFormatter.compactToken(value))
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .trailing)
    }

    private var breakdownFooterRow: some View {
        let totals = currentTotalsAll
        return HStack(spacing: 0) {
            Text("\(tr("Total", "合计")) · \(breakdownRows.count) \(tr("rows", "行"))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 182, alignment: .leading)
            Spacer(minLength: 0)
            breakdownTokenCell(totals.inputTokens, width: 72)
            breakdownTokenCell(totals.cacheReadTokens, width: 84)
            breakdownTokenCell(totals.cacheCreationTokens, width: 84)
            breakdownTokenCell(totals.outputTokens, width: 72)
            breakdownTokenCell(totals.totalTokens, width: 84)
            Text(StatsFormatter.cost(totals.costUSD))
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 92, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// 当前筛选(区间 + 服务)下的 bucket 行,按选中列排序。
    private var breakdownRows: [BreakdownRow] {
        let asc = breakdownSortAscending
        func cmp<T: Comparable>(_ a: T, _ b: T) -> Bool { asc ? a < b : a > b }

        let sorted = filteredBuckets.sorted { a, b in
            switch breakdownSortColumn {
            case .date:
                if a.day != b.day { return cmp(a.day, b.day) }
            case .service:
                if a.app != b.app { return cmp(appOrder(a.app), appOrder(b.app)) }
            case .model:
                if a.model != b.model { return cmp(a.model, b.model) }
            case .input:
                if a.inputTokens != b.inputTokens { return cmp(a.inputTokens, b.inputTokens) }
            case .cacheRead:
                if a.cacheReadTokens != b.cacheReadTokens { return cmp(a.cacheReadTokens, b.cacheReadTokens) }
            case .cacheWrite:
                if a.cacheCreationTokens != b.cacheCreationTokens { return cmp(a.cacheCreationTokens, b.cacheCreationTokens) }
            case .output:
                if a.outputTokens != b.outputTokens { return cmp(a.outputTokens, b.outputTokens) }
            case .total:
                if a.breakdownTotalTokens != b.breakdownTotalTokens { return cmp(a.breakdownTotalTokens, b.breakdownTotalTokens) }
            case .cost:
                if a.costUSD != b.costUSD { return cmp(a.costUSD, b.costUSD) }
            }
            // 同值兜底:日期降序 → Codex 先于 Claude → 花费降序。
            if a.day != b.day { return a.day > b.day }
            if a.app != b.app { return appOrder(a.app) < appOrder(b.app) }
            return a.costUSD > b.costUSD
        }
        return sorted.map { BreakdownRow(bucket: $0) }
    }

    /// Codex 永远排在 Claude 前(项目规则)。
    private func appOrder(_ app: UsageApp) -> Int {
        app == .codex ? 0 : 1
    }

    private func exportBreakdownCSV() {
        let rows = breakdownRows
        guard !rows.isEmpty else { return }

        var csv = "date,service,model,input,cache_read,cache_write,output,total,cost_usd\n"
        for row in rows {
            let b = row.bucket
            let service = b.app == .codex ? "Codex" : "Claude"
            let model = "\"\(b.model.replacingOccurrences(of: "\"", with: "\"\""))\""
            csv += "\(StatsFormatter.day(b.day)),\(service),\(model),"
            csv += "\(b.inputTokens),\(b.cacheReadTokens),\(b.cacheCreationTokens),"
            csv += "\(b.outputTokens),\(b.breakdownTotalTokens),\(b.costUSD.asPlainString)\n"
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "manabar-usage-\(StatsFormatter.day(Date())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? csv.data(using: .utf8)?.write(to: url)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            sidebarGroup(title: "Service", chinese: "服务") {
                sidebarItem(
                    english: "All",
                    chinese: "全部",
                    active: serviceFilter == .all
                ) {
                    serviceFilter = .all
                }
                ForEach(enabledFilters, id: \.self) { item in
                    sidebarItem(
                        english: item.englishLabel,
                        chinese: item.chineseLabel,
                        tint: item.tint,
                        trailing: sidebarPercent(item),
                        active: serviceFilter == item
                    ) {
                        serviceFilter = item
                    }
                }
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
        trailing: String? = nil,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let tint {
                    ServiceMark(color: active ? .white : tint, size: 8)
                        .frame(width: 13, height: 13, alignment: .center)
                } else {
                    Color.clear.frame(width: 13, height: 13)
                }

                Text(tr(english, chinese))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(active ? Color.white : Color.primary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                if let trailing {
                    Text(trailing)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(active ? Color.white.opacity(0.88) : Color.secondary)
                }
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

    // MARK: Toolbar

    private var statsToolbar: some View {
        HStack(spacing: 8) {
            Picker("", selection: $viewMode) {
                Text(tr("Overview", "概览")).tag(StatsViewMode.overview)
                Text(tr("Timeline", "时间轴")).tag(StatsViewMode.timeline)
                Text(tr("Breakdown", "明细")).tag(StatsViewMode.breakdown)
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Spacer(minLength: 12)

            if viewMode == .breakdown {
                Button(action: exportBreakdownCSV) {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.down")
                        Text(tr("Export CSV", "导出 CSV"))
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(breakdownRows.isEmpty || serviceFilter == .cursor)
                .pointingHandCursor()
            }

            Picker("", selection: $range) {
                ForEach(StatsRange.allCases, id: \.self) { item in
                    Text(tr(item.englishLabel, item.chineseLabel)).tag(item)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Claude 花费统计本机 CLI + 桌面 App 会话,网页/移动端消耗只反映在额度环、不计入花费。
    /// 放在「本地用量」标题下。不用 hover(`.help()` 在 .accessory 应用里仍不稳)。
    private var localSpendNote: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle")
                .font(.system(size: 10.5))
            Text(tr(
                "Claude spend counts local CLI + desktop app sessions; web / mobile usage shows in the quota, not here",
                "Claude 花费统计本机 CLI 与桌面 App 会话;网页 / 移动端消耗见额度环、不计入"
            ))
            .font(.system(size: 11))
        }
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
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

    // MARK: Overview

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: tr("Current quota", "当前额度"),
                subtitle: tr(
                    "Live remaining. It does not follow the date range. Click a card to focus that service.",
                    "实时剩余，不跟下面的日期走。点一张卡片只看这个服务。"
                )
            )
            quotaGrid
        }
    }

    @ViewBuilder
    private var quotaGrid: some View {
        let items = visibleQuotaFilters
        if items.count <= 1, let only = items.first {
            quotaCard(only)
                .frame(maxWidth: 380, alignment: .leading)
        } else {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
                    count: max(items.count, 1)
                ),
                spacing: 12
            ) {
                ForEach(items, id: \.self) { item in
                    quotaCard(item)
                }
            }
        }
    }

    private func quotaCard(_ filter: StatsServiceFilter) -> QuotaHeroCard {
        switch filter {
        case .codex:
            return standardQuotaCard(
                filter: .codex,
                snapshot: appState.codexQuota,
                title: "Codex",
                plan: accountPlan(appState.codexAccount?.planType),
                logoName: "codex",
                fallback: "C",
                tint: .codexAccent
            )
        case .claude:
            return standardQuotaCard(
                filter: .claude,
                snapshot: appState.claudeQuota,
                title: "Claude Code",
                plan: accountPlan(appState.claudeAccount?.subscriptionType),
                logoName: "claude",
                fallback: "K",
                tint: .claudeAccent
            )
        case .cursor:
            return cursorQuotaCard()
        case .all:
            return cursorQuotaCard()
        }
    }

    private func standardQuotaCard(
        filter: StatsServiceFilter,
        snapshot: QuotaSnapshot?,
        title: String,
        plan: String,
        logoName: String,
        fallback: String,
        tint: Color
    ) -> QuotaHeroCard {
        let unlimited = snapshot?.fiveHourUnlimited == true
        let primary = snapshot?.monitoredWindow()
        let weekly = unlimited ? nil : snapshot?.displayWeekly()
        let windowLabel = unlimited
            ? tr("Weekly · no 5h cap", "周额度 · 无 5 小时限制")
            : tr("5 hours", "5 小时")
        let reset = primary.map { formatResetHint($0.resetsAt) }
            ?? tr("Shown after refresh", "刷新后显示")
        return QuotaHeroCard(
            title: title,
            plan: plan,
            logoName: logoName,
            fallback: fallback,
            tint: tint,
            windowLabel: windowLabel,
            resetText: reset,
            remaining: primary?.remainingPercent,
            weeklyRemaining: weekly?.remainingPercent,
            weeklyLabel: weekly == nil ? nil : tr("Weekly", "周额度"),
            action: { focus(filter) }
        )
    }

    private func cursorQuotaCard() -> QuotaHeroCard {
        let cycle = appState.cursorQuota?.displayBillingCycle()
        let onDemand = appState.cursorQuota?.displayOnDemand()
        let unsupported = cursorUnsupported
        return QuotaHeroCard(
            title: "Cursor",
            plan: cursorPlanLine,
            logoName: "cursor",
            fallback: "R",
            tint: .cursorAccent,
            logoSize: 11,
            windowLabel: unsupported ? tr("Unsupported", "暂不支持") : tr("Billing cycle", "账期"),
            resetText: cycle.map { formatResetHint($0.resetsAt) }
                ?? tr("Shown here after a refresh", "查询后显示在这里"),
            remaining: cycle?.remainingPercent,
            extraRemaining: onDemand?.remainingPercent,
            extraLabel: onDemand == nil ? nil : tr("On-demand left", "按量剩余"),
            action: { focus(.cursor) }
        )
    }

    private var cursorSpendEmpty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("Cursor has no local usage", "Cursor 没有本地用量"))
                .font(.system(size: 13, weight: .semibold))
            Text(tr(
                "The billing cycle is above. This page does not count its spend, and there is no per-model breakdown.",
                "账期剩余就在上面。这里不统计它的花费，也没有按模型的明细。"
            ))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ccPanel(cornerRadius: 12)
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: tr("Local usage", "本地用量"),
                subtitle: usageSubtitle
            )
            localSpendNote
                .padding(.bottom, 4)
            metricStrip
            compositionCard
                .padding(.top, 4)
        }
    }

    private var metricStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(metricItems.enumerated()), id: \.element.id) { index, item in
                metricCell(label: item.label, value: item.value, delta: item.delta)
                    .overlay(alignment: .leading) {
                        if index > 0 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.12))
                                .frame(width: 0.5)
                        }
                    }
            }
        }
        .ccPanel(cornerRadius: 12)
    }

    private func metricCell(label: String, value: String, delta: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .kerning(-0.4)
                .monospacedDigit()
                .foregroundStyle(.primary)
            if let delta {
                Text(formatSpendDelta(delta))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(delta > 0 ? Color.green : Color.red)
            } else {
                Color.clear.frame(height: 14)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compositionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tr("Composition", "构成"))
                .font(.system(size: 13, weight: .semibold))
            Text(dailySamples.count < 2
                 ? tr("Spend share for this range.", "这个范围的花费占比。")
                 : tr("Stacked by day. Codex on the bottom, Claude Code on top.", "按天堆叠，Codex 在下，Claude Code 在上。"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 3)
                .padding(.bottom, 12)

            shareBar
            shareLegend
                .padding(.top, 10)

            if dailySamples.count > 1 {
                DailyUsageChart(samples: dailySamples)
                    .frame(height: 160)
                    .padding(.top, 6)
            }

            compositionModels
                .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ccPanel(cornerRadius: 12)
    }

    private var shareBar: some View {
        let parts = spendShares
        let total = parts.reduce(0) { $0 + $1.value }
        return Group {
            if total <= 0 {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 10)
            } else {
                GeometryReader { proxy in
                    let gaps = CGFloat(max(parts.count - 1, 0)) * 3
                    let usable = max(0, proxy.size.width - gaps)
                    HStack(spacing: 3) {
                        ForEach(parts, id: \.app) { part in
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(part.app == .codex ? Color.codexAccent : Color.claudeAccent)
                                .frame(width: max(6, usable * CGFloat(part.value / total)))
                        }
                    }
                }
                .frame(height: 10)
            }
        }
    }

    private var shareLegend: some View {
        let parts = spendShares
        let total = parts.reduce(0) { $0 + $1.value }
        return HStack(spacing: 16) {
            ForEach(parts, id: \.app) { part in
                let pct = total > 0 ? Int((part.value / total * 100).rounded()) : 0
                HStack(spacing: 6) {
                    ServiceMark(
                        color: part.app == .codex ? .codexAccent : .claudeAccent,
                        size: 8
                    )
                    Text(part.app == .codex ? "Codex" : "Claude Code")
                    Text(StatsFormatter.cost(currentTotals(part.app).costUSD))
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text("· \(pct)%")
                        .monospacedDigit()
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var compositionModels: some View {
        VStack(spacing: 0) {
            if spendModelRows.isEmpty {
                VStack(spacing: 4) {
                    Text(tr("No usage in this range", "这个范围没有用量"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(tr("Try another date, or confirm the service is enabled.", "换一个日期，或确认服务已经打开。"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ForEach(Array(spendModelRows.enumerated()), id: \.element.id) { index, row in
                    VStack(spacing: 0) {
                    if index > 0 { Divider() }
                    HStack(spacing: 10) {
                        ServiceMark(
                            color: row.app == .codex ? .codexAccent : .claudeAccent,
                            size: 8
                        )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.model)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Text("\(tr("in", "入")) \(StatsFormatter.compactToken(row.totals.inputWithCacheTokens)) · \(tr("out", "出")) \(StatsFormatter.compactToken(row.totals.outputTokens))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Spacer(minLength: 8)
                        let priced = Pricing.hasPrice(model: row.model)
                        Text(priced ? StatsFormatter.cost(row.totals.costUSD) : StatsFormatter.unpriced)
                            .font(.system(size: 13, weight: priced ? .semibold : .regular))
                            .foregroundStyle(priced ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 10)
                    }
                }
            }
        }
        .overlay(alignment: .top) { Divider() }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }

    // MARK: Timeline

    private var timelineHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("Quota changes", "额度变化"))
                    .font(.system(size: 18, weight: .semibold))
                Text(tr(
                    "Only quota changes are shown. 5H window is tracked when available, weekly otherwise.",
                    "仅展示额度发生变化的时间点。有 5H 额度时监测 5H,否则监测周额度。"
                ))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(timelineDateLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var timelineDateLabel: String {
        if range == .all { return tr("All time", "全部") }
        let (from, to) = rangeBounds
        let fromStr = StatsFormatter.day(from)
        let toStr = StatsFormatter.day(to.addingTimeInterval(-1))
        return fromStr == toStr ? fromStr : "\(fromStr) ~ \(toStr)"
    }

    /// 额度历史里最早一条事件的时间(跨天留存从改动当天才开始累积)。
    private var earliestHistoryDate: Date? {
        appState.quotaHistory.events.map(\.sampledAt).min()
    }

    /// 选中区间起点早于已记录的最早一天时,提示"更早还没有数据",避免误以为筛选失灵。
    private var showHistoryStartNote: Bool {
        guard range != .today, let earliest = earliestHistoryDate else { return false }
        return rangeBounds.from < Calendar.current.startOfDay(for: earliest)
    }

    private var historyStartNote: some View {
        let dateStr = earliestHistoryDate.map(StatsFormatter.day) ?? ""
        return HStack(spacing: 4) {
            Image(systemName: "info.circle")
                .font(.system(size: 10.5))
            Text(tr(
                "Quota history starts \(dateStr); earlier data isn't recorded yet",
                "额度历史从 \(dateStr) 起记录;更早暂无数据"
            ))
            .font(.system(size: 11))
        }
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var showsCursorHistoryNote: Bool {
        guard settingsStore.showCursor else { return false }
        return serviceFilter == .all || serviceFilter == .cursor
    }

    private var cursorHistoryNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("Cursor does not keep quota history", "Cursor 不记录额度历史"))
                .font(.system(size: 13, weight: .semibold))
            Text(tr(
                "This view keeps Codex and Claude Code window changes. Use the current billing cycle for Cursor.",
                "这里只保留 Codex 和 Claude Code 的窗口变化。Cursor 看当前账期即可。"
            ))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ccPanel(cornerRadius: 12)
    }

    private var timelineSections: [QuotaTimelineSection] {
        var sections: [QuotaTimelineSection] = []

        if serviceFilter != .claude && serviceFilter != .cursor && settingsStore.showCodex {
            let key = QuotaHistoryAccountKey.codexPrimary(accountId: appState.codexAccount?.accountId)
            if shouldShowTimelineSection(key: key, snapshot: appState.codexQuota, accountExists: appState.codexAccount != nil) {
                sections.append(timelineSection(
                    key: key,
                    title: tr("Codex · Primary", "Codex · 主账号"),
                    tint: .codexAccent,
                    snapshot: appState.codexQuota
                ))
            }

            for (idx, account) in appState.importedCodexAccounts.enumerated() {
                let key = QuotaHistoryAccountKey.codexImported(id: account.id)
                sections.append(timelineSection(
                    key: key,
                    title: importedCodexTimelineTitle(account, index: idx),
                    tint: .codexAccent,
                    snapshot: appState.importedCodexQuota(for: account)
                ))
            }
        }

        if serviceFilter != .codex && serviceFilter != .cursor && settingsStore.showClaude {
            let key = QuotaHistoryAccountKey.claudePrimary()
            if shouldShowTimelineSection(key: key, snapshot: appState.claudeQuota, accountExists: appState.claudeAccount != nil) {
                sections.append(timelineSection(
                    key: key,
                    title: "Claude Code",
                    tint: .claudeAccent,
                    snapshot: appState.claudeQuota
                ))
            }
        }

        return sections
    }

    private func timelineSection(
        key: String,
        title: String,
        tint: Color,
        snapshot: QuotaSnapshot?
    ) -> QuotaTimelineSection {
        let events = timelineEvents(for: key)
        let sample = appState.quotaHistory.lastSamples[key]
        return QuotaTimelineSection(
            accountKey: key,
            title: title,
            tint: tint,
            window: sample?.windowKind ?? events.last?.windowKind ?? trackedWindowKind(snapshot),
            currentRemaining: sample?.remainingPercent ?? roundedRemaining(snapshot),
            totalDelta: events.reduce(0) { $0 + $1.deltaPercent },
            latestEventAt: events.last?.sampledAt,
            events: events
        )
    }

    /// 当前快照会被记录的窗口类型:5H 优先,无则周(与 QuotaHistoryStore.record 一致)。
    private func trackedWindowKind(_ snapshot: QuotaSnapshot?) -> QuotaHistoryWindowKind? {
        guard let snapshot else { return nil }
        if snapshot.fiveHour != nil { return .fiveHour }
        if snapshot.weekly != nil { return .weekly }
        return nil
    }

    private func shouldShowTimelineSection(key: String, snapshot: QuotaSnapshot?, accountExists: Bool) -> Bool {
        accountExists || snapshot != nil || appState.quotaHistory.lastSamples[key] != nil || !timelineEvents(for: key).isEmpty
    }

    private func timelineEvents(for key: String) -> [QuotaChangeEvent] {
        let (from, to) = rangeBounds
        return appState.quotaHistory.events
            .filter { $0.accountKey == key && $0.sampledAt >= from && $0.sampledAt < to }
            .sorted { $0.sampledAt < $1.sampledAt }
    }

    private func roundedRemaining(_ snapshot: QuotaSnapshot?) -> Int? {
        // 与记录逻辑一致:5H 优先,无 5H 窗口时回退周额度。
        guard let remaining = snapshot?.fiveHour?.remainingPercent
            ?? snapshot?.weekly?.remainingPercent else { return nil }
        return max(0, min(100, Int(remaining.rounded())))
    }

    private func importedCodexTimelineTitle(_ account: ImportedCodexAccount, index: Int) -> String {
        if SettingsStore.shared.privacyMode {
            return tr("Codex · Account \(index + 1)", "Codex · 账号 \(index + 1)")
        }
        if !account.alias.isEmpty { return "Codex · \(account.alias)" }
        if let email = account.email, !email.isEmpty {
            return "Codex · \(email.components(separatedBy: "@").first ?? email)"
        }
        return "Codex · \(account.id)"
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
                        let priced = Pricing.hasPrice(model: row.model)
                        Text(priced ? StatsFormatter.cost(row.totals.costUSD) : StatsFormatter.unpriced)
                            .font(.system(size: 12.5, weight: priced ? .semibold : .regular))
                            .foregroundStyle(priced ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
                            .monospacedDigit()
                            .frame(width: 96, alignment: .trailing)
                    }
                    .padding(.leading, 12)
                }
            }
        }
    }

    // MARK: Data helpers

    private var settingsStore: SettingsStore { SettingsStore.shared }

    private var enabledFilters: [StatsServiceFilter] {
        var items: [StatsServiceFilter] = []
        if settingsStore.showCodex { items.append(.codex) }
        if settingsStore.showClaude { items.append(.claude) }
        if settingsStore.showCursor { items.append(.cursor) }
        return items
    }

    private var visibleQuotaFilters: [StatsServiceFilter] {
        switch serviceFilter {
        case .all:
            return enabledFilters
        default:
            return enabledFilters.contains(serviceFilter) ? [serviceFilter] : []
        }
    }

    private var spendApps: [UsageApp] {
        visibleQuotaFilters.compactMap { filter in
            switch filter {
            case .codex: return .codex
            case .claude: return .claude
            case .all, .cursor: return nil
            }
        }
    }

    private func sidebarPercent(_ filter: StatsServiceFilter) -> String {
        let snapshot: QuotaSnapshot?
        switch filter {
        case .all:
            return ""
        case .codex:
            snapshot = appState.codexQuota
        case .claude:
            snapshot = appState.claudeQuota
        case .cursor:
            snapshot = appState.cursorQuota
        }
        guard let window = snapshot?.monitoredWindow() else { return "—" }
        return "\(Int(window.remainingPercent.rounded()))%"
    }

    private func focus(_ filter: StatsServiceFilter) {
        serviceFilter = serviceFilter == filter ? .all : filter
    }

    private func accountPlan(_ raw: String?) -> String {
        if let raw, !raw.isEmpty { return raw }
        return tr("This Mac", "本机账号")
    }

    private var cursorUnsupported: Bool {
        guard appState.cursorQuota?.displayBillingCycle() == nil else { return false }
        let error = appState.cursorQuotaError ?? ""
        return error.contains("暂不支持")
            || error.localizedCaseInsensitiveContains("unsupported")
            || error.contains("没有个人")
    }

    private var cursorPlanLine: String {
        if appState.cursorQuota?.displayBillingCycle() != nil {
            return accountPlan(appState.cursorAccount?.planType)
        }
        if let error = appState.cursorQuotaError, !error.isEmpty {
            return error
        }
        if appState.cursorAccount?.accessToken?.isEmpty == false {
            return tr("Signed in. Quota hasn't come back yet.", "已登录，额度尚未返回")
        }
        return tr("Not detected", "未识别")
    }

    private var usageSubtitle: String {
        let rangeName = tr(range.englishLabel, range.chineseLabel)
        if range == .thisWeek, dailySamples.count <= 1 {
            return "\(rangeName) · \(tr("The week starts on Monday. Only one day has usage so far.", "本周从周一开始，目前只有一天有用量。"))"
        }
        return "\(rangeName) · \(tr("Local logs, summed by day. Cursor is not included.", "本机日志按天汇总。Cursor 不计入。"))"
    }

    private func formatSpendDelta(_ value: Double) -> String {
        let arrow = value > 0 ? "↑" : "↓"
        return "\(arrow) \(String(format: "%.1f", Swift.abs(value)))%"
    }

    private var metricItems: [MetricItem] {
        var items: [MetricItem] = [
            MetricItem(
                id: "tokens",
                label: "Tokens",
                value: StatsFormatter.compactToken(currentTotalsAll.totalTokens),
                delta: deltaPercent(
                    current: Double(currentTotalsAll.totalTokens),
                    previous: Double(previousTotalsAll.totalTokens)
                )
            )
        ]
        if spendApps.count == 2 {
            items.append(MetricItem(
                id: "spend",
                label: tr("Spend", "花费"),
                value: StatsFormatter.cost(currentTotalsAll.costUSD),
                delta: deltaPercent(
                    current: currentTotalsAll.costUSD.doubleValue,
                    previous: previousTotalsAll.costUSD.doubleValue
                )
            ))
        }
        for app in spendApps {
            items.append(MetricItem(
                id: app.rawValue,
                label: app == .codex ? "Codex" : "Claude Code",
                value: StatsFormatter.cost(currentTotals(app).costUSD),
                delta: deltaPercent(
                    current: currentTotals(app).costUSD.doubleValue,
                    previous: previousTotals(app).costUSD.doubleValue
                )
            ))
        }
        return items
    }

    private var spendShares: [SpendShare] {
        spendApps.map { app in
            SpendShare(app: app, value: currentTotals(app).costUSD.doubleValue)
        }
    }

    private var spendModelRows: [SpendModelRow] {
        spendApps.flatMap { app in
            modelRows(for: app).map {
                SpendModelRow(app: app, model: $0.model, totals: $0.totals)
            }
        }
    }

    private var rangeBounds: (from: Date, to: Date) {
        range.bounds(customFrom: customFrom, customTo: customTo)
    }

    private var previousRangeBounds: (from: Date, to: Date)? {
        range.previousBounds(customFrom: customFrom, customTo: customTo)
    }

    private var filteredBuckets: [UsageBucket] {
        let (from, to) = rangeBounds
        let apps = Set(spendApps)
        return appState.usageService.aggregator.snapshot()
            .filter { $0.day >= from && $0.day < to && apps.contains($0.app) }
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
        let apps = Set(spendApps)
        let buckets = appState.usageService.aggregator.snapshot()
            .filter { $0.day >= bounds.from && $0.day < bounds.to && apps.contains($0.app) }
        var t = UsageTotals.zero
        for b in buckets { t.add(b) }
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

// MARK: - Overview models

private struct MetricItem: Identifiable {
    let id: String
    let label: String
    let value: String
    let delta: Double?
}

private struct SpendShare {
    let app: UsageApp
    let value: Double
}

private struct SpendModelRow: Identifiable {
    var id: String { "\(app.rawValue)|\(model)" }
    let app: UsageApp
    let model: String
    let totals: UsageTotals
}

private struct QuotaHeroCard: View {
    let title: String
    let plan: String
    let logoName: String
    let fallback: String
    let tint: Color
    var logoSize: CGFloat = 13
    let windowLabel: String
    let resetText: String
    let remaining: Double?
    var weeklyRemaining: Double? = nil
    var weeklyLabel: String? = nil
    var extraRemaining: Double? = nil
    var extraLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ServiceTile(
                        logoName: logoName,
                        fallback: fallback,
                        tint: tint,
                        size: 22,
                        logoSize: logoSize,
                        cornerRadius: 6
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(plan)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    ring
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(windowLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(resetText)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .lineLimit(2)
                }
                .padding(.top, 12)

                if let weeklyRemaining, let weeklyLabel {
                    meter(label: weeklyLabel, percent: weeklyRemaining)
                }
                if let extraRemaining, let extraLabel {
                    meter(label: extraLabel, percent: extraRemaining)
                }
                if weeklyLabel == nil && extraLabel == nil {
                    meter(label: " ", percent: 0)
                        .opacity(0)
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .ccPanel(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private var ring: some View {
        ProgressRing(value: (remaining ?? 0) / 100, tint: ringColor, diameter: 58, stroke: 5) {
            Text(remaining.map { "\(Int($0.rounded()))" } ?? "—")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    private var ringColor: Color {
        guard let remaining else { return Color.secondary.opacity(0.35) }
        if remaining > 50 { return tint }
        if remaining < 10 { return statusColor(remainingPercent: 0, tint: tint) }
        return statusColor(remainingPercent: remaining, tint: tint)
    }

    private func meter(label: String, percent: Double) -> some View {
        let color = statusColor(remainingPercent: percent, tint: tint)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(percent.rounded()))%")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
            ProgressBar(value: percent / 100, tint: color, height: 5)
        }
        .padding(.top, 12)
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
                        .foregroundStyle(delta > 0 ? Color.green : Color.red)
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
    /// 服务端未下发 5h 窗口(取消限制)时为 true,显示 ∞ + 满环
    var unlimited: Bool = false

    var body: some View {
        HStack(spacing: 11) {
            ProgressRing(
                value: unlimited ? 1 : (window?.remainingPercent ?? 0) / 100,
                tint: ringColor,
                diameter: 32,
                stroke: 4
            ) {
                Text(percentText)
                    .font(.system(size: 9.5, weight: .semibold))
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    ServiceMark(color: tint, size: 7)
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                }
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
        if unlimited { return tint }
        guard let remaining = window?.remainingPercent else { return .secondary }
        if remaining > 50 { return tint }
        if remaining < 10 { return statusColor(remainingPercent: 0, tint: tint) }
        return statusColor(remainingPercent: remaining, tint: tint)
    }

    private var percentText: String {
        if unlimited { return "∞" }
        guard let window else { return "--" }
        return "\(Int(window.remainingPercent.rounded()))"
    }

    private var resetText: String {
        if unlimited { return tr("No 5-hour limit", "无 5 小时限制") }
        return formatResetHint(window?.resetsAt)
    }
}

// MARK: - Quota timeline

private struct QuotaTimelineAccountPanel: View {
    let section: QuotaTimelineSection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if section.events.isEmpty {
                Text(tr("No changes in range", "该区间暂无变动"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
            } else {
                QuotaTimelineChart(events: section.events, tint: section.tint)
                    .frame(height: 180)
                QuotaTimelineTable(events: section.events)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ccPanel(cornerRadius: 12)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: 7) {
                ServiceMark(color: section.tint, size: 8)
                Text(section.title)
                    .font(.system(size: 13, weight: .semibold))
                if let label = windowLabel {
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule().fill(Color.secondary.opacity(0.12))
                        )
                }
            }
            Spacer()
            timelineMetric(label: tr("Current", "当前"), value: currentText)
            timelineMetric(
                label: tr("Net", "净变"),
                value: StatsFormatter.quotaDelta(section.totalDelta),
                valueColor: section.totalDelta < 0 ? .red : .green
            )
            timelineMetric(label: tr("Latest", "最近"), value: latestText)
        }
    }

    private func timelineMetric(label: String, value: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(valueColor)
        }
    }

    private var windowLabel: String? {
        switch section.window {
        case .fiveHour: return tr("5H", "5H")
        case .weekly: return tr("Weekly", "周")
        case nil: return nil
        }
    }

    private var currentText: String {
        guard let value = section.currentRemaining else { return "--" }
        return "\(value)%"
    }

    private var latestText: String {
        guard let date = section.latestEventAt else { return "--" }
        return Calendar.current.isDateInToday(date)
            ? StatsFormatter.time(date)
            : StatsFormatter.monthDayTime(date)
    }
}

private struct QuotaTimelineChart: View {
    let events: [QuotaChangeEvent]
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered: QuotaChangeEvent?

    /// 给 X 轴首尾各留约 4% padding,避免首点贴着 Y 轴标签、尾点贴着右缘。
    /// 单点(lo == hi)时给 ±5 分钟,防止 domain 退化。
    private var xDomain: ClosedRange<Date> {
        let dates = events.map(\.sampledAt)
        guard let lo = dates.min(), let hi = dates.max() else {
            let now = Date()
            return now.addingTimeInterval(-300)...now.addingTimeInterval(300)
        }
        guard lo < hi else {
            return lo.addingTimeInterval(-300)...lo.addingTimeInterval(300)
        }
        let pad = hi.timeIntervalSince(lo) * 0.04
        return lo.addingTimeInterval(-pad)...hi.addingTimeInterval(pad)
    }

    /// 跨天区间:X 轴与浮层显示日期而非纯时刻。
    private var multiDay: Bool {
        let dates = events.map(\.sampledAt)
        guard let lo = dates.min(), let hi = dates.max() else { return false }
        return !Calendar.current.isDate(lo, inSameDayAs: hi)
    }

    private var axisFormat: Date.FormatStyle {
        multiDay ? .dateTime.month(.abbreviated).day() : .dateTime.hour().minute()
    }

    var body: some View {
        Chart(events) { event in
            AreaMark(
                x: .value("Time", event.sampledAt),
                yStart: .value("Base", 0),
                yEnd: .value("Remaining", event.afterRemainingPercent)
            )
            .foregroundStyle(tint.opacity(0.12))
            .interpolationMethod(.linear)

            LineMark(
                x: .value("Time", event.sampledAt),
                y: .value("Remaining", event.afterRemainingPercent)
            )
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.linear)
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                    .foregroundStyle(.quaternary)
                AxisValueLabel(format: axisFormat)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.65))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 20, 50, 80, 100]) { value in
                AxisGridLine()
                    .foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text("\(intValue)%")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Color.primary.opacity(0.65))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let anchor = proxy.plotFrame {
                    let plot = geo[anchor]
                    ForEach(events) { event in
                        if let xPos = proxy.position(forX: event.sampledAt),
                           let yPos = proxy.position(forY: event.afterRemainingPercent) {
                            timelineDot
                                .position(x: plot.minX + xPos, y: plot.minY + yPos)
                        }
                    }
                }
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hovered = event(at: location, proxy: proxy, geo: geo)
                        case .ended:
                            hovered = nil
                        }
                    }
                if let hovered, let anchor = proxy.plotFrame,
                   let xPos = proxy.position(forX: hovered.sampledAt) {
                    let plot = geo[anchor]
                    let yPos = proxy.position(forY: hovered.afterRemainingPercent) ?? 0
                    ChartCallout(lines: calloutLines(hovered))
                        .position(
                            x: clampX(plot.minX + xPos, in: plot),
                            y: clampY(plot.minY + yPos - 30, in: plot)
                        )
                }
            }
        }
    }

    /// 样式稿的点:直径 6.4pt 的实心圆,1.5pt 卡片色描边,把点和折线、面积隔开。
    private var timelineDot: some View {
        Circle()
            .fill(tint)
            .frame(width: 6.4, height: 6.4)
            .overlay(Circle().stroke(dotRing, lineWidth: 1.5))
    }

    private var dotRing: Color {
        colorScheme == .dark ? Color(white: 0.22) : .white
    }

    private func event(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> QuotaChangeEvent? {
        guard let anchor = proxy.plotFrame else { return nil }
        let plot = geo[anchor]
        let xInPlot = location.x - plot.minX
        guard xInPlot >= 0, xInPlot <= plot.width else { return nil }
        guard let time: Date = proxy.value(atX: xInPlot, as: Date.self) else { return nil }
        return events.min {
            abs($0.sampledAt.timeIntervalSince(time)) < abs($1.sampledAt.timeIntervalSince(time))
        }
    }

    private func clampX(_ x: CGFloat, in plot: CGRect) -> CGFloat {
        min(max(x, plot.minX + 48), plot.maxX - 48)
    }

    private func clampY(_ y: CGFloat, in plot: CGRect) -> CGFloat {
        min(max(y, plot.minY + 22), plot.maxY - 22)
    }

    private func calloutLines(_ e: QuotaChangeEvent) -> [ChartCallout.Line] {
        let header = multiDay ? StatsFormatter.monthDayTime(e.sampledAt) : StatsFormatter.time(e.sampledAt)
        return [
            ChartCallout.Line(label: header, value: nil, color: nil),
            ChartCallout.Line(label: tr("Remaining", "剩余"), value: "\(e.afterRemainingPercent)%", color: nil),
            ChartCallout.Line(label: tr("Change", "变动"), value: StatsFormatter.quotaDelta(e.deltaPercent), color: nil)
        ]
    }
}

private struct QuotaTimelineTable: View {
    let events: [QuotaChangeEvent]

    private var rows: [QuotaChangeEvent] {
        events.sorted { $0.sampledAt > $1.sampledAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            ForEach(rows) { event in
                Divider()
                row(event)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 0.5)
        )
    }

    private var headerRow: some View {
        HStack {
            tableHeader("Time", "时间", width: 82, alignment: .leading)
            tableHeader("Change", "变动值", width: 82, alignment: .trailing)
            tableHeader("After", "变动后剩余", width: 104, alignment: .trailing)
            tableHeader("Reset", "重置时间", width: 130, alignment: .trailing)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.06))
    }

    private func row(_ event: QuotaChangeEvent) -> some View {
        HStack {
            tableText(StatsFormatter.time(event.sampledAt), width: 82, alignment: .leading)
            tableText(StatsFormatter.quotaDelta(event.deltaPercent), width: 82, alignment: .trailing)
                .foregroundStyle(event.deltaPercent < 0 ? Color.red : Color.green)
            tableText("\(event.afterRemainingPercent)%", width: 104, alignment: .trailing)
                .foregroundStyle(statusColor(remainingPercent: Double(event.afterRemainingPercent), tint: .secondary))
            tableText(StatsFormatter.resetTime(event.resetsAt), width: 130, alignment: .trailing)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func tableHeader(
        _ english: String,
        _ chinese: String,
        width: CGFloat,
        alignment: Alignment
    ) -> some View {
        Text(tr(english, chinese))
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
    }

    private func tableText(_ text: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(.primary)
            .frame(width: width, alignment: alignment)
    }
}

// MARK: - Daily usage chart (hover tooltip)

private struct DailyUsageChart: View {
    let samples: [DailySample]
    @State private var hovered: DailySample?

    var body: some View {
        Chart(samples) { sample in
            BarMark(
                x: .value("Day", sample.day, unit: .day),
                y: .value("Cost", sample.codexCost.doubleValue),
                stacking: .standard
            )
            .foregroundStyle(Color.codexAccent)
            .cornerRadius(2)
            .opacity(barOpacity(sample))

            BarMark(
                x: .value("Day", sample.day, unit: .day),
                y: .value("Cost", sample.claudeCost.doubleValue),
                stacking: .standard
            )
            .foregroundStyle(Color.claudeAccent)
            .cornerRadius(2)
            .opacity(barOpacity(sample))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: max(1, samples.count / 5))) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.65))
            }
        }
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hovered = sample(at: location, proxy: proxy, geo: geo)
                        case .ended:
                            hovered = nil
                        }
                    }
                if let hovered, let anchor = proxy.plotFrame,
                   let xPos = proxy.position(forX: hovered.day) {
                    let plot = geo[anchor]
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1, height: plot.height)
                        .position(x: plot.minX + xPos, y: plot.midY)
                    ChartCallout(lines: calloutLines(hovered))
                        .position(x: clampX(plot.minX + xPos, in: plot), y: plot.minY + 24)
                }
            }
        }
    }

    private func barOpacity(_ s: DailySample) -> Double {
        guard let hovered else { return 1 }
        return hovered.id == s.id ? 1 : 0.4
    }

    private func sample(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> DailySample? {
        guard let anchor = proxy.plotFrame else { return nil }
        let plot = geo[anchor]
        let xInPlot = location.x - plot.minX
        guard xInPlot >= 0, xInPlot <= plot.width else { return nil }
        guard let day: Date = proxy.value(atX: xInPlot, as: Date.self) else { return nil }
        return samples.min {
            abs($0.day.timeIntervalSince(day)) < abs($1.day.timeIntervalSince(day))
        }
    }

    private func clampX(_ x: CGFloat, in plot: CGRect) -> CGFloat {
        min(max(x, plot.minX + 52), plot.maxX - 52)
    }

    private func calloutLines(_ s: DailySample) -> [ChartCallout.Line] {
        [
            ChartCallout.Line(label: StatsFormatter.day(s.day), value: nil, color: nil),
            ChartCallout.Line(label: "Codex", value: StatsFormatter.cost(s.codexCost), color: .codexAccent),
            ChartCallout.Line(label: "Claude", value: StatsFormatter.cost(s.claudeCost), color: .claudeAccent)
        ]
    }
}

// MARK: - Chart hover callout

private struct ChartCallout: View {
    struct Line: Identifiable {
        let id = UUID()
        let label: String
        let value: String?
        let color: Color?
    }
    let lines: [Line]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(lines) { line in
                HStack(spacing: 5) {
                    if let color = line.color {
                        ServiceMark(color: color, size: 7)
                    }
                    Text(line.label)
                        .font(.system(size: 10.5, weight: line.value == nil ? .semibold : .regular))
                        .foregroundStyle(line.value == nil ? Color.primary : .secondary)
                    if let value = line.value {
                        Spacer(minLength: 10)
                        Text(value)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5)
        )
        .fixedSize()
        .allowsHitTesting(false)
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
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

/// 明细表一行 = 一个 (day × app × model) bucket。
/// id 用三元组拼接,聚合器保证其唯一。
private struct BreakdownRow: Identifiable {
    let bucket: UsageBucket
    var id: String { "\(bucket.day.timeIntervalSince1970)-\(bucket.app.rawValue)-\(bucket.model)" }
}

private struct QuotaTimelineSection: Identifiable {
    var id: String { accountKey }
    let accountKey: String
    let title: String
    let tint: Color
    /// 当前监测的额度窗口(5H / 周),无可用窗口时为 nil。
    let window: QuotaHistoryWindowKind?
    let currentRemaining: Int?
    let totalDelta: Int
    let latestEventAt: Date?
    let events: [QuotaChangeEvent]
}

// MARK: - Formatter

enum StatsFormatter {
    /// 价格表（远程 + 内置）里查不到的模型不显示 $0.00，避免被误读成免费。
    @MainActor
    static var unpriced: String { tr("Unpriced", "未定价") }

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

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    private static let monthDayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    /// 跨天时间线浮层用:`MM-dd HH:mm`。
    static func monthDayTime(_ date: Date) -> String {
        monthDayTimeFormatter.string(from: date)
    }

    static func resetTime(_ date: Date?) -> String {
        guard let date else { return "--" }
        // 非当天(如周窗口在 7 天后重置)带上日期,只显示 HH:mm 会误导。
        return Calendar.current.isDateInToday(date) ? time(date) : monthDayTime(date)
    }

    static func quotaDelta(_ value: Int) -> String {
        if value > 0 { return "+\(value)%" }
        return "\(value)%"
    }
}

// MARK: - Decimal helper

private extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

// MARK: - UsageBucket helper

private extension UsageBucket {
    /// 全量 token(输入含缓存 + 输出),口径与 UsageTotals.totalTokens 一致。
    var breakdownTotalTokens: Int {
        inputTokens + cacheReadTokens + cacheCreationTokens + outputTokens
    }
}
