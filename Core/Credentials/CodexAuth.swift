import Foundation

enum CodexAuth {
    nonisolated static func load() throws -> CodexAccount {
        let url = authFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CredentialError.fileNotFound(url.path)
        }
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CredentialError.invalidJSON(url.path)
        }
        let tokens = root["tokens"] as? [String: Any] ?? [:]
        let idToken = tokens["id_token"] as? String
        let accessToken = tokens["access_token"] as? String
        let refreshToken = tokens["refresh_token"] as? String
        let accountId = tokens["account_id"] as? String
        let lastRefresh = parseDate(root["last_refresh"])

        var email: String?
        var planType: String?
        var claimKeys: [String] = []
        if let idToken, let claims = JWT.decodePayload(idToken) {
            claimKeys = Array(claims.keys).sorted()
            email = claims["email"] as? String
            if let auth = claims["https://api.openai.com/auth"] as? [String: Any] {
                planType = auth["chatgpt_plan_type"] as? String
            }
            if planType == nil {
                planType = claims["chatgpt_plan_type"] as? String
            }
        }

        let expiredGuess: Bool = {
            guard let lastRefresh else { return true }
            return Date().timeIntervalSince(lastRefresh) > 8 * 24 * 3600
        }()

        return CodexAccount(
            email: email,
            planType: planType,
            accountId: accountId,
            lastRefresh: lastRefresh,
            expiredGuess: expiredGuess,
            rawClaimKeys: claimKeys,
            accessToken: accessToken,
            refreshToken: refreshToken
        )
    }

    nonisolated static func authFileURL() -> URL {
        if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home).appendingPathComponent("auth.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
    }

    nonisolated private static func parseDate(_ any: Any?) -> Date? {
        if let s = any as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: s)
        }
        if let n = any as? Double { return Date(timeIntervalSince1970: n) }
        return nil
    }
}
