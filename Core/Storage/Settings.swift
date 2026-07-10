import AppKit
import CoreGraphics
import Foundation
import Observation
import ServiceManagement

enum AppAppearanceChoice: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

enum QuotaIntervalChoice: String, CaseIterable, Identifiable {
    case m1
    case m2
    case m3
    case m5
    case m10

    var id: String { rawValue }

    var seconds: TimeInterval? {
        switch self {
        case .m1: return 60
        case .m2: return 2 * 60
        case .m3: return 3 * 60
        case .m5: return 5 * 60
        case .m10: return 10 * 60
        }
    }

    var displayName: String {
        switch self {
        case .m1: return "1 分钟"
        case .m2: return "2 分钟"
        case .m3: return "3 分钟"
        case .m5: return "5 分钟"
        case .m10: return "10 分钟"
        }
    }
}

enum UsageIntervalChoice: String, CaseIterable, Identifiable {
    case m1
    case m2
    case m3
    case m5
    case m10

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .m1: return 60
        case .m2: return 2 * 60
        case .m3: return 3 * 60
        case .m5: return 5 * 60
        case .m10: return 10 * 60
        }
    }

    var displayName: String {
        switch self {
        case .m1: return "1 分钟"
        case .m2: return "2 分钟"
        case .m3: return "3 分钟"
        case .m5: return "5 分钟"
        case .m10: return "10 分钟"
        }
    }
}

enum ResetTimeDisplay: String, CaseIterable, Identifiable {
    case relative
    case absolute

    var id: String { rawValue }
}

enum MenuBarWindowChoice: String, CaseIterable, Identifiable {
    case fiveHour
    case weekly
    case both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fiveHour: return "5H 窗口"
        case .weekly: return "WK 窗口"
        case .both: return "两者都显示"
        }
    }
}

@Observable
@MainActor
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    // 账号
    var showCodex: Bool { didSet { defaults.set(showCodex, forKey: Keys.showCodex) } }
    var showClaude: Bool { didSet { defaults.set(showClaude, forKey: Keys.showClaude) } }

    // 菜单栏
    var menuBarShowCodex: Bool { didSet { defaults.set(menuBarShowCodex, forKey: Keys.menuBarShowCodex) } }
    var menuBarShowClaude: Bool { didSet { defaults.set(menuBarShowClaude, forKey: Keys.menuBarShowClaude) } }
    var menuBarWindow: MenuBarWindowChoice { didSet { defaults.set(menuBarWindow.rawValue, forKey: Keys.menuBarWindow) } }

    // 悬浮窗（占位，M8 接）
    var floatingEnabled: Bool { didSet { defaults.set(floatingEnabled, forKey: Keys.floatingEnabled) } }
    var floatingShowCodex: Bool { didSet { defaults.set(floatingShowCodex, forKey: Keys.floatingShowCodex) } }
    var floatingShowClaude: Bool { didSet { defaults.set(floatingShowClaude, forKey: Keys.floatingShowClaude) } }
    var floatingShowReset: Bool { didSet { defaults.set(floatingShowReset, forKey: Keys.floatingShowReset) } }

    /// 全局快捷键 ⌃⌥F 显示/隐藏悬浮窗（Carbon HotKey,后台可用,见 Core/HotKey.swift）
    var floatingHotkeyEnabled: Bool {
        didSet {
            defaults.set(floatingHotkeyEnabled, forKey: Keys.floatingHotkeyEnabled)
            HotKeyCenter.shared.setToggleFloatingEnabled(floatingHotkeyEnabled)
        }
    }

    // 刷新
    var quotaInterval: QuotaIntervalChoice { didSet { defaults.set(quotaInterval.rawValue, forKey: Keys.quotaInterval) } }
    var usageInterval: UsageIntervalChoice { didSet { defaults.set(usageInterval.rawValue, forKey: Keys.usageInterval) } }
    var resetTimeDisplay: ResetTimeDisplay { didSet { defaults.set(resetTimeDisplay.rawValue, forKey: Keys.resetTimeDisplay) } }

    /// 是否在 Popover 中显示 OpenAI / Anthropic 服务状态圆点
    var showServiceStatus: Bool { didSet { defaults.set(showServiceStatus, forKey: Keys.showServiceStatus) } }

    // 通用
    /// 外观：跟随系统 / 浅色 / 深色。生效见 `applyAppearance()`。
    var appAppearance: AppAppearanceChoice {
        didSet {
            defaults.set(appAppearance.rawValue, forKey: Keys.appAppearance)
            applyAppearance()
        }
    }

    var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: Keys.appLanguage)
            // 切换语言立即刷新 _cachedLanguage,不依赖下一次 resolvedLanguage 渲染访问
            _ = resolvedLanguage
        }
    }
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) } }

    /// 隐私模式：Popover 中主账号邮箱、Codex 副账号名称均隐藏
    var privacyMode: Bool { didSet { defaults.set(privacyMode, forKey: Keys.privacyMode) } }

    /// 是否已经向用户解释过"接下来会出现 Keychain 授权弹窗"
    var didShowKeychainPrompt: Bool {
        didSet { defaults.set(didShowKeychainPrompt, forKey: Keys.didShowKeychainPrompt) }
    }

    /// 是否已经完成首次启动引导
    var didCompleteOnboarding: Bool {
        didSet { defaults.set(didCompleteOnboarding, forKey: Keys.didCompleteOnboarding) }
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 一次性迁移旧 CCBar 数据/设置(必须在读取任何 key 之前,也早于文件存储读取)
        LegacyMigration.runIfNeeded(defaults: defaults)
        // 账号
        showCodex = defaults.object(forKey: Keys.showCodex) as? Bool ?? true
        showClaude = defaults.object(forKey: Keys.showClaude) as? Bool ?? true
        // 菜单栏
        menuBarShowCodex = defaults.object(forKey: Keys.menuBarShowCodex) as? Bool ?? true
        menuBarShowClaude = defaults.object(forKey: Keys.menuBarShowClaude) as? Bool ?? true
        let mbWindowRaw = defaults.string(forKey: Keys.menuBarWindow) ?? MenuBarWindowChoice.fiveHour.rawValue
        menuBarWindow = MenuBarWindowChoice(rawValue: mbWindowRaw) ?? .fiveHour
        // 悬浮窗
        floatingEnabled = defaults.object(forKey: Keys.floatingEnabled) as? Bool ?? false
        floatingShowCodex = defaults.object(forKey: Keys.floatingShowCodex) as? Bool ?? true
        floatingShowClaude = defaults.object(forKey: Keys.floatingShowClaude) as? Bool ?? true
        floatingShowReset = defaults.object(forKey: Keys.floatingShowReset) as? Bool ?? true
        floatingHotkeyEnabled = defaults.object(forKey: Keys.floatingHotkeyEnabled) as? Bool ?? true
        // 刷新
        let qiRaw = defaults.string(forKey: Keys.quotaInterval) ?? QuotaIntervalChoice.m2.rawValue
        quotaInterval = QuotaIntervalChoice(rawValue: qiRaw) ?? .m2
        let uiRaw = defaults.string(forKey: Keys.usageInterval) ?? UsageIntervalChoice.m2.rawValue
        usageInterval = UsageIntervalChoice(rawValue: uiRaw) ?? .m2
        let rtdRaw = defaults.string(forKey: Keys.resetTimeDisplay) ?? ResetTimeDisplay.relative.rawValue
        resetTimeDisplay = ResetTimeDisplay(rawValue: rtdRaw) ?? .relative
        showServiceStatus = defaults.object(forKey: Keys.showServiceStatus) as? Bool ?? true
        // 通用：launchAtLogin 以系统当前注册状态为准
        let appearanceRaw = defaults.string(forKey: Keys.appAppearance) ?? AppAppearanceChoice.system.rawValue
        appAppearance = AppAppearanceChoice(rawValue: appearanceRaw) ?? .system
        let langRaw = defaults.string(forKey: Keys.appLanguage) ?? AppLanguage.system.rawValue
        appLanguage = AppLanguage(rawValue: langRaw) ?? .system
        let stored = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        launchAtLogin = stored
        privacyMode = defaults.object(forKey: Keys.privacyMode) as? Bool ?? true
        didShowKeychainPrompt = defaults.object(forKey: Keys.didShowKeychainPrompt) as? Bool ?? false
        didCompleteOnboarding = defaults.object(forKey: Keys.didCompleteOnboarding) as? Bool ?? false
        // 立即播种 _cachedLanguage,避免首个 tr() 调用早于任何 resolvedLanguage 访问时拿到默认值
        _ = resolvedLanguage
    }

    /// 账号与菜单栏开关的合取，最终决定菜单栏该不该画该应用
    var effectiveMenuBarShowCodex: Bool { showCodex && menuBarShowCodex }
    var effectiveMenuBarShowClaude: Bool { showClaude && menuBarShowClaude }

    /// 悬浮窗的行可见性同样需要叠加全局「显示该应用」开关
    var effectiveFloatingShowCodex: Bool { showCodex && floatingShowCodex }
    var effectiveFloatingShowClaude: Bool { showClaude && floatingShowClaude }

    /// 把 `appLanguage` 解析为最终渲染语言。`.system` 看系统首选语言是否以 `zh` 开头。
    /// 不用 `Locale.current`:它返回的是 App 当前生效的本地化语言,工程未添加中文资源时会回退到开发语言 `en`,
    /// 导致即便系统设为中文也判定为英文。`Locale.preferredLanguages.first` 反映用户在系统设置中排首位的语言,
    /// 与 App 本地化无关,例如 `zh-Hans-CN` / `zh-Hant-TW`,前缀判断对简繁均成立。
    var resolvedLanguage: ResolvedLanguage {
        let result: ResolvedLanguage
        switch appLanguage {
        case .system:
            let code = Locale.preferredLanguages.first ?? "en"
            result = code.hasPrefix("zh") ? .zh : .en
        case .zh: result = .zh
        case .en: result = .en
        }
        _cachedLanguage = result
        return result
    }

    // MARK: - Floating panel frame

    /// 悬浮窗 frame，nil 表示尚未拖动过；启动时由 controller 还原
    var floatingPanelFrame: CGRect? {
        get {
            guard
                let x = defaults.object(forKey: Keys.floatingFrameX) as? Double,
                let y = defaults.object(forKey: Keys.floatingFrameY) as? Double,
                let w = defaults.object(forKey: Keys.floatingFrameW) as? Double,
                let h = defaults.object(forKey: Keys.floatingFrameH) as? Double,
                w > 0, h > 0
            else { return nil }
            return CGRect(x: x, y: y, width: w, height: h)
        }
        set {
            if let r = newValue {
                defaults.set(Double(r.origin.x), forKey: Keys.floatingFrameX)
                defaults.set(Double(r.origin.y), forKey: Keys.floatingFrameY)
                defaults.set(Double(r.size.width), forKey: Keys.floatingFrameW)
                defaults.set(Double(r.size.height), forKey: Keys.floatingFrameH)
            } else {
                defaults.removeObject(forKey: Keys.floatingFrameX)
                defaults.removeObject(forKey: Keys.floatingFrameY)
                defaults.removeObject(forKey: Keys.floatingFrameW)
                defaults.removeObject(forKey: Keys.floatingFrameH)
            }
        }
    }

    // MARK: - Appearance

    /// 把当前外观设置应用到整个 App（主窗口 / Popover / 悬浮窗都跟随 NSApp.appearance）。
    /// 启动时由 AppDelegate 调一次，之后由 `appAppearance.didSet` 触发。
    func applyAppearance() {
        switch appAppearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: - Launch at login

    /// 当前系统记录的注册状态
    var launchAtLoginRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 切换开机自启；失败时抛出原始错误
    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        launchAtLogin = enabled
    }

    private enum Keys {
        static let showCodex = "manabar.settings.showCodex"
        static let showClaude = "manabar.settings.showClaude"
        static let menuBarShowCodex = "manabar.settings.menuBarShowCodex"
        static let menuBarShowClaude = "manabar.settings.menuBarShowClaude"
        static let menuBarWindow = "manabar.settings.menuBarWindow"
        static let floatingEnabled = "manabar.settings.floatingEnabled"
        static let floatingShowCodex = "manabar.settings.floatingShowCodex"
        static let floatingShowClaude = "manabar.settings.floatingShowClaude"
        static let floatingShowReset = "manabar.settings.floatingShowReset"
        static let floatingHotkeyEnabled = "manabar.settings.floatingHotkeyEnabled"
        static let quotaInterval = "manabar.settings.quotaInterval"
        static let usageInterval = "manabar.settings.usageInterval"
        static let resetTimeDisplay = "manabar.settings.resetTimeDisplay"
        static let showServiceStatus = "manabar.settings.showServiceStatus"
        static let appAppearance = "manabar.settings.appAppearance"
        static let launchAtLogin = "manabar.settings.launchAtLogin"
        static let appLanguage = "manabar.settings.appLanguage"
        static let privacyMode = "manabar.settings.privacyMode"
        static let didShowKeychainPrompt = "manabar.settings.didShowKeychainPrompt"
        static let didCompleteOnboarding = "manabar.settings.didCompleteOnboarding"
        static let floatingFrameX = "manabar.settings.floatingFrame.x"
        static let floatingFrameY = "manabar.settings.floatingFrame.y"
        static let floatingFrameW = "manabar.settings.floatingFrame.w"
        static let floatingFrameH = "manabar.settings.floatingFrame.h"
    }
}

// MARK: - Legacy migration (CCBar → ManaBar)
//
// 2026-06 改名 + 换 Bundle ID 后,旧版数据落在 `~/Library/Application Support/CCBar/`
// 和旧 UserDefaults 域 `com.nanvon.ccbar`(键前缀 `ccbar.settings.`)。这里在首启时做
// 一次性、幂等的迁移,让用户无感升级。
//
// 不迁移钥匙串:导入 Codex token 的服务名故意保留 `com.cc-bar.codex.imported`(见
// ImportedCodexStore);换签名身份后若系统拒绝访问,用户重导一次即可。
enum LegacyMigration {
    private static let oldSupportDir = "CCBar"
    private static let newSupportDir = "ManaBar"
    private static let oldDefaultsSuite = "com.nanvon.ccbar"
    private static let oldKeyPrefix = "ccbar.settings."
    private static let newKeyPrefix = "manabar.settings."
    private static let migratedFlagKey = "manabar.settings._migratedFromCCBar"

    static func runIfNeeded(defaults: UserDefaults) {
        guard !defaults.bool(forKey: migratedFlagKey) else { return }
        migrateSupportFolder()
        migrateDefaults(into: defaults)
        defaults.set(true, forKey: migratedFlagKey)
    }

    /// 旧数据目录整目录拷到新目录(仅当新目录尚不存在或为空时)。
    private static func migrateSupportFolder() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let oldDir = support.appendingPathComponent(oldSupportDir, isDirectory: true)
        let newDir = support.appendingPathComponent(newSupportDir, isDirectory: true)

        guard fm.fileExists(atPath: oldDir.path) else { return }
        let existing = (try? fm.contentsOfDirectory(atPath: newDir.path)) ?? []
        guard existing.isEmpty else { return }   // 新目录已有内容 → 视为迁移过,不覆盖

        try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        let items = (try? fm.contentsOfDirectory(at: oldDir, includingPropertiesForKeys: nil)) ?? []
        for item in items {
            let dest = newDir.appendingPathComponent(item.lastPathComponent)
            if !fm.fileExists(atPath: dest.path) {
                try? fm.copyItem(at: item, to: dest)
            }
        }
    }

    /// 旧 UserDefaults 域里的 `ccbar.settings.*` 拷成新版的 `manabar.settings.*`。
    /// 仅在新键尚未存在时写入,避免覆盖用户在新版里已经改过的设置。
    private static func migrateDefaults(into defaults: UserDefaults) {
        guard let oldDomain = defaults.persistentDomain(forName: oldDefaultsSuite) else { return }
        for (key, value) in oldDomain where key.hasPrefix(oldKeyPrefix) {
            let newKey = newKeyPrefix + key.dropFirst(oldKeyPrefix.count)
            if defaults.object(forKey: newKey) == nil {
                defaults.set(value, forKey: newKey)
            }
        }
    }
}
