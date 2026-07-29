import XCTest
@testable import CodexTokenCostCore

final class PathUtilitiesSecurityTests: XCTestCase {
    func testSystemRootsAreRejected() {
        for path in TokenCostPathUtilities.forbiddenScanRoots {
            XCTAssertFalse(
                TokenCostPathUtilities.isSafeScanRoot(URL(fileURLWithPath: path)),
                "Expected \(path) to be rejected"
            )
        }
    }

    func testNormalCodexSessionDirectoryIsAllowed() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        XCTAssertTrue(TokenCostPathUtilities.isSafeScanRoot(url))
    }

    func testSensitiveUserDirectoriesAreRejected() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sensitivePaths = [
            ".ssh",
            ".gnupg/private-keys-v1.d",
            ".aws/credentials",
            "Library/Keychains/login.keychain-db",
            "Library/Application Support/Google/Chrome/Default"
        ]
        for path in sensitivePaths {
            XCTAssertFalse(
                TokenCostPathUtilities.isSafeScanRoot(home.appendingPathComponent(path)),
                "Expected \(path) to be rejected"
            )
        }
    }

    func testSymlinkToForbiddenRootIsRejected() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("path-security-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let link = temporaryDirectory.appendingPathComponent("users-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/Users"))

        XCTAssertFalse(TokenCostPathUtilities.isSafeScanRoot(link))
    }
}
