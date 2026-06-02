import Foundation
import Security

public enum SecureCredentialStore {
    private static let service = "com.yanghaoran.CodexTokenCost.opencode-go"
    private static let workspaceIDAccount = "workspace-id"
    private static let authCookieAccount = "auth-cookie"

    private nonisolated(unsafe) static var cachedWorkspaceID: String?
    private nonisolated(unsafe) static var cachedAuthCookie: String?
    private nonisolated(unsafe) static var cacheValid = false

    private static func invalidateCache() {
        cachedWorkspaceID = nil
        cachedAuthCookie = nil
        cacheValid = false
    }

    public static func saveWorkspaceID(_ id: String) {
        save(account: workspaceIDAccount, value: id, service: service)
        UserDefaults.standard.set(id, forKey: workspaceIDDefaultsKey(service: service))
        invalidateCache()
    }
    static func saveWorkspaceID(_ id: String, service: String) {
        save(account: workspaceIDAccount, value: id, service: service)
    }

    public static func getWorkspaceID() -> String? {
        if let workspaceID = UserDefaults.standard.string(forKey: workspaceIDDefaultsKey(service: service)),
           !workspaceID.isEmpty {
            return workspaceID
        }
        return read(account: workspaceIDAccount, service: service)
    }
    static func getWorkspaceID(service: String) -> String? {
        read(account: workspaceIDAccount, service: service)
    }

    public static func saveAuthCookie(_ cookie: String) {
        save(account: authCookieAccount, value: cookie, service: service)
        invalidateCache()
    }
    static func saveAuthCookie(_ cookie: String, service: String) {
        save(account: authCookieAccount, value: cookie, service: service)
    }

    public static func getAuthCookie() -> String? {
        read(account: authCookieAccount, service: service)
    }
    static func getAuthCookie(service: String) -> String? {
        read(account: authCookieAccount, service: service)
    }

    public static func discoverCredentials() -> (workspaceID: String?, cookie: String?) {
        if cacheValid {
            return (cachedWorkspaceID, cachedAuthCookie)
        }

        if let id = getWorkspaceID(), let cookie = getAuthCookie() {
            return cache(workspaceID: id, cookie: cookie)
        }

        let env = ProcessInfo.processInfo.environment
        if let id = env["OPENCODE_GO_WORKSPACE_ID"], let cookie = env["OPENCODE_GO_AUTH_COOKIE"] {
            return cache(workspaceID: id, cookie: cookie)
        }

        if let imported = readOpenCodeBarConfig() {
            return cache(workspaceID: imported.0, cookie: imported.1)
        }

        return (nil, nil)
    }

    private static func cache(workspaceID: String, cookie: String) -> (workspaceID: String?, cookie: String?) {
        cachedWorkspaceID = workspaceID
        cachedAuthCookie = cookie
        cacheValid = true
        return (workspaceID, cookie)
    }

    public static func deleteWorkspaceID() {
        delete(account: workspaceIDAccount, service: service)
        UserDefaults.standard.removeObject(forKey: workspaceIDDefaultsKey(service: service))
        invalidateCache()
    }
    static func deleteWorkspaceID(service: String) {
        delete(account: workspaceIDAccount, service: service)
    }

    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false
        ]
        SecItemDelete(query as CFDictionary)
        setSavedCredential(false, account: workspaceIDAccount, service: service)
        setSavedCredential(false, account: authCookieAccount, service: service)
        UserDefaults.standard.removeObject(forKey: workspaceIDDefaultsKey(service: service))
        invalidateCache()
    }

    private static func save(account: String, value: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            setSavedCredential(true, account: account, service: service)
            return
        }

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
        if addStatus == errSecSuccess {
            setSavedCredential(true, account: account, service: service)
        } else {
            #if DEBUG
            print("[SecureCredentialStore] Warning: failed to add keychain item for '\(account)': status \(addStatus)")
            #endif
        }
    }

    private static func delete(account: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            setSavedCredential(false, account: account, service: service)
        } else {
            #if DEBUG
            print("[SecureCredentialStore] Warning: failed to delete keychain item for '\(account)': status \(status)")
            #endif
        }
    }

    private static func read(account: String, service: String) -> String? {
        guard hasSavedCredential(account: account, service: service) else {
            return nil
        }

        let query = readQuery(account: account, service: service)
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            setSavedCredential(false, account: account, service: service)
            return nil
        }

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }

        return string
    }

    static func readQuery(account: String, service: String) -> [String: Any] {
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

    private static func hasSavedCredential(account: String, service: String) -> Bool {
        UserDefaults.standard.bool(forKey: savedCredentialDefaultsKey(account: account, service: service))
    }

    private static func setSavedCredential(_ saved: Bool, account: String, service: String) {
        let key = savedCredentialDefaultsKey(account: account, service: service)
        if saved {
            UserDefaults.standard.set(true, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func savedCredentialDefaultsKey(account: String, service: String) -> String {
        "SecureCredentialStore.saved.\(service).\(account)"
    }

    private static func workspaceIDDefaultsKey(service: String) -> String {
        "SecureCredentialStore.workspaceID.\(service)"
    }

    private static func readOpenCodeBarConfig() -> (String, String)? {
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
}
