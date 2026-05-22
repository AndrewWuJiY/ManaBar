import SwiftUI

@main
struct CCBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverRootView()
                .environment(appState)
        } label: {
            MenuBarLabel()
                .environment(appState)
                .task { await appState.bootstrap() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView()
                .environment(appState)
        }
    }
}
