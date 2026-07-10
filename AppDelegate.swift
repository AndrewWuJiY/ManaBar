import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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
