import Foundation

@MainActor
final class Scheduler {
    private weak var appState: AppState?
    private var task: Task<Void, Never>?
    private(set) var quotaInterval: TimeInterval = 120

    func start(appState: AppState, quotaInterval: TimeInterval = 120) {
        self.appState = appState
        self.quotaInterval = quotaInterval
        stop()
        task = Task { [weak self] in
            await self?.loop()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// 立即触发一次刷新（不打断现有周期）
    func refreshNow() {
        guard let appState else { return }
        Task { await appState.refreshQuotas(reason: .userInitiated) }
    }

    func setQuotaInterval(_ seconds: TimeInterval) {
        guard seconds != quotaInterval, let appState else { return }
        quotaInterval = seconds
        start(appState: appState, quotaInterval: seconds)
    }

    private func loop() async {
        while !Task.isCancelled {
            let nanos = UInt64(quotaInterval * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanos)
            } catch {
                return
            }
            guard let appState, !Task.isCancelled else { return }
            await appState.refreshQuotas(reason: .periodic)
        }
    }
}
