import Foundation

enum MenuBarWindow {
    case fiveHour
    case weekly
}

enum MenuBarLabelFormatter {
    /// 默认显示规则：`C:34% · K:60%`，百分比为剩余额度。
    /// - 缺数据的应用显示 `--`（如 `C:-- · K:60%`）
    /// - 两边都没数据返回空字符串（只显示图标）
    static func format(
        codex: QuotaSnapshot?,
        claude: QuotaSnapshot?,
        window: MenuBarWindow = .fiveHour,
        showCodex: Bool = true,
        showClaude: Bool = true
    ) -> String {
        var parts: [String] = []
        if showCodex {
            parts.append("C:\(pct(codex, window: window))")
        }
        if showClaude {
            parts.append("K:\(pct(claude, window: window))")
        }
        if parts.isEmpty { return "" }
        let hasAnyData = (showCodex && pickWindow(codex, window) != nil)
            || (showClaude && pickWindow(claude, window) != nil)
        return hasAnyData ? parts.joined(separator: " · ") : ""
    }

    private static func pct(_ snap: QuotaSnapshot?, window: MenuBarWindow) -> String {
        guard let w = pickWindow(snap, window) else { return "--" }
        return "\(Int(w.remainingPercent.rounded()))%"
    }

    private static func pickWindow(_ snap: QuotaSnapshot?, _ window: MenuBarWindow) -> QuotaWindow? {
        guard let snap else { return nil }
        switch window {
        case .fiveHour: return snap.fiveHour
        case .weekly: return snap.weekly
        }
    }
}
