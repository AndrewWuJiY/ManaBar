import Foundation

@MainActor
final class Scheduler {
    private weak var appState: AppState?
    private var quotaTask: Task<Void, Never>?
    private var usageTask: Task<Void, Never>?
    private var serviceStatusTask: Task<Void, Never>?
    private var widgetHeartbeatTask: Task<Void, Never>?
    private var remotePricingTask: Task<Void, Never>?
    private(set) var quotaInterval: TimeInterval?
    private(set) var usageInterval: TimeInterval?

    /// statuspage.io 变化很慢,固定 5 分钟一次,不跟 quotaInterval 抖。
    private let serviceStatusInterval: TimeInterval = 5 * 60

    /// 远程价格表检查间隔。真正请求由 `AppState.refreshRemotePricing` 按「距上次成功 ≥ 12h」判断,
    /// 这里每小时检查一次,睡眠唤醒后也能较快补上。
    private let remotePricingCheckInterval: TimeInterval = 60 * 60

    /// 桌面小组件心跳。同样固定 5 分钟、不跟 quotaInterval 抖:
    /// 小组件靠它把「主 App 未运行」空态的翻转时刻不断往后推,见 docs/草案-桌面小组件.md §4.1。
    private let widgetHeartbeatInterval: TimeInterval = WidgetSharedStore.heartbeatInterval

    func start(appState: AppState, quotaInterval: TimeInterval?, usageInterval: TimeInterval?) {
        self.appState = appState
        self.quotaInterval = quotaInterval
        self.usageInterval = usageInterval
        stop()
        startQuotaLoop()
        startUsageLoop()
        startServiceStatusLoop()
        startWidgetHeartbeatLoop()
        startRemotePricingLoop()
    }

    func stop() {
        quotaTask?.cancel()
        quotaTask = nil
        usageTask?.cancel()
        usageTask = nil
        serviceStatusTask?.cancel()
        serviceStatusTask = nil
        widgetHeartbeatTask?.cancel()
        widgetHeartbeatTask = nil
        remotePricingTask?.cancel()
        remotePricingTask = nil
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

    private func startWidgetHeartbeatLoop() {
        let interval = widgetHeartbeatInterval
        widgetHeartbeatTask = Task { [weak self] in
            await self?.widgetHeartbeatLoop(interval: interval)
        }
    }

    private func startRemotePricingLoop() {
        let interval = remotePricingCheckInterval
        remotePricingTask = Task { [weak self] in
            await self?.remotePricingLoop(interval: interval)
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

    /// 心跳只写共享状态 + reload,不碰网络:主 App 空闲(额度没变化)时也要让小组件知道自己还活着。
    private func widgetHeartbeatLoop(interval: TimeInterval) async {
        while !Task.isCancelled {
            let nanos = UInt64(interval * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanos)
            } catch {
                return
            }
            guard let appState, !Task.isCancelled else { return }
            appState.publishWidgetState(force: true)
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

    private func remotePricingLoop(interval: TimeInterval) async {
        while !Task.isCancelled {
            let nanos = UInt64(interval * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanos)
            } catch {
                return
            }
            guard let appState, !Task.isCancelled else { return }
            await appState.refreshRemotePricing()
        }
    }
}
