import SwiftUI
import AppKit

struct MenuBarLabel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Image(nsImage: MenuBarBadgeImage.make(
            codex: appState.codexQuota,
            claude: appState.claudeQuota,
            cursor: appState.cursorQuota,
            showCodex: SettingsStore.shared.effectiveMenuBarShowCodex,
            showClaude: SettingsStore.shared.effectiveMenuBarShowClaude,
            showCursor: SettingsStore.shared.effectiveMenuBarShowCursor,
            window: SettingsStore.shared.menuBarWindow
        ))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(MenuBarBadgeImage.accessibilityLabel(
            codex: appState.codexQuota,
            claude: appState.claudeQuota,
            cursor: appState.cursorQuota,
            showCodex: SettingsStore.shared.effectiveMenuBarShowCodex,
            showClaude: SettingsStore.shared.effectiveMenuBarShowClaude,
            showCursor: SettingsStore.shared.effectiveMenuBarShowCursor,
            window: SettingsStore.shared.menuBarWindow
        ))
    }
}

enum MenuBarLogo {
    private static let cache = NSCache<NSString, NSImage>()
    private static let size = NSSize(width: 18, height: 18)

    static func rawImage(named name: String) -> NSImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.size = size
        cache.setObject(img, forKey: name as NSString)
        return img
    }
}

enum MenuBarBadgeImage {
    private static let height: CGFloat = 22
    private static let font = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.menuBarFont(ofSize: 0).pointSize,
        weight: .regular
    )

    /// 一或两个服务保持原来的疏朗尺寸。三个并排时收紧，并去掉百分号。
    private struct Metrics {
        let icon: CGFloat
        let textGap: CGFloat
        let segmentGap: CGFloat
        let omitPercentSign: Bool

        static let regular = Metrics(icon: 18, textGap: 3, segmentGap: 9, omitPercentSign: false)
        static let compact = Metrics(icon: 16, textGap: 2, segmentGap: 6, omitPercentSign: true)

        static func forCount(_ count: Int) -> Metrics {
            count >= 3 ? .compact : .regular
        }
    }

    /// 官方立方体几乎顶满画布，Codex / Claude 的实心标只占格子的约 80%。
    /// 菜单栏里缩小，让外轮廓和另外两个对齐。
    private static let cursorIconScale: CGFloat = 0.82

    /// 各 logo 画布里透明留白占绘制尺寸的比例。间距按可见边缘算，不按画布边缘。
    private struct LogoInk {
        let leading: CGFloat
        let trailing: CGFloat

        static func of(_ logo: String) -> LogoInk {
            switch logo {
            case "codex": return LogoInk(leading: 0.10, trailing: 0.11)
            case "claude": return LogoInk(leading: 0.10, trailing: 0.10)
            case "cursor": return LogoInk(leading: 0.06, trailing: 0.06)
            default: return LogoInk(leading: 0, trailing: 0)
            }
        }
    }

    private struct Placement {
        let iconX: CGFloat
        let iconSize: CGFloat
        let textX: CGFloat
        let text: String
    }

    private static func iconExtent(logo: String, metrics: Metrics) -> CGFloat {
        let raw = logo == "cursor" ? metrics.icon * cursorIconScale : metrics.icon
        return min(raw, height - 1)
    }

    /// Codex / Claude 的留白已经含在 textGap、segmentGap 里。其它标按自己的留白补齐，可见间距才一致。
    private static func placements(
        items: [BadgeItem],
        texts: [String],
        textWidths: [CGFloat],
        metrics: Metrics
    ) -> [Placement] {
        let referencePad = metrics.icon * 0.10
        let iconTextVisual = metrics.textGap + referencePad
        let segmentVisual = metrics.segmentGap + referencePad
        var x: CGFloat = 0
        var placed: [Placement] = []
        for (index, item) in items.enumerated() {
            let size = iconExtent(logo: item.logo, metrics: metrics)
            let ink = LogoInk.of(item.logo)
            if index > 0 {
                x += segmentVisual - ink.leading * size
            }
            let iconX = x
            x += size
            let text = texts[index]
            var textX = x
            if !text.isEmpty {
                textX = x - ink.trailing * size + iconTextVisual
                x = textX + ceil(textWidths[index])
            }
            placed.append(Placement(iconX: iconX, iconSize: size, textX: textX, text: text))
        }
        return placed
    }

    static func make(
        codex: QuotaSnapshot?,
        claude: QuotaSnapshot?,
        cursor: QuotaSnapshot?,
        showCodex: Bool,
        showClaude: Bool,
        showCursor: Bool,
        window: MenuBarWindowChoice
    ) -> NSImage {
        var items: [BadgeItem] = []
        if showCodex {
            items.append(BadgeItem(logo: "codex", fallback: "C", text: pctText(codex, window: window)))
        }
        if showClaude {
            items.append(BadgeItem(logo: "claude", fallback: "K", text: pctText(claude, window: window)))
        }
        if showCursor {
            items.append(BadgeItem(logo: "cursor", fallback: "R", text: pctText(cursor, window: window, billingCycle: true)))
        }

        let metrics = Metrics.forCount(items.count)
        let attrs = textAttributes
        let displayTexts = items.map { metrics.omitPercentSign ? $0.text.replacingOccurrences(of: "%", with: "") : $0.text }
        let textWidths = displayTexts.map { $0.size(withAttributes: attrs).width }
        let placed = placements(items: items, texts: displayTexts, textWidths: textWidths, metrics: metrics)
        let width = placed.map { item in
            item.text.isEmpty ? item.iconX + item.iconSize : item.textX + ceil(item.text.size(withAttributes: attrs).width)
        }.max() ?? 0

        // 没有任何 item 时仍要返回一个最小图像（至少留一个 logo 占位以免菜单栏图标完全消失）
        if items.isEmpty {
            return placeholderImage()
        }

        // 用 drawingHandler 而非 lockFocus/unlockFocus:
        // 后者拍一张静态位图,可能在状态栏拿到外观/tint 上下文前就生成,导致 MenuBarExtra
        // 首帧空白、要点一下菜单栏才重绘。drawingHandler 会在系统每次需要渲染时(含首次显示、
        // 外观切换)重新调用,菜单栏图标启动即可见。
        let imageWidth = max(ceil(width), metrics.icon)
        let image = NSImage(size: NSSize(width: imageWidth, height: height), flipped: false) { _ in
            for (index, item) in placed.enumerated() {
                drawIcon(items[index], x: item.iconX, size: item.iconSize)
                if !item.text.isEmpty {
                    let textSize = item.text.size(withAttributes: attrs)
                    item.text.draw(at: NSPoint(x: item.textX, y: floor((height - textSize.height) / 2)),
                                   withAttributes: attrs)
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func accessibilityLabel(
        codex: QuotaSnapshot?,
        claude: QuotaSnapshot?,
        cursor: QuotaSnapshot?,
        showCodex: Bool,
        showClaude: Bool,
        showCursor: Bool,
        window: MenuBarWindowChoice
    ) -> String {
        var parts: [String] = []
        if showCodex { parts.append("Codex \(pctText(codex, window: window))") }
        if showClaude { parts.append("Claude \(pctText(claude, window: window))") }
        if showCursor { parts.append("Cursor \(pctText(cursor, window: window, billingCycle: true))") }
        return parts.isEmpty ? "ManaBar" : parts.joined(separator: ", ")
    }

    private static var textAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: NSColor.black
        ]
    }

    private static func pctText(
        _ snap: QuotaSnapshot?,
        window: MenuBarWindowChoice,
        billingCycle: Bool = false
    ) -> String {
        // Cursor 没有 5h / 周窗口,菜单栏只显示账期剩余,不跟「都显示」拼成两段。
        if billingCycle || snap?.app == .cursor {
            return pctOrPlaceholder(snap?.displayBillingCycle())
        }
        // 服务端取消 5h 限制时(如 2026-07 Codex):
        // - 5H 模式:∞ 在菜单栏没有信息量,回退显示周额度
        // - 都显示模式:保留 ∞/WK,让两个窗口语义完整
        switch window {
        case .fiveHour:
            if snap?.fiveHourUnlimited == true { return pctOrPlaceholder(snap?.displayWeekly()) }
            return pctOrPlaceholder(snap?.displayFiveHour())
        case .weekly:
            return pctOrPlaceholder(snap?.displayWeekly())
        case .both:
            let fiveHourText = snap?.fiveHourUnlimited == true ? "∞" : pctOrPlaceholder(snap?.displayFiveHour())
            return "\(fiveHourText)/\(pctOrPlaceholder(snap?.displayWeekly()))"
        }
    }

    private static func pctOrPlaceholder(_ window: QuotaWindow?) -> String {
        guard let window else { return "--" }
        return "\(Int(window.remainingPercent.rounded()))%"
    }

    private static func placeholderImage() -> NSImage {
        let icon = Metrics.regular.icon
        let image = NSImage(size: NSSize(width: icon, height: height), flipped: false) { _ in
            if let img = MenuBarLogo.rawImage(named: "codex") {
                img.draw(in: NSRect(x: 0, y: floor((height - icon) / 2),
                                    width: icon, height: icon))
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawIcon(_ item: BadgeItem, x: CGFloat, size: CGFloat) {
        let rect = NSRect(x: x, y: floor((height - size) / 2), width: size, height: size)
        if let img = MenuBarLogo.rawImage(named: item.logo) {
            img.draw(in: rect)
            return
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        let textSize = item.fallback.size(withAttributes: attrs)
        item.fallback.draw(at: NSPoint(x: x + floor((size - textSize.width) / 2),
                                       y: floor((height - textSize.height) / 2)),
                           withAttributes: attrs)
    }

    private struct BadgeItem {
        let logo: String
        let fallback: String
        let text: String
    }
}
