import Foundation

/// 协调 JSONL 扫描 → 聚合 → 持久化 → 通知 AppState 的入口。
@MainActor
final class UsageService {
    let aggregator = UsageAggregator()
    private(set) var isScanning = false
    private(set) var lastScanAt: Date?
    private(set) var lastError: String?

    private weak var appState: AppState?

    /// 价格表变化后置位：下一次扫描先清空内存聚合再全量重扫（指纹不一致时 ScanCache 会返回空 watermark），
    /// 否则旧价算出的桶会和重扫结果叠加。
    private var resetAggregatorOnNextScan = false
    /// 价格表变化时恰好有扫描在跑：排队，当前扫描结束后立刻再跑一次。
    private var rescanPending = false

    func bootstrap(appState: AppState) {
        self.appState = appState
        // 启动同步：先把 rollup 灌进内存
        let payload = UsageRollupCache.load()
        aggregator.load(from: payload.buckets)
        publishTotals()
    }

    /// 由 Scheduler / 手动触发；防重入。
    func scanNow() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let started = Date()
        // 指纹在扫描开始时固定：扫描中途远程价格表更新时，本轮仍按旧指纹落盘，
        // 下一轮 load 发现不一致 → 全量重算，不会把混合价格的结果当成新价格缓存。
        let pricingFingerprint = Pricing.fingerprint
        if resetAggregatorOnNextScan {
            resetAggregatorOnNextScan = false
            aggregator.load(from: [])
        }
        let prev = await Task.detached(priority: .utility) {
            ScanCache.load()
        }.value

        let prevSeen = prev.claudeSeenMessageIds
        async let claudeTask = Task.detached(priority: .utility) {
            ClaudeJSONLScanner.scan(previous: prev.claude, seenMessageIds: prevSeen)
        }.value
        async let codexTask = Task.detached(priority: .utility) {
            CodexJSONLScanner.scan(previous: prev.codex)
        }.value

        let claude = await claudeTask
        let codex = await codexTask

        aggregator.ingest(claude.entries)
        aggregator.ingest(codex.entries)

        // 持久化
        let buckets = aggregator.snapshot()
        let newScanState = ScanState(
            pricingFingerprint: pricingFingerprint,
            claude: claude.newState,
            codex: codex.newState,
            claudeSeenMessageIds: claude.newSeenIds
        )
        let rollup = UsageRollupPayload(
            pricingFingerprint: pricingFingerprint,
            buckets: buckets,
            updatedAt: Date()
        )
        await Task.detached(priority: .utility) {
            do {
                try ScanCache.save(newScanState)
            } catch {
                print("[UsageScan 用量扫描] 扫描状态写盘失败 scan-state save failed: \(error)")
            }
            do {
                try UsageRollupCache.save(rollup)
            } catch {
                print("[UsageScan 用量扫描] 汇总写盘失败 usage-rollup save failed: \(error)")
            }
        }.value

        lastScanAt = Date()
        lastError = nil
        publishTotals()

        let elapsed = String(format: "%.2fs", Date().timeIntervalSince(started))
        print("[UsageScan 用量扫描] claude files=\(claude.filesScanned) lines=\(claude.linesParsed) new=\(claude.entries.count); codex files=\(codex.filesScanned) lines=\(codex.linesParsed) new=\(codex.entries.count); elapsed=\(elapsed)")

        if rescanPending {
            rescanPending = false
            // 本函数返回、isScanning 复位后再跑
            Task { await self.scanNow() }
        }
    }

    /// 价格表变化（远程表更新）后调用：清空聚合并全量重扫，用新价格重算全部历史桶。
    func rescanForPricingChange() async {
        resetAggregatorOnNextScan = true
        if isScanning {
            rescanPending = true
            return
        }
        await scanNow()
    }

    private func publishTotals() {
        guard let appState else { return }
        appState.codexTodayCost = aggregator.todayCost(for: .codex)
        appState.claudeTodayCost = aggregator.todayCost(for: .claude)
    }
}
