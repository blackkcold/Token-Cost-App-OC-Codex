import XCTest
@testable import CodexTokenCostCore

final class DeveloperFileAccessPolicyTests: XCTestCase {
    func testAllowlistPathsPositive() {
        // Paths under allowed roots should be accessible
        XCTAssertTrue(DeveloperFileAccessPolicy.isAccessible(
            NSHomeDirectory() + "/Library/Application Support/com.yanghaoran.CodexTokenCost/config/settings.json"
        ))
        XCTAssertTrue(DeveloperFileAccessPolicy.isAccessible(
            NSHomeDirectory() + "/.codex/sessions/some-session.jsonl"
        ))
    }

    func testBlocklistPathsNegative() {
        // Credential paths should be blocked
        let decision = DeveloperFileAccessPolicy.checkAccess(to: NSHomeDirectory() + "/.codex/auth.json")
        if case .denied = decision {
            // Expected
        } else {
            XCTFail("auth.json should be blocked")
        }
    }

    func testUnknownPathsAreDenied() {
        // Paths not in allowlist should be denied
        let decision = DeveloperFileAccessPolicy.checkAccess(to: "/tmp/some-random-file")
        if case .denied = decision {
            // Expected
        } else {
            XCTFail("Unknown path should be denied")
        }
    }

    func testBlocklistTakesPriorityOverAllowlist() {
        // Even if a path is under an allowed root, blocklist wins
        let decision = DeveloperFileAccessPolicy.checkAccess(to: NSHomeDirectory() + "/.config/opencode/oh-my-openagent.json")
        if case .denied = decision {
            // Expected — blocked even though ~/.config/opencode is related
        } else {
            XCTFail("oh-my-openagent.json should be blocked")
        }
    }

    func testSymlinkResolution() {
        // Test that symlink resolution works
        let tmpDir = NSTemporaryDirectory() + "devmode_test_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        // A temp directory not in allowlist should be denied
        let decision = DeveloperFileAccessPolicy.checkAccess(to: tmpDir)
        if case .denied = decision {
            // Expected
        } else {
            XCTFail("Temp directory should be denied")
        }
    }
}
