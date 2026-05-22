import SwiftUI
import AppKit

struct MenuBarLabel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Image(nsImage: MenuBarBadgeImage.make(codex: appState.codexQuota,
                                              claude: appState.claudeQuota))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(MenuBarBadgeImage.accessibilityLabel(codex: appState.codexQuota,
                                                                 claude: appState.claudeQuota))
    }
}

enum MenuBarLogo {
    private static let cache = NSCache<NSString, NSImage>()
    private static let size = NSSize(width: 14, height: 14)

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
    private static let iconSize: CGFloat = 14
    private static let height: CGFloat = 18
    private static let iconTextGap: CGFloat = 2
    private static let segmentGap: CGFloat = 7
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

    static func make(codex: QuotaSnapshot?, claude: QuotaSnapshot?) -> NSImage {
        let items = [
            BadgeItem(logo: "codex", fallback: "C", text: pctText(codex)),
            BadgeItem(logo: "claude", fallback: "K", text: pctText(claude))
        ]
        let attrs = textAttributes
        let textWidths = items.map { $0.text.size(withAttributes: attrs).width }
        let width = items.enumerated().reduce(CGFloat.zero) { partial, entry in
            let gap = entry.offset == 0 ? CGFloat.zero : segmentGap
            return partial + gap + iconSize + iconTextGap + ceil(textWidths[entry.offset])
        }

        let image = NSImage(size: NSSize(width: ceil(width), height: height))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        var x: CGFloat = 0
        for (index, item) in items.enumerated() {
            if index > 0 { x += segmentGap }
            drawIcon(item, x: x)
            x += iconSize + iconTextGap

            let textSize = item.text.size(withAttributes: attrs)
            item.text.draw(at: NSPoint(x: x, y: floor((height - textSize.height) / 2)),
                           withAttributes: attrs)
            x += ceil(textSize.width)
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    static func accessibilityLabel(codex: QuotaSnapshot?, claude: QuotaSnapshot?) -> String {
        "Codex \(pctText(codex)), Claude \(pctText(claude))"
    }

    private static var textAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: NSColor.black
        ]
    }

    private static func pctText(_ snap: QuotaSnapshot?) -> String {
        guard let w = snap?.fiveHour else { return "--" }
        return "\(Int(w.remainingPercent.rounded()))%"
    }

    private static func drawIcon(_ item: BadgeItem, x: CGFloat) {
        let rect = NSRect(x: x, y: floor((height - iconSize) / 2), width: iconSize, height: iconSize)
        if let img = MenuBarLogo.rawImage(named: item.logo) {
            img.draw(in: rect)
            return
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        let size = item.fallback.size(withAttributes: attrs)
        item.fallback.draw(at: NSPoint(x: x + floor((iconSize - size.width) / 2),
                                       y: floor((height - size.height) / 2)),
                           withAttributes: attrs)
    }

    private struct BadgeItem {
        let logo: String
        let fallback: String
        let text: String
    }
}
