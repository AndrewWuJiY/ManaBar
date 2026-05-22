import Foundation

enum CodexTokenRefresher {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let tokenEndpoint = URL(string: "https://auth.openai.com/oauth/token")!
    static let refreshSkew: TimeInterval = 300

    struct Refreshed: Sendable {
        var accessToken: String
        var refreshToken: String
        var idToken: String?
    }

    /// 若 access_token 即将过期则用 refresh_token 续期并原子写回 auth.json。
    /// 返回当前可用的最新 access_token（未过期时即原值）。
    nonisolated static func ensureFreshAccessToken(
        currentAccessToken: String,
        refreshToken: String?
    ) async -> Result<String, QuotaError> {
        if !isExpired(accessToken: currentAccessToken) {
            return .success(currentAccessToken)
        }
        guard let refreshToken, !refreshToken.isEmpty else {
            return .failure(.tokenRefreshFailed("no refresh_token"))
        }
        do {
            let r = try await refresh(using: refreshToken)
            return .success(r.accessToken)
        } catch let err as QuotaError {
            return .failure(err)
        } catch {
            return .failure(.tokenRefreshFailed("\(error)"))
        }
    }

    nonisolated static func isExpired(accessToken: String) -> Bool {
        guard let payload = JWT.decodePayload(accessToken),
              let exp = payload["exp"] as? Double
        else { return true }
        return Date(timeIntervalSince1970: exp).timeIntervalSinceNow < refreshSkew
    }

    nonisolated private static func refresh(using refreshToken: String) async throws -> Refreshed {
        var req = URLRequest(url: tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = "grant_type=refresh_token"
            + "&refresh_token=\(percent(refreshToken))"
            + "&client_id=\(clientID)"
            + "&scope=openid%20profile%20email"
        req.httpBody = body.data(using: .utf8)

        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw QuotaError.tokenRefreshFailed("transport: \(error)")
        }
        guard let http = resp as? HTTPURLResponse else {
            throw QuotaError.tokenRefreshFailed("non-http response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw QuotaError.tokenRefreshFailed("http \(http.statusCode): \(msg)")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaError.tokenRefreshFailed("invalid json")
        }
        guard let newAccess = root["access_token"] as? String else {
            throw QuotaError.tokenRefreshFailed("no access_token in response")
        }
        let newId = root["id_token"] as? String
        let newRefresh = root["refresh_token"] as? String ?? refreshToken
        try writeBack(accessToken: newAccess, idToken: newId, refreshToken: newRefresh)
        return Refreshed(accessToken: newAccess, refreshToken: newRefresh, idToken: newId)
    }

    nonisolated private static func writeBack(
        accessToken: String,
        idToken: String?,
        refreshToken: String
    ) throws {
        let url = CodexAuth.authFileURL()
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = obj
        }
        var tokens = root["tokens"] as? [String: Any] ?? [:]
        tokens["access_token"] = accessToken
        if let idToken { tokens["id_token"] = idToken }
        tokens["refresh_token"] = refreshToken
        root["tokens"] = tokens
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        root["last_refresh"] = iso.string(from: Date())

        let out = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try out.write(to: url, options: [.atomic])
    }

    nonisolated private static func percent(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
}
