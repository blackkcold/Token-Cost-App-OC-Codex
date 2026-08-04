import XCTest
@testable import CodexTokenCostCore

final class BackupCompletenessTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupCompletenessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    private func makeLayeredDir(named name: String, containing files: [String]) throws -> URL {
        let dir = tempRoot.appendingPathComponent(name, isDirectory: true)
        let configSnapshot = dir.appendingPathComponent("config-snapshot", isDirectory: true)
        try FileManager.default.createDirectory(at: configSnapshot, withIntermediateDirectories: true)
        for file in files {
            try Data("{}".utf8).write(to: configSnapshot.appendingPathComponent(file))
        }
        return dir
    }

    /// Regression: a config file that exists ONLY in a layered backup directory
    /// must still report `hasBackup == true`, even when the passed backupRecords
    /// array contains no `.layered` record (as verifyCompleteness previously did).
    func testLayeredOnlyFileReportsBackedUpWhenRecordsAreFlatOnly() throws {
        let layeredDir = try makeLayeredDir(named: "backup-layered", containing: ["opencode.json"])

        // Simulates the pre-fix verifyCompleteness call: backupRecords has only a flat
        // record (unrelated file), so no .layered record is present in the array.
        let records: [BackupFileRecord] = [
            BackupFileRecord(
                fileName: "AGENTS-timestamp.md", sourceFileName: "AGENTS.md",
                path: tempRoot.appendingPathComponent("AGENTS-timestamp.md").path,
                byteCount: 2, createdAt: Date(), backupType: .flat
            )
        ]

        let groups = BackupService.configFileGroups(
            showDeprecated: false,
            backupRecords: records,
            latestLayeredDir: layeredDir.path
        )

        let opencodeGroup = groups.first { $0.id == "opencode" }
        let status = opencodeGroup?.files.first { $0.fileName == "opencode.json" }
        XCTAssertNotNil(opencodeGroup, "opencode group should be present")
        XCTAssertNotNil(status, "opencode.json status should be present")
        XCTAssertTrue(status?.hasBackup == true,
                      "File present only in layered backup should count as backed up")
    }

    func testFlatRecordReportsBackedUp() throws {
        let records: [BackupFileRecord] = [
            BackupFileRecord(
                fileName: "opencode-timestamp.json", sourceFileName: "opencode.json",
                path: tempRoot.appendingPathComponent("opencode-timestamp.json").path,
                byteCount: 2, createdAt: Date(), backupType: .flat
            )
        ]

        let groups = BackupService.configFileGroups(
            showDeprecated: false,
            backupRecords: records,
            latestLayeredDir: nil
        )

        let status = groups.first { $0.id == "opencode" }?
            .files.first { $0.fileName == "opencode.json" }
        XCTAssertTrue(status?.hasBackup == true)
    }

    func testNoBackupReportsNotBackedUp() throws {
        let groups = BackupService.configFileGroups(
            showDeprecated: false,
            backupRecords: [],
            latestLayeredDir: nil
        )

        let status = groups.first { $0.id == "opencode" }?
            .files.first { $0.fileName == "opencode.json" }
        XCTAssertTrue(status?.hasBackup == false)
    }

    func testVerifyCompletenessExcludesDeprecatedGroupWhenShowDeprecatedFalse() throws {
        let service = BackupService()
        let report = service.verifyCompleteness(in: tempRoot.path, showDeprecated: false)
        XCTAssertNotNil(report)
        XCTAssertFalse(
            report.groupReports.keys.contains("deprecated"),
            "状态概览在 showDeprecated=false 时不应包含已弃用分组"
        )
    }

    func testVerifyCompletenessIncludesDeprecatedGroupWhenShowDeprecatedTrue() throws {
        let service = BackupService()
        let report = service.verifyCompleteness(in: tempRoot.path, showDeprecated: true)
        XCTAssertNotNil(report)
        XCTAssertTrue(
            report.groupReports.keys.contains("deprecated"),
            "状态概览在 showDeprecated=true 时应包含已弃用分组"
        )
    }
}
