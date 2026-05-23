import Foundation

enum ClaudeTokenRefresher {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let tokenEndpoint = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let refreshSkew: TimeInterval = 300
    static let keychainService = "Claude Code-credentials"

    struct Refreshed: Sendable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    /// 若 access_token 已过期或临近过期则用 refresh_token 续期，并写回原存储位置。
    /// 返回当前可用的最新 access_token，并同步更新 account 内的 token / expiresAt。
    nonisolated static func ensureFreshAccessToken(
        account: inout ClaudeAccount
    ) async -> Result<String, QuotaError> {
        guard let current = account.accessToken else {
            return .failure(.missingToken)
        }
        if !isExpired(expiresAt: account.expiresAt) {
            return .success(current)
        }
        guard let refreshToken = account.refreshToken, !refreshToken.isEmpty else {
            return .failure(.tokenRefreshFailed("no refresh_token"))
        }
        do {
            let r = try await refresh(using: refreshToken)
            try writeBack(source: account.source, refreshed: r)
            account.accessToken = r.accessToken
            account.refreshToken = r.refreshToken
            account.expiresAt = r.expiresAt
            account.expiredGuess = false
            return .success(r.accessToken)
        } catch let err as QuotaError {
            return .failure(err)
        } catch {
            return .failure(.tokenRefreshFailed("\(error)"))
        }
    }

    nonisolated static func isExpired(expiresAt: Date?) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < refreshSkew
    }

    nonisolated private static func refresh(using refreshToken: String) async throws -> Refreshed {
        var req = URLRequest(url: tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 30

        var comps = URLComponents()
        comps.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientID),
        ]
        req.httpBody = (comps.percentEncodedQuery ?? "").data(using: .utf8)

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
        let newRefresh = root["refresh_token"] as? String ?? refreshToken
        let expiresIn: TimeInterval = {
            if let n = root["expires_in"] as? Double { return n }
            if let i = root["expires_in"] as? Int { return TimeInterval(i) }
            return 3600
        }()
        let expiresAt = Date(timeIntervalSinceNow: expiresIn)
        return Refreshed(accessToken: newAccess, refreshToken: newRefresh, expiresAt: expiresAt)
    }

    nonisolated private static func writeBack(
        source: CredentialSource,
        refreshed: Refreshed
    ) throws {
        switch source {
        case .file:
            try writeBackToFile(refreshed: refreshed)
        case .keychain:
            try writeBackToKeychain(refreshed: refreshed)
        }
    }

    nonisolated private static func writeBackToFile(refreshed: Refreshed) throws {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = obj
        }
        var oauth = root["claudeAiOauth"] as? [String: Any] ?? [:]
        oauth["accessToken"] = refreshed.accessToken
        oauth["refreshToken"] = refreshed.refreshToken
        // Claude CLI 用毫秒时间戳
        oauth["expiresAt"] = Int(refreshed.expiresAt.timeIntervalSince1970 * 1000)
        root["claudeAiOauth"] = oauth
        let out = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try out.write(to: url, options: [.atomic])
    }

    nonisolated private static func writeBackToKeychain(refreshed: Refreshed) throws {
        // 读出原 JSON，更新 token 字段后整体回写，保留其他字段（subscriptionType 等）。
        let existing = try readKeychainJSON()
        var root = existing
        var oauth = root["claudeAiOauth"] as? [String: Any] ?? [:]
        oauth["accessToken"] = refreshed.accessToken
        oauth["refreshToken"] = refreshed.refreshToken
        oauth["expiresAt"] = Int(refreshed.expiresAt.timeIntervalSince1970 * 1000)
        root["claudeAiOauth"] = oauth
        let data = try JSONSerialization.data(withJSONObject: root, options: [])
        guard let str = String(data: data, encoding: .utf8) else {
            throw QuotaError.tokenRefreshFailed("encode keychain payload failed")
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = [
            "add-generic-password",
            "-U",
            "-s", keychainService,
            "-a", NSUserName(),
            "-w", str,
        ]
        let err = Pipe()
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                ?? "exit \(proc.terminationStatus)"
            throw QuotaError.tokenRefreshFailed("keychain write failed: \(msg)")
        }
    }

    nonisolated private static func readKeychainJSON() throws -> [String: Any] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        guard proc.terminationStatus == 0, !out.isEmpty,
              let str = String(data: out, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let data = str.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw QuotaError.tokenRefreshFailed("read keychain for merge failed")
        }
        return root
    }
}
