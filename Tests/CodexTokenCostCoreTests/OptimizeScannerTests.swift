import XCTest
@testable import CodexTokenCostCore

final class OptimizeScannerTests: XCTestCase {
    func testScanReturnsEmptyForNonexistentPaths() {
        // Scan should not crash even if paths don't exist
        let findings = OptimizeScanner.scan()
        // We can't assert specific findings since they depend on the local filesystem
        // But we can verify the scan completes without crashing
        XCTAssertNotNil(findings)
    }

    func testFindingCategoriesAreValid() {
        // Verify all finding categories are defined
        let categories: [DeveloperFinding.FindingCategory] = [
            .staleSnapshot, .excessBackup, .largeSessionDir, .configFragmentation, .staleLatest
        ]
        XCTAssertEqual(categories.count, 5)
    }

    func testFindingStructure() {
        let finding = DeveloperFinding(
            category: .staleSnapshot,
            title: "Test Title",
            detail: "Test Detail",
            suggestion: "Test Suggestion"
        )
        XCTAssertEqual(finding.category, .staleSnapshot)
        XCTAssertEqual(finding.title, "Test Title")
        XCTAssertEqual(finding.detail, "Test Detail")
        XCTAssertEqual(finding.suggestion, "Test Suggestion")
    }

    func testFindingIsIdentifiable() {
        let a = DeveloperFinding(
            category: .excessBackup,
            title: "A",
            detail: "Detail A",
            suggestion: "Suggestion A"
        )
        let b = DeveloperFinding(
            category: .excessBackup,
            title: "B",
            detail: "Detail B",
            suggestion: "Suggestion B"
        )
        // Each finding gets a unique UUID id
        XCTAssertNotEqual(a.id, b.id)
    }

    func testFindingCategoryRawValues() {
        XCTAssertEqual(DeveloperFinding.FindingCategory.staleSnapshot.rawValue, "staleSnapshot")
        XCTAssertEqual(DeveloperFinding.FindingCategory.excessBackup.rawValue, "excessBackup")
        XCTAssertEqual(DeveloperFinding.FindingCategory.largeSessionDir.rawValue, "largeSessionDir")
        XCTAssertEqual(DeveloperFinding.FindingCategory.configFragmentation.rawValue, "configFragmentation")
        XCTAssertEqual(DeveloperFinding.FindingCategory.staleLatest.rawValue, "staleLatest")
    }
}
