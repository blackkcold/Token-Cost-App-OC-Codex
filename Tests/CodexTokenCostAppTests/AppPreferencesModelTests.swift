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

    // MARK: - sortBalanceSnapshots

    func testSortBalanceSnapshotsCustomOrder() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_prefs_sort_custom_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        model.updatePreferences { prefs in
            prefs.balanceCustomOrder = [.codex, .deepseek, .opencodeGo]
        }

        let snapshots: [BalanceSnapshot] = [
            BalanceSnapshot.unavailable(.opencodeGo, reason: "n/a"),
            BalanceSnapshot.unavailable(.codex, reason: "n/a"),
            BalanceSnapshot.unavailable(.deepseek, reason: "n/a"),
            BalanceSnapshot.unavailable(.opencodeZen, reason: "n/a"),
        ]

        let sorted = model.sortBalanceSnapshots(snapshots)
        let order = sorted.map(\.provider)
        XCTAssertEqual(order, [.codex, .deepseek, .opencodeGo, .opencodeZen])
    }

    func testSortBalanceSnapshotsCustomOrderWithMissingProvider() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_prefs_sort_missing_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        model.updatePreferences { prefs in
            prefs.balanceCustomOrder = [.opencodeGo, .ollama]
        }

        let snapshots: [BalanceSnapshot] = [
            BalanceSnapshot.unavailable(.codex, reason: "n/a"),
            BalanceSnapshot.unavailable(.opencodeGo, reason: "n/a"),
            BalanceSnapshot.unavailable(.deepseek, reason: "n/a"),
        ]

        let sorted = model.sortBalanceSnapshots(snapshots)
        let order = sorted.map(\.provider)
        XCTAssertEqual(order.first, .opencodeGo)
        XCTAssertFalse(order.contains(.ollama))
    }

    func testSortBalanceSnapshotsFallbackWhenCustomOrderEmpty() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_prefs_sort_fallback_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        model.updatePreferences { prefs in
            prefs.balanceSortOrder = .byProvider
        }

        let snapshots: [BalanceSnapshot] = [
            BalanceSnapshot.unavailable(.deepseek, reason: "n/a"),
            BalanceSnapshot.unavailable(.opencodeGo, reason: "n/a"),
            BalanceSnapshot.unavailable(.codex, reason: "n/a"),
        ]

        let sorted = model.sortBalanceSnapshots(snapshots)
        let order = sorted.map(\.provider)
        XCTAssertEqual(order, [.opencodeGo, .codex, .deepseek])
    }

    func testResetBalanceCustomOrder() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_prefs_reset_order_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        model.updatePreferences { prefs in
            prefs.balanceCustomOrder = [.codex, .opencodeGo]
            prefs.balanceOrderLocked = false
        }

        model.resetBalanceCustomOrder()
        XCTAssertTrue(model.preferences.balanceCustomOrder.isEmpty)
        XCTAssertTrue(model.preferences.balanceOrderLocked)
    }

    // MARK: - sortBalanceSnapshots custom order with unavailable providers

    /// When `balanceCustomOrder` only contains available providers, unavailable providers
    /// must still appear in the result, sorted by `sortOrder` via the remaining branch.
    func testSortBalanceSnapshotsCustomOrderPreservesUnavailableProviders() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_prefs_sort_unavail_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        model.updatePreferences { prefs in
            prefs.balanceCustomOrder = [.codex, .opencodeGo]
            prefs.balanceOrderLocked = false
        }

        let snapshots: [BalanceSnapshot] = [
            BalanceSnapshot.unavailable(.opencodeGo, reason: "n/a"),
            BalanceSnapshot.unavailable(.codex, reason: "n/a"),
            BalanceSnapshot.unavailable(.opencodeZen, reason: "n/a"),
            BalanceSnapshot.unavailable(.deepseek, reason: "n/a"),
        ]

        let sorted = model.sortBalanceSnapshots(snapshots)
        let order = sorted.map(\.provider)
        // Custom order first (.codex, .opencodeGo), then remaining by sortOrder (.opencodeZen=2, .deepseek=3)
        XCTAssertEqual(order, [.codex, .opencodeGo, .opencodeZen, .deepseek])
    }

    // MARK: - sortBalanceSnapshots robustness against dirty customOrder

    func testSortBalanceSnapshotsDedupesDuplicateCustomOrder() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_prefs_sort_dup_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        model.updatePreferences { prefs in
            prefs.balanceCustomOrder = [.codex, .opencodeGo, .codex, .deepseek]
        }

        let snapshots: [BalanceSnapshot] = [
            BalanceSnapshot.unavailable(.opencodeGo, reason: "n/a"),
            BalanceSnapshot.unavailable(.codex, reason: "n/a"),
            BalanceSnapshot.unavailable(.deepseek, reason: "n/a"),
            BalanceSnapshot.unavailable(.opencodeZen, reason: "n/a"),
        ]

        let sorted = model.sortBalanceSnapshots(snapshots)
        let order = sorted.map(\.provider)
        XCTAssertEqual(order, [.codex, .opencodeGo, .deepseek, .opencodeZen])
        XCTAssertEqual(Set(order).count, order.count, "result must not contain duplicates")
    }

    func testSortBalanceSnapshotsIgnoresCustomOrderProviderNotInSnapshots() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_prefs_sort_ghost_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        model.updatePreferences { prefs in
            prefs.balanceCustomOrder = [.ollama, .codex, .opencodeGo, .ollama]
        }

        let snapshots: [BalanceSnapshot] = [
            BalanceSnapshot.unavailable(.opencodeGo, reason: "n/a"),
            BalanceSnapshot.unavailable(.codex, reason: "n/a"),
            BalanceSnapshot.unavailable(.opencodeZen, reason: "n/a"),
        ]

        let sorted = model.sortBalanceSnapshots(snapshots)
        let order = sorted.map(\.provider)
        XCTAssertFalse(order.contains(.ollama))
        XCTAssertEqual(order, [.codex, .opencodeGo, .opencodeZen])
        XCTAssertEqual(Set(order).count, order.count, "result must not contain duplicates")
    }

    func testNormalizedBalanceProviderOrderDedupesDuplicateCustomOrder() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_prefs_provider_order_dup_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        model.updatePreferences { prefs in
            prefs.balanceCustomOrder = [.codex, .opencodeGo, .codex, .deepseek, .ollama, .ollama]
        }

        let order = model.normalizedBalanceProviderOrder()
        XCTAssertEqual(order, [.codex, .opencodeGo, .deepseek, .ollama, .opencodeZen])
        XCTAssertEqual(Set(order).count, order.count, "settings order must not contain duplicate ForEach ids")
        XCTAssertEqual(Set(order), Set(BalanceProviderKind.allCases), "settings order must preserve every provider")
    }

    func testBalanceProviderOrderMovePreservesHiddenProviders() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_prefs_provider_order_move_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        model.updatePreferences { prefs in
            prefs.balanceCustomOrder = [.opencodeGo, .codex, .opencodeZen, .deepseek, .ollama]
        }

        let order = model.balanceProviderOrder(
            moving: [.opencodeGo, .opencodeZen],
            fromOffsets: IndexSet(integer: 1),
            toOffset: 0
        )

        XCTAssertEqual(order, [.opencodeZen, .codex, .opencodeGo, .deepseek, .ollama])
        XCTAssertEqual(Set(order), Set(BalanceProviderKind.allCases), "filtered drag must not drop hidden/unavailable providers")
    }
}
