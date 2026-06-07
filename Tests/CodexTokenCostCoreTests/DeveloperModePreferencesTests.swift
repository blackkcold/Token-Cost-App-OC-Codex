import XCTest
@testable import CodexTokenCostCore

final class DeveloperModePreferencesTests: XCTestCase {
    func testDeveloperModePreferencesRoundtrip() throws {
        let prefs = DeveloperModePreferences(
            isEnabled: true,
            taskClassificationEnabled: true,
            optimizeEnabled: false,
            localGovernanceEnabled: true,
            multiCurrencyEnabled: false,
            modelCompareEnabled: true,
            aiAnalysisEnabled: false
        )
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(DeveloperModePreferences.self, from: data)
        XCTAssertEqual(prefs, decoded)
    }

    func testOldConfigWithoutDeveloperModeDefaultsToAllOff() throws {
        // Simulate old JSON without developerMode key
        let json = """
        {"language":"zh-Hans","balance_enabled":false,"balance_refresh_minutes":10}
        """
        let data = json.data(using: .utf8)!
        let prefs = try JSONDecoder().decode(AppPreferences.self, from: data)
        XCTAssertFalse(prefs.developerMode.isEnabled)
        XCTAssertFalse(prefs.developerMode.taskClassificationEnabled)
        XCTAssertFalse(prefs.developerMode.optimizeEnabled)
        XCTAssertFalse(prefs.developerMode.localGovernanceEnabled)
        XCTAssertFalse(prefs.developerMode.multiCurrencyEnabled)
        XCTAssertFalse(prefs.developerMode.modelCompareEnabled)
        XCTAssertFalse(prefs.developerMode.aiAnalysisEnabled)
    }

    func testDeveloperModeOffStatePreservesSubToggles() throws {
        var prefs = DeveloperModePreferences(
            isEnabled: true,
            taskClassificationEnabled: true,
            optimizeEnabled: true
        )
        prefs.isEnabled = false
        // Sub-toggle values should be preserved
        XCTAssertTrue(prefs.taskClassificationEnabled)
        XCTAssertTrue(prefs.optimizeEnabled)
    }

    func testAiAnalysisEnabledIsAlwaysFalseByDefault() {
        let prefs = DeveloperModePreferences()
        XCTAssertFalse(prefs.aiAnalysisEnabled)
    }

    func testAppPreferencesResetToDefaults() throws {
        var prefs = AppPreferences()
        prefs.developerMode = DeveloperModePreferences(isEnabled: true, taskClassificationEnabled: true)
        // Reset
        prefs.developerMode = DeveloperModePreferences()
        XCTAssertFalse(prefs.developerMode.isEnabled)
        XCTAssertFalse(prefs.developerMode.taskClassificationEnabled)
    }

    // MARK: - P0 Tests (additional)

    func testDeveloperModeToggleCycle() throws {
        var prefs = DeveloperModePreferences()
        XCTAssertFalse(prefs.isEnabled)
        prefs.isEnabled = true
        XCTAssertTrue(prefs.isEnabled)
        prefs.isEnabled = false
        XCTAssertFalse(prefs.isEnabled)
        // Verify encoding roundtrip after toggle
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(DeveloperModePreferences.self, from: data)
        XCTAssertFalse(decoded.isEnabled)
    }

    func testDeveloperModeOffDoesNotChangeSubToggles() {
        var prefs = DeveloperModePreferences(
            isEnabled: true,
            taskClassificationEnabled: true,
            optimizeEnabled: true,
            localGovernanceEnabled: true
        )
        prefs.isEnabled = false
        // All sub-toggles should retain their values
        XCTAssertTrue(prefs.taskClassificationEnabled)
        XCTAssertTrue(prefs.optimizeEnabled)
        XCTAssertTrue(prefs.localGovernanceEnabled)
    }

    // MARK: - Edge Cases

    func testAllSubTogglesCanBeEnabledIndependently() {
        var prefs = DeveloperModePreferences()
        prefs.taskClassificationEnabled = true
        XCTAssertTrue(prefs.taskClassificationEnabled)
        XCTAssertFalse(prefs.optimizeEnabled)

        prefs.optimizeEnabled = true
        XCTAssertTrue(prefs.optimizeEnabled)
        XCTAssertFalse(prefs.localGovernanceEnabled)
    }

    func testDefaultInitAllFalse() {
        let prefs = DeveloperModePreferences()
        XCTAssertFalse(prefs.isEnabled)
        XCTAssertFalse(prefs.taskClassificationEnabled)
        XCTAssertFalse(prefs.optimizeEnabled)
        XCTAssertFalse(prefs.localGovernanceEnabled)
        XCTAssertFalse(prefs.multiCurrencyEnabled)
        XCTAssertFalse(prefs.modelCompareEnabled)
        XCTAssertFalse(prefs.aiAnalysisEnabled)
    }

    func testEquality() {
        let a = DeveloperModePreferences(isEnabled: true)
        let b = DeveloperModePreferences(isEnabled: true)
        let c = DeveloperModePreferences(isEnabled: false)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testCodableWithAllTrue() throws {
        let prefs = DeveloperModePreferences(
            isEnabled: true,
            taskClassificationEnabled: true,
            optimizeEnabled: true,
            localGovernanceEnabled: true,
            multiCurrencyEnabled: true,
            modelCompareEnabled: true,
            aiAnalysisEnabled: true
        )
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(DeveloperModePreferences.self, from: data)
        XCTAssertEqual(prefs, decoded)
    }
}
