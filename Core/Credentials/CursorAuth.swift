import CommonCrypto
import Foundation

/// 只读 Cursor 桌面端 / CLI 已有登录态。不刷新、不写回 state.vscdb 或钥匙串,
/// 避免和正在运行的 Cursor 抢同一份会轮换的 refresh token。
enum CursorAuth {
    nonisolated static let stateDBRelativePath = "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    nonisolated static let accessTokenKey = "cursorAuth/accessToken"
    nonisolated static let emailKey = "cursorAuth/cachedEmail"
    nonisolated static let membershipKey = "cursorAuth/stripeMembershipType"
    /// `agent login` 落在钥匙串里的 access token。桌面端 SQLite 没有 token 时才读。
    nonisolated static let keychainAccessTokenService = "cursor-access-token"
    /// Electron safeStorage 在 macOS 上用来加密 `cursorAuth/accessToken` 的钥匙串项。
    nonisolated static let safeStorageService = "Cursor Safe Storage"
    nonisolated private static let safeStoragePrefix = "cursor-safe-storage:v1:"
    nonisolated(unsafe) private static var cachedSafeStoragePassword: String?
    nonisolated private static let passwordLock = NSLock()

    nonisolated static func load() throws -> CursorAccount {
        if FileManager.default.fileExists(atPath: stateDBURL().path) {
            let rows = try readStateDB()
            if let stored = nonEmpty(rows[accessTokenKey]) {
                let token = try unwrapAccessToken(stored)
                return makeAccount(
                    token: token,
                    email: nonEmpty(rows[emailKey]),
                    planType: nonEmpty(rows[membershipKey]),
                    source: .file
                )
            }
        }
        if let stored = readKeychainToken() {
            let token = try unwrapAccessToken(stored)
            return makeAccount(token: token, email: nil, planType: nil, source: .keychain)
        }
        throw CredentialError.fileNotFound(stateDBURL().path)
    }

    /// 剩余不足 30 秒视为过期。解不出 `exp` 时不拦截,交给接口返回 401。
    nonisolated static func isExpired(_ token: String, now: Date = Date()) -> Bool {
        guard let expiresAt = accessTokenExpiresAt(token) else { return false }
        return expiresAt.timeIntervalSince(now) < 30
    }

    nonisolated static func accessTokenExpiresAt(_ token: String) -> Date? {
        guard let exp = JWT.decodePayload(token)?["exp"] else { return nil }
        if let n = exp as? Double { return Date(timeIntervalSince1970: n) }
        if let i = exp as? Int { return Date(timeIntervalSince1970: Double(i)) }
        if let n = exp as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
        return nil
    }

    /// 桌面端把 access token 包成 `cursor-safe-storage:v1:` 时,第一次解密会弹钥匙串授权。
    nonisolated static func storedTokenNeedsKeychain() -> Bool {
        guard let rows = try? readStateDB(),
              let stored = nonEmpty(rows[accessTokenKey])
        else { return false }
        return stored.hasPrefix(safeStoragePrefix) && !isJWT(stored)
    }

    /// 旧版是裸 JWT。新版是 safeStorage 密文,密钥在钥匙串「Cursor Safe Storage」。
    /// 把密文直接当 Bearer 会得到 401,看起来像登录过期。
    nonisolated static func unwrapAccessToken(_ stored: String) throws -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        if isJWT(trimmed) { return trimmed }
        guard trimmed.hasPrefix(safeStoragePrefix) else {
            throw CredentialError.decodeFailed("unrecognized cursor token")
        }
        let b64 = String(trimmed.dropFirst(safeStoragePrefix.count))
        guard let blob = Data(base64Encoded: b64),
              blob.starts(with: Data("v10".utf8)),
              blob.count > 3
        else {
            throw CredentialError.decodeFailed("unsupported cursor safe storage")
        }
        guard let password = safeStoragePassword() else {
            throw CredentialError.keychainUnavailable(safeStorageService)
        }
        guard let jwt = decryptChromiumV10(Data(blob.dropFirst(3)), password: password),
              isJWT(jwt)
        else {
            throw CredentialError.decodeFailed("cursor safe storage decrypt failed")
        }
        return jwt
    }

    nonisolated static func stateDBURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(stateDBRelativePath)
    }

    nonisolated private static func makeAccount(
        token: String,
        email: String?,
        planType: String?,
        source: CredentialSource
    ) -> CursorAccount {
        CursorAccount(
            source: source,
            email: email,
            planType: planType,
            expiresAt: accessTokenExpiresAt(token),
            expiredGuess: isExpired(token),
            accessToken: token
        )
    }

    nonisolated private static func readStateDB() throws -> [String: String] {
        let keys = [accessTokenKey, emailKey, membershipKey]
        let list = keys.map { "'\(sqlEscaped($0))'" }.joined(separator: ",")
        let sql = "SELECT key || char(31) || value FROM ItemTable WHERE key IN (\(list));"
        let output = try runSQLite(sql: sql)
        var rows: [String: String] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\u{1F}", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { rows[key] = value }
        }
        return rows
    }

    nonisolated private static func runSQLite(sql: String) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = ["-readonly", stateDBURL().path, sql]
        let pipe = Pipe()
        let err = Pipe()
        proc.standardOutput = pipe
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        guard proc.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                ?? "exit \(proc.terminationStatus)"
            throw CredentialError.decodeFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(data: out, encoding: .utf8) ?? ""
    }

    /// 找不到条目时返回 nil,不把「未登录 CLI」当成读取失败。
    nonisolated private static func readKeychainToken() -> String? {
        readGenericPassword(service: keychainAccessTokenService)
    }

    nonisolated private static func sqlEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    nonisolated private static func isJWT(_ token: String) -> Bool {
        let parts = token.split(separator: ".")
        return parts.count == 3 && token.hasPrefix("eyJ")
    }

    nonisolated private static func safeStoragePassword() -> String? {
        passwordLock.lock()
        defer { passwordLock.unlock() }
        if let cachedSafeStoragePassword, !cachedSafeStoragePassword.isEmpty {
            return cachedSafeStoragePassword
        }
        guard let password = readGenericPassword(service: safeStorageService) else { return nil }
        cachedSafeStoragePassword = password
        return password
    }

    /// Chromium / Electron safeStorage:PBKDF2-SHA1 + AES-128-CBC,IV 为 16 个空格。
    nonisolated private static func decryptChromiumV10(_ ciphertext: Data, password: String) -> String? {
        let salt = Data("saltysalt".utf8)
        var key = Data(count: kCCKeySizeAES128)
        let derived = key.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password,
                    password.lengthOfBytes(using: .utf8),
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    1003,
                    keyBytes.bindMemory(to: UInt8.self).baseAddress,
                    kCCKeySizeAES128
                )
            }
        }
        guard derived == kCCSuccess else { return nil }

        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var out = Data(count: ciphertext.count + kCCBlockSizeAES128)
        let outCapacity = out.count
        var outLength = 0
        let status = out.withUnsafeMutableBytes { outBytes in
            ciphertext.withUnsafeBytes { ctBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, kCCKeySizeAES128,
                            ivBytes.baseAddress,
                            ctBytes.baseAddress, ciphertext.count,
                            outBytes.baseAddress, outCapacity,
                            &outLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess, outLength > 0 else { return nil }
        out.removeSubrange(outLength..<out.count)
        return String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func readGenericPassword(service: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-generic-password", "-s", service, "-w"]
        let pipe = Pipe()
        let err = Pipe()
        proc.standardOutput = pipe
        proc.standardError = err
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        return nonEmpty(String(data: out, encoding: .utf8))
    }

    nonisolated private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
