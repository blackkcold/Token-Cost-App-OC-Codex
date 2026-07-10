import Foundation
import OSLog

/// Core-local credential service that wraps `LocalEncryptedCredentialStore`.
///
/// All normal runtime paths use this service.  It **never** accesses the macOS
/// Keychain or the `Security` framework — credentials are stored in an
/// AES-256-GCM encrypted file under `TokenCostPaths.runtimeRoot/credentials/`.
///
/// ## Key behaviours
/// - Browser-extracted credentials are persisted here, not in Keychain.
/// - Environment-variable fallback is gated behind an explicit opt-in flag
///   inside ``discoverCredentials(allowEnvironment:)``.
/// - The ``importLegacyKeychainCredentials()`` API is the **only** code path
///   that may touch ``SecureCredentialStore`` — it must be invoked explicitly
///   and never runs automatically.
public class LocalCredentialService: @unchecked Sendable {
    public static let shared = LocalCredentialService()

    private static let logger = Logger(
        subsystem: "com.yanghaoran.CodexTokenCost",
        category: "LocalCredentialService"
    )

    /// `nil` when the store could not be initialised — reads return `nil` and
    /// writes fail closed without persisting credentials elsewhere.
    private let store: LocalEncryptedCredentialStore?

    private var isAvailable: Bool { store != nil }

    private init() {
        do {
            store = try LocalEncryptedCredentialStore(rootDirectory: LocalEncryptedCredentialStore.defaultRoot)
        } catch {
            Self.logger.error("Local credential store unavailable")
            store = nil
        }
    }

    // MARK: - Workspace ID

    public func getWorkspaceID() -> String? {
        store?.readCredentials()?.workspaceID
    }

    public func saveWorkspaceID(_ id: String) {
        guard let store else {
            Self.logger.error("Cannot save workspace ID: store unavailable")
            return
        }
        do {
            try store.modifyCredentials { current in
                var next = current ?? LocalCredentialPayload()
                next.workspaceID = id
                return next
            }
        } catch {
            Self.logger.error("Failed to save workspace ID")
        }
    }

    // MARK: - Go auth cookie

    public func getAuthCookie() -> String? {
        store?.readCredentials()?.goAuthCookie
    }

    public func saveAuthCookie(_ cookie: String) {
        guard let store else {
            Self.logger.error("Cannot save auth cookie: store unavailable")
            return
        }
        do {
            try store.modifyCredentials { current in
                var next = current ?? LocalCredentialPayload()
                next.goAuthCookie = cookie
                return next
            }
        } catch {
            Self.logger.error("Failed to save auth cookie")
        }
    }

    // MARK: - Ollama cookie

    public func getOllamaCookie() -> String? {
        store?.readCredentials()?.ollamaCookie
    }

    public func saveOllamaCookie(_ cookie: String) {
        guard let store else {
            Self.logger.error("Cannot save Ollama cookie: store unavailable")
            return
        }
        do {
            try store.modifyCredentials { current in
                var next = current ?? LocalCredentialPayload()
                next.ollamaCookie = cookie
                return next
            }
        } catch {
            Self.logger.error("Failed to save Ollama cookie")
        }
    }

    // MARK: - Bulk operations

    /// Saves both Go workspace ID and auth cookie atomically.
    public func saveGoCredentials(workspaceID: String?, cookie: String?) {
        guard let store else {
            Self.logger.error("Cannot save Go credentials: store unavailable")
            return
        }
        do {
            try store.modifyCredentials { current in
                var next = current ?? LocalCredentialPayload()
                next.workspaceID = workspaceID
                next.goAuthCookie = cookie
                return next
            }
        } catch {
            Self.logger.error("Failed to save Go credentials")
        }
    }

    /// Atomically reads Go workspace ID and auth cookie, falling back to
    /// environment variables when `allowEnvironment` is `true`.
    ///
    /// - Returns: `(workspaceID, cookie)` tuple, where either or both may be `nil`.
    public func discoverCredentials(
        allowEnvironment: Bool = false
    ) -> (workspaceID: String?, cookie: String?) {
        let payload = store?.readCredentials()
        let id = payload?.workspaceID
        let cookie = payload?.goAuthCookie

        if let id, let cookie { return (id, cookie) }

        if allowEnvironment,
           let envCredentials = Self.credentialsFromEnvironment(
            ProcessInfo.processInfo.environment
           ) {
            return (envCredentials.workspaceID, envCredentials.cookie)
        }

        // Fallback: read legacy opencode-bar config file
        if let imported = Self.readOpenCodeBarConfig() {
            return (imported.0, imported.1)
        }

        return (nil, nil)
    }

    /// Deletes all locally stored credentials (data file only; key file preserved).
    public func deleteAll() {
        guard let store else {
            Self.logger.error("Cannot delete credentials: store unavailable")
            return
        }
        do {
            try store.deleteCredentials()
            Self.logger.info("Local credentials deleted")
        } catch {
            Self.logger.error("Failed to delete local credentials")
        }
    }

    // MARK: - Legacy Keychain Import (explicit only)

    /// Explicitly imports credentials from the legacy macOS Keychain into the
    /// local encrypted store.
    ///
    /// - Important: This is the **only** code path that touches
    ///   ``SecureCredentialStore``.  It is never invoked automatically —
    ///   callers must opt in explicitly.
    ///
    /// - This API copies values; it **never** deletes Keychain records.
    /// - If local storage already has a value for a particular field,
    ///   the Keychain value is silently skipped for that field (local-first).
    ///
    /// - Returns: A summary of what was copied.
    @discardableResult
    public func importLegacyKeychainCredentials() -> ImportResult {
        guard let store else {
            Self.logger.error("Keychain import skipped: local store unavailable")
            return ImportResult(copiedFields: [])
        }

        let keychain = SecureCredentialStore.shared

        let keychainGoCookie = keychain.getAuthCookie()
        let keychainWorkspaceID = keychain.getWorkspaceID()
        let keychainOllamaCookie = keychain.getOllamaCookie()

        let current = store.readCredentials()
        var copiedFields: [String] = []

        let hasWorkspaceID = current?.workspaceID != nil
        let hasGoCookie = current?.goAuthCookie != nil
        let hasOllamaCookie = current?.ollamaCookie != nil

        do {
            var payload = current ?? LocalCredentialPayload()

            if !hasWorkspaceID, let wid = keychainWorkspaceID, !wid.isEmpty {
                payload.workspaceID = wid
                copiedFields.append("workspaceID")
            }
            if !hasGoCookie, let go = keychainGoCookie, !go.isEmpty {
                payload.goAuthCookie = go
                copiedFields.append("goAuthCookie")
            }
            if !hasOllamaCookie, let ollama = keychainOllamaCookie, !ollama.isEmpty {
                payload.ollamaCookie = ollama
                copiedFields.append("ollamaCookie")
            }

            if !copiedFields.isEmpty {
                try store.writeCredentials(payload)
                Self.logger.info("Imported \(copiedFields.count) Keychain entries")
            } else {
                Self.logger.info("Keychain import: no new fields to copy (local data already present)")
            }

            return ImportResult(copiedFields: copiedFields)
        } catch {
            Self.logger.error("Keychain import failed")
            return ImportResult(copiedFields: [])
        }
    }

    /// Result of a legacy Keychain import.
    public struct ImportResult: Sendable {
        /// The field names that were copied (e.g. `"workspaceID"`, `"goAuthCookie"`,
        /// `"ollamaCookie"`).
        public let copiedFields: [String]

        public var didCopy: Bool { !copiedFields.isEmpty }
    }

    // MARK: - Private helpers

    private static func credentialsFromEnvironment(
        _ environment: [String: String]
    ) -> (workspaceID: String, cookie: String)? {
        guard let workspaceID = environment["OPENCODE_GO_WORKSPACE_ID"],
              let cookie = environment["OPENCODE_GO_AUTH_COOKIE"]
        else { return nil }
        return (workspaceID, cookie)
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
