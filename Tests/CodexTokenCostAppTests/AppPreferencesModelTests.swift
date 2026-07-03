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

    // MARK: - Ollama overlay tests

    func testEffectiveConfigExcludesOllamaWhenGateOff() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_prefs_ollama_off_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        model.updateBalanceConfiguration { config in
            config.enabledBalanceProviders = [.opencodeGo, .ollama]
        }

        XCTAssertFalse(model.preferences.developerMode.ollamaUsageTrackingEnabled)
        let effective = model.effectiveBalanceConfiguration
        XCTAssertFalse(effective.enabledBalanceProviders.contains(.ollama))
    }

    func testEffectiveConfigIncludesOllamaWhenGateOn() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_prefs_ollama_on_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        model.updatePreferences { prefs in
            prefs.developerMode.ollamaUsageTrackingEnabled = true
        }
        model.updateBalanceConfiguration { config in
            config.enabledBalanceProviders = [.opencodeGo]
        }

        let effective = model.effectiveBalanceConfiguration
        XCTAssertTrue(effective.enabledBalanceProviders.contains(.ollama))
    }

    func testOllamaGateCyclePreservesOriginalConfig() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_prefs_ollama_cycle_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        model.updateBalanceConfiguration { config in
            config.enabledBalanceProviders = [.opencodeGo, .codex, .ollama]
        }

        let original = model.preferences.balanceConfig
        XCTAssertNotNil(original)
        XCTAssertEqual(original?.enabledBalanceProviders.contains(.ollama), true)

        XCTAssertFalse(model.effectiveBalanceConfiguration.enabledBalanceProviders.contains(.ollama))

        model.updatePreferences { prefs in
            prefs.developerMode.ollamaUsageTrackingEnabled = true
        }
        XCTAssertTrue(model.effectiveBalanceConfiguration.enabledBalanceProviders.contains(.ollama))

        model.updatePreferences { prefs in
            prefs.developerMode.ollamaUsageTrackingEnabled = false
        }
        XCTAssertFalse(model.effectiveBalanceConfiguration.enabledBalanceProviders.contains(.ollama))

        XCTAssertEqual(model.preferences.balanceConfig?.enabledBalanceProviders, original?.enabledBalanceProviders)
    }
}
