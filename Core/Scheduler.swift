import Foundation

@MainActor
final class Scheduler {
    private weak var appState: AppState?
    private var quotaTask: Task<Void, Never>?
    private var usageTask: Task<Void, Never>?
    private var serviceStatusTask: Task<Void, Never>?
    private(set) var quotaInterval: TimeInterval?
    private(set) var usageInterval: TimeInterval?

    /// statuspage.io 变化很慢,固定 5 分钟一次,不跟 quotaInterval 抖。
    private let serviceStatusInterval: TimeInterval = 5 * 60

    func start(appState: AppState, quotaInterval: TimeInterval?, usageInterval: TimeInterval?) {
        self.appState = appState
        self.quotaInterval = quotaInterval
        self.usageInterval = usageInterval
        stop()
        startQuotaLoop()
        startUsageLoop()
        startServiceStatusLoop()
    }

    func stop() {
        quotaTask?.cancel()
        quotaTask = nil
        usageTask?.cancel()
        usageTask = nil
        serviceStatusTask?.cancel()
        serviceStatusTask = nil
    }

    /// 立即触发一次刷新（不打断现有周期）
    func refreshNow() {
        guard let appState else { return }
        Task { await appState.refreshQuotas(reason: .userInitiated) }
    }

    func setQuotaInterval(_ seconds: TimeInterval?) {
        guard seconds != quotaInterval else { return }
        quotaInterval = seconds
        quotaTask?.cancel()
        quotaTask = nil
        startQuotaLoop()
    }

    func setUsageInterval(_ seconds: TimeInterval?) {
        guard seconds != usageInterval else { return }
        usageInterval = seconds
        usageTask?.cancel()
        usageTask = nil
        startUsageLoop()
    }

    private func startQuotaLoop() {
        guard let interval = quotaInterval, interval > 0 else { return }
        quotaTask = Task { [weak self] in
            await self?.quotaLoop(interval: interval)
        }
    }

    private func startUsageLoop() {
        guard let interval = usageInterval, interval > 0 else { return }
        usageTask = Task { [weak self] in
            await self?.usageLoop(interval: interval)
        }
    }

    private func startServiceStatusLoop() {
        let interval = serviceStatusInterval
        serviceStatusTask = Task { [weak self] in
            await self?.serviceStatusLoop(interval: interval)
        }
    }

    private func quotaLoop(interval: TimeInterval) async {
        while !Task.isCancelled {
            let nanos = UInt64(interval * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanos)
            } catch {
                return
            }
            guard let appState, !Task.isCancelled else { return }
            await appState.refreshQuotas(reason: .periodic)
        }
    }

    private func usageLoop(interval: TimeInterval) async {
        while !Task.isCancelled {
            let nanos = UInt64(interval * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanos)
            } catch {
                return
            }
            guard let appState, !Task.isCancelled else { return }
            await appState.usageService.scanNow()
        }
    }

    private func serviceStatusLoop(interval: TimeInterval) async {
        while !Task.isCancelled {
            let nanos = UInt64(interval * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanos)
            } catch {
                return
            }
            guard let appState, !Task.isCancelled else { return }
            await appState.refreshServiceStatus()
        }
    }
}
