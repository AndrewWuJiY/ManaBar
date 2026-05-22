import SwiftUI

struct SettingsRootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gearshape") }

            AccountSettingsView()
                .tabItem { Label("账号", systemImage: "person.crop.circle") }

            MenuBarSettingsView()
                .tabItem { Label("菜单栏", systemImage: "menubar.rectangle") }

            RefreshSettingsView()
                .tabItem { Label("刷新", systemImage: "arrow.clockwise") }
        }
        .frame(width: 480, height: 320)
    }
}

private struct GeneralSettingsView: View {
    var body: some View {
        Form { Text("待接入") }
    }
}

private struct AccountSettingsView: View {
    var body: some View {
        Form { Text("待接入") }
    }
}

private struct MenuBarSettingsView: View {
    var body: some View {
        Form { Text("待接入") }
    }
}

private struct RefreshSettingsView: View {
    var body: some View {
        Form { Text("待接入") }
    }
}
