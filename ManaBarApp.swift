import SwiftUI

@main
struct ManaBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverRootView()
                .environment(appState)
        } label: {
            MenuBarLabelRoot()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Window("ManaBar", id: "main") {
            MainWindowRootView()
                .environment(appState)
        }
        .defaultSize(width: 1280, height: 680)
        .commands {
            AppCommands(appState: appState)
        }

        Window(tr("Welcome", "欢迎"), id: "onboarding") {
            OnboardingView()
                .environment(appState)
        }
        .defaultSize(width: 620, height: 520)
        .windowResizability(.contentSize)
    }
}

/// 包一层 view 以便用 @Environment(\.openWindow) 触发 Onboarding。
private struct MenuBarLabelRoot: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarLabel()
            .task {
                await appState.bootstrap()
                FloatingPanelController.shared.attach(appState: appState)
                FloatingPanelController.shared.sync()
            }
            .onChange(of: appState.shouldShowOnboarding) { _, show in
                guard show else { return }
                appState.shouldShowOnboarding = false
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "onboarding")
            }
            .onChange(of: appState.shouldOpenMainWindow) { _, open in
                guard open else { return }
                appState.shouldOpenMainWindow = false
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
    }
}

/// 主窗口 / 刷新 / 设置 的全局快捷键。
/// ⌘Q 由 SwiftUI 默认提供;Esc 关闭 popover 由 MenuBarExtra(.window) 默认提供。
private struct AppCommands: Commands {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(tr("Preferences…", "设置")) {
                appState.mainTab = .settings
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .windowList) {
            Button(tr("Statistics", "统计")) {
                appState.mainTab = .stats
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .keyboardShortcut("1", modifiers: .command)

            Button(tr("Refresh now", "立即刷新")) {
                Task { await appState.refreshNow() }
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}
