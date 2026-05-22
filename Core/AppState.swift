import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var codexAccount: CodexAccount?
    var claudeAccount: ClaudeAccount?
    var codexError: String?
    var claudeError: String?

    var codexQuota: QuotaSnapshot?
    var claudeQuota: QuotaSnapshot?
    var codexQuotaError: String?
    var claudeQuotaError: String?
    var codexQuotaSource: QuotaSnapshotSource?
    var claudeQuotaSource: QuotaSnapshotSource?
    var codexRefreshState = QuotaRefreshState()
    var claudeRefreshState = QuotaRefreshState()

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
        await loadCodex()
        await loadClaude()
        logCredentialSummary()

        scheduler.start(appState: self)
    }

    func refreshNow() async {
        if codexAccount == nil {
            await loadCodex()
        }
        if claudeAccount == nil {
            await loadClaude()
        }
        await refreshQuotas(reason: .userInitiated)
    }

    func refreshQuotas(reason: QuotaRefreshReason = .periodic) async {
        await loadCodexQuota(reason: reason)
        await loadClaudeQuota(reason: reason)
        logQuotaSummary()
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
    }

    private func saveQuotaCache() {
        do {
            try QuotaCache.save(quotaCache)
        } catch {
            print("[M3] quota cache save failed: \(error)")
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

        guard let account = claudeAccount else {
            markClaudeFailure("no claude account")
            return
        }
        guard let token = account.accessToken else {
            markClaudeFailure(QuotaError.missingToken.description)
            return
        }
        let result = await ClaudeQuotaClient.fetch(accessToken: token)
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
            print("[M1] Codex: email=\(c.email ?? "—") plan=\(c.planType ?? "—") account_id=\(c.accountId ?? "—") expiredGuess=\(c.expiredGuess) hasAccessToken=\(c.accessToken != nil) hasRefreshToken=\(c.refreshToken != nil)")
        } else {
            print("[M1] Codex: <none> error=\(codexError ?? "unknown")")
        }
        if let c = claudeAccount {
            print("[M1] Claude: source=\(c.source.rawValue) email=\(c.email ?? "—") plan=\(c.subscriptionType ?? "—") expiresAt=\(c.expiresAt.map { "\($0)" } ?? "—") expiredGuess=\(c.expiredGuess) hasAccessToken=\(c.accessToken != nil)")
        } else {
            print("[M1] Claude: <none> error=\(claudeError ?? "unknown")")
        }
    }

    private func logQuotaSummary() {
        if let q = codexQuota {
            print("[M2] Codex quota: source=\(codexQuotaSource?.rawValue ?? "—") plan=\(q.planType ?? "—") \(format(q))")
        } else {
            print("[M2] Codex quota: <none> error=\(codexQuotaError ?? "unknown")")
        }
        if let q = claudeQuota {
            print("[M2] Claude quota: source=\(claudeQuotaSource?.rawValue ?? "—") \(format(q))")
            if let opus = q.weeklyOpus { print("       └─ weeklyOpus=\(format(window: opus))") }
            if let sonnet = q.weeklySonnet { print("       └─ weeklySonnet=\(format(window: sonnet))") }
        } else {
            print("[M2] Claude quota: <none> error=\(claudeQuotaError ?? "unknown")")
        }
    }

    private func format(_ q: QuotaSnapshot) -> String {
        let parts = [
            q.fiveHour.map { "5h=\(format(window: $0))" },
            q.weekly.map { "1w=\(format(window: $0))" }
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
