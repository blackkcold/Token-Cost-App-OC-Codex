import XCTest
@testable import CodexTokenCostCore

final class DeveloperModePreferencesTests: XCTestCase {
    func testDeveloperModePreferencesRoundtrip() throws {
        let prefs = DeveloperModePreferences(
            isEnabled: true,
            localGovernanceEnabled: true,
            aiAnalysisEnabled: false
        )
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(DeveloperModePreferences.self, from: data)
        XCTAssertEqual(prefs, decoded)
    }

    func testOldConfigWithoutDeveloperModeDefaultsToAllOff() throws {
        let json = """
        {"language":"zh-Hans","balance_enabled":false,"balance_refresh_minutes":10}
        """
        let data = json.data(using: .utf8)!
        let prefs = try JSONDecoder().decode(AppPreferences.self, from: data)
        XCTAssertFalse(prefs.developerMode.isEnabled)
        XCTAssertFalse(prefs.developerMode.localGovernanceEnabled)
        XCTAssertFalse(prefs.developerMode.aiAnalysisEnabled)
    }

    func testMigratedFieldsDefaultToTrue() throws {
        let json = """
        {"language":"zh-Hans"}
        """
        let data = json.data(using: .utf8)!
        let prefs = try JSONDecoder().decode(AppPreferences.self, from: data)
        XCTAssertTrue(prefs.taskClassificationEnabled)
        XCTAssertTrue(prefs.optimizeEnabled)
        XCTAssertTrue(prefs.multiCurrencyEnabled)
        XCTAssertTrue(prefs.modelCompareEnabled)
    }

    func testAiAnalysisEnabledIsAlwaysFalseByDefault() {
        let prefs = DeveloperModePreferences()
        XCTAssertFalse(prefs.aiAnalysisEnabled)
    }

    func testDeveloperModeToggleCycle() throws {
        var prefs = DeveloperModePreferences()
        XCTAssertFalse(prefs.isEnabled)
        prefs.isEnabled = true
        XCTAssertTrue(prefs.isEnabled)
        prefs.isEnabled = false
        XCTAssertFalse(prefs.isEnabled)
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(DeveloperModePreferences.self, from: data)
        XCTAssertFalse(decoded.isEnabled)
    }

    func testDefaultInitAllFalse() {
        let prefs = DeveloperModePreferences()
        XCTAssertFalse(prefs.isEnabled)
        XCTAssertFalse(prefs.localGovernanceEnabled)
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
            localGovernanceEnabled: true,
            aiAnalysisEnabled: true
        )
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(DeveloperModePreferences.self, from: data)
        XCTAssertEqual(prefs, decoded)
    }

    // MARK: - forceUpdateFromGitHub

    func testForceUpdateFromGitHubDefaultsToFalse() {
        let prefs = DeveloperModePreferences()
        XCTAssertFalse(prefs.forceUpdateFromGitHub)
    }

    func testForceUpdateFromGitHubRoundtrip() throws {
        let prefs = DeveloperModePreferences(
            isEnabled: true,
            forceUpdateFromGitHub: true
        )
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(DeveloperModePreferences.self, from: data)
        XCTAssertEqual(prefs, decoded)
        XCTAssertTrue(decoded.forceUpdateFromGitHub)
    }

    func testOldJSONWithoutForceUpdateFieldDecodesAsFalse() throws {
        let json = """
        {"isEnabled":true,"localGovernanceEnabled":false,"aiAnalysisEnabled":false}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DeveloperModePreferences.self, from: data)
        XCTAssertFalse(decoded.forceUpdateFromGitHub)
        XCTAssertTrue(decoded.isEnabled)
    }
}
