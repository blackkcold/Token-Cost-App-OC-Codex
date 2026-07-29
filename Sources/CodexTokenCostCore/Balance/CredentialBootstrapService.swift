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
/// it validates the encrypted local cache first, then checks browser/profile
/// candidates in deterministic order until a valid credential is found. On
/// success, credentials are cached in memory for the entire session and
/// persisted to local encrypted storage.
///
/// In `.keychainOnly` mode (decoded compatibly as local-only), credentials
/// are read from local encrypted storage without any browser decryption.
///
/// All cached values are cleared when the app terminates or when the user
/// explicitly deletes credentials.
public final class CredentialBootstrapService: @unchecked Sendable {
    public static let shared = CredentialBootstrapService()

    private static let logger = Logger(subsystem: "com.yanghaoran.CodexTokenCost", category: "CredentialBootstrap")
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
    public func bootstrap(
        mode: CredentialSourceMode,
        enabledProviders: Set<BalanceProviderKind> = [.opencodeGo, .ollama],
        validator: any CredentialCandidateValidating = LiveCredentialCandidateValidator(),
        candidateProvider: any BrowserCredentialCandidateProviding = LiveBrowserCredentialCandidateProvider()
    ) async -> CredentialBootstrapResult {
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
            return await bootstrapFromBrowser(
                enabledProviders: enabledProviders,
                validator: validator,
                candidateProvider: candidateProvider
            )
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

    private func bootstrapFromBrowser(
        enabledProviders: Set<BalanceProviderKind>,
        validator: any CredentialCandidateValidating,
        candidateProvider: any BrowserCredentialCandidateProviding
    ) async -> CredentialBootstrapResult {
        let local = LocalCredentialService.shared
        let localWorkspaceID = normalized(local.getWorkspaceID())
        let localGoCookie = normalized(local.getAuthCookie())
        let localOllamaCookie = normalized(local.getOllamaCookie())

        let localGoCandidate: ResolvedGoCandidate? = {
            guard enabledProviders.contains(.opencodeGo),
                  let localWorkspaceID,
                  let localGoCookie else { return nil }
            return ResolvedGoCandidate(
                workspaceID: localWorkspaceID,
                cookie: localGoCookie,
                source: "encrypted-cache",
                isLocal: true
            )
        }()
        let localOllamaCandidate: ResolvedOllamaCandidate? = {
            guard enabledProviders.contains(.ollama), let localOllamaCookie else { return nil }
            return ResolvedOllamaCandidate(
                cookie: localOllamaCookie,
                source: "encrypted-cache",
                isLocal: true
            )
        }()

        async let localGoValidation: CredentialCandidateValidation? = {
            guard let localGoCandidate else { return nil }
            return await validator.validateGo(
                workspaceID: localGoCandidate.workspaceID,
                cookie: localGoCandidate.cookie
            )
        }()
        async let localOllamaValidation: CredentialCandidateValidation? = {
            guard let localOllamaCandidate else { return nil }
            return await validator.validateOllama(cookie: localOllamaCandidate.cookie)
        }()

        var selectedGo: ResolvedGoCandidate?
        var selectedOllama: ResolvedOllamaCandidate?
        var importedFromBrowser = false
        var validationUnavailable = false
        let goLocalStatus = await localGoValidation
        let ollamaLocalStatus = await localOllamaValidation

        switch goLocalStatus {
        case .valid:
            selectedGo = localGoCandidate
            Self.logger.info("Go credential validated from encrypted cache")
        case .unavailable:
            selectedGo = localGoCandidate
            validationUnavailable = true
            Self.logger.warning("Go credential validation unavailable; encrypted cache preserved")
        case .invalid, nil:
            break
        }

        switch ollamaLocalStatus {
        case .valid:
            selectedOllama = localOllamaCandidate
            Self.logger.info("Ollama credential validated from encrypted cache")
        case .unavailable:
            selectedOllama = localOllamaCandidate
            validationUnavailable = true
            Self.logger.warning("Ollama credential validation unavailable; encrypted cache preserved")
        case .invalid, nil:
            break
        }

        async let browserGoResolution: CredentialCandidateResolver.Resolution<ResolvedGoCandidate>? = {
            guard enabledProviders.contains(.opencodeGo),
                  goLocalStatus != .valid,
                  goLocalStatus != .unavailable else { return nil }
            let candidates = await Task.detached(priority: .userInitiated) {
                candidateProvider.goCandidates()
            }.value.compactMap { candidate -> ResolvedGoCandidate? in
                guard let workspaceID = normalized(candidate.workspaceID) ?? localWorkspaceID,
                      let cookie = normalized(candidate.cookie) else {
                    return nil
                }
                return ResolvedGoCandidate(
                    workspaceID: workspaceID,
                    cookie: cookie,
                    source: candidate.source,
                    isLocal: false
                )
            }
            return await CredentialCandidateResolver.firstValid(candidates) { candidate in
                await validator.validateGo(workspaceID: candidate.workspaceID, cookie: candidate.cookie)
            }
        }()

        async let browserOllamaResolution: CredentialCandidateResolver.Resolution<ResolvedOllamaCandidate>? = {
            guard enabledProviders.contains(.ollama),
                  ollamaLocalStatus != .valid,
                  ollamaLocalStatus != .unavailable else { return nil }
            let candidates = await Task.detached(priority: .userInitiated) {
                candidateProvider.ollamaCandidates()
            }.value.compactMap { candidate -> ResolvedOllamaCandidate? in
                guard let cookie = normalized(candidate.cookie) else { return nil }
                return ResolvedOllamaCandidate(cookie: cookie, source: candidate.source, isLocal: false)
            }
            return await CredentialCandidateResolver.firstValid(candidates) { candidate in
                await validator.validateOllama(cookie: candidate.cookie)
            }
        }()

        let resolvedGo = await browserGoResolution
        let resolvedOllama = await browserOllamaResolution

        switch resolvedGo {
        case .valid(let candidate):
            selectedGo = candidate
            if !candidate.isLocal {
                local.saveGoCredentials(workspaceID: candidate.workspaceID, cookie: candidate.cookie)
                importedFromBrowser = true
            }
            Self.logger.info("Go credential validated from \(candidate.source, privacy: .public)")
        case .unavailable:
            validationUnavailable = true
            Self.logger.warning("Go browser candidate validation unavailable")
        case .exhausted:
            if goLocalStatus == .invalid {
                local.saveGoCredentials(workspaceID: localWorkspaceID, cookie: nil)
            }
            Self.logger.notice("No valid Go browser credential found")
        case nil:
            break
        }

        switch resolvedOllama {
        case .valid(let candidate):
            selectedOllama = candidate
            if !candidate.isLocal {
                local.saveOllamaCookie(candidate.cookie)
                importedFromBrowser = true
            }
            Self.logger.info("Ollama credential validated from \(candidate.source, privacy: .public)")
        case .unavailable:
            validationUnavailable = true
            Self.logger.warning("Ollama browser candidate validation unavailable")
        case .exhausted:
            if ollamaLocalStatus == .invalid {
                local.saveOllamaCookie("")
            }
            Self.logger.notice("No valid Ollama browser credential found")
        case nil:
            break
        }

        lock.withLock {
            cachedGoCookie = selectedGo?.cookie
            cachedGoWorkspaceID = selectedGo?.workspaceID
            cachedOllamaCookie = selectedOllama?.cookie
            cachePopulated = true
        }

        if importedFromBrowser { return .extracted }
        if selectedGo != nil || selectedOllama != nil { return .localStore }
        if enabledProviders.isDisjoint(with: [.opencodeGo, .ollama]) { return .localStore }
        if validationUnavailable {
            return .failed(error: "凭证验证服务暂时不可用，已保留本地缓存")
        }
        return .failed(error: "未找到有效的浏览器 Cookie")
    }

    private func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

private struct ResolvedGoCandidate: Sendable {
    let workspaceID: String
    let cookie: String
    let source: String
    let isLocal: Bool
}

private struct ResolvedOllamaCandidate: Sendable {
    let cookie: String
    let source: String
    let isLocal: Bool
}
