import Foundation

enum CodexQuotaClient {
    static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    nonisolated static func fetch(
        accessToken: String,
        accountId: String?
    ) async -> Result<QuotaSnapshot, QuotaError> {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        if let accountId, !accountId.isEmpty {
            req.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { return .failure(.transport("\(error)")) }
        guard let http = resp as? HTTPURLResponse else {
            return .failure(.transport("non-http"))
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            return .failure(.http(http.statusCode, msg))
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.decode("not json object"))
        }
        return .success(parse(root: root))
    }

    nonisolated private static func parse(root: [String: Any]) -> QuotaSnapshot {
        let planType = root["plan_type"] as? String
        let rate = root["rate_limit"] as? [String: Any] ?? [:]
        let primary = parseWindow(rate["primary_window"] as? [String: Any])
        let secondary = parseWindow(rate["secondary_window"] as? [String: Any])
        let (fiveHour, weekly) = classify(primary: primary, secondary: secondary)
        return QuotaSnapshot(
            app: .codex,
            fiveHour: fiveHour,
            weekly: weekly,
            weeklyOpus: nil,
            weeklySonnet: nil,
            planType: planType,
            fetchedAt: Date()
        )
    }

    /// 2026-07 OpenAI 暂时移除 Plus/Business/Pro 的 5 小时限制后,响应里可能只剩一个周窗口,
    /// 且会顶在 primary_window 的位置。因此不能再按「primary=5h / secondary=weekly」的位置假设,
    /// 改按窗口时长归类:≥24h 归 weekly,其余归 fiveHour;两个窗口互不挤占。
    nonisolated private static func classify(
        primary: QuotaWindow?,
        secondary: QuotaWindow?
    ) -> (fiveHour: QuotaWindow?, weekly: QuotaWindow?) {
        var fiveHour: QuotaWindow?
        var weekly: QuotaWindow?
        for window in [primary, secondary] {
            guard let window else { continue }
            if isWeeklyLike(window) {
                if weekly == nil { weekly = window } else if fiveHour == nil { fiveHour = window }
            } else {
                if fiveHour == nil { fiveHour = window } else if weekly == nil { weekly = window }
            }
        }
        return (fiveHour, weekly)
    }

    /// 时长 ≥24h 视为周窗口;缺 limit_window_seconds 时用「距重置 >24h」兜底
    /// (5h 窗口的重置不可能在 24h 之后;周窗口临近重置时该兜底会失准,但此时行为等同旧逻辑)。
    nonisolated private static func isWeeklyLike(_ window: QuotaWindow) -> Bool {
        if let seconds = window.windowSeconds { return seconds >= 24 * 3600 }
        if let resetsAt = window.resetsAt { return resetsAt.timeIntervalSinceNow > 24 * 3600 }
        return false
    }

    nonisolated private static func parseWindow(_ dict: [String: Any]?) -> QuotaWindow? {
        guard let dict else { return nil }
        let used: Double = {
            if let d = dict["used_percent"] as? Double { return d }
            if let i = dict["used_percent"] as? Int { return Double(i) }
            return 0
        }()
        var resetAt: Date?
        if let n = dict["reset_at"] as? Double {
            resetAt = Date(timeIntervalSince1970: n)
        } else if let i = dict["reset_at"] as? Int {
            resetAt = Date(timeIntervalSince1970: Double(i))
        } else if let secs = dict["reset_after_seconds"] as? Double {
            resetAt = Date(timeIntervalSinceNow: secs)
        } else if let secs = dict["reset_after_seconds"] as? Int {
            resetAt = Date(timeIntervalSinceNow: Double(secs))
        }
        let window: Int? = (dict["limit_window_seconds"] as? Int)
            ?? (dict["limit_window_seconds"] as? Double).map { Int($0) }
        return QuotaWindow(usedPercent: used, resetsAt: resetAt, windowSeconds: window)
    }
}
