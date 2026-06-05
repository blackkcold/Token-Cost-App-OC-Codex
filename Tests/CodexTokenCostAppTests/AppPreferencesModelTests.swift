import XCTest
@testable import CodexTokenCostApp
@testable import CodexTokenCostCore

@MainActor
final class AppPreferencesModelTests: XCTestCase {
    func testEffectiveBalanceConfigurationFallsBackToDefault() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_preferences_model_default_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)

        XCTAssertEqual(model.effectiveBalanceConfiguration, BalanceConfiguration())
    }

    func testUpdateBalanceConfigurationPersistsImmediately() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_preferences_model_balance_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        model.updateBalanceConfiguration { config in
            config.enabledBalanceProviders = [.deepseek, .codex]
            config.allowEnvironmentCredentials = true
        }

        let reloaded = AppPreferencesModel(runtimeRoot: tempDir)
        XCTAssertEqual(
            reloaded.preferences.balanceConfig,
            BalanceConfiguration(
                enabledBalanceProviders: [.deepseek, .codex],
                allowEnvironmentCredentials: true
            )
        )
    }
}
