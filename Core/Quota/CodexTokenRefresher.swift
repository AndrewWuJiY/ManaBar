import Foundation

enum CodexTokenRefresher {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let tokenEndpoint = URL(string: "https://auth.openai.com/oauth/token")!
    static let refreshSkew: TimeInterval = 300
    /// 默认账号只读判定过期用的 skew,只需覆盖网络往返。
    static let readOnlySkew: TimeInterval = 30

    struct Refreshed: Sendable {
        var accessToken: String
        var refreshToken: String
        var idToken: String?
    }

    /// 续期成功后,新 token 该落到哪里。
    /// 只剩 `importedAccount(id:)`:回写到 Keychain (ImportedCodexStore),用户手动导入的副账号用。
    /// 默认账号(`~/.codex/auth.json`,与 codex CLI 共享)只读,不续期、不回写,见 `readOnlyAccessToken`。
    enum WriteBack: Sendable {
        case importedAccount(id: String)
    }

    /// 默认账号的只读取用:`~/.codex/auth.json` 归 codex CLI 所有,refresh_token 会旋转,
    /// ManaBar 自己续期会和 CLI 抢 token、把 CLI 顶掉线。因此 access_token 过期时
    /// 直接返回 `tokenExpired`,等 codex CLI 下次运行刷新写回;AppState 每轮刷新都会重读 auth.json。
    /// 解不出 `exp` 时不拦截,交给接口自己判定。
    nonisolated static func readOnlyAccessToken(_ accessToken: String) -> Result<String, QuotaError> {
        if let payload = JWT.decodePayload(accessToken),
           let exp = payload["exp"] as? Double,
           Date(timeIntervalSince1970: exp).timeIntervalSinceNow < readOnlySkew {
            return .failure(.tokenExpired(.codex))
        }
        return .success(accessToken)
    }

    /// 导入副账号:若 access_token 即将过期则用 refresh_token 续期并回写 ImportedCodexStore。
    /// 返回当前可用的最新 access_token（未过期时即原值）。
    /// 这份 token 是 ManaBar 自己保管的副本,由 ManaBar 负责续期。
    nonisolated static func ensureFreshAccessToken(
        currentAccessToken: String,
        refreshToken: String?,
        writeBack: WriteBack
    ) async -> Result<String, QuotaError> {
        if !isExpired(accessToken: currentAccessToken) {
            return .success(currentAccessToken)
        }
        guard let refreshToken, !refreshToken.isEmpty else {
            return .failure(.tokenRefreshFailed("no refresh_token"))
        }
        do {
            let r = try await refresh(using: refreshToken, writeBack: writeBack)
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

    nonisolated private static func refresh(
        using refreshToken: String,
        writeBack: WriteBack
    ) async throws -> Refreshed {
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
        switch writeBack {
        case .importedAccount(let id):
            try ImportedCodexStore.saveTokens(
                ImportedCodexTokens(accessToken: newAccess, refreshToken: newRefresh, idToken: newId),
                accountId: id
            )
        }
        return Refreshed(accessToken: newAccess, refreshToken: newRefresh, idToken: newId)
    }

    nonisolated private static func percent(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
}
