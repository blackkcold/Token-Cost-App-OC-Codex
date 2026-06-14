import XCTest
@testable import CodexTokenCostCore

final class AppPreferencesTests: XCTestCase {
    func testAppPreferencesRoundtrip() throws {
        let original = AppPreferences(
            language: .en,
            balanceEnabled: true,
            balanceRefreshSeconds: 300,
            theme: .forest,
            displayCurrency: .cny,
            developerMode: DeveloperModePreferences(isEnabled: true, localGovernanceEnabled: true)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)
        XCTAssertEqual(original, decoded)
        XCTAssertTrue(decoded.developerMode.isEnabled)
        XCTAssertTrue(decoded.developerMode.localGovernanceEnabled)
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
    func testOldBalanceRefreshMinutesMigratesToSeconds() throws {
        let json = """
        {"language":"zh-Hans","balance_refresh_minutes":10}
        """
        let data = json.data(using: .utf8)!
        let prefs = try JSONDecoder().decode(AppPreferences.self, from: data)
        XCTAssertEqual(prefs.balanceRefreshSeconds, 600)
    }

    func testNewBalanceRefreshSecondsKey() throws {
        let prefs = AppPreferences(balanceRefreshSeconds: 90)
        let data = try JSONEncoder().encode(prefs)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(dict)
        XCTAssertEqual(dict?["balance_refresh_seconds"] as? Int, 90)
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

    func testAppPreferencesResetToDefaults() throws {
        var prefs = AppPreferences()
        prefs.developerMode = DeveloperModePreferences(isEnabled: true)
        prefs.developerMode = DeveloperModePreferences()
        XCTAssertFalse(prefs.developerMode.isEnabled)
    }
}
