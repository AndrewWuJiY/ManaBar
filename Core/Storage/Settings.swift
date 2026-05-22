import Foundation

@MainActor
final class SettingsStore {
    static let shared = SettingsStore()
    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
}
