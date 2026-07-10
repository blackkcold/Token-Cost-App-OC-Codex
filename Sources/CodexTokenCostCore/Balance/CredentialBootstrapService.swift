import Foundation
import OSLog

/// Credential source mode controlling how credentials are obtained at launch.
public enum CredentialSourceMode: String, Codable, CaseIterable, Sendable {
    /// Automatically decrypt browser cookies on launch when cache is empty.
    case autoBrowser
    /// Only read from local encrypted storage; never attempt browser decryption.
    /// Decodes existing stored value `"keychainOnly"` compatibly as local-only.
    case keychainOnly

    public var displayName: String {
        switch self {
        case .autoBrowser: return "自动从浏览器导入"
        case .keychainOnly: return "仅使用本地加密存储"
        }
    }
}

/// Result of a credential bootstrap attempt.
public enum CredentialBootstrapResult: Sendable {
    /// Cache was already populated; no action taken.
    case cached
    /// Successfully extracted credentials from browser and populated cache.
    case extracted
    /// Read credentials from local encrypted storage (local-only mode).
    case localStore
    /// Failed after exhausting all retry attempts.
    case failed(error: String)
}

/// Session-scoped credential bootstrap service.
///
/// On app launch, `bootstrap(mode:)` is called. In `.autoBrowser` mode,
/// it attempts to decrypt browser cookies up to 3 times (1s delay between
/// rounds). On success, credentials are cached in memory for the entire
/// session and persisted to local encrypted storage. Previously-saved local
/// values are never overwritten by browser-extracted values automatically.
///
/// In `.keychainOnly` mode (decoded compatibly as local-only), credentials
/// are read from local encrypted storage without any browser decryption.
///
/// All cached values are cleared when the app terminates or when the user
/// explicitly deletes credentials.
public final class CredentialBootstrapService: @unchecked Sendable {
    public static let shared = CredentialBootstrapService()

    private static let logger = Logger(subsystem: "com.yanghaoran.CodexTokenCost", category: "CredentialBootstrap")
    private static let maxRetries = 3
    private static let retryDelayNanoseconds: UInt64 = 1_000_000_000

    private let lock = NSLock()
    private var cachedGoCookie: String?
    private var cachedGoWorkspaceID: String?
    private var cachedOllamaCookie: String?
    private var cachePopulated = false
    private var bootstrapInProgress = false

    private init() {}

    // MARK: - Public API

    /// Performs credential bootstrap at app launch.
    ///
    /// - Parameter mode: The credential source mode.
    /// - Returns: The result of the bootstrap attempt.
    @discardableResult
    public func bootstrap(mode: CredentialSourceMode) async -> CredentialBootstrapResult {
        let shouldProceed: Bool = lock.withLock {
            if cachePopulated { return false }
            if bootstrapInProgress { return false }
            bootstrapInProgress = true
            return true
        }

        if !shouldProceed {
            Self.logger.info("Bootstrap skipped: cache already populated or in progress")
            return .cached
        }

        defer {
            lock.withLock { bootstrapInProgress = false }
        }

        switch mode {
        case .keychainOnly:
            return bootstrapFromLocalStore()
        case .autoBrowser:
            return await bootstrapFromBrowser()
        }
    }

    // MARK: - Cache readers

    public func getCachedGoCookie() -> String? {
        lock.withLock { cachedGoCookie }
    }

    public func getCachedGoWorkspaceID() -> String? {
        lock.withLock { cachedGoWorkspaceID }
    }

    public func getCachedOllamaCookie() -> String? {
        lock.withLock { cachedOllamaCookie }
    }

    /// Returns true if the cache has been populated (successfully or not).
    public var isCachePopulated: Bool {
        lock.withLock { cachePopulated }
    }

    // MARK: - Cache management

    /// Clears the in-memory credential cache. Called when user deletes
    /// credentials or when a re-bootstrap is needed.
    public func clearCache() {
        lock.withLock {
            cachedGoCookie = nil
            cachedGoWorkspaceID = nil
            cachedOllamaCookie = nil
            cachePopulated = false
        }
        Self.logger.info("Credential cache cleared")
    }

    /// Updates a single cached Go cookie value (e.g. after manual browser import
    /// in Settings). Does not affect the `cachePopulated` flag.
    public func updateCachedGoCookie(_ cookie: String?, workspaceID: String?) {
        lock.withLock {
            cachedGoCookie = cookie
            cachedGoWorkspaceID = workspaceID
            if cookie != nil { cachePopulated = true }
        }
    }

    /// Updates a single cached Ollama cookie value (e.g. after manual browser
    /// import in Settings).
    public func updateCachedOllamaCookie(_ cookie: String?) {
        lock.withLock {
            cachedOllamaCookie = cookie
            if cookie != nil { cachePopulated = true }
        }
    }

    // MARK: - Internal (testable)

    /// Test helper: resets all internal state for test isolation.
    func resetForTesting() {
        clearCache()
    }

    /// Test helper: directly populates cache without browser extraction.
    func populateForTesting(goCookie: String?, goWorkspaceID: String?, ollamaCookie: String?) {
        lock.withLock {
            cachedGoCookie = goCookie
            cachedGoWorkspaceID = goWorkspaceID
            cachedOllamaCookie = ollamaCookie
            cachePopulated = true
        }
    }

    // MARK: - Private: Local-store bootstrap

    private func bootstrapFromLocalStore() -> CredentialBootstrapResult {
        let local = LocalCredentialService.shared
        let goCookie = local.getAuthCookie()
        let goWorkspaceID = local.getWorkspaceID()
        let ollamaCookie = local.getOllamaCookie()

        lock.withLock {
            cachedGoCookie = goCookie
            cachedGoWorkspaceID = goWorkspaceID
            cachedOllamaCookie = ollamaCookie
            cachePopulated = true
        }

        if goCookie != nil || ollamaCookie != nil {
            Self.logger.info("Local store bootstrap: credentials found and cached")
        } else {
            Self.logger.info("Local store bootstrap: no credentials in local storage")
        }

        return .localStore
    }

    // MARK: - Private: Browser bootstrap

    private func bootstrapFromBrowser() async -> CredentialBootstrapResult {
        var lastError: String?

        for attempt in 1...Self.maxRetries {
            Self.logger.info("Browser bootstrap attempt \(attempt)/\(Self.maxRetries)")

            async let goResult = Task.detached(priority: .userInitiated) {
                BrowserCookieExtractor.extractCredentials()
            }.value

            async let ollamaResult = Task.detached(priority: .userInitiated) {
                BrowserCookieExtractor.extractOllamaCookie()
            }.value

            let (browserGoCookie, browserGoWorkspaceID) = await goResult
            let browserOllamaCookie = await ollamaResult

            let goSuccess = browserGoCookie?.isEmpty == false
            let ollamaSuccess = browserOllamaCookie?.isEmpty == false

            if goSuccess || ollamaSuccess {
                let local = LocalCredentialService.shared

                // Resolve each field: existing local nonempty value wins;
                // browser fills only missing slots.
                let resolvedGoCookie: String? = {
                    if let localVal = local.getAuthCookie(), !localVal.isEmpty {
                        return localVal
                    }
                    return browserGoCookie
                }()
                let resolvedGoWorkspaceID: String? = {
                    if let localVal = local.getWorkspaceID(), !localVal.isEmpty {
                        return localVal
                    }
                    return browserGoWorkspaceID
                }()
                let resolvedOllamaCookie: String? = {
                    if let localVal = local.getOllamaCookie(), !localVal.isEmpty {
                        return localVal
                    }
                    return browserOllamaCookie
                }()

                lock.withLock {
                    cachedGoCookie = resolvedGoCookie
                    cachedGoWorkspaceID = resolvedGoWorkspaceID
                    cachedOllamaCookie = resolvedOllamaCookie
                    cachePopulated = true
                }

                // Persist browser values only when local storage is empty
                // for that field — never overwrite an existing local value.
                if goSuccess {
                    if local.getAuthCookie() == nil, let cookie = browserGoCookie, !cookie.isEmpty {
                        local.saveAuthCookie(cookie)
                    }
                    if local.getWorkspaceID() == nil, let wid = browserGoWorkspaceID, !wid.isEmpty {
                        local.saveWorkspaceID(wid)
                    }
                    Self.logger.info("Browser bootstrap: Go credentials cached and persisted to local storage")
                }

                if ollamaSuccess {
                    if local.getOllamaCookie() == nil, let cookie = browserOllamaCookie, !cookie.isEmpty {
                        local.saveOllamaCookie(cookie)
                    }
                    Self.logger.info("Browser bootstrap: Ollama cookie cached and persisted to local storage")
                }

                return .extracted
            }

            lastError = "浏览器中未找到有效凭证 (尝试 \(attempt)/\(Self.maxRetries))"
            Self.logger.warning("Browser bootstrap attempt \(attempt) failed: no credentials found")

            if attempt < Self.maxRetries {
                try? await Task.sleep(nanoseconds: Self.retryDelayNanoseconds)
            }
        }

        // All retries exhausted — try local storage as last resort
        let local = LocalCredentialService.shared
        let goCookie = local.getAuthCookie()
        let ollamaCookie = local.getOllamaCookie()

        if goCookie != nil || ollamaCookie != nil {
            lock.withLock {
                cachedGoCookie = goCookie
                cachedGoWorkspaceID = local.getWorkspaceID()
                cachedOllamaCookie = ollamaCookie
                cachePopulated = true
            }
            Self.logger.info("Browser bootstrap failed after \(Self.maxRetries) retries, but local storage had credentials")
            return .localStore
        }

        // Total failure: leave cache empty so a future bootstrap can retry.
        Self.logger.error("Browser bootstrap failed after \(Self.maxRetries) retries")
        return .failed(error: lastError ?? "浏览器凭证解密失败")
    }
}
