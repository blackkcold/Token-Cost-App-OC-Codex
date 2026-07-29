import XCTest
@testable import CodexTokenCostApp

final class UpdateCheckerInstallTests: XCTestCase {

    // MARK: - replaceAppBundle

    func testReplaceAppBundleAtomic() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("replace_atomic_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let currentApp = tempDir.appendingPathComponent("MyApp.app", isDirectory: true)
        let newApp = tempDir.appendingPathComponent("NewApp.app", isDirectory: true)
        try FileManager.default.createDirectory(at: currentApp, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newApp, withIntermediateDirectories: true)
        try "old".write(to: currentApp.appendingPathComponent("marker"), atomically: true, encoding: .utf8)
        try "new".write(to: newApp.appendingPathComponent("marker"), atomically: true, encoding: .utf8)

        let backupName = "MyApp.old"
        let resultURL = try UpdateChecker.replaceAppBundle(
            currentAppURL: currentApp,
            newAppURL: newApp,
            backupName: backupName
        )

        XCTAssertEqual(resultURL, currentApp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resultURL.path))
        let markerContent = try String(contentsOf: resultURL.appendingPathComponent("marker"), encoding: .utf8)
        XCTAssertEqual(markerContent, "new")

        let oldBackup = tempDir.appendingPathComponent(backupName, isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldBackup.path))
        let oldMarker = try String(contentsOf: oldBackup.appendingPathComponent("marker"), encoding: .utf8)
        XCTAssertEqual(oldMarker, "old")

        XCTAssertFalse(FileManager.default.fileExists(atPath: newApp.path))
    }

    func testReplaceAppBundleRollbackOnFailure() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("replace_rollback_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let currentApp = tempDir.appendingPathComponent("MyApp.app", isDirectory: true)
        try FileManager.default.createDirectory(at: currentApp, withIntermediateDirectories: true)
        try "old".write(to: currentApp.appendingPathComponent("marker"), atomically: true, encoding: .utf8)

        let nonExistentNewApp = tempDir.appendingPathComponent("DoesNotExist.app", isDirectory: true)

        XCTAssertThrowsError(try UpdateChecker.replaceAppBundle(
            currentAppURL: currentApp,
            newAppURL: nonExistentNewApp
        ))

        XCTAssertTrue(FileManager.default.fileExists(atPath: currentApp.path))
        let markerContent = try String(contentsOf: currentApp.appendingPathComponent("marker"), encoding: .utf8)
        XCTAssertEqual(markerContent, "old")
    }

    // MARK: - cleanupOldBackup

    func testCleanupOldBackupRemovesOld() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cleanup_old_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let backupName = "Token Cost App - OC Codex.old"
        let oldURL = tempDir.appendingPathComponent(backupName, isDirectory: true)
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path))

        UpdateChecker.cleanupOldBackup(in: tempDir, backupName: backupName)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
    }

    func testCleanupOldBackupNoOldNoop() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cleanup_noop_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        UpdateChecker.cleanupOldBackup(in: tempDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path))
    }

    // MARK: - scheduleRelaunch

    func testScheduleRelaunchLaunchesShell() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("relaunch_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let markerFile = tempDir.appendingPathComponent("relaunch_marker")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; touch \"\(markerFile.path)\""]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()

        process.waitUntilExit()

        XCTAssertTrue(FileManager.default.fileExists(atPath: markerFile.path))
    }
}