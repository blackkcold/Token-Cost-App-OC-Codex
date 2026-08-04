import AppKit
import SwiftUI
import XCTest
@testable import CodexTokenCostApp
@testable import CodexTokenCostCore

@MainActor
final class AppPreferencesModelTests: XCTestCase {
    func testAccentAndAppearanceBindingsPersistIndependently() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_preferences_model_appearance_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        model.accentPaletteBinding.wrappedValue = .sunset
        model.appearanceModeBinding.wrappedValue = .dark

        let reloaded = AppPreferencesModel(runtimeRoot: tempDir)
        XCTAssertEqual(reloaded.preferences.accentPalette, .sunset)
        XCTAssertEqual(reloaded.preferences.appearanceMode, .dark)
    }

    func testLegacySourceThemeMigrationRunsOnlyForFallbackPreferences() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_preferences_model_legacy_theme_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        model.migrateThemeFromSettingsIfNeeded(.forest)
        XCTAssertEqual(model.preferences.accentPalette, .forest)
        XCTAssertEqual(model.preferences.appearanceMode, .system)

        model.accentPaletteBinding.wrappedValue = .ocean
        model.migrateThemeFromSettingsIfNeeded(.violet)
        XCTAssertEqual(model.preferences.accentPalette, .ocean)
    }

    func testAppearanceModeMapsToPreferredColorScheme() {
        XCTAssertNil(TokenCostAppearanceMode.system.preferredColorScheme)
        XCTAssertEqual(TokenCostAppearanceMode.light.preferredColorScheme, .light)
        XCTAssertEqual(TokenCostAppearanceMode.dark.preferredColorScheme, .dark)
        XCTAssertNil(TokenCostAppearanceMode.system.appKitAppearance)
        XCTAssertEqual(TokenCostAppearanceMode.light.appKitAppearance?.name, .aqua)
        XCTAssertEqual(TokenCostAppearanceMode.dark.appKitAppearance?.name, .darkAqua)
    }

    func testWorkshopPaletteUsesBrutalistSurfaceMetrics() {
        let palette = TokenCostPalette(accentPalette: .workshop)

        XCTAssertTrue(palette.usesWorkshopStyle)
        XCTAssertEqual(palette.cardBorderWidth, 2.5)
        XCTAssertEqual(palette.surfaceBorderWidth, 2.5)
        XCTAssertEqual(palette.shadowRadius, 0)
        XCTAssertEqual(palette.shadowX, 5)
        XCTAssertEqual(palette.shadowY, 5)
        XCTAssertEqual(palette.success, palette.accentSecondary)
    }

    func testExistingPaletteKeepsDefaultSurfaceMetrics() {
        let palette = TokenCostPalette(accentPalette: .ocean)

        XCTAssertFalse(palette.usesWorkshopStyle)
        XCTAssertEqual(palette.cardBorderWidth, 1)
        XCTAssertEqual(palette.surfaceBorderWidth, 1)
        XCTAssertEqual(palette.shadowRadius, TokenShadow.large.radius)
        XCTAssertEqual(palette.shadowX, 0)
        XCTAssertEqual(palette.shadowY, TokenShadow.large.y)
    }

    func testWorkshopThemeRendersInLightAndDark() throws {
        let lightImage = try renderWorkshopFixture(colorScheme: .light, filename: "workshop-light.png")
        let darkImage = try renderWorkshopFixture(colorScheme: .dark, filename: "workshop-dark.png")

        XCTAssertEqual(lightImage.size, NSSize(width: 900, height: 620))
        XCTAssertEqual(darkImage.size, NSSize(width: 900, height: 620))
    }

    private func renderWorkshopFixture(colorScheme: ColorScheme, filename: String) throws -> NSImage {
        let renderer = ImageRenderer(
            content: WorkshopThemeFixture()
                .environment(\.colorScheme, colorScheme)
        )
        renderer.proposedSize = ProposedViewSize(width: 900, height: 620)
        renderer.scale = 2

        let image = try XCTUnwrap(renderer.nsImage)
        if let outputDirectory = ProcessInfo.processInfo.environment["WORKSHOP_SNAPSHOT_DIR"] {
            let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
                .appendingPathComponent(filename)
            let tiffData = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
            let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try pngData.write(to: outputURL, options: .atomic)
        }
        return image
    }

    func testEffectiveBalanceConfigurationFallsBackToDefault() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_preferences_model_default_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)

        XCTAssertEqual(model.effectiveBalanceConfiguration, BalanceConfiguration())
    }

    func testBalanceRefreshSchedulerWaitsForCredentialBootstrap() {
        XCTAssertFalse(BalanceRefreshScheduler.shouldAttemptRefresh(
            balanceEnabled: true,
            credentialBootstrapComplete: false,
            intervalElapsed: true
        ))
        XCTAssertTrue(BalanceRefreshScheduler.shouldAttemptRefresh(
            balanceEnabled: true,
            credentialBootstrapComplete: true,
            intervalElapsed: true
        ))
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

    func testBalanceMenuBarExtraAndAlwaysOnTopBindingsPersistImmediately() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_preferences_model_balance_flags_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        model.balanceMenuBarExtraEnabledBinding.wrappedValue = true
        model.balanceFloatingPanelAlwaysOnTopBinding.wrappedValue = false

        let reloaded = AppPreferencesModel(runtimeRoot: tempDir)
        XCTAssertTrue(reloaded.preferences.balanceMenuBarExtraEnabled)
        XCTAssertFalse(reloaded.preferences.balanceFloatingPanelAlwaysOnTop)
    }

    func testBalanceFloatingPanelDisplayModeBindingPersistsRoundTrip() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_preferences_model_balance_display_mode_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        model.balanceFloatingPanelDisplayModeBinding.wrappedValue = .minimal

        let minimalReloaded = AppPreferencesModel(runtimeRoot: tempDir)
        XCTAssertEqual(minimalReloaded.preferences.balanceFloatingPanelDisplayMode, .minimal)

        minimalReloaded.balanceFloatingPanelDisplayModeBinding.wrappedValue = .normal

        let normalReloaded = AppPreferencesModel(runtimeRoot: tempDir)
        XCTAssertEqual(normalReloaded.preferences.balanceFloatingPanelDisplayMode, .normal)
    }

    func testBalanceMenuBarExtraEnabledBindingSameValueIsNoOp() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_preferences_model_menu_bar_guard_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let backupDir = tempDir.appendingPathComponent("config/backups/app-preferences")

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        model.balanceMenuBarExtraEnabledBinding.wrappedValue = true
        let backupCountAfterFirstWrite = backupFileCount(in: backupDir)

        model.balanceMenuBarExtraEnabledBinding.wrappedValue = true
        XCTAssertEqual(backupFileCount(in: backupDir), backupCountAfterFirstWrite,
                       "Same-value setter must be a no-op: no new backup created")

        model.balanceMenuBarExtraEnabledBinding.wrappedValue = false
        XCTAssertEqual(backupFileCount(in: backupDir), backupCountAfterFirstWrite + 1,
                       "Real value change must trigger exactly one backup")

        let reloaded = AppPreferencesModel(runtimeRoot: tempDir)
        XCTAssertFalse(reloaded.preferences.balanceMenuBarExtraEnabled)
    }

    private func backupFileCount(in directory: URL) -> Int {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return urls.filter { $0.pathExtension == "json" }.count
    }

    func testCustomSubscriptionCycleBindingPreservesOrInitializesPerProvider() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_preferences_model_custom_cycle_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        let preservedStart = Date(timeIntervalSince1970: 1_700_000_000)
        let preservedEnd = Date(timeIntervalSince1970: 1_700_086_400)

        model.updatePreferences { prefs in
            prefs.setBillingSelection(
                BillingPlanSelection(
                    mode: .preset,
                    presetID: BillingPlanCatalog.defaultSubscriptionSelection(for: .opencode).presetID,
                    isSubscribed: true,
                    periodGranularity: .month,
                    periodStart: preservedStart,
                    periodEnd: preservedEnd,
                    periodPreset: .monthly,
                    hasPeriodTracking: true
                ),
                for: .opencode
            )
            prefs.setBillingSelection(
                BillingPlanSelection(
                    mode: .preset,
                    presetID: BillingPlanCatalog.defaultSubscriptionSelection(for: .codex).presetID,
                    isSubscribed: true
                ),
                for: .codex
            )
        }

        model.periodPresetBinding(for: .opencode).wrappedValue = nil
        model.periodPresetBinding(for: .codex).wrappedValue = nil

        let opencode = model.preferences.billingSelection(for: .opencode)
        let codex = model.preferences.billingSelection(for: .codex)

        XCTAssertEqual(opencode.periodStart, preservedStart)
        XCTAssertEqual(opencode.periodEnd, preservedEnd)
        XCTAssertNil(opencode.periodPreset)
        XCTAssertTrue(opencode.hasPeriodTracking)

        XCTAssertNotNil(codex.periodStart)
        XCTAssertNotNil(codex.periodEnd)
        XCTAssertLessThanOrEqual(codex.periodStart!, codex.periodEnd!)
        XCTAssertNil(codex.periodPreset)
        XCTAssertTrue(codex.hasPeriodTracking)
    }

    func testCustomSubscriptionCycleManualEditsClampAndStayPerProvider() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_preferences_model_custom_cycle_clamp_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        let opencodeStart = Date(timeIntervalSince1970: 1_700_000_000)
        let opencodeEnd = Date(timeIntervalSince1970: 1_700_086_400)
        let codexStart = Date(timeIntervalSince1970: 1_600_000_000)
        let codexEnd = Date(timeIntervalSince1970: 1_600_086_400)

        model.updatePreferences { prefs in
            prefs.setBillingSelection(
                BillingPlanSelection(
                    mode: .preset,
                    presetID: BillingPlanCatalog.defaultSubscriptionSelection(for: .opencode).presetID,
                    isSubscribed: true,
                    periodGranularity: .month,
                    periodStart: opencodeStart,
                    periodEnd: opencodeEnd,
                    periodPreset: .monthly,
                    hasPeriodTracking: true
                ),
                for: .opencode
            )
            prefs.setBillingSelection(
                BillingPlanSelection(
                    mode: .preset,
                    presetID: BillingPlanCatalog.defaultSubscriptionSelection(for: .codex).presetID,
                    isSubscribed: true,
                    periodGranularity: .month,
                    periodStart: codexStart,
                    periodEnd: codexEnd,
                    periodPreset: .monthly,
                    hasPeriodTracking: true
                ),
                for: .codex
            )
        }

        model.periodPresetBinding(for: .opencode).wrappedValue = nil

        let laterStart = opencodeEnd.addingTimeInterval(86_400)
        model.periodStartBinding(for: .opencode).wrappedValue = laterStart

        let afterStartEdit = model.preferences.billingSelection(for: .opencode)
        XCTAssertEqual(afterStartEdit.periodStart, laterStart)
        XCTAssertEqual(afterStartEdit.periodEnd, laterStart)
        XCTAssertNil(afterStartEdit.periodPreset)

        XCTAssertEqual(model.preferences.billingSelection(for: .codex).periodStart, codexStart)
        XCTAssertEqual(model.preferences.billingSelection(for: .codex).periodEnd, codexEnd)

        let earlierEnd = laterStart.addingTimeInterval(-172_800)
        model.periodEndBinding(for: .opencode).wrappedValue = earlierEnd

        let afterEndEdit = model.preferences.billingSelection(for: .opencode)
        XCTAssertEqual(afterEndEdit.periodStart, earlierEnd)
        XCTAssertEqual(afterEndEdit.periodEnd, earlierEnd)
        XCTAssertNil(afterEndEdit.periodPreset)

        XCTAssertEqual(model.preferences.billingSelection(for: .codex).periodStart, codexStart)
        XCTAssertEqual(model.preferences.billingSelection(for: .codex).periodEnd, codexEnd)
    }

    func testReportingRangeDateRangeMatchesCoreResolverForAllModes() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_preferences_model_reporting_range_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = AppPreferencesModel(runtimeRoot: tempDir)
        var payload = DashboardPayload.empty()
        payload.rawData = [
            DashboardPayload.RawRow(
                date: "2026-06-30",
                model: "m1",
                provider: "opencode",
                input: 1,
                output: 1,
                reasoning: 0,
                cacheRead: 0,
                cacheWrite: 0,
                cacheWriteMissingCount: 0,
                cacheWriteReportedCount: 0,
                total: 2,
                cost: 0.1,
                msgCount: 1
            ),
            DashboardPayload.RawRow(
                date: "2026-07-05",
                model: "m2",
                provider: "codex",
                input: 2,
                output: 2,
                reasoning: 0,
                cacheRead: 0,
                cacheWrite: 0,
                cacheWriteMissingCount: 0,
                cacheWriteReportedCount: 0,
                total: 4,
                cost: 0.2,
                msgCount: 1
            ),
            DashboardPayload.RawRow(
                date: "2026-07-18",
                model: "m3",
                provider: "deepseek",
                input: 3,
                output: 3,
                reasoning: 0,
                cacheRead: 0,
                cacheWrite: 0,
                cacheWriteMissingCount: 0,
                cacheWriteReportedCount: 0,
                total: 6,
                cost: 0.3,
                msgCount: 1
            )
        ]

        let customBounds = ReportingRangeCustomBounds(
            start: Date(timeIntervalSince1970: 1_700_000_000),
            end: Date(timeIntervalSince1970: 1_700_691_200)
        )

        let cases: [(ReportingRangeMode, ReportingRangeCustomBounds)] = [
            (.allAvailable, ReportingRangeCustomBounds()),
            (.currentMonth, ReportingRangeCustomBounds()),
            (.last30Days, ReportingRangeCustomBounds()),
            (.custom, customBounds)
        ]

        let calendar = Calendar.autoupdatingCurrent

        for (mode, bounds) in cases {
            model.updatePreferences { prefs in
                prefs.reportingRangeMode = mode
                prefs.reportingRangeCustomBounds = bounds
            }

            let appRange = model.reportingRangeDateRange(for: payload)
            let coreRange = AppPreferences.resolveReportingRange(mode: mode, customBounds: bounds, payload: payload)

            guard let appRange else {
                XCTFail("app range nil for \(mode)")
                continue
            }

            guard let coreRange else {
                XCTFail("core range nil for \(mode)")
                continue
            }

            XCTAssertEqual(calendar.startOfDay(for: appRange.start), calendar.startOfDay(for: coreRange.start), "start mismatch for \(mode)")
            XCTAssertEqual(calendar.startOfDay(for: appRange.end), calendar.startOfDay(for: coreRange.end), "end mismatch for \(mode)")
            XCTAssertLessThanOrEqual(appRange.start, appRange.end)
            XCTAssertLessThanOrEqual(coreRange.start, coreRange.end)
        }
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

private struct WorkshopThemeFixture: View {
    private let palette = TokenCostPalette(accentPalette: .workshop)

    var body: some View {
        ZStack {
            palette.pageBackground

            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("TOKEN COST WORKSHOP")
                            .font(TokenTypography.headline(weight: .black, palette: palette))
                            .foregroundStyle(palette.title)
                        Text("A structured sketch board for cost signals")
                            .font(TokenTypography.caption(palette: palette))
                            .foregroundStyle(palette.subtitle)
                    }
                    Spacer()
                    TokenStatusPill(
                        title: "LIVE BOARD",
                        tint: palette.accentSecondary,
                        palette: palette,
                        systemImage: "cursorarrow.rays"
                    )
                }

                HStack(spacing: 20) {
                    TokenMetricCard(
                        title: "MONTHLY COST",
                        value: "$48.20",
                        subtitle: "OpenCode + Codex",
                        tint: palette.accent,
                        palette: palette
                    )
                    TokenMetricCard(
                        title: "TOKENS",
                        value: "12.4M",
                        subtitle: "30-day total",
                        tint: palette.accentSecondary,
                        palette: palette
                    )
                    TokenMetricCard(
                        title: "CACHE HIT",
                        value: "68%",
                        subtitle: "Stable this week",
                        tint: palette.warning,
                        palette: palette
                    )
                }

                TokenSectionCard(
                    title: "WORKFLOW SIGNALS",
                    subtitle: "Cards remain readable while the board keeps its rough workshop character",
                    trailing: nil,
                    palette: palette
                ) {
                    VStack(spacing: 14) {
                        DistributionRow(
                            title: "Input",
                            value: 7.2,
                            total: 12.4,
                            tint: palette.accent,
                            palette: palette,
                            suffix: "Primary model context"
                        )
                        DistributionRow(
                            title: "Output",
                            value: 5.2,
                            total: 12.4,
                            tint: palette.accentSecondary,
                            palette: palette,
                            suffix: "Generated responses"
                        )
                    }
                }
            }
            .padding(44)
        }
        .frame(width: 900, height: 620)
    }
}
