import XCTest
@testable import CodexTokenCostCore

final class AppPreferencesTests: XCTestCase {
    func testAppPreferencesRoundtrip() throws {
        let original = AppPreferences(
            language: .en,
            balanceEnabled: true,
            balanceRefreshMinutes: 5,
            theme: .forest,
            displayCurrency: .cny,
            developerMode: DeveloperModePreferences(isEnabled: true, optimizeEnabled: true)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)
        XCTAssertEqual(original, decoded)
        XCTAssertTrue(decoded.developerMode.isEnabled)
        XCTAssertTrue(decoded.developerMode.optimizeEnabled)
    }

    func testOldConfigWithoutDeveloperModeDefaultsToAllOff() throws {
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

    func testAppPreferencesResetToDefaults() throws {
        var prefs = AppPreferences()
        prefs.developerMode = DeveloperModePreferences(isEnabled: true, taskClassificationEnabled: true)
        prefs.developerMode = DeveloperModePreferences()
        XCTAssertFalse(prefs.developerMode.isEnabled)
        XCTAssertFalse(prefs.developerMode.taskClassificationEnabled)
    }
}
