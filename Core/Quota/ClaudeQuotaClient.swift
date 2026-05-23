import Foundation

enum ClaudeQuotaClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let userAgent = "claude-code/2.1.0"

    nonisolated static func fetch(
        accessToken: String
    ) async -> Result<QuotaSnapshot, QuotaError> {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 30

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
        QuotaSnapshot(
            app: .claude,
            fiveHour: parseWindow(root["five_hour"] as? [String: Any]),
            weekly: parseWindow(root["seven_day"] as? [String: Any]),
            weeklyOpus: parseWindow(root["seven_day_opus"] as? [String: Any]),
            weeklySonnet: parseWindow(root["seven_day_sonnet"] as? [String: Any]),
            weeklyDesign: parseFirstWindow(root: root, keys: [
                "seven_day_omelette",
                "seven_day_design",
                "seven_day_claude_design",
                "claude_design",
                "design",
            ]),
            planType: nil,
            fetchedAt: Date()
        )
    }

    nonisolated private static func parseFirstWindow(root: [String: Any], keys: [String]) -> QuotaWindow? {
        for key in keys {
            if let dict = root[key] as? [String: Any],
               let window = parseWindow(dict) {
                return window
            }
        }
        return nil
    }

    nonisolated private static func parseWindow(_ dict: [String: Any]?) -> QuotaWindow? {
        guard let dict else { return nil }
        let used: Double = {
            if let d = dict["utilization"] as? Double { return d }
            if let i = dict["utilization"] as? Int { return Double(i) }
            return 0
        }()
        var resetsAt: Date?
        if let s = dict["resets_at"] as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) {
                resetsAt = d
            } else {
                iso.formatOptions = [.withInternetDateTime]
                resetsAt = iso.date(from: s)
            }
        } else if let n = dict["resets_at"] as? Double {
            resetsAt = Date(timeIntervalSince1970: n)
        } else if let i = dict["resets_at"] as? Int {
            resetsAt = Date(timeIntervalSince1970: Double(i))
        }
        return QuotaWindow(usedPercent: used, resetsAt: resetsAt, windowSeconds: nil)
    }
}
