import SwiftUI

// MARK: - FloatingContentView
//
// 见 docs/04-界面布局.md §2。
// 默认变体:Two-row pill。
// 结构:14pt 圆角 HUD 容器 + .hudWindow material 背景 + 两行 pill。
// 每行:18pt ServiceTile + flex 4pt bar(状态色) + 40pt 百分比(主文字色)。

struct FloatingContentView: View {
    @Environment(AppState.self) private var appState
    let settings: SettingsStore

    var body: some View {
        let showCodex = settings.effectiveFloatingShowCodex
        let showClaude = settings.effectiveFloatingShowClaude

        VStack(alignment: .leading, spacing: 7) {
            // 无 5h 限制时(fiveHour 为 nil)回退显示周窗口:
            // 悬浮窗是常驻小组件,∞ 没有信息量,周耗量才有监控价值
            if showCodex {
                FloatingRow(
                    logoName: "codex",
                    fallback: "C",
                    tint: .codexAccent,
                    window: appState.codexQuota?.fiveHour ?? appState.codexQuota?.weekly,
                    showReset: settings.floatingShowReset
                )
            }
            if showClaude {
                FloatingRow(
                    logoName: "claude",
                    fallback: "K",
                    tint: .claudeAccent,
                    window: appState.claudeQuota?.fiveHour ?? appState.claudeQuota?.weekly,
                    showReset: settings.floatingShowReset
                )
            }
            if !showCodex && !showClaude {
                Text(tr("No services", "未启用"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 168, alignment: .leading)
        .background {
            // 三层叠加,解决 `.hudWindow` 在彩色桌面下前景被吃掉的问题:
            // 1) 实色窗背景压一层,使桌面像素不再直接透上来
            // 2) `.popover` material 接管毛玻璃质感(比 .hudWindow 厚)
            // 3) hairline 描边,任何背景下都能勾出 HUD 边缘
            ZStack {
                Color(nsColor: .windowBackgroundColor).opacity(0.55)
                VisualEffectBackground(material: .popover, blendingMode: .behindWindow)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        // 阴影交给 NSPanel 的 hasShadow,它按内容 alpha 自动取圆角形状,
        // SwiftUI 这层 shadow 会被 panel 边界裁掉而且和系统阴影叠加,所以移除。
        .fixedSize()
        .contextMenu {
            Button {
                settings.floatingEnabled = false
                FloatingPanelController.shared.sync()
            } label: {
                Text(settings.floatingHotkeyEnabled
                     ? tr("Hide Floating HUD (⌃⌥F)", "关闭悬浮窗 (⌃⌥F)")
                     : tr("Hide Floating HUD", "关闭悬浮窗"))
            }
            Divider()
            Button {
                appState.mainTab = .settings
                appState.shouldOpenMainWindow = true
            } label: {
                Text(tr("Settings…", "设置…"))
            }
        }
    }
}

private struct FloatingRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let logoName: String
    let fallback: String
    let tint: Color
    let window: QuotaWindow?
    var showReset: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            ServiceTile(
                logoName: logoName,
                fallback: fallback,
                tint: tint,
                size: 18,
                logoSize: 12,
                cornerRadius: 5
            )

            ProgressBar(value: barValue, tint: barColor, height: 4)
                .frame(minWidth: 56)

            Text(percentText)
                .font(.system(size: 13, weight: .semibold))
                .kerning(-0.3)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 40, alignment: .trailing)
                .background {
                    if criticalQuota {
                        Capsule()
                            .fill(criticalColor.opacity(criticalBadgeOpacity))
                            .frame(width: 40, height: 19)
                    }
                }

            if showReset {
                // 两行都恒定渲染:无 resetsAt 时 formatResetCompact 返回 "—",保证百分比列对齐。
                // 倒计时按分钟自走,否则 .accessory 非激活态会冻在渲染那一刻。
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(formatResetCompact(window?.resetsAt, now: context.date))
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.secondary.opacity(0.86))
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 46, alignment: .trailing)
            }
        }
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
        if criticalQuota { return criticalColor }
        return statusColor(remainingPercent: window?.remainingPercent, tint: tint)
    }

    private var criticalQuota: Bool {
        guard let value = window?.remainingPercent else { return false }
        return value < 10
    }

    private var criticalColor: Color {
        statusColor(remainingPercent: 0, tint: tint)
    }

    private var criticalBadgeOpacity: Double {
        colorScheme == .dark ? 0.2 : 0.14
    }
}
