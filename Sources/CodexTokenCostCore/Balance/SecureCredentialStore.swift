import Foundation
import Security

/// Thread-safe credential store for OpenCode Go workspace ID and auth cookie.
///
/// Credentials are cached in memory with NSLock protection.
/// Keychain access is direct (no UserDefaults guard); env fallback is gated
/// behind an explicit opt-in flag (Phase 0 guard, Phase 4 unified control).
public final class SecureCredentialStore: @unchecked Sendable {
    public static let shared = SecureCredentialStore()

    private let service = "com.yanghaoran.CodexTokenCost.opencode-go"
    private let workspaceIDAccount = "workspace-id"
    private let authCookieAccount = "auth-cookie"

    private let lock = NSLock()
    private var cachedWorkspaceID: String?
    private var cachedAuthCookie: String?
    private var cacheValid = false
    private var migrationCompleted = false

    private init() {
        performOneTimeMigration()
    }

    // MARK: - Public API

    public func saveWorkspaceID(_ id: String) {
        save(account: workspaceIDAccount, value: id)
        lock.withLock {
            cachedWorkspaceID = id
            cacheValid = true
        }
    }

    public func getWorkspaceID() -> String? {
        read(account: workspaceIDAccount)
    }

    public func saveAuthCookie(_ cookie: String) {
        save(account: authCookieAccount, value: cookie)
        lock.withLock {
            cachedAuthCookie = cookie
            cacheValid = true
        }
    }

    public func getAuthCookie() -> String? {
        read(account: authCookieAccount)
    }

    public func discoverCredentials(allowEnvironment: Bool = false) -> (workspaceID: String?, cookie: String?) {
        lock.lock()
        if cacheValid, let id = cachedWorkspaceID, let cookie = cachedAuthCookie {
            lock.unlock()
            return (id, cookie)
        }
        lock.unlock()

        let (id, cookie) = batchReadCredentials()
        if let id, let cookie {
            return cacheAndReturn(workspaceID: id, cookie: cookie)
        }

        if allowEnvironment,
           let environmentCredentials = Self.credentialsFromEnvironment(ProcessInfo.processInfo.environment) {
            return cacheAndReturn(
                workspaceID: environmentCredentials.workspaceID,
                cookie: environmentCredentials.cookie
            )
        }

        if let imported = readOpenCodeBarConfig() {
            return cacheAndReturn(workspaceID: imported.0, cookie: imported.1)
        }

        return (nil, nil)
    }

    public func deleteWorkspaceID() {
        delete(account: workspaceIDAccount)
        lock.withLock { invalidateCache() }
    }

    public func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false
        ]
        SecItemDelete(query as CFDictionary)

        lock.withLock {
            invalidateCache()
            migrationCompleted = false
            // Clear migration flag so credentials can be re-imported.
            UserDefaults.standard.removeObject(forKey: migrationCompletedKey)
        }
    }

    // MARK: - Internal (service-scoped variants for tests)

    func saveWorkspaceID(_ id: String, service: String) {
        save(account: workspaceIDAccount, value: id, service: service)
    }

    func getWorkspaceID(service: String) -> String? {
        read(account: workspaceIDAccount, service: service)
    }

    func saveAuthCookie(_ cookie: String, service: String) {
        save(account: authCookieAccount, value: cookie, service: service)
    }

    func getAuthCookie(service: String) -> String? {
        read(account: authCookieAccount, service: service)
    }

    func deleteWorkspaceID(service: String) {
        delete(account: workspaceIDAccount, service: service)
    }

    func discoverCredentialsForTesting(
        allowEnvironment: Bool,
        service: String,
        environment: [String: String],
        includeImportedConfig: Bool = false
    ) -> (workspaceID: String?, cookie: String?) {
        let (id, cookie) = batchReadCredentials(service: service)
        if let id, let cookie {
            return (id, cookie)
        }

        if allowEnvironment,
           let environmentCredentials = Self.credentialsFromEnvironment(environment) {
            return (environmentCredentials.workspaceID, environmentCredentials.cookie)
        }

        if includeImportedConfig, let imported = readOpenCodeBarConfig() {
            return imported
        }

        return (nil, nil)
    }

    // MARK: - Private: Keychain CRUD (no UserDefaults guard)

    private func save(account: String, value: String, service: String? = nil) {
        let svc = service ?? self.service
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: svc,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }

        if updateStatus != errSecItemNotFound {
#if DEBUG
            print("[SecureCredentialStore] Warning: failed to update keychain item for '\(account)': status \(updateStatus)")
#endif
            return
        }

        var addQuery = query
        addQuery[kSecValueData as String] = Data(value.utf8)
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
#if DEBUG
            print("[SecureCredentialStore] Warning: failed to add keychain item for '\(account)': status \(addStatus)")
#endif
        }
    }

    private func delete(account: String, service: String? = nil) {
        let svc = service ?? self.service
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: svc,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
#if DEBUG
            print("[SecureCredentialStore] Warning: failed to delete keychain item for '\(account)': status \(status)")
#endif
        }
    }

    /// Reads both workspaceID and authCookie in a single Keychain query.
    /// Uses kSecMatchLimitAll to avoid multiple SecItemCopyMatching calls.
    private func batchReadCredentials(service: String? = nil) -> (workspaceID: String?, authCookie: String?) {
        let svc = service ?? self.service
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: svc,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecAttrSynchronizable as String: false,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let items = result as? [[String: Any]]
        else {
            if status == errSecInteractionNotAllowed {
#if DEBUG
                print("[SecureCredentialStore] Keychain access denied (locked) during batch read")
#endif
            }
            return (nil, nil)
        }

        var workspaceID: String? = nil
        var authCookie: String? = nil

        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data,
                  let value = String(data: data, encoding: .utf8)
            else { continue }

            switch account {
            case workspaceIDAccount:
                workspaceID = value
            case authCookieAccount:
                authCookie = value
            default:
                break
            }
        }

        return (workspaceID, authCookie)
    }

    /// Reads a credential directly from the Keychain (no UserDefaults guard).
    private func read(account: String, service: String? = nil) -> String? {
        let svc = service ?? self.service
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: svc,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: false,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed:
            // Keychain is locked (e.g. device locked, user not logged in).
#if DEBUG
            print("[SecureCredentialStore] Keychain access denied (locked) for '\(account)'")
#endif
            return nil
        case errSecMissingEntitlement:
            // Compile-time / provisioning error — crash to surface the bug.
            fatalError("[SecureCredentialStore] Missing Keychain entitlement for '\(account)'. Check code signing and entitlements.")
        default:
#if DEBUG
            print("[SecureCredentialStore] Unexpected Keychain error for '\(account)': status \(status)")
#endif
            return nil
        }

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }

        return string
    }

    // MARK: - Internal query builder (for tests)

    func readQuery(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: false,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]
    }

    // MARK: - Cache

    private func cacheAndReturn(workspaceID: String, cookie: String) -> (String?, String?) {
        lock.withLock {
            cachedWorkspaceID = workspaceID
            cachedAuthCookie = cookie
            cacheValid = true
        }
        return (workspaceID, cookie)
    }

    private func invalidateCache() {
        cachedWorkspaceID = nil
        cachedAuthCookie = nil
        cacheValid = false
    }

    // MARK: - One-time Keychain Migration (EF-3)

    private var migrationCompletedKey: String {
        "SecureCredentialStore.migrationCompleted_v2"
    }

    private func performOneTimeMigration() {
        guard !UserDefaults.standard.bool(forKey: migrationCompletedKey) else { return }

        // Read directly from Keychain in one batch call.
        let (id, cookie) = batchReadCredentials()
        if let id, let cookie {
            lock.withLock {
                cachedWorkspaceID = id
                cachedAuthCookie = cookie
                cacheValid = true
            }
        }

        // Clean up old UserDefaults keys from previous version.
        let oldSavedKey = (service, workspaceIDAccount)
        let oldCookieKey = (service, authCookieAccount)

        UserDefaults.standard.removeObject(forKey: "SecureCredentialStore.saved.\(oldSavedKey.0).\(oldSavedKey.1)")
        UserDefaults.standard.removeObject(forKey: "SecureCredentialStore.saved.\(oldCookieKey.0).\(oldCookieKey.1)")
        UserDefaults.standard.removeObject(forKey: "SecureCredentialStore.workspaceID.\(service)")

        UserDefaults.standard.set(true, forKey: migrationCompletedKey)
        lock.withLock { migrationCompleted = true }
    }

    // MARK: - Legacy config import

    private func readOpenCodeBarConfig() -> (String, String)? {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode-bar/opencode-go.json")
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let id = json["workspaceId"] as? String
            ?? json["workspaceID"] as? String
            ?? json["workspace_id"] as? String
        let cookie = json["authCookie"] as? String
            ?? json["auth_cookie"] as? String
            ?? json["cookie"] as? String

        guard let id, let cookie else { return nil }
        return (id, cookie)
    }

    private static func credentialsFromEnvironment(_ environment: [String: String]) -> (workspaceID: String, cookie: String)? {
        guard let workspaceID = environment["OPENCODE_GO_WORKSPACE_ID"],
              let cookie = environment["OPENCODE_GO_AUTH_COOKIE"] else {
            return nil
        }
        return (workspaceID, cookie)
    }
}
