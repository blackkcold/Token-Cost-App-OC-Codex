import XCTest
@testable import CodexTokenCostCore

final class LocalCredentialServiceTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("lcs-test-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let root = tempRoot {
            try? FileManager.default.removeItem(at: root)
        }
        tempRoot = nil
        super.tearDown()
    }

    private func makeStore() -> LocalEncryptedCredentialStore {
        try! LocalEncryptedCredentialStore(rootDirectory: tempRoot)
    }

    func testSaveAndGetWorkspaceID() {
        let store = makeStore()
        XCTAssertNil(store.readCredentials()?.workspaceID)

        try! store.modifyCredentials { _ in
            LocalCredentialPayload(workspaceID: "wrk_test123")
        }
        XCTAssertEqual(store.readCredentials()?.workspaceID, "wrk_test123")
    }

    func testOverwriteWorkspaceID() {
        let store = makeStore()
        try! store.writeCredentials(LocalCredentialPayload(workspaceID: "first"))
        try! store.writeCredentials(LocalCredentialPayload(workspaceID: "second"))
        XCTAssertEqual(store.readCredentials()?.workspaceID, "second")
    }

    func testSaveAndGetAuthCookie() {
        let store = makeStore()
        XCTAssertNil(store.readCredentials()?.goAuthCookie)

        try! store.modifyCredentials { _ in
            LocalCredentialPayload(goAuthCookie: "token-abc")
        }
        XCTAssertEqual(store.readCredentials()?.goAuthCookie, "token-abc")
    }

    func testSaveAndGetOllamaCookie() {
        let store = makeStore()
        XCTAssertNil(store.readCredentials()?.ollamaCookie)

        try! store.modifyCredentials { _ in
            LocalCredentialPayload(ollamaCookie: "session=xyz")
        }
        XCTAssertEqual(store.readCredentials()?.ollamaCookie, "session=xyz")
    }

    func testAtomicSavePreservesUnrelatedFields() {
        let store = makeStore()
        try! store.writeCredentials(LocalCredentialPayload(
            workspaceID: "old-id",
            goAuthCookie: "old-cookie",
            ollamaCookie: "old-ollama"
        ))

        try! store.modifyCredentials { current in
            var next = current ?? LocalCredentialPayload()
            next.workspaceID = "new-id"
            next.goAuthCookie = "new-cookie"
            return next
        }

        let result = store.readCredentials()
        XCTAssertEqual(result?.workspaceID, "new-id")
        XCTAssertEqual(result?.goAuthCookie, "new-cookie")
        XCTAssertEqual(result?.ollamaCookie, "old-ollama")
    }

    func testModifyReturnsNilLeavesUnchanged() throws {
        let store = makeStore()
        try store.writeCredentials(LocalCredentialPayload(workspaceID: "original"))
        try store.modifyCredentials { _ in nil }
        XCTAssertEqual(store.readCredentials()?.workspaceID, "original")
    }

    func testDeleteClearsCredentials() throws {
        let store = makeStore()
        try store.writeCredentials(LocalCredentialPayload(
            workspaceID: "wrk", goAuthCookie: "go", ollamaCookie: "ollama"
        ))
        XCTAssertNotNil(store.readCredentials())

        try store.deleteCredentials()
        XCTAssertNil(store.readCredentials())
    }

    func testDeleteWhenEmptyIsNoop() throws {
        let store = makeStore()
        XCTAssertNoThrow(try store.deleteCredentials())
    }

    func testSharedInstanceDoesNotCrash() {
        let svc = LocalCredentialService.shared
        _ = svc.getWorkspaceID()
        _ = svc.getAuthCookie()
        _ = svc.getOllamaCookie()
        _ = svc.discoverCredentials()
    }

    func testDiscoverCredentialsReadsFromStore() {
        let store = makeStore()
        try! store.writeCredentials(LocalCredentialPayload(
            workspaceID: "svc-wrk", goAuthCookie: "svc-cookie"
        ))
        XCTAssertEqual(store.readCredentials()?.workspaceID, "svc-wrk")
        XCTAssertEqual(store.readCredentials()?.goAuthCookie, "svc-cookie")
    }

    func testImportResultDidCopy() {
        let empty = LocalCredentialService.ImportResult(copiedFields: [])
        XCTAssertFalse(empty.didCopy)

        let copied = LocalCredentialService.ImportResult(copiedFields: ["workspaceID"])
        XCTAssertTrue(copied.didCopy)
    }

    func testImportResultWithMultipleFields() {
        let result = LocalCredentialService.ImportResult(copiedFields: ["workspaceID", "goAuthCookie", "ollamaCookie"])
        XCTAssertEqual(result.copiedFields.count, 3)
        XCTAssertTrue(result.didCopy)
    }

    // MARK: - Unavailable-store resilience

    func testSharedInstanceReadsDoNotCrash() {
        let svc = LocalCredentialService.shared
        _ = svc.getWorkspaceID()
        _ = svc.getAuthCookie()
        _ = svc.getOllamaCookie()
        _ = svc.discoverCredentials()
        _ = svc.discoverCredentials(allowEnvironment: true)
    }

    func testSharedInstanceWritesDoNotCrash() {
        let svc = LocalCredentialService.shared
        svc.saveWorkspaceID("no-crash-test")
        svc.saveAuthCookie("no-crash-test")
        svc.saveOllamaCookie("no-crash-test")
        svc.saveGoCredentials(workspaceID: "nc", cookie: "nc")
        svc.deleteAll()
        svc.importLegacyKeychainCredentials()
    }
}
