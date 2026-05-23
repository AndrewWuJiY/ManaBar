import SwiftUI

enum MainTab: Hashable {
    case stats
    case settings
}

struct MainWindowRootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var bindable = appState
        TabView(selection: $bindable.mainTab) {
            StatsView()
                .tabItem { Label(tr("Statistics", "用量统计"), systemImage: "chart.bar") }
                .tag(MainTab.stats)

            SettingsRootView()
                .tabItem { Label(tr("Settings", "设置"), systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
        .frame(minWidth: 1040, minHeight: 520)
    }
}
