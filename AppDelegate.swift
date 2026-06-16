import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // 启动即应用用户选择的外观（跟随系统 / 浅色 / 深色）
        SettingsStore.shared.applyAppearance()
    }
}
