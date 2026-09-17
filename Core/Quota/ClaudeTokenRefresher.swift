import Foundation
import os

private let refresherLog = Logger(subsystem: "com.andrewwujiy.manabar", category: "claude-refresh")

/// Claude 凭据的**只读**取用。
///
/// Claude 的 OAuth refresh_token 是一次性的(每次刷新服务端旋转新值、旧值作废),
/// 凭据归 Claude Code CLI 所有。ManaBar 若自己拿 refresh_token 续期,会和正在运行的
/// CLI 会话抢同一个 token,导致 CLI 被 `invalid_grant` 顶掉线。因此这里:
/// - **从不**请求 OAuth token 端点,**从不**回写 Keychain / credentials.json;
/// - access_token 过期时只重读存储(CLI 可能刚刷新写回);
/// - 仍过期则后台委托本机 `claude` CLI 自己刷新(`ClaudeDelegatedRefresh`),
///   本次返回 `tokenExpired`,由 AppState 转 CLI 兜底并保留已有快照。
enum ClaudeTokenRefresher {
    /// access_token 临期判定 skew,只用于判断"还能不能直接用"。
    static let refreshSkew: TimeInterval = 30
    static let keychainService = "Claude Code-credentials"

    /// 进程内的"被存储里偷读到的"凭据快照,只取我们关心的字段。
    struct StoredSnapshot: Sendable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date?
    }

    /// 返回当前可用的 access_token;过期时重读存储,仍过期则委托 CLI 刷新并返回失败。
    /// 读到新值时同步更新 account 内的 token / expiresAt(仅内存,不落盘)。
    nonisolated static func ensureFreshAccessToken(
        account: inout ClaudeAccount
    ) async -> Result<String, QuotaError> {
        // 空字符串视同缺失:凭据空壳(access/refresh 都为空)时直接报 missingToken,
        // 让上层走 CLI 兜底。
        guard let current = account.accessToken, !current.isEmpty else {
            return .failure(.missingToken)
        }
        if !isExpired(expiresAt: account.expiresAt) {
            return .success(current)
        }
        // CLI / Desktop 可能刚刷新并写回了新值,重读一次存储。
        if let onDisk = peekStored(source: account.source),
           let storedExpiresAt = onDisk.expiresAt,
           !isExpired(expiresAt: storedExpiresAt) {
            account.accessToken = onDisk.accessToken
            account.refreshToken = onDisk.refreshToken
            account.expiresAt = storedExpiresAt
            account.expiredGuess = false
            return .success(onDisk.accessToken)
        }
        // 仍过期:交给凭据的主人 claude CLI 去刷新。成功后经
        // .claudeDelegatedRefreshDidSucceed 通知触发 AppState 完整刷新,自动恢复。
        refresherLog.notice("access_token expired, delegating refresh to claude CLI")
        ClaudeDelegatedRefresh.attemptInBackground(source: account.source)
        return .failure(.tokenExpired(.claude))
    }

    nonisolated static func isExpired(expiresAt: Date?, skew: TimeInterval = refreshSkew) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < skew
    }

    // MARK: - Peek stored credentials (cheap re-read, bypass ClaudeAuth.load)

    nonisolated static func peekStored(source: CredentialSource) -> StoredSnapshot? {
        switch source {
        case .file: return peekFile()
        case .keychain: return peekKeychain()
        }
    }

    nonisolated private static func peekFile() -> StoredSnapshot? {
        let url = credentialsFileURL()
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any]
        else { return nil }
        return parseOAuth(oauth)
    }

    nonisolated private static func peekKeychain() -> StoredSnapshot? {
        guard let root = try? readKeychainJSON(),
              let oauth = root["claudeAiOauth"] as? [String: Any]
        else { return nil }
        return parseOAuth(oauth)
    }

    nonisolated private static func parseOAuth(_ oauth: [String: Any]) -> StoredSnapshot? {
        let access = oauth["accessToken"] as? String ?? oauth["access_token"] as? String
        guard let access, !access.isEmpty else { return nil }
        let refresh = oauth["refreshToken"] as? String ?? oauth["refresh_token"] as? String
        let expiresAt: Date? = {
            if let n = oauth["expiresAt"] as? Double {
                return Date(timeIntervalSince1970: n > 10_000_000_000 ? n / 1000 : n)
            }
            if let s = oauth["expiresAt"] as? String, let n = Double(s) {
                return Date(timeIntervalSince1970: n > 10_000_000_000 ? n / 1000 : n)
            }
            return nil
        }()
        return StoredSnapshot(accessToken: access, refreshToken: refresh, expiresAt: expiresAt)
    }

    nonisolated private static func credentialsFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
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
