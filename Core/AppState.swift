import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var codexAccount: CodexAccount?
    var claudeAccount: ClaudeAccount?
    var codexError: String?
    var claudeError: String?

    // MARK: 导入的 Codex 副账号
    //
    // 用户手动粘贴 auth.json 添加的"其他账号"。与默认账号(`~/.codex/auth.json`)解耦,
    // 允许重复出现,token 走 Keychain (见 ImportedCodexStore)。
    // - `importedCodexAccounts` 元数据列表,保持添加顺序。
    // - `importedCodexQuotas / Sources / Errors / RefreshStates` 按 account.id 索引,
    //   只在该账号 `visibleInPopover` 为 true 时才刷新与展示。
    var importedCodexAccounts: [ImportedCodexAccount] = []
    var importedCodexQuotas: [String: QuotaSnapshot] = [:]
    var importedCodexSources: [String: QuotaSnapshotSource] = [:]
    var importedCodexErrors: [String: String] = [:]
    var importedCodexRefreshStates: [String: QuotaRefreshState] = [:]

    /// 主窗口当前 tab,允许 ⌘1 / ⌘, 等命令从外部驱动切换
    var mainTab: MainTab = .stats

    /// 首次启动时由 bootstrap 设为 true,触发 Onboarding 窗口
    var shouldShowOnboarding: Bool = false

    var codexQuota: QuotaSnapshot?
    var claudeQuota: QuotaSnapshot?
    var codexQuotaError: String?
    var claudeQuotaError: String?
    var codexQuotaSource: QuotaSnapshotSource?
    var claudeQuotaSource: QuotaSnapshotSource?
    var codexRefreshState = QuotaRefreshState()
    var claudeRefreshState = QuotaRefreshState()

    var codexTodayCost: Decimal?
    var claudeTodayCost: Decimal?

    /// OpenAI / Anthropic statuspage.io 最新快照,失败时保留上一份。
    var codexServiceStatus: ServiceStatus?
    var claudeServiceStatus: ServiceStatus?

    let usageService = UsageService()
    private let scheduler = Scheduler()
    private var didBootstrap = false
    private var quotaCache = QuotaCachePayload()
    private var claudeFallbackBackoffUntil: Date?

    private let minSuccessInterval: TimeInterval = 60
    private let rateLimitBackoff: TimeInterval = 10 * 60

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        loadQuotaCache()
        reloadImportedCodexAccounts()
        usageService.bootstrap(appState: self)
        await loadCodex()
        maybeShowKeychainPrompt()
        await loadClaude()
        logCredentialSummary()

        if !SettingsStore.shared.didCompleteOnboarding {
            shouldShowOnboarding = true
        }

        let settings = SettingsStore.shared
        scheduler.start(
            appState: self,
            quotaInterval: settings.quotaInterval.seconds,
            usageInterval: settings.usageInterval.seconds
        )
        // 启动后台触发一次 JSONL 扫描，让今日 cost 立刻更新（不阻塞 bootstrap）
        Task { await usageService.scanNow() }
        // 启动后异步拉一次服务状态;后续由 Scheduler 5 分钟刷新一次
        Task { await refreshServiceStatus() }
    }

    /// 设置变更后，把刷新间隔同步到 Scheduler
    func applySettingsChange() {
        let settings = SettingsStore.shared
        scheduler.setQuotaInterval(settings.quotaInterval.seconds)
        scheduler.setUsageInterval(settings.usageInterval.seconds)
    }

    func refreshNow() async {
        if codexAccount == nil {
            await loadCodex()
        }
        if claudeAccount == nil {
            await loadClaude()
        }
        await refreshQuotas(reason: .userInitiated)
        await usageService.scanNow()
        await refreshServiceStatus()
    }

    func refreshQuotas(reason: QuotaRefreshReason = .periodic) async {
        await loadCodexQuota(reason: reason)
        await loadClaudeQuota(reason: reason)
        await loadAllImportedCodexQuotas(reason: reason)
        logQuotaSummary()
    }

    /// 拉取 OpenAI / Anthropic statuspage 状态。失败保留旧快照,不清空。
    /// 两个请求并发,任意一个失败不影响另一个。
    func refreshServiceStatus() async {
        async let codex = Self.fetchServiceStatus(url: ServiceStatusClient.openAIStatusURL, tag: "openai")
        async let claude = Self.fetchServiceStatus(url: ServiceStatusClient.anthropicStatusURL, tag: "anthropic")
        let codexResult = await codex
        let claudeResult = await claude
        if let codexResult { codexServiceStatus = codexResult }
        if let claudeResult { claudeServiceStatus = claudeResult }
    }

    private static func fetchServiceStatus(url: URL, tag: String) async -> ServiceStatus? {
        do {
            return try await ServiceStatusClient.fetch(from: url)
        } catch {
            print("[service-status] \(tag) fetch failed: \(error)")
            return nil
        }
    }

    func quotaStatusLine(for app: QuotaApp) -> String? {
        let snapshot: QuotaSnapshot?
        let source: QuotaSnapshotSource?
        let error: String?
        let state: QuotaRefreshState
        switch app {
        case .codex:
            snapshot = codexQuota
            source = codexQuotaSource
            error = codexQuotaError
            state = codexRefreshState
        case .claude:
            snapshot = claudeQuota
            source = claudeQuotaSource
            error = claudeQuotaError
            state = claudeRefreshState
        }

        var parts: [String] = []
        if let snapshot, !format(snapshot).isEmpty {
            parts.append(format(snapshot))
        }
        if let source {
            parts.append(source.displayName)
        }
        if let lastSuccessAt = state.lastSuccessAt {
            parts.append("更新 \(relativeAge(from: lastSuccessAt))前")
        }
        if let backoffUntil = state.backoffUntil, backoffUntil > Date() {
            parts.append("限流退避 \(relativeAge(until: backoffUntil))")
        }
        if let error, !error.isEmpty {
            parts.append("错误: \(shortError(error))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func loadQuotaCache() {
        quotaCache = QuotaCache.load()
        if let record = quotaCache.codex {
            codexQuota = record.snapshot
            codexQuotaSource = .cache
            codexRefreshState.lastSuccessAt = record.updatedAt
            codexRefreshState.source = .cache
        }
        if let record = quotaCache.claude {
            claudeQuota = record.snapshot
            claudeQuotaSource = .cache
            claudeRefreshState.lastSuccessAt = record.updatedAt
            claudeRefreshState.source = .cache
        }
        for (id, record) in quotaCache.importedCodex ?? [:] {
            importedCodexQuotas[id] = record.snapshot
            importedCodexSources[id] = .cache
            var state = QuotaRefreshState()
            state.lastSuccessAt = record.updatedAt
            state.source = .cache
            importedCodexRefreshStates[id] = state
        }
    }

    // MARK: - Imported Codex accounts

    /// 从磁盘读取元数据列表,移除内存中已经不存在的账号的运行时状态。
    /// 设置页增删账号后由调用方触发。
    func reloadImportedCodexAccounts() {
        importedCodexAccounts = ImportedCodexStore.loadAll()
        let alive = Set(importedCodexAccounts.map(\.id))
        importedCodexQuotas = importedCodexQuotas.filter { alive.contains($0.key) }
        importedCodexSources = importedCodexSources.filter { alive.contains($0.key) }
        importedCodexErrors = importedCodexErrors.filter { alive.contains($0.key) }
        importedCodexRefreshStates = importedCodexRefreshStates.filter { alive.contains($0.key) }
        var importedCache = quotaCache.importedCodex ?? [:]
        importedCache = importedCache.filter { alive.contains($0.key) }
        quotaCache.importedCodex = importedCache.isEmpty ? nil : importedCache
        saveQuotaCache()
    }

    /// 增 / 改:同 account_id 静默覆盖 token,元数据按入参更新;新增时落到列表末尾。
    func upsertImportedCodexAccount(
        from parsed: ImportedCodexPaste.Parsed,
        alias: String,
        visibleInPopover: Bool
    ) throws {
        let tokens = ImportedCodexTokens(
            accessToken: parsed.accessToken,
            refreshToken: parsed.refreshToken,
            idToken: parsed.idToken
        )
        try ImportedCodexStore.saveTokens(tokens, accountId: parsed.id)

        var list = ImportedCodexStore.loadAll()
        if let idx = list.firstIndex(where: { $0.id == parsed.id }) {
            var existing = list[idx]
            existing.alias = alias
            existing.email = parsed.email ?? existing.email
            existing.planType = parsed.planType ?? existing.planType
            existing.visibleInPopover = visibleInPopover
            list[idx] = existing
        } else {
            list.append(ImportedCodexAccount(
                id: parsed.id,
                alias: alias,
                email: parsed.email,
                planType: parsed.planType,
                visibleInPopover: visibleInPopover,
                addedAt: Date()
            ))
        }
        try ImportedCodexStore.saveAll(list)
        reloadImportedCodexAccounts()
    }

    /// 仅更新元数据(别名、颜色、显示开关),不动 token。
    func updateImportedCodexMetadata(id: String, mutate: (inout ImportedCodexAccount) -> Void) {
        var list = ImportedCodexStore.loadAll()
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        mutate(&list[idx])
        do { try ImportedCodexStore.saveAll(list) } catch {
            print("[imported-codex] save metadata failed: \(error)")
            return
        }
        reloadImportedCodexAccounts()
    }

    /// 按给定 id 顺序重排导入账号(忽略不存在的 id,缺失的追加到末尾)。
    func reorderImportedCodexAccounts(orderedIds: [String]) {
        let list = ImportedCodexStore.loadAll()
        let byId = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        var seen = Set<String>()
        var reordered: [ImportedCodexAccount] = []
        for id in orderedIds {
            guard let acc = byId[id], !seen.contains(id) else { continue }
            reordered.append(acc)
            seen.insert(id)
        }
        for acc in list where !seen.contains(acc.id) {
            reordered.append(acc)
        }
        guard reordered.map(\.id) != list.map(\.id) else { return }
        do { try ImportedCodexStore.saveAll(reordered) } catch {
            print("[imported-codex] reorder failed: \(error)")
            return
        }
        reloadImportedCodexAccounts()
    }

    /// 删除:同步清 Keychain、元数据、运行时状态与缓存。
    func removeImportedCodexAccount(id: String) {
        ImportedCodexStore.deleteTokens(accountId: id)
        let list = ImportedCodexStore.loadAll().filter { $0.id != id }
        do { try ImportedCodexStore.saveAll(list) } catch {
            print("[imported-codex] delete failed: \(error)")
        }
        reloadImportedCodexAccounts()
    }

    /// 对所有 `visibleInPopover` 为 true 的导入账号并发拉一遍配额,并发上限 3。
    private func loadAllImportedCodexQuotas(reason: QuotaRefreshReason) async {
        let visible = importedCodexAccounts.filter(\.visibleInPopover)
        guard !visible.isEmpty else { return }
        let maxConcurrent = 3
        var index = 0
        while index < visible.count {
            let batch = Array(visible[index..<min(index + maxConcurrent, visible.count)])
            await withTaskGroup(of: Void.self) { group in
                for account in batch {
                    group.addTask { [weak self] in
                        guard let self else { return }
                        await self.loadImportedCodexQuota(account: account, reason: reason)
                    }
                }
            }
            index += maxConcurrent
        }
    }

    private func loadImportedCodexQuota(account: ImportedCodexAccount, reason: QuotaRefreshReason) async {
        guard beginImportedCodexRefresh(id: account.id, reason: reason) else { return }
        defer { importedCodexRefreshStates[account.id]?.inFlight = false }

        guard let tokens = ImportedCodexStore.loadTokens(accountId: account.id) else {
            markImportedCodexFailure(id: account.id, message: "missing tokens in keychain")
            return
        }
        let refreshed = await CodexTokenRefresher.ensureFreshAccessToken(
            currentAccessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            writeBack: .importedAccount(id: account.id)
        )
        let activeToken: String
        switch refreshed {
        case .success(let t):
            activeToken = t
        case .failure(let err):
            markImportedCodexFailure(id: account.id, message: err.description, error: err)
            return
        }
        let result = await CodexQuotaClient.fetch(accessToken: activeToken, accountId: account.chatgptAccountId)
        switch result {
        case .success(let snapshot):
            storeImportedCodex(id: account.id, snapshot: snapshot, source: .api)
        case .failure(let err):
            markImportedCodexFailure(id: account.id, message: err.description, error: err)
        }
    }

    private func beginImportedCodexRefresh(id: String, reason: QuotaRefreshReason) -> Bool {
        let now = Date()
        var state = importedCodexRefreshStates[id] ?? QuotaRefreshState()
        guard !state.inFlight else { return false }
        if let backoffUntil = state.backoffUntil, backoffUntil > now {
            state.lastError = backoffMessage(until: backoffUntil)
            importedCodexRefreshStates[id] = state
            importedCodexErrors[id] = state.lastError
            return false
        }
        if reason == .periodic,
           let lastSuccessAt = state.lastSuccessAt,
           now.timeIntervalSince(lastSuccessAt) < minSuccessInterval
        {
            return false
        }
        state.inFlight = true
        state.lastAttemptAt = now
        importedCodexRefreshStates[id] = state
        return true
    }

    private func storeImportedCodex(id: String, snapshot: QuotaSnapshot, source: QuotaSnapshotSource) {
        let updatedAt = Date()
        importedCodexQuotas[id] = snapshot
        importedCodexSources[id] = source
        importedCodexErrors[id] = nil
        var state = importedCodexRefreshStates[id] ?? QuotaRefreshState()
        state.lastSuccessAt = updatedAt
        state.lastError = nil
        state.backoffUntil = nil
        state.source = source
        importedCodexRefreshStates[id] = state

        var cache = quotaCache.importedCodex ?? [:]
        cache[id] = QuotaCacheRecord(snapshot: snapshot, source: source, updatedAt: updatedAt)
        quotaCache.importedCodex = cache
        saveQuotaCache()
    }

    private func markImportedCodexFailure(id: String, message: String, error: QuotaError? = nil) {
        importedCodexErrors[id] = message
        var state = importedCodexRefreshStates[id] ?? QuotaRefreshState()
        state.lastError = message
        if error?.isRateLimited == true {
            state.backoffUntil = Date().addingTimeInterval(rateLimitBackoff)
        }
        importedCodexRefreshStates[id] = state
    }

    private func saveQuotaCache() {
        do {
            try QuotaCache.save(quotaCache)
        } catch {
            print("[QuotaCache 额度缓存] 写盘失败 save failed: \(error)")
        }
    }

    private func loadCodex() async {
        do {
            self.codexAccount = try await Task.detached(priority: .utility) {
                try CodexAuth.load()
            }.value
            self.codexError = nil
        } catch {
            self.codexAccount = nil
            self.codexError = "\(error)"
        }
    }

    /// 没有本地凭据文件、且尚未提示过时,先用一个模态 alert 告诉用户
    /// 接下来会弹出系统 Keychain 授权窗口,避免一上来就被系统弹窗吓到。
    private func maybeShowKeychainPrompt() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        let hasFile = FileManager.default.fileExists(atPath: url.path)
        let settings = SettingsStore.shared
        guard !hasFile, !settings.didShowKeychainPrompt else { return }

        let alert = NSAlert()
        alert.messageText = tr("Allow Keychain Access", "允许访问 Keychain")
        alert.informativeText = tr(
            "cc-bar reads the Claude credential stored in your macOS Keychain to query your quota. After you continue, macOS will ask for permission — choose \"Always Allow\".",
            "cc-bar 需要读取 macOS 钥匙串里的 Claude 凭据来查询额度。点击「继续」后会弹出系统授权窗口,请选择「始终允许」。"
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: tr("Continue", "继续"))
        alert.runModal()
        settings.didShowKeychainPrompt = true
    }

    private func loadClaude() async {
        do {
            self.claudeAccount = try await Task.detached(priority: .utility) {
                try ClaudeAuth.load()
            }.value
            self.claudeError = nil
        } catch {
            self.claudeAccount = nil
            self.claudeError = "\(error)"
        }
    }

    private func loadCodexQuota(reason: QuotaRefreshReason) async {
        guard beginCodexRefresh(reason: reason) else { return }
        defer { codexRefreshState.inFlight = false }

        guard var account = codexAccount else {
            markCodexFailure("no codex account")
            return
        }
        guard let token = account.accessToken else {
            markCodexFailure(QuotaError.missingToken.description)
            return
        }
        let refreshed = await CodexTokenRefresher.ensureFreshAccessToken(
            currentAccessToken: token,
            refreshToken: account.refreshToken
        )
        let activeToken: String
        switch refreshed {
        case .success(let t):
            activeToken = t
            if t != token {
                account.accessToken = t
                codexAccount = account
            }
        case .failure(let err):
            markCodexFailure(err.description)
            return
        }
        let result = await CodexQuotaClient.fetch(
            accessToken: activeToken,
            accountId: account.accountId
        )
        switch result {
        case .success(let snapshot):
            storeCodex(snapshot: snapshot, source: .api)
        case .failure(let err):
            markCodexFailure(err.description, error: err)
        }
    }

    private func loadClaudeQuota(reason: QuotaRefreshReason) async {
        guard beginClaudeRefresh(reason: reason) else { return }
        defer { claudeRefreshState.inFlight = false }

        guard var account = claudeAccount else {
            markClaudeFailure("no claude account")
            return
        }
        guard account.accessToken != nil else {
            markClaudeFailure(QuotaError.missingToken.description)
            return
        }
        let refreshed = await ClaudeTokenRefresher.ensureFreshAccessToken(account: &account)
        let activeToken: String
        switch refreshed {
        case .success(let t):
            activeToken = t
            if t != claudeAccount?.accessToken {
                claudeAccount = account
            }
        case .failure(let err):
            markClaudeFailure(err.description, error: err)
            return
        }
        let result = await ClaudeQuotaClient.fetch(accessToken: activeToken)
        switch result {
        case .success(let snapshot):
            storeClaude(snapshot: snapshot, source: .api)
        case .failure(let err):
            markClaudeFailure(err.description, error: err)
            if reason == .userInitiated, claudeQuota == nil {
                await loadClaudeCLIFallback(apiError: err)
            }
        }
    }

    private func loadClaudeCLIFallback(apiError: QuotaError) async {
        let now = Date()
        if let claudeFallbackBackoffUntil, claudeFallbackBackoffUntil > now {
            markClaudeFailure("\(apiError.description); cli fallback cooling down until \(claudeFallbackBackoffUntil)")
            return
        }

        claudeFallbackBackoffUntil = now.addingTimeInterval(rateLimitBackoff)
        let result = await ClaudeCLIFallbackQuotaClient.fetch()
        switch result {
        case .success(let snapshot):
            storeClaude(snapshot: snapshot, source: .cliFallback)
        case .failure(let err):
            markClaudeFailure("\(apiError.description); cli fallback failed: \(err.description)", error: err)
        }
    }

    private func beginCodexRefresh(reason: QuotaRefreshReason) -> Bool {
        let now = Date()
        guard !codexRefreshState.inFlight else { return false }
        if let backoffUntil = codexRefreshState.backoffUntil, backoffUntil > now {
            markCodexFailure(backoffMessage(until: backoffUntil))
            return false
        }
        if reason == .periodic,
           let lastSuccessAt = codexRefreshState.lastSuccessAt,
           now.timeIntervalSince(lastSuccessAt) < minSuccessInterval
        {
            return false
        }
        codexRefreshState.inFlight = true
        codexRefreshState.lastAttemptAt = now
        return true
    }

    private func beginClaudeRefresh(reason: QuotaRefreshReason) -> Bool {
        let now = Date()
        guard !claudeRefreshState.inFlight else { return false }
        if let backoffUntil = claudeRefreshState.backoffUntil, backoffUntil > now {
            markClaudeFailure(backoffMessage(until: backoffUntil))
            return false
        }
        if reason == .periodic,
           let lastSuccessAt = claudeRefreshState.lastSuccessAt,
           now.timeIntervalSince(lastSuccessAt) < minSuccessInterval
        {
            return false
        }
        claudeRefreshState.inFlight = true
        claudeRefreshState.lastAttemptAt = now
        return true
    }

    private func storeCodex(snapshot: QuotaSnapshot, source: QuotaSnapshotSource) {
        let updatedAt = Date()
        codexQuota = snapshot
        codexQuotaSource = source
        codexQuotaError = nil
        codexRefreshState.lastSuccessAt = updatedAt
        codexRefreshState.lastError = nil
        codexRefreshState.backoffUntil = nil
        codexRefreshState.source = source
        quotaCache.codex = QuotaCacheRecord(snapshot: snapshot, source: source, updatedAt: updatedAt)
        saveQuotaCache()
    }

    private func storeClaude(snapshot: QuotaSnapshot, source: QuotaSnapshotSource) {
        let updatedAt = Date()
        claudeQuota = snapshot
        claudeQuotaSource = source
        claudeQuotaError = nil
        claudeRefreshState.lastSuccessAt = updatedAt
        claudeRefreshState.lastError = nil
        if source == .api {
            claudeRefreshState.backoffUntil = nil
        }
        claudeRefreshState.source = source
        quotaCache.claude = QuotaCacheRecord(snapshot: snapshot, source: source, updatedAt: updatedAt)
        saveQuotaCache()
    }

    private func markCodexFailure(_ message: String, error: QuotaError? = nil) {
        codexQuotaError = message
        codexRefreshState.lastError = message
        if error?.isRateLimited == true {
            codexRefreshState.backoffUntil = Date().addingTimeInterval(rateLimitBackoff)
        }
    }

    private func markClaudeFailure(_ message: String, error: QuotaError? = nil) {
        claudeQuotaError = message
        claudeRefreshState.lastError = message
        if error?.isRateLimited == true {
            claudeRefreshState.backoffUntil = Date().addingTimeInterval(rateLimitBackoff)
        }
    }

    private func backoffMessage(until: Date) -> String {
        "rate limited; retry in \(relativeAge(until: until))"
    }

    private func logCredentialSummary() {
        if let c = codexAccount {
            print("[Credentials 凭据] Codex: email=\(c.email ?? "—") plan=\(c.planType ?? "—") account_id=\(c.accountId ?? "—") expiredGuess=\(c.expiredGuess) hasAccessToken=\(c.accessToken != nil) hasRefreshToken=\(c.refreshToken != nil)")
        } else {
            print("[Credentials 凭据] Codex 未加载: error=\(codexError ?? "unknown")")
        }
        if let c = claudeAccount {
            print("[Credentials 凭据] Claude: source=\(c.source.rawValue) email=\(c.email ?? "—") plan=\(c.subscriptionType ?? "—") expiresAt=\(c.expiresAt.map { "\($0)" } ?? "—") expiredGuess=\(c.expiredGuess) hasAccessToken=\(c.accessToken != nil)")
        } else {
            print("[Credentials 凭据] Claude 未加载: error=\(claudeError ?? "unknown")")
        }
    }

    private func logQuotaSummary() {
        if let q = codexQuota {
            print("[Quota 额度] Codex: source=\(codexQuotaSource?.rawValue ?? "—") plan=\(q.planType ?? "—") \(format(q))")
        } else {
            print("[Quota 额度] Codex 拉取失败: error=\(codexQuotaError ?? "unknown")")
        }
        if let q = claudeQuota {
            print("[Quota 额度] Claude: source=\(claudeQuotaSource?.rawValue ?? "—") \(format(q))")
            if let opus = q.weeklyOpus { print("       └─ weeklyOpus=\(format(window: opus))") }
            if let sonnet = q.weeklySonnet { print("       └─ weeklySonnet=\(format(window: sonnet))") }
            if let design = q.weeklyDesign { print("       └─ weeklyDesign=\(format(window: design))") }
        } else {
            print("[Quota 额度] Claude 拉取失败: error=\(claudeQuotaError ?? "unknown")")
        }
    }

    private func format(_ q: QuotaSnapshot) -> String {
        let parts = [
            q.fiveHour.map { "5h=\(format(window: $0))" },
            q.weekly.map { "1w=\(format(window: $0))" },
            q.weeklyDesign.map { "design=\(format(window: $0))" }
        ].compactMap { $0 }
        return parts.joined(separator: " ")
    }

    private func format(window w: QuotaWindow) -> String {
        let pct = String(format: "%.1f%% left", w.remainingPercent)
        let reset: String
        if let r = w.resetsAt {
            let mins = Int(r.timeIntervalSinceNow / 60)
            reset = mins > 0 ? "resets in ~\(mins)m" : "resets now"
        } else {
            reset = "resets ?"
        }
        return "\(pct) (\(reset))"
    }

    private func relativeAge(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h"
    }

    private func relativeAge(until date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(Date())))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h"
    }

    private func shortError(_ error: String) -> String {
        let oneLine = error.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if oneLine.count <= 120 { return oneLine }
        return String(oneLine.prefix(117)) + "..."
    }
}
