import SwiftUI
import AppKit

// MARK: - Product accent colors
//
// Codex / Claude 识别色定义在 Asset Catalog (CodexAccent / ClaudeAccent)。
// 浅色 #718DFF / #D97757,深色 #8FA6FF / #E68A6E。
// Xcode 自动从 .xcassets 生成 `Color.codexAccent` / `Color.claudeAccent`,直接使用即可。
// 见 docs/03-设计风格.md §4.2。


extension Color {
    /// 设置页「已连接」状态用的绿。参考 GitHub success green(成熟的"连接/成功"绿),
    /// 浅深各一套、白底深底都清晰:浅色 #2DA44E,深色 #3FB950。
    static let connectedStatus = quotaAdaptiveColor(
        light: (red: 45, green: 164, blue: 78),    // #2DA44E
        dark: (red: 63, green: 185, blue: 80)      // #3FB950
    )
}

// MARK: - Reset time (hover 切换格式)

/// 重置时间文案,鼠标悬浮时切换显示「相反格式」(相对↔绝对)。
///
/// 菜单栏 App 处于 `.accessory` 非激活态,系统 `.help()` tooltip 不会触发,
/// 因此用 `onHover` 直接切换文案来实现「悬浮看另一种格式」。
/// `font` / `foregroundStyle` 等由调用方在外层指定。
struct ResetTimeText: View {
    let resetsAt: Date?
    @State private var hovering = false

    var body: some View {
        // 相对倒计时是按「距现在还有多久」实时算的,本身没有任何 @Observable 输入,
        // 不会随时间自动重绘(.accessory 非激活态尤甚),否则文案会冻在渲染那一刻、
        // 要鼠标移入才跳。用周期 TimelineView 每分钟推进一次,并把 context.date
        // 作为 now 传入,保证倒计时自己走动。绝对格式不依赖 now,一并重算无副作用。
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(hovering
                 ? formatResetAltCompact(resetsAt, now: context.date)
                 : formatResetCompact(resetsAt, now: context.date))
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .padding(.horizontal, -8)
                .padding(.vertical, -4)
        }
    }
}

// MARK: - Panel background / stroke (浅深色对照)
//
// 见 docs/03-设计风格.md §12.3。
// Stats KPI 卡、Daily usage panel、Settings PrefsGroup body、Onboarding DetectedAccount 全部用这一对。

private struct PanelBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Group {
            if colorScheme == .dark {
                Color(white: 0.235, opacity: 0.4)
            } else {
                Color.white
            }
        }
    }
}

/// Panel 0.5pt 内描边,做"卡片感"。
struct CCPanelStroke: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark
                        ? Color.white.opacity(0.06)
                        : Color.black.opacity(0.06),
                    lineWidth: 0.5
                )
        )
    }
}

extension View {
    /// 给 Panel / KPI 卡上 0.5pt 内描边。
    func ccPanelStroke(cornerRadius: CGFloat) -> some View {
        modifier(CCPanelStroke(cornerRadius: cornerRadius))
    }

    /// 一步给出 Panel 完整外观:背景 + 圆角 + 0.5pt 描边。
    func ccPanel(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.background)
                    .overlay(PanelBackground().clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
            )
            .ccPanelStroke(cornerRadius: cornerRadius)
    }
}

// MARK: - ServiceMark (色块)
//
// 见 docs/03-设计风格.md §11.1。
// prototype 用的是 8×8 squircle(圆角 2pt),不是圆。

struct ServiceMark: View {
    let color: Color
    var size: CGFloat = 8
    var cornerRadius: CGFloat = 2

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
    }
}


// MARK: - ProgressRing (进度环)
//
// 见 docs/03-设计风格.md §11.3。
// Popover 56/5.5、Stats limits 32/4、HUD dual rings 26/3.5、HUD single 34/4。
// value 取 0...1,值越大环越满。颜色由调用方传入(通常用 statusColor)。

struct ProgressRing<Center: View>: View {
    let value: Double
    let tint: Color
    var diameter: CGFloat = 56
    var stroke: CGFloat = 5.5
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), style: StrokeStyle(lineWidth: stroke))

            Circle()
                .trim(from: 0, to: clampedValue)
                .stroke(tint, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: clampedValue)

            center()
        }
        .frame(width: diameter, height: diameter)
    }

    private var clampedValue: CGFloat {
        max(0, min(1, CGFloat(value)))
    }
}

extension ProgressRing where Center == EmptyView {
    init(value: Double, tint: Color, diameter: CGFloat = 56, stroke: CGFloat = 5.5) {
        self.init(value: value, tint: tint, diameter: diameter, stroke: stroke) {
            EmptyView()
        }
    }
}


// MARK: - Bilingual label helpers
//
// 见 docs/03-设计风格.md §5。
// 单语切换 · 由 SettingsStore.shared.resolvedLanguage 决定渲染中文还是英文。
// 调用方保留 `english` + `chinese` 两个字段,组件内自动选词,无需迁移调用点。

/// 行内单语显示 · zh 渲染 chinese,en 渲染 english。
struct BilingualInline: View {
    let english: String
    let chinese: String
    /// 保留参数以兼容历史调用,运行时不再拼接。
    var separator: String = " · "

    var body: some View {
        switch SettingsStore.shared.resolvedLanguage {
        case .zh: Text(chinese)
        case .en: Text(english)
        }
    }
}

/// 节标题 / KPI label · 单语模式下退化为单行 Text,保留主字体。
struct BilingualStack: View {
    let english: String
    let chinese: String
    var englishFont: Font = .headline
    var chineseFont: Font = .caption

    var body: some View {
        switch SettingsStore.shared.resolvedLanguage {
        case .zh: Text(chinese).font(englishFont)
        case .en: Text(english).font(englishFont)
        }
    }
}

// MARK: - Spacing tokens (4pt 基线)
//
// 见 docs/03-设计风格.md §10。

enum CCSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s2: CGFloat = 6
    static let s: CGFloat = 8
    static let m2: CGFloat = 10
    static let m: CGFloat = 12
    static let l2: CGFloat = 14
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 28
    static let huge: CGFloat = 32
}

// MARK: - VisualEffectBackground
//
// SwiftUI 包 NSVisualEffectView,用于把指定 material(.hudWindow / .popover / .sidebar 等)
// 接到 SwiftUI 视图层级里。HUD 必须用 .hudWindow material(prototype 给的 alpha + blur)。
// 不要用 .background(.regularMaterial),它对应的是 .popover material。

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
    }
}

// MARK: - Refresh state badge
//
// Popover header 状态点;Live / Stale / Offline。

enum CCRefreshState {
    case live, stale, offline

    var color: Color {
        switch self {
        case .live: return .green
        case .stale: return .orange
        case .offline: return .red
        }
    }

    var tooltip: String {
        switch self {
        case .live: return tr("Live", "在线")
        case .stale: return tr("Stale", "数据陈旧")
        case .offline: return tr("Offline", "离线")
        }
    }
}

// MARK: - Pointing-hand cursor
//
// 全局统一的 hover 手型光标 ViewModifier。用在所有 `.borderless` / `.plain`
// 自定义按钮上,弥补 SwiftUI 默认按钮在 macOS 上无光标提示的问题。

private struct PointingHandCursor: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

extension View {
    /// 鼠标进入时切换为手型光标,离开时还原。
    func pointingHandCursor() -> some View { modifier(PointingHandCursor()) }
}

// MARK: - PopoverIconButtonStyle
//
// Popover 顶部 26×22 圆角 5pt borderless 图标按钮。
// hover 浅灰背景 + 手型光标,匹配 docs/04-界面布局.md §1.3。

struct PopoverIconButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 26, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hovering && isEnabled ? Color.primary.opacity(0.08) : .clear)
            )
            .opacity(configuration.isPressed ? 0.5 : 1)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .pointingHandCursor()
    }
}
