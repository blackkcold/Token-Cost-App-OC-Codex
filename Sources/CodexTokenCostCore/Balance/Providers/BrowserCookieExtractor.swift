import Foundation
import SQLite3
import CCryptoBridge

public enum BrowserKind: CaseIterable {
    case edge
    case chrome
    case brave
    case arc

    var displayName: String {
        switch self {
        case .edge: return "Microsoft Edge"
        case .chrome: return "Google Chrome"
        case .brave: return "Brave Browser"
        case .arc: return "Arc"
        }
    }

    var keychainService: String {
        switch self {
        case .edge: return "Microsoft Edge Safe Storage"
        case .chrome: return "Chrome Safe Storage"
        case .brave: return "Brave Safe Storage"
        case .arc: return "Arc Safe Storage"
        }
    }

    var profileDirs: [String] {
        let base: String
        switch self {
        case .edge: base = "Microsoft Edge"
        case .chrome: base = "Google/Chrome"
        case .brave: base = "BraveSoftware/Brave-Browser"
        case .arc: base = "Arc/User Data"
        }
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(base)
        return ["Default"] + (1...5).compactMap { i in
            let dir = root.appendingPathComponent("Profile \(i)")
            return FileManager.default.fileExists(atPath: dir.path) ? "Profile \(i)" : nil
        }
    }

    func cookiesURL(profileDir: String) -> URL {
        appSupportURL.appendingPathComponent("\(profileDir)/Cookies")
    }

    func historyURL(profileDir: String) -> URL {
        appSupportURL.appendingPathComponent("\(profileDir)/History")
    }

    var appSupportURL: URL {
        let base: String
        switch self {
        case .edge: base = "Microsoft Edge"
        case .chrome: base = "Google/Chrome"
        case .brave: base = "BraveSoftware/Brave-Browser"
        case .arc: base = "Arc/User Data"
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(base)
    }
}

// MARK: - Extractor

public enum BrowserCookieExtractor {

    public static func extractCredentials() -> (workspaceID: String?, cookie: String?) {
        for browser in BrowserKind.allCases {
            for profileDir in browser.profileDirs {
                let cookiesURL = browser.cookiesURL(profileDir: profileDir)
                let historyURL = browser.historyURL(profileDir: profileDir)

                guard FileManager.default.fileExists(atPath: cookiesURL.path) else { continue }

                guard let encryptionKey = fetchEncryptionKey(service: browser.keychainService),
                      let cookie = decryptCookie(dbURL: cookiesURL, key: encryptionKey),
                      !cookie.isEmpty
                else { continue }

                let workspaceID = extractWorkspaceID(historyURL: historyURL)
                return (workspaceID, cookie)
            }
        }
        return (nil, nil)
    }

    // MARK: - Ollama cookie extraction

    public static func extractOllamaCookie() -> String? {
        for browser in BrowserKind.allCases {
            for profileDir in browser.profileDirs {
                let baseURL = browser.appSupportURL.appendingPathComponent(profileDir)
                let dbCandidates: [URL] = [
                    baseURL.appendingPathComponent("Network/Cookies"),
                    baseURL.appendingPathComponent("Cookies")
                ]
                for dbURL in dbCandidates {
                    guard FileManager.default.fileExists(atPath: dbURL.path) else { continue }
                    guard let encryptionKey = fetchEncryptionKey(service: browser.keychainService),
                          let header = decryptOllamaCookie(dbURL: dbURL, key: encryptionKey)
                    else { continue }
                    return header
                }
            }
        }
        return nil
    }

    private static func decryptOllamaCookie(dbURL: URL, key: Data) -> String? {
        let tempURL = secureTempDirectory()
            .appendingPathComponent("ollama_cookies_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        do {
            try FileManager.default.copyItem(at: dbURL, to: tempURL)
        } catch {
            return nil
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(tempURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else { return nil }
        defer { sqlite3_close(db) }
        let metaVersion = readMetaVersion(db: db)
        var statement: OpaquePointer?
        let sql = """
            SELECT name, value, encrypted_value FROM cookies
            WHERE host_key LIKE '%ollama.com'
            AND name IN ('auth', '__Host-auth', '__Secure-auth', 'session', '__Host-session', '__Secure-session', 'sid', 'token')
            ORDER BY last_access_utc DESC LIMIT 10
            """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        var candidates: [(name: String, value: String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let namePtr = sqlite3_column_text(statement, 0) else { continue }
            let name = String(cString: namePtr)
            var foundValue: String?
            if let valuePtr = sqlite3_column_text(statement, 1) {
                let val = String(cString: valuePtr)
                if !val.isEmpty { foundValue = val }
            }
            if foundValue == nil,
               let blobPtr = sqlite3_column_blob(statement, 2) {
                let blobLen = sqlite3_column_bytes(statement, 2)
                let blobData = Data(bytes: blobPtr, count: Int(blobLen))
                if let decrypted = decryptOllamaEncryptedValue(blobData: blobData, key: key, metaVersion: metaVersion) {
                    foundValue = decrypted
                }
            }
            if let val = foundValue { candidates.append((name, val)) }
        }
        let preferred: [String] = ["__Host-auth", "__Secure-auth", "auth", "__Host-session", "__Secure-session", "session", "sid", "token"]
        for p in preferred {
            if let match = candidates.first(where: { $0.name == p }) {
                return "\(match.name)=\(match.value)"
            }
        }
        return candidates.first.map { "\($0.name)=\($0.value)" }
    }

    private static func decryptOllamaEncryptedValue(blobData: Data, key: Data, metaVersion: Int) -> String? {
        guard blobData.count > 3 else { return nil }
        let prefix = String(data: blobData.prefix(3), encoding: .utf8) ?? ""
        guard prefix.hasPrefix("v10") || prefix.hasPrefix("v1") else { return nil }
        let ciphertext = blobData.dropFirst(3)
        guard let plaintext = aescbcDecrypt(key: key, ciphertext: Data(ciphertext)),
              plaintext.count > 32
        else { return nil }
        let skipBytes = metaVersion >= 24 ? 32 : 32
        guard plaintext.count > skipBytes else { return nil }
        let cookieValue = plaintext.dropFirst(skipBytes)
        return String(data: cookieValue, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func aescbcDecrypt(key: Data, ciphertext: Data) -> Data? {
        let iv = Data(repeating: 0x20, count: 16)
        var outLen = ciphertext.count + 16
        var out = [UInt8](repeating: 0, count: outLen)
        let status = key.withUnsafeBytes { keyPtr in
            iv.withUnsafeBytes { ivPtr in
                ciphertext.withUnsafeBytes { ctPtr in
                    cc_aescbc_decrypt(keyPtr.baseAddress, key.count, ivPtr.baseAddress, ctPtr.baseAddress, ciphertext.count, &out, &outLen)
                }
            }
        }
        guard status == 0 else { return nil }
        return Data(out.prefix(outLen))
    }

    // MARK: - Keychain

    private static func fetchEncryptionKey(service: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 10, execute: timeout)

        do {
            try process.run()
            process.waitUntilExit()
            timeout.cancel()
        } catch {
            timeout.cancel()
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let passwordData = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let password = String(data: passwordData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !password.isEmpty
        else { return nil }

        return deriveKey(password: password)
    }

    // MARK: - PBKDF2

    private static func deriveKey(password: String) -> Data {
        let salt = Array("saltysalt".utf8)
        var derivedKey = [UInt8](repeating: 0, count: 16)
        _ = password.withCString { pwPtr in
            cc_pbkdf2_sha1(pwPtr, strlen(pwPtr), salt, salt.count, 1003, &derivedKey, 16)
        }
        return Data(derivedKey)
    }

    // MARK: - AES-128-CBC decryption

    private static func aesDecrypt(key: Data, ciphertext: Data) -> Data? {
        let iv = Data(repeating: 0x20, count: 16)
        var outLen = ciphertext.count + 16
        var out = [UInt8](repeating: 0, count: outLen)

        let status = key.withUnsafeBytes { keyPtr in
            iv.withUnsafeBytes { ivPtr in
                ciphertext.withUnsafeBytes { ctPtr in
                    cc_aes128cbc_decrypt(
                        keyPtr.baseAddress, ivPtr.baseAddress,
                        ctPtr.baseAddress, ciphertext.count,
                        &out, &outLen
                    )
                }
            }
        }

        guard status == 0 else { return nil }
        return Data(out.prefix(outLen))
    }

    // MARK: - Cookie decryption

    /// Creates a secure temporary directory for browser database copies.
    /// Uses a dedicated subdirectory with 0700 permissions to prevent
    /// other users from reading cookie data in multi-user environments.
    private static func secureTempDirectory() -> URL {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("com.yanghaoran.CodexTokenCost.browserext", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        // Restrict to owner-only access
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: tempRoot.path
        )
        return tempRoot
    }

    private static func decryptCookie(dbURL: URL, key: Data) -> String? {
        let tempURL = secureTempDirectory()
            .appendingPathComponent("opencode_cookies_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            try FileManager.default.copyItem(at: dbURL, to: tempURL)
        } catch {
            return nil
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tempURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else { return nil }
        defer { sqlite3_close(db) }

        let metaVersion = readMetaVersion(db: db)

        var statement: OpaquePointer?
        let sql = """
                    SELECT encrypted_value FROM cookies
                    WHERE (host_key LIKE '%.opencode.ai' OR host_key = 'opencode.ai')
                    AND name IN ('__Host-auth', 'auth')
                    ORDER BY CASE name WHEN '__Host-auth' THEN 0 WHEN 'auth' THEN 1 END, last_access_utc DESC LIMIT 1
                    """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        guard let blobPtr = sqlite3_column_blob(statement, 0) else { return nil }
        let blobLen = sqlite3_column_bytes(statement, 0)
        let blobData = Data(bytes: blobPtr, count: Int(blobLen))

        guard blobData.count > 3 else { return nil }

        let prefix = String(data: blobData.prefix(3), encoding: .utf8) ?? ""
        guard prefix.hasPrefix("v10") || prefix.hasPrefix("v11") || prefix.hasPrefix("v1") else { return nil }

        let ciphertext = blobData.dropFirst(3)

        guard let plaintext = aesDecrypt(key: key, ciphertext: Data(ciphertext)),
              plaintext.count > 32
        else { return nil }

        let skipBytes = metaVersion >= 24 ? 32 : 32
        guard plaintext.count > skipBytes else { return nil }

        let cookieValue = plaintext.dropFirst(skipBytes)
        return String(data: cookieValue, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func readMetaVersion(db: OpaquePointer) -> Int {
        var statement: OpaquePointer?
        let sql = "SELECT value FROM meta WHERE key = 'version'"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return 0 }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        if let textPtr = sqlite3_column_text(statement, 0) {
            return Int(String(cString: textPtr)) ?? 0
        }
        return 0
    }

    // MARK: - Ollama cookie SQLite test helper

    /// Queries a browser cookies SQLite DB for ollama.com plaintext cookie
    /// entries.  This internal test helper does NOT require the macOS
    /// Chromium Keychain encryption key.
    ///
    /// Returns the first matching entry as `name=value`, or `nil`.
    static func findOllamaPlaintextCookieValue(dbURL: URL) -> String? {
        let tempURL = secureTempDirectory()
            .appendingPathComponent("ollama_test_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard (try? FileManager.default.copyItem(at: dbURL, to: tempURL)) != nil
        else { return nil }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tempURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else { return nil }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        let sql = """
            SELECT name, value FROM cookies
            WHERE host_key LIKE '%ollama.com'
            AND value IS NOT NULL AND value != ''
            ORDER BY last_access_utc DESC LIMIT 10
            """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let namePtr = sqlite3_column_text(statement, 0),
                  let valuePtr = sqlite3_column_text(statement, 1)
            else { continue }
            let name = String(cString: namePtr)
            let value = String(cString: valuePtr)
            if !value.isEmpty {
                return "\(name)=\(value)"
            }
        }
        return nil
    }

    // MARK: - Workspace ID extraction

    static func extractWorkspaceID(historyURL: URL) -> String? {
        guard FileManager.default.fileExists(atPath: historyURL.path) else {
            return nil
        }

        let tempURL = secureTempDirectory()
            .appendingPathComponent("opencode_history_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            try FileManager.default.copyItem(at: historyURL, to: tempURL)
        } catch {
            return nil
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tempURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else { return nil }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        let sql = """
            SELECT url FROM urls
            WHERE url LIKE '%opencode.ai/workspace/%'
            ORDER BY last_visit_time DESC LIMIT 1
            """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        guard let textPtr = sqlite3_column_text(statement, 0) else { return nil }
        let urlString = String(cString: textPtr)

        guard let regex = try? NSRegularExpression(
            pattern: #"workspace/(wrk_[A-Za-z0-9]+)"#,
            options: []
        ) else { return nil }

        let range = NSRange(urlString.startIndex..., in: urlString)
        guard let match = regex.firstMatch(in: urlString, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: urlString)
        else { return nil }

        return String(urlString[captureRange])
    }
}
