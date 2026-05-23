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
        return QuotaSnapshot(
            app: .codex,
            fiveHour: parseWindow(rate["primary_window"] as? [String: Any]),
            weekly: parseWindow(rate["secondary_window"] as? [String: Any]),
            weeklyOpus: nil,
            weeklySonnet: nil,
            weeklyDesign: nil,
            planType: planType,
            fetchedAt: Date()
        )
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
