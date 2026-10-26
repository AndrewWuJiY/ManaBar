import SwiftUI

// MARK: - SettingsRootView
//
// 见 docs/04-界面布局.md §4。
// 使用 prototype 的 PrefsGroup + PrefsRow 卡片结构,放弃 Form .grouped。

struct SettingsRootView: View {
    @Environment(AppState.self) private var appState
    @State private var launchAtLoginError: String?
    @State private var page: SettingsPage = .accounts

    private enum SettingsPage: Hashable, CaseIterable {
        case accounts
        case menuBar
        case floating
        case refresh
        case general

        var english: String {
            switch self {
            case .accounts: return "Accounts"
            case .menuBar: return "Menu Bar"
            case .floating: return "Floating HUD"
            case .refresh: return "Refresh"
            case .general: return "General"
            }
        }

        var chinese: String {
            switch self {
            case .accounts: return "账号"
            case .menuBar: return "菜单栏"
            case .floating: return "悬浮窗"
            case .refresh: return "刷新"
            case .general: return "通用"
            }
        }

        var icon: String {
            switch self {
            case .accounts: return "person"
            case .menuBar: return "menubar.rectangle"
            case .floating: return "macwindow"
            case .refresh: return "arrow.clockwise"
            case .general: return "gearshape"
            }
        }
    }

    var body: some View {
        @Bindable var settings = SettingsStore.shared

        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 200)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch page {
                    case .accounts:
                        accountsGroup(settings: settings)
                    case .menuBar:
                        menuBarGroup(settings: settings)
                    case .floating:
                        floatingGroup(settings: settings)
                    case .refresh:
                        refreshGroup(settings: settings)
                    case .general:
                        generalGroup(settings: settings)
                        footer
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: 680, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tr("Settings", "设置").uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            ForEach(SettingsPage.allCases, id: \.self) { item in
                let selected = page == item
                Button {
                    page = item
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.system(size: 13))
                            .frame(width: 16, height: 16)
                            .foregroundStyle(selected ? Color.white : Color.secondary)
                        Text(tr(item.english, item.chinese))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                        Spacer()
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selected ? Color.accentColor : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }

    // MARK: Accounts

    private func accountsGroup(settings: SettingsStore) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // 主账号（自动检测）
            PrefsGroup(
                title: "Accounts",
                chinese: "账号",
                desc: "Auto-detected on your Mac. Toggle which services to display.",
                chineseDesc: "自动检测,自行勾选要显示的"
            ) {
                AccountRow(
                    title: "Codex",
                    subtitle: "OpenAI",
                    tint: .codexAccent,
                    logoName: "codex",
                    fallback: "C",
                    email: appState.codexAccount?.email,
                    plan: appState.codexAccount?.planType,
                    isOn: Binding(get: { settings.showCodex }, set: { settings.showCodex = $0 })
                )
                AccountRow(
                    title: "Claude Code",
                    subtitle: "Anthropic",
                    tint: .claudeAccent,
                    logoName: "claude",
                    fallback: "K",
                    email: appState.claudeAccount?.email,
                    plan: appState.claudeAccount?.subscriptionType,
                    isOn: Binding(get: { settings.showClaude }, set: { settings.showClaude = $0 })
                )
                AccountRow(
                    title: "Cursor",
                    subtitle: "Billing cycle",
                    tint: .cursorAccent,
                    logoName: "cursor",
                    fallback: "R",
                    email: appState.cursorAccount?.email,
                    plan: appState.cursorAccount?.planType,
                    detected: appState.cursorAccount?.accessToken?.isEmpty == false,
                    isOn: Binding(get: { settings.showCursor }, set: { newValue in
                        settings.showCursor = newValue
                        appState.publishWidgetState(force: true)
                        if newValue {
                            Task { await appState.refreshQuotas(reason: .userInitiated) }
                        }
                    })
                )
            }

            // 其他 Codex 账号（手动导入）
            PrefsGroup(
                title: "Other Codex Accounts",
                chinese: "其他 Codex 账号",
                desc: "Paste auth.json to monitor additional Codex accounts (view only).",
                chineseDesc: "粘贴 auth.json 添加更多 Codex 账号额度，仅查看，不会切换 CLI 登录状态"
            ) {
                ImportedCodexAccountsView()
            }
        }
    }

    // MARK: Menu Bar

    private func menuBarGroup(settings: SettingsStore) -> some View {
        PrefsGroup(
            title: "Menu Bar",
            chinese: "菜单栏",
            desc: "What appears next to the icon.",
            chineseDesc: "图标旁显示什么"
        ) {
            PrefsRow(label: "Show Codex", chinese: "显示 Codex") {
                Toggle("", isOn: Binding(get: { settings.menuBarShowCodex }, set: { settings.menuBarShowCodex = $0 }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(.green)
            }
            PrefsRow(label: "Show Claude", chinese: "显示 Claude") {
                Toggle("", isOn: Binding(get: { settings.menuBarShowClaude }, set: { settings.menuBarShowClaude = $0 }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(.green)
            }
            PrefsRow(
                label: "Show Cursor",
                chinese: "显示 Cursor",
                desc: "Billing-cycle percent. Ignores the 5H / WK picker.",
                chineseDesc: "显示账期剩余,不跟 5H / WK 切换"
            ) {
                Toggle("", isOn: Binding(get: { settings.menuBarShowCursor }, set: { settings.menuBarShowCursor = $0 }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(.green)
                    .disabled(!settings.showCursor)
            }
            PrefsRow(
                label: "Quota period",
                chinese: "额度周期",
                desc: "Which window to display in the menu bar.",
                chineseDesc: "菜单栏显示哪个窗口"
            ) {
                Picker("", selection: Binding(get: { settings.menuBarWindow }, set: { settings.menuBarWindow = $0 })) {
                    Text("5H").tag(MenuBarWindowChoice.fiveHour)
                    Text("WK").tag(MenuBarWindowChoice.weekly)
                    Text(tr("Both", "都显示")).tag(MenuBarWindowChoice.both)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
    }

    // MARK: Floating HUD

    private func floatingGroup(settings: SettingsStore) -> some View {
        PrefsGroup(
            title: "Floating HUD",
            chinese: "桌面悬浮窗",
            desc: "A small always-on-top window pinned to your desktop.",
            chineseDesc: "桌面常驻的小悬浮窗"
        ) {
            PrefsRow(label: "Show floating window", chinese: "显示悬浮窗") {
                Toggle("", isOn: Binding(
                    get: { settings.floatingEnabled },
                    set: { newValue in
                        settings.floatingEnabled = newValue
                        FloatingPanelController.shared.sync()
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.green)
            }
            PrefsRow(
                label: "Global hotkey ⌃⌥F",
                chinese: "全局快捷键 ⌃⌥F",
                desc: "Press ⌃⌥F in any app to show / hide the floating HUD.",
                chineseDesc: "在任意应用中按 ⌃⌥F 显示/隐藏悬浮窗;也可右键悬浮窗关闭"
            ) {
                Toggle("", isOn: Binding(
                    get: { settings.floatingHotkeyEnabled },
                    set: { settings.floatingHotkeyEnabled = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.green)
            }
            PrefsRow(label: "Show Codex row", chinese: "显示 Codex 行") {
                Toggle("", isOn: Binding(
                    get: { settings.floatingShowCodex },
                    set: { newValue in
                        settings.floatingShowCodex = newValue
                        FloatingPanelController.shared.sync()
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.green)
                .disabled(!settings.floatingEnabled)
            }
            PrefsRow(label: "Show Claude row", chinese: "显示 Claude 行") {
                Toggle("", isOn: Binding(
                    get: { settings.floatingShowClaude },
                    set: { newValue in
                        settings.floatingShowClaude = newValue
                        FloatingPanelController.shared.sync()
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.green)
                .disabled(!settings.floatingEnabled)
            }
            PrefsRow(label: "Show Cursor row", chinese: "显示 Cursor 行") {
                Toggle("", isOn: Binding(
                    get: { settings.floatingShowCursor },
                    set: { newValue in
                        settings.floatingShowCursor = newValue
                        FloatingPanelController.shared.sync()
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.green)
                .disabled(!settings.floatingEnabled || !settings.showCursor)
            }
            PrefsRow(label: "Show 5h reset time", chinese: "显示 5h 重置时间") {
                Toggle("", isOn: Binding(
                    get: { settings.floatingShowReset },
                    set: { newValue in
                        settings.floatingShowReset = newValue
                        FloatingPanelController.shared.sync()
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.green)
                .disabled(!settings.floatingEnabled)
            }
        }
    }

    // MARK: Refresh

    private func refreshGroup(settings: SettingsStore) -> some View {
        PrefsGroup(
            title: "Refresh",
            chinese: "刷新",
            desc: "How often the app polls usage in the background.",
            chineseDesc: "后台轮询用量的频率"
        ) {
            PrefsRow(label: "Quota refresh", chinese: "额度刷新") {
                Picker("", selection: Binding(
                    get: { settings.quotaInterval },
                    set: { newValue in
                        settings.quotaInterval = newValue
                        appState.applySettingsChange()
                    }
                )) {
                    ForEach(QuotaIntervalChoice.allCases) { choice in
                        Text(choice.bilingualDisplayName).tag(choice)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            PrefsRow(label: "Log scan", chinese: "日志扫描") {
                Picker("", selection: Binding(
                    get: { settings.usageInterval },
                    set: { newValue in
                        settings.usageInterval = newValue
                        appState.applySettingsChange()
                    }
                )) {
                    ForEach(UsageIntervalChoice.allCases) { choice in
                        Text(choice.bilingualDisplayName).tag(choice)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            PrefsRow(
                label: "Reset time",
                chinese: "重置时间",
                desc: "How quota reset time is shown.",
                chineseDesc: "额度重置时间的显示方式"
            ) {
                Picker("", selection: Binding(
                    get: { settings.resetTimeDisplay },
                    set: { settings.resetTimeDisplay = $0 }
                )) {
                    Text(tr("Remaining", "剩余时长")).tag(ResetTimeDisplay.relative)
                    Text(tr("Exact time", "具体时间")).tag(ResetTimeDisplay.absolute)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            PrefsRow(label: "Last refresh", chinese: "上次刷新") {
                Text(lastRefreshText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            PrefsRow(
                label: "Service status dot",
                chinese: "服务状态圆点",
                desc: "Show OpenAI / Anthropic status next to each service in the popover.",
                chineseDesc: "在弹出窗口为每个服务显示官方状态页圆点"
            ) {
                Toggle("", isOn: Binding(get: { settings.showServiceStatus }, set: { settings.showServiceStatus = $0 }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(.green)
            }
        }
    }

    // MARK: General

    private func generalGroup(settings: SettingsStore) -> some View {
        PrefsGroup(title: "General", chinese: "通用") {
            PrefsRow(
                label: "Appearance",
                chinese: "外观",
                desc: "Applies to popover, main window and floating HUD.",
                chineseDesc: "对弹出窗口、主窗口和悬浮窗都生效"
            ) {
                Picker("", selection: Binding(
                    get: { settings.appAppearance },
                    set: { settings.appAppearance = $0 }
                )) {
                    Text(tr("System", "跟随系统")).tag(AppAppearanceChoice.system)
                    Text(tr("Light", "浅色")).tag(AppAppearanceChoice.light)
                    Text(tr("Dark", "深色")).tag(AppAppearanceChoice.dark)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            PrefsRow(label: "Language", chinese: "语言") {
                Picker("", selection: Binding(
                    get: { settings.appLanguage },
                    set: { settings.appLanguage = $0 }
                )) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            PrefsRow(
                label: "Privacy mode",
                chinese: "隐私模式",
                desc: "Hide email in the popover and account names for other Codex accounts.",
                chineseDesc: "弹出窗口中隐藏主账号邮箱,并隐藏 Codex 副账号名称"
            ) {
                Toggle("", isOn: Binding(get: { settings.privacyMode }, set: { settings.privacyMode = $0 }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(.green)
            }
            PrefsRow(label: "Launch at login", chinese: "开机自动启动") {
                Toggle("", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { newValue in
                        do {
                            try settings.setLaunchAtLogin(newValue)
                            launchAtLoginError = nil
                        } catch {
                            launchAtLoginError = error.localizedDescription
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.green)
            }
            if let launchAtLoginError {
                PrefsRow(label: "Error", chinese: "错误") {
                    Text(launchAtLoginError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .frame(maxWidth: 200, alignment: .trailing)
                }
            }
            PrefsRow(label: "Version", chinese: "版本") {
                Text(appVersion)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(tr("ManaBar \(shortVersion) · made with Liquid Glass",
                    "ManaBar \(shortVersion) · 双应用额度与本地用量统计"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: Helpers

    private var lastRefreshText: String {
        let latest = [
            appState.codexRefreshState.lastSuccessAt,
            appState.claudeRefreshState.lastSuccessAt
        ].compactMap { $0 }.max()
        guard let latest else { return "—" }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        return "\(timeFormatter.string(from: latest)) · \(PopoverRootView.relativeAge(from: latest)) \(tr("ago", "前"))"
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    private var shortVersion: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - PrefsGroup

private struct PrefsGroup<Content: View>: View {
    let title: String
    let chinese: String
    var desc: String? = nil
    var chineseDesc: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr(title, chinese))
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(-0.05)
                if let desc, let chineseDesc {
                    Text(tr(desc, chineseDesc))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .ccPanel(cornerRadius: 10)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

// MARK: - PrefsRow

private struct PrefsRow<Trailing: View>: View {
    let label: String
    let chinese: String
    var desc: String? = nil
    var chineseDesc: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(tr(label, chinese))
                    .font(.system(size: 12.5))
                if let desc, let chineseDesc {
                    Text(tr(desc, chineseDesc))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
}

// MARK: - AccountRow

private struct AccountRow: View {
    let title: String
    let subtitle: String
    let tint: Color
    let logoName: String
    let fallback: String
    let email: String?
    let plan: String?
    /// 覆盖「有邮箱才算已连接」。Cursor 钥匙串回退可能没有邮箱,但 token 已经在。
    var detected: Bool? = nil
    @Binding var isOn: Bool

    private var isDetected: Bool { detected ?? (email != nil) }

    var body: some View {
        HStack(spacing: 11) {
            ServiceTile(logoName: logoName, fallback: fallback, tint: tint, size: 28, logoSize: 16, cornerRadius: 7)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("· \(subtitle)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Text(detailText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                statusBadge

                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(.green)
                    .disabled(!isDetected)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }

    private var detailText: String {
        if let email {
            if let plan, !plan.isEmpty {
                return "\(email) · \(plan)"
            }
            return email
        }
        if isDetected, let plan, !plan.isEmpty { return plan }
        if isDetected { return tr("Signed in", "已登录") }
        return tr("Not detected", "未识别")
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isDetected {
            HStack(spacing: 4) {
                Circle().fill(Color.connectedStatus).frame(width: 7, height: 7)
                Text(tr("Connected", "已连接"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.connectedStatus)
            }
        } else {
            HStack(spacing: 4) {
                Circle().fill(Color.orange).frame(width: 7, height: 7)
                Text(tr("Not detected", "未识别"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Bilingual display names for existing enums

extension QuotaIntervalChoice {
    var bilingualDisplayName: String {
        switch self {
        case .m1: return tr("1 minute", "1 分钟")
        case .m2: return tr("2 minutes", "2 分钟")
        case .m3: return tr("3 minutes", "3 分钟")
        case .m5: return tr("5 minutes", "5 分钟")
        case .m10: return tr("10 minutes", "10 分钟")
        }
    }
}

extension UsageIntervalChoice {
    var bilingualDisplayName: String {
        switch self {
        case .m1: return tr("1 minute", "1 分钟")
        case .m2: return tr("2 minutes", "2 分钟")
        case .m3: return tr("3 minutes", "3 分钟")
        case .m5: return tr("5 minutes", "5 分钟")
        case .m10: return tr("10 minutes", "10 分钟")
        }
    }
}
