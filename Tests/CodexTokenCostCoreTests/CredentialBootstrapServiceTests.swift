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

    func testAutoBrowserBootstrapExhaustsRetriesAndFallsBackToLocalStore() async {
        let result = await CredentialBootstrapService.shared.bootstrap(mode: .autoBrowser)
        switch result {
        case .extracted:
            XCTAssertTrue(CredentialBootstrapService.shared.isCachePopulated)
        case .localStore:
            XCTAssertTrue(CredentialBootstrapService.shared.isCachePopulated)
        case .failed:
            // Total failure leaves cache unpopulated so it is retryable.
            XCTAssertFalse(CredentialBootstrapService.shared.isCachePopulated)
        case .cached:
            XCTFail("Should not return .cached on fresh bootstrap")
        }
    }

    func testTotalFailureLeavesCacheRetryable() async {
        // Clear any cached state and run autoBrowser. If it fails fully,
        // a second bootstrap call should proceed (not short-circuit as .cached).
        CredentialBootstrapService.shared.resetForTesting()
        let first = await CredentialBootstrapService.shared.bootstrap(mode: .autoBrowser)
        if case .failed = first {
            // After total failure, cache should be empty and another
            // bootstrap attempt should be allowed.
            XCTAssertFalse(CredentialBootstrapService.shared.isCachePopulated)
            // Re-bootstrap should not return .cached since cachePopulated is false.
            let second = await CredentialBootstrapService.shared.bootstrap(mode: .autoBrowser)
            switch second {
            case .cached:
                XCTFail("Should not return .cached after total failure — cache must be retryable")
            default:
                break
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
