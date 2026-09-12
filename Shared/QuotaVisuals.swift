import AppKit
import SwiftUI

// MARK: - QuotaVisuals
//
// 主 App 与桌面小组件(ManaBarWidget)共用的额度视觉元素。见 docs/草案-桌面小组件.md §3.1。
// 从 Main/DesignSystem.swift 抽出,那边只保留主窗口专用组件。
//
// 只抽"元素"不抽"行布局":悬浮窗容器 168pt、小组件 systemMedium 约 330pt,
// 同一套 Row 硬套过去会一头堆一头留白,所以两边各自排版、共用这里的 tile / 进度条 / 状态色。
//
// 注意:`Color.codexAccent` / `.claudeAccent` 由各 target 自己的 Asset Catalog 生成,
// 主 App 走 Resources/Assets.xcassets,小组件走 ManaBarWidget/Assets.xcassets,两处取值必须一致。

// MARK: - Status color

/// 按剩余百分比解析 4 档状态色:>50% → normal / 20~50% → warning / <20% → low / <=0 → empty。
///
/// 见 docs/03-设计风格.md §4.3。Popover / Floating / Stats KPI 全部走这里。
/// `tint`(服务识别色)当前不参与额度着色,保留参数以备将来切回「服务色打底」方案。
func statusColor(remainingPercent: Double?, tint: Color) -> Color {
    guard let value = remainingPercent else { return .secondary }
    if value <= 0 { return quotaEmptyColor }
    if value < 20 { return quotaLowColor }
    if value <= 50 { return quotaWarningColor }
    return quotaNormalColor
}

// normal 档统一用石墨灰(中性灰),不随服务识别色变化。
// 2026-06 加深一档:原 #6C6C70 / #98989D 在大字号和浅色卡片上偏淡,可读性不足。
private let quotaNormalColor = quotaAdaptiveColor(
    light: (red: 72, green: 72, blue: 77),    // #48484D
    dark: (red: 180, green: 180, blue: 186)   // #B4B4BA
)

// warning 浅色档不能用亮黄(#F6C343 在白底对比度 <2:1,文字几乎看不见),
// 改用深琥珀;进度条/图表点一并变深,"黄=警告"语义不变。深色仍用亮黄。
private let quotaWarningColor = quotaAdaptiveColor(
    light: (red: 178, green: 124, blue: 0),   // #B27C00
    dark: (red: 255, green: 226, blue: 122)   // #FFE27A
)

// low 浅色档同理加深一点,白底上 #FF7A2F 文字偏浅。
private let quotaLowColor = quotaAdaptiveColor(
    light: (red: 224, green: 96, blue: 21),   // #E06015
    dark: (red: 255, green: 161, blue: 95)    // #FFA15F
)

private let quotaEmptyColor = quotaAdaptiveColor(
    light: (red: 255, green: 77, blue: 109),  // #FF4D6D
    dark: (red: 255, green: 122, blue: 144)   // #FF7A90
)

func quotaAdaptiveColor(
    light: (red: CGFloat, green: CGFloat, blue: CGFloat),
    dark: (red: CGFloat, green: CGFloat, blue: CGFloat)
) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let rgb = isDark ? dark : light
        return NSColor(
            calibratedRed: rgb.red / 255,
            green: rgb.green / 255,
            blue: rgb.blue / 255,
            alpha: 1
        )
    })
}

// MARK: - ServiceTile (带 logo 的 squircle)
//
// 见 docs/03-设计风格.md §11.2。
// Popover 服务行左侧、Stats sidebar 服务条目、Onboarding 账号列表都用。

struct ServiceTile: View {
    /// 资源名,对应 Resources/Logos/ 下的 svg。
    let logoName: String
    /// 备用字母(SVG 加载失败时显示)。
    let fallback: String
    /// 背景填充色(服务识别色)。Codex 走 OpenAI 官方观感(白底黑 logo),会忽略此值。
    let tint: Color
    /// tile 尺寸,默认 Popover 用 22pt。
    var size: CGFloat = 22
    /// 内 logo 尺寸,默认 14pt。
    var logoSize: CGFloat = 14
    /// 圆角半径,默认 6pt。
    var cornerRadius: CGFloat = 6

    /// Codex 的 tile 还原 OpenAI 官方品牌图标:白底黑 logo + 极细边框。
    /// 其余地方(文字色、环形、图表)的 `Color.codexAccent` 是蓝紫(#718DFF / #8FA6FF),不受影响。
    private var isOpenAIBrand: Bool { logoName == "codex" }

    private var background: Color { isOpenAIBrand ? .white : tint }
    private var foreground: Color { isOpenAIBrand ? .black : .white }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(background)
            .frame(width: size, height: size)
            .overlay {
                if isOpenAIBrand {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                }
            }
            .overlay(logoView)
    }

    @ViewBuilder
    private var logoView: some View {
        if let nsImage = LogoCache.image(named: logoName) {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(foreground)
                .frame(width: logoSize, height: logoSize)
        } else {
            Text(fallback)
                .font(.system(size: logoSize * 0.7, weight: .semibold))
                .foregroundStyle(foreground)
        }
    }
}

private enum LogoCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(named name: String) -> NSImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = true
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

// MARK: - ProgressBar (横条)
//
// 见 docs/03-设计风格.md §11.4。
// Popover weekly 5/2.5、HUD 4/2、Dense compact 3/1.5、BigStat 6/3。

struct ProgressBar: View {
    let value: Double
    let tint: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))

                Capsule()
                    .fill(tint)
                    .frame(width: max(0, proxy.size.width * clampedValue))
                    .animation(.easeOut(duration: 0.25), value: clampedValue)
            }
        }
        .frame(height: height)
    }

    private var clampedValue: CGFloat {
        max(0, min(1, CGFloat(value)))
    }
}

// MARK: - Reset time (compact)
//
// 从 Core/L10n.swift 抽出,主 App 悬浮窗与小组件共用同一套紧凑格式。
// 纯函数、不依赖 SettingsStore,所以两个 target 都能编译。
//
// 小组件必须用它生成**静态文本**而不是 Text(date:style:):后者的固有宽度在布局期不确定,
// 会在 HStack 里抢走超额宽度、把同行的其他元素压成 0 宽。倒计时的走动改由 timeline 的
// 多个 entry 推进(见 Provider.getTimeline)。
/// 紧凑相对时长,如 "4h37m" / "5d3h" / "<1m"(无空格无后缀)。
/// 供悬浮窗的 formatResetCompact / formatResetAltCompact 与小组件共享。
func compactRelativeReset(_ resetsAt: Date, now: Date) -> String {
    let seconds = max(0, Int(resetsAt.timeIntervalSince(now)))
    if seconds < 60 { return "<1m" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    if hours < 24 {
        return remainingMinutes > 0 ? "\(hours)h\(remainingMinutes)m" : "\(hours)h"
    }
    let days = hours / 24
    let remainingHours = hours % 24
    return remainingHours > 0 ? "\(days)d\(remainingHours)h" : "\(days)d"
}
