import SwiftUI
import AppKit

// MARK: - PopoverRootView
//
// 见 docs/04-界面布局.md §1。
// 结构:Header(标题 + 状态点 + 统计/刷新/设置 三个一级图标 + ⋯ kebab) /
//      Codex block(tile + 服务名/plan + reset / 56pt 环 + weekly 条 + stats 行) /
//      Claude block(同上)。footer 已合并到 header,不再单独存在。

struct PopoverRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var isRefreshing = false
    @State private var refreshRotation: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
        }
        .frame(width: 340)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("Usage", "用量"))
                    .font(.system(size: 13, weight: .semibold))

                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer()

            if let state = headerState {
                Circle()
                    .fill(state.color)
                    .frame(width: 7, height: 7)
                    .help(state.tooltip)
                    .padding(.trailing, 4)
            }

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(refreshRotation))
                    .animation(.easeInOut(duration: 0.7), value: refreshRotation)
            }
            .buttonStyle(PopoverIconButtonStyle())
            .disabled(isRefreshing)
            .help(tr("Refresh now", "立即刷新"))

            Button { activateAndOpenMain() } label: {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(PopoverIconButtonStyle())
            .help(tr("Open Statistics", "查看统计"))

            Button { activateAndOpenMain() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(PopoverIconButtonStyle())
            .help(tr("Settings", "设置"))

            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(PopoverIconButtonStyle())
            .help(tr("Quit", "退出"))
        }
        .padding(.top, 14)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var headerSubtitle: String {
        let latest = [
            appState.codexRefreshState.lastSuccessAt,
            appState.claudeRefreshState.lastSuccessAt
        ].compactMap { $0 }.max()

        if let latest {
            let age = Self.relativeAge(from: latest)
            return tr("refreshed \(age) ago", "\(age) 前已刷新")
        }
        if appState.codexQuotaError != nil || appState.claudeQuotaError != nil {
            return tr("refresh failed", "刷新失败")
        }
        return tr("waiting…", "等待数据")
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        let showCodex = SettingsStore.shared.showCodex
        let showClaude = SettingsStore.shared.showClaude

        if !showCodex && !showClaude {
            VStack(spacing: 6) {
                Text(tr("No services enabled", "未启用任何服务"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(tr("Enable a service in Settings → Accounts", "到「设置 → 账号」开启"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            VStack(spacing: 0) {
                if showCodex {
                    ServiceBlockView(
                        title: "Codex",
                        subtitle: codexSubtitle,
                        tint: .codexAccent,
                        logoName: "codex",
                        fallback: "C",
                        snapshot: appState.codexQuota,
                        error: appState.codexQuotaError,
                        weekSpend: weekSpend(for: .codex),
                        todayCost: appState.codexTodayCost,
                        showsDesignQuota: false
                    )
                }
                if showCodex && showClaude {
                    Divider().padding(.horizontal, 16)
                }
                if showClaude {
                    ServiceBlockView(
                        title: "Claude Code",
                        subtitle: claudeSubtitle,
                        tint: .claudeAccent,
                        logoName: "claude",
                        fallback: "K",
                        snapshot: appState.claudeQuota,
                        error: appState.claudeQuotaError,
                        weekSpend: weekSpend(for: .claude),
                        todayCost: appState.claudeTodayCost,
                        showsDesignQuota: true
                    )
                }
            }
        }
    }

    private var codexSubtitle: String {
        var parts = ["OpenAI"]
        if let plan = appState.codexAccount?.planType, !plan.isEmpty {
            parts.append(plan.capitalized)
        }
        return parts.joined(separator: " · ")
    }

    private var claudeSubtitle: String {
        var parts = ["Anthropic"]
        if let plan = appState.claudeAccount?.subscriptionType, !plan.isEmpty {
            parts.append(plan.capitalized)
        }
        return parts.joined(separator: " · ")
    }

    private func weekSpend(for app: UsageApp) -> Decimal {
        let (from, to) = Self.weekBounds()
        let totals = appState.usageService.aggregator.totals(app: app, from: from, to: to)
        return totals.costUSD
    }

    // MARK: Header state (live / stale / offline)

    private var headerState: CCRefreshState? {
        let settings = SettingsStore.shared
        let codex = appState.codexRefreshState
        let claude = appState.claudeRefreshState
        let codexLast = settings.showCodex ? codex.lastSuccessAt : nil
        let claudeLast = settings.showClaude ? claude.lastSuccessAt : nil
        let latest = [codexLast, claudeLast].compactMap { $0 }.max()
        let hasError = (settings.showCodex && codex.lastError != nil)
            || (settings.showClaude && claude.lastError != nil)

        guard let latest else {
            return hasError ? .offline : nil
        }

        let interval = settings.quotaInterval.seconds ?? 300
        let age = Date().timeIntervalSince(latest)
        if age <= interval * 1.5 { return .live }
        if age <= interval * 3 { return .stale }
        return .offline
    }

    // MARK: Open main window

    /// 菜单栏 App (`.accessory`) 默认不抢焦点,打开窗口后会被压在其他 App 后面;
    /// 先 `activate(ignoringOtherApps:)` 把进程置前,再 `openWindow` 才会出现在最前。
    private func activateAndOpenMain() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }

    // MARK: Refresh

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshRotation += 360

        Task {
            let startedAt = Date()
            await appState.refreshNow()

            let elapsed = Date().timeIntervalSince(startedAt)
            if elapsed < 0.5 {
                try? await Task.sleep(nanoseconds: UInt64((0.5 - elapsed) * 1_000_000_000))
            }
            await MainActor.run { isRefreshing = false }
        }
    }

    // MARK: Helpers

    private static func weekBounds(now: Date = Date()) -> (Date, Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        cal.firstWeekday = 2
        let startOfToday = cal.startOfDay(for: now)
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let weekStart = cal.date(from: comps) ?? startOfToday
        return (weekStart, startOfTomorrow)
    }

    static func relativeAge(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}

// MARK: - ServiceBlockView

private struct ServiceBlockView: View {
    let title: String
    let subtitle: String
    let tint: Color
    let logoName: String
    let fallback: String
    let snapshot: QuotaSnapshot?
    let error: String?
    let weekSpend: Decimal
    let todayCost: Decimal?
    let showsDesignQuota: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            bodyRow
            weeklyRow
            if showsDesignQuota {
                designRow
            }
            if let message = shortError(error) {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerRow: some View {
        HStack(spacing: 9) {
            ServiceTile(logoName: logoName, fallback: fallback, tint: tint)

            (
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .kerning(-0.1)
                    .foregroundColor(.primary)
                + Text("   ")
                + Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.75))
            )
            .lineLimit(1)
            .truncationMode(.tail)

            Spacer(minLength: 0)
        }
    }

    private var bodyRow: some View {
        HStack(alignment: .center, spacing: 16) {
            // 左:5h 大百分比 + 小标签
            VStack(alignment: .center, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(fiveHourValueText)
                        .font(.system(size: 32, weight: .semibold))
                        .monospacedDigit()
                        .kerning(-0.8)
                        .foregroundStyle(fiveHourColor)
                        .lineLimit(1)
                    Text("%")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(fiveHourColor.opacity(0.75))
                }
                .fixedSize()

                Text("5-HOUR · 五小时")
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(.quaternary)
            }

            // 右:5h 进度条 + 两行(数值 / label)
            VStack(alignment: .leading, spacing: 8) {
                ProgressBar(value: fiveHourRemaining / 100, tint: fiveHourColor, height: 7)

                VStack(spacing: 1) {
                    HStack(spacing: 0) {
                        Text(formatResetCompact(snapshot?.fiveHour?.resetsAt))
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        HStack(spacing: 10) {
                            statInline(value: formatCostInt(todayCost), english: "today", chinese: "今日")
                            statInline(value: formatCostInt(weekSpend), english: "this week", chinese: "本周")
                        }
                    }

                    HStack(spacing: 0) {
                        BilingualInline(english: "reset", chinese: "重置")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.quaternary)

                        Spacer(minLength: 0)

                        BilingualInline(english: "cost", chinese: "花费")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.quaternary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var weeklyRow: some View {
        HStack(spacing: 10) {
            Text("1w")
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(.quaternary)
                .frame(width: 36, alignment: .leading)

            ProgressBar(value: weeklyRemaining / 100, tint: weeklyColor, height: 2.5)

            Text(weeklyPercentText)
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text(formatResetCompact(snapshot?.weekly?.resetsAt))
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(.quaternary)
        }
    }

    private var designRow: some View {
        HStack(spacing: 10) {
            Text("Design")
                .font(.system(size: 8.5, weight: .semibold))
                .kerning(0)
                .foregroundStyle(.quaternary)
                .frame(width: 36, alignment: .leading)

            ProgressBar(value: designRemaining / 100, tint: designColor, height: 2.5)

            Text(designPercentText)
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text(formatResetCompact(snapshot?.weeklyDesign?.resetsAt))
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(.quaternary)
        }
    }

    private func statInline(value: String, english: String, chinese: String) -> some View {
        HStack(spacing: 4) {
            BilingualInline(english: english, chinese: chinese)
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    // MARK: Derived data

    private var fiveHourRemaining: Double {
        snapshot?.fiveHour?.remainingPercent ?? 0
    }

    private var weeklyRemaining: Double {
        snapshot?.weekly?.remainingPercent ?? 0
    }

    private var designRemaining: Double {
        snapshot?.weeklyDesign?.remainingPercent ?? 0
    }

    private var fiveHourColor: Color {
        guard snapshot?.fiveHour != nil else { return .secondary }
        return statusColor(remainingPercent: fiveHourRemaining, tint: tint)
    }

    private var weeklyColor: Color {
        guard snapshot?.weekly != nil else { return .secondary }
        return statusColor(remainingPercent: weeklyRemaining, tint: tint)
    }

    private var designColor: Color {
        guard snapshot?.weeklyDesign != nil else { return .secondary }
        return statusColor(remainingPercent: designRemaining, tint: tint)
    }

    private var fiveHourValueText: String {
        guard let window = snapshot?.fiveHour else { return "--" }
        return "\(Int(window.remainingPercent.rounded()))"
    }

    private var weeklyPercentText: String {
        guard let window = snapshot?.weekly else { return "--%" }
        return "\(Int(window.remainingPercent.rounded()))%"
    }

    private var designPercentText: String {
        guard let window = snapshot?.weeklyDesign else { return "--%" }
        return "\(Int(window.remainingPercent.rounded()))%"
    }

    /// 取整美元金额:`<$1` 用于 0 ~ 0.99,`$0` 仅在 nil/0 时显示。
    private func formatCostInt(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        let d = NSDecimalNumber(decimal: value).doubleValue
        if d <= 0 { return "$0" }
        if d < 1 { return "<$1" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return "$\(formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0")"
    }

    private func shortError(_ error: String?) -> String? {
        guard let error, !error.isEmpty else { return nil }
        let oneLine = error.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if oneLine.count <= 110 { return oneLine }
        return String(oneLine.prefix(107)) + "..."
    }
}
