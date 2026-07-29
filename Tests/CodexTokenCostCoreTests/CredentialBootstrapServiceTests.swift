import XCTest
@testable import CodexTokenCostCore

final class CredentialBootstrapServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CredentialBootstrapService.shared.resetForTesting()
    }

    override func tearDown() {
        CredentialBootstrapService.shared.resetForTesting()
        super.tearDown()
    }

    // MARK: - Cache behavior

    func testCachedResultReturnsCachedWithoutReBootstrap() async {
        CredentialBootstrapService.shared.populateForTesting(
            goCookie: "test-cookie",
            goWorkspaceID: "wrk_test",
            ollamaCookie: "ollama-cookie"
        )

        let result = await CredentialBootstrapService.shared.bootstrap(mode: .keychainOnly)
        if case .cached = result {} else {
            XCTFail("Expected .cached, got \(result)")
        }

        XCTAssertEqual(CredentialBootstrapService.shared.getCachedGoCookie(), "test-cookie")
        XCTAssertEqual(CredentialBootstrapService.shared.getCachedGoWorkspaceID(), "wrk_test")
        XCTAssertEqual(CredentialBootstrapService.shared.getCachedOllamaCookie(), "ollama-cookie")
    }

    func testLocalStoreBootstrapPopulatesCache() async {
        let result = await CredentialBootstrapService.shared.bootstrap(mode: .keychainOnly)
        if case .localStore = result {} else {
            XCTFail("Expected .localStore, got \(result)")
        }
        XCTAssertTrue(CredentialBootstrapService.shared.isCachePopulated)
    }

    // MARK: - Auto browser mode

    func testAutoBrowserBootstrapExhaustsCandidatesAndFallsBackToLocalStore() async {
        let result = await CredentialBootstrapService.shared.bootstrap(
            mode: .autoBrowser,
            validator: AlwaysInvalidCredentialValidator(),
            candidateProvider: EmptyBrowserCredentialCandidateProvider()
        )
        switch result {
        case .extracted:
            XCTAssertTrue(CredentialBootstrapService.shared.isCachePopulated)
        case .localStore:
            XCTAssertTrue(CredentialBootstrapService.shared.isCachePopulated)
        case .failed:
            // Exhaustion is cached for the session to avoid repeatedly reading browsers.
            XCTAssertTrue(CredentialBootstrapService.shared.isCachePopulated)
        case .cached:
            XCTFail("Should not return .cached on fresh bootstrap")
        }
    }

    func testTotalFailureCachesNoCredentialStateForSession() async {
        // Clear any cached state and run autoBrowser. If it fails fully,
        // a second call should not scan browser stores again in the same session.
        CredentialBootstrapService.shared.resetForTesting()
        let first = await CredentialBootstrapService.shared.bootstrap(
            mode: .autoBrowser,
            validator: AlwaysInvalidCredentialValidator(),
            candidateProvider: EmptyBrowserCredentialCandidateProvider()
        )
        if case .failed = first {
            XCTAssertTrue(CredentialBootstrapService.shared.isCachePopulated)
            let second = await CredentialBootstrapService.shared.bootstrap(
                mode: .autoBrowser,
                validator: AlwaysInvalidCredentialValidator(),
                candidateProvider: EmptyBrowserCredentialCandidateProvider()
            )
            guard case .cached = second else {
                return XCTFail("Expected cached no-credential state after exhaustive scan")
            }
        } else if case .extracted = first {
            XCTAssertTrue(CredentialBootstrapService.shared.isCachePopulated)
        } else if case .localStore = first {
            XCTAssertTrue(CredentialBootstrapService.shared.isCachePopulated)
        }
    }

    // MARK: - Cache management

    func testClearCacheResetsAllFields() {
        CredentialBootstrapService.shared.populateForTesting(
            goCookie: "c",
            goWorkspaceID: "w",
            ollamaCookie: "o"
        )
        XCTAssertTrue(CredentialBootstrapService.shared.isCachePopulated)

        CredentialBootstrapService.shared.clearCache()
        XCTAssertNil(CredentialBootstrapService.shared.getCachedGoCookie())
        XCTAssertNil(CredentialBootstrapService.shared.getCachedGoWorkspaceID())
        XCTAssertNil(CredentialBootstrapService.shared.getCachedOllamaCookie())
        XCTAssertFalse(CredentialBootstrapService.shared.isCachePopulated)
    }

    func testUpdateCachedGoCookieSetsValues() {
        CredentialBootstrapService.shared.updateCachedGoCookie(
            "new-cookie",
            workspaceID: "wrk_new"
        )
        XCTAssertEqual(CredentialBootstrapService.shared.getCachedGoCookie(), "new-cookie")
        XCTAssertEqual(CredentialBootstrapService.shared.getCachedGoWorkspaceID(), "wrk_new")
        XCTAssertTrue(CredentialBootstrapService.shared.isCachePopulated)
    }

    func testUpdateCachedOllamaCookieSetsValue() {
        CredentialBootstrapService.shared.updateCachedOllamaCookie("ollama-new")
        XCTAssertEqual(CredentialBootstrapService.shared.getCachedOllamaCookie(), "ollama-new")
        XCTAssertTrue(CredentialBootstrapService.shared.isCachePopulated)
    }

    func testUpdateCachedGoCookieWithNilDoesNotMarkPopulated() {
        CredentialBootstrapService.shared.clearCache()
        CredentialBootstrapService.shared.updateCachedGoCookie(nil, workspaceID: nil)
        XCTAssertFalse(CredentialBootstrapService.shared.isCachePopulated)
    }

    func testDisabledCookieProvidersDoNotReadBrowserCandidates() async {
        let provider = CountingBrowserCredentialCandidateProvider()
        _ = await CredentialBootstrapService.shared.bootstrap(
            mode: .autoBrowser,
            enabledProviders: [.codex, .opencodeZen],
            validator: AlwaysInvalidCredentialValidator(),
            candidateProvider: provider
        )

        XCTAssertEqual(provider.readCount, 0)
    }

    // MARK: - CredentialSourceMode

    func testCredentialSourceModeDisplayName() {
        XCTAssertFalse(CredentialSourceMode.autoBrowser.displayName.isEmpty)
        XCTAssertFalse(CredentialSourceMode.keychainOnly.displayName.isEmpty)
        XCTAssertNotEqual(CredentialSourceMode.autoBrowser.displayName, CredentialSourceMode.keychainOnly.displayName)
    }

    func testCredentialSourceModeLocalStoreDisplayNameIsUpdated() {
        XCTAssertEqual(CredentialSourceMode.keychainOnly.displayName, "仅使用本地加密存储")
    }
}

private struct AlwaysInvalidCredentialValidator: CredentialCandidateValidating {
    func validateGo(workspaceID: String, cookie: String) async -> CredentialCandidateValidation {
        .invalid
    }

    func validateOllama(cookie: String) async -> CredentialCandidateValidation {
        .invalid
    }
}

private struct EmptyBrowserCredentialCandidateProvider: BrowserCredentialCandidateProviding {
    func goCandidates() -> [BrowserCookieExtractor.GoCredentialCandidate] { [] }
    func ollamaCandidates() -> [BrowserCookieExtractor.OllamaCookieCandidate] { [] }
}

private final class CountingBrowserCredentialCandidateProvider: BrowserCredentialCandidateProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _readCount = 0

    var readCount: Int { lock.withLock { _readCount } }

    func goCandidates() -> [BrowserCookieExtractor.GoCredentialCandidate] {
        lock.withLock { _readCount += 1 }
        return []
    }

    func ollamaCandidates() -> [BrowserCookieExtractor.OllamaCookieCandidate] {
        lock.withLock { _readCount += 1 }
        return []
    }
}

final class CredentialCandidateResolverTests: XCTestCase {
    func testResolverSkipsInvalidCandidateAndReturnsNextValidCandidate() async {
        let resolution = await CredentialCandidateResolver.firstValid(["expired", "valid"]) { candidate in
            candidate == "valid" ? .valid : .invalid
        }

        guard case .valid(let candidate) = resolution else {
            return XCTFail("Expected the second candidate to be selected")
        }
        XCTAssertEqual(candidate, "valid")
    }

    func testResolverStopsWhenValidationServiceIsUnavailable() async {
        var validated: [String] = []
        let resolution = await CredentialCandidateResolver.firstValid(["first", "second"]) { candidate in
            validated.append(candidate)
            return .unavailable
        }

        guard case .unavailable = resolution else {
            return XCTFail("Expected unavailable resolution")
        }
        XCTAssertEqual(validated, ["first"])
    }

    func testResolverReportsExhaustedWhenEveryCandidateIsInvalid() async {
        let resolution = await CredentialCandidateResolver.firstValid([1, 2, 3]) { _ in .invalid }
        guard case .exhausted = resolution else {
            return XCTFail("Expected exhausted resolution")
        }
    }
}
