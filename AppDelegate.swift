import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - URL scheme
    //
    // 桌面小组件点击跳转:manabar://stats → 打开主窗口「用量统计」。
    // 见 docs/草案-桌面小组件.md §5。
    //
    // 处理放在 AppDelegate 而不是 SwiftUI 的 onOpenURL:本 App 的根场景是 MenuBarExtra,
    // onOpenURL 挂在其中行为不稳,AppDelegate 的回调是确定的。

    /// AppState 由 ManaBarApp 在启动时注入(同 FloatingPanelController.attach 的做法)。
    private weak static var appState: AppState?
    /// 冷启动时 URL 会早于 SwiftUI scene 的 .task 到达,先存下来,注入后立刻补发。
    private static var pendingURL: URL?

    static func attach(appState: AppState) {
        self.appState = appState
        if let pending = pendingURL {
            pendingURL = nil
            handle(pending)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.scheme == "manabar" }) else { return }
        Self.handle(url)
    }

    private static func handle(_ url: URL) {
        guard let appState else {
            pendingURL = url
            return
        }
        // 目前只有 stats 一个入口。LSUIElement App 被 URL 唤起后不会自动抢焦点,要显式 activate,
        // 否则窗口开在后台。
        NSApp.activate(ignoringOtherApps: true)
        appState.mainTab = .stats
        appState.shouldOpenMainWindow = true
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // 启动即应用用户选择的外观（跟随系统 / 浅色 / 深色）
        SettingsStore.shared.applyAppearance()

        // 全局快捷键 ⌃⌥F:切换悬浮窗显示/隐藏,并按设置决定是否注册
        HotKeyCenter.shared.onToggleFloating = {
            let settings = SettingsStore.shared
            settings.floatingEnabled.toggle()
            FloatingPanelController.shared.sync()
        }
        HotKeyCenter.shared.setToggleFloatingEnabled(SettingsStore.shared.floatingHotkeyEnabled)
    }
}
