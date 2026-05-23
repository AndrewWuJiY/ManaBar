import Foundation

// MARK: - Language model
//
// 见 docs/03-设计风格.md §5。
// 应用界面只显示一种语言:跟随系统(根据 Locale.current 解析为 zh / en)、中文、English。
// 调用方使用全局 `tr(en, zh)` 选词,由 SettingsStore.shared.resolvedLanguage 决定渲染哪一种。

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zh
    case en

    var id: String { rawValue }

    /// Picker 中始终双语显示,任意档位用户都需要看懂。
    var displayName: String {
        switch self {
        case .system: return "Follow System · 跟随系统"
        case .zh: return "中文"
        case .en: return "English"
        }
    }
}

enum ResolvedLanguage {
    case zh
    case en
}

@MainActor
enum L10n {
    static var current: ResolvedLanguage { SettingsStore.shared.resolvedLanguage }

    static func tr(_ english: String, _ chinese: String) -> String {
        switch current {
        case .zh: return chinese
        case .en: return english
        }
    }
}

/// SwiftUI view body 内的便捷选词函数。等同于 `L10n.tr(en, zh)`。
@MainActor
func tr(_ english: String, _ chinese: String) -> String {
    L10n.tr(english, chinese)
}

/// 根据用户设置把额度重置时间格式化为「剩余时长」或「绝对时间(MM-dd HH:mm)」。
@MainActor
func formatResetHint(_ resetsAt: Date?, now: Date = Date()) -> String {
    guard let resetsAt else { return tr("reset unknown", "时间未知") }

    switch SettingsStore.shared.resetTimeDisplay {
    case .absolute:
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        let stamp = formatter.string(from: resetsAt)
        return tr("resets at \(stamp)", "\(stamp) 重置")
    case .relative:
        let seconds = max(0, Int(resetsAt.timeIntervalSince(now)))
        if seconds < 60 { return tr("resets in <1m", "<1m 后重置") }
        let minutes = seconds / 60
        if minutes < 60 { return tr("resets in \(minutes)m", "\(minutes)m 后重置") }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours < 24 {
            return remainingMinutes > 0
                ? tr("resets in \(hours)h \(remainingMinutes)m", "\(hours)h \(remainingMinutes)m 后重置")
                : tr("resets in \(hours)h", "\(hours)h 后重置")
        }
        let days = hours / 24
        let remainingHours = hours % 24
        return remainingHours > 0
            ? tr("resets in \(days)d \(remainingHours)h", "\(days)d \(remainingHours)h 后重置")
            : tr("resets in \(days)d", "\(days)d 后重置")
    }
}

/// Popover 等紧凑场景使用:仅返回 `4h37m` / `5d3h` / `<1m` 这种无空格无后缀的形式。
@MainActor
func formatResetCompact(_ resetsAt: Date?, now: Date = Date()) -> String {
    guard let resetsAt else { return "—" }

    switch SettingsStore.shared.resetTimeDisplay {
    case .absolute:
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: resetsAt)
    case .relative:
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
}
