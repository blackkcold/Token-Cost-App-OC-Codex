import XCTest
import Security
import SQLite3
import CCryptoBridge
@testable import CodexTokenCostCore

final class CodexTokenCostCoreTests: XCTestCase {
    func testActualTokensSubtractCachedInputPerSession() {
        let usage = CodexTokenUsage(
            inputTokens: 100,
            cachedInputTokens: 25,
            outputTokens: 7,
            reasoningOutputTokens: 3,
            totalTokens: 135
        )

        XCTAssertEqual(usage.actualInputTokens, 75)
        XCTAssertEqual(usage.actualTokens, 85)
    }

    func testDashboardPayloadTotalActualInputTokens() {
        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 250,
                totalActualTokens: 999,
                totalCacheReadTokens: 40,
                totalCacheWriteTokens: 10,
                totalCacheTokens: 50,
                totalCost: 0,
                totalMessages: 2,
                activeDays: 1,
                dateRange: .init(start: "2026-05-15", end: "2026-05-15"),
                updatedAt: "2026-05-15T12:00:00Z"
            ),
            dailyTotals: [:],
            modelTotals: [:],
            providerCosts: [:],
            providerTotals: [:],
            rawData: [
                DashboardPayload.RawRow(
                    date: "2026-05-15",
                    model: "m1",
                    provider: "p1",
                    input: 120,
                    output: 10,
                    reasoning: 0,
                    cacheRead: 30,
                    cacheWrite: 5,
                    cacheWriteMissingCount: 0,
                    cacheWriteReportedCount: 1,
                    total: 135,
                    cost: 0,
                    msgCount: 1
                ),
                DashboardPayload.RawRow(
                    date: "2026-05-15",
                    model: "m2",
                    provider: "p2",
                    input: 80,
                    output: 5,
                    reasoning: 0,
                    cacheRead: 10,
                    cacheWrite: 5,
                    cacheWriteMissingCount: 0,
                    cacheWriteReportedCount: 1,
                    total: 90,
                    cost: 0,
                    msgCount: 1
                )
            ]
        )

        XCTAssertEqual(payload.totalInputTokens, 200)
        XCTAssertEqual(payload.totalActualInputTokens, 200)
    }

    func testDashboardSummaryTrendAndSessionsShareTheSameActualTokenMath() {
        let firstSession = makeSession(
            sessionID: "session-a",
            updatedAt: "2026-05-15T09:00:00Z",
            usage: CodexTokenUsage(
                inputTokens: 100,
                cachedInputTokens: 25,
                outputTokens: 7,
                reasoningOutputTokens: 3,
                totalTokens: 135
            )
        )
        let secondSession = makeSession(
            sessionID: "session-b",
            updatedAt: "2026-05-15T11:00:00Z",
            usage: CodexTokenUsage(
                inputTokens: 50,
                cachedInputTokens: 10,
                outputTokens: 1,
                reasoningOutputTokens: 0,
                totalTokens: 61
            )
        )

        let payload = CodexDashboardPayload(
            summary: CodexDashboardPayload.Summary(
                sessionCount: 2,
                tokenCountEvents: 2,
                validTokenCountEvents: 2,
                totalInputTokens: 150,
                totalCachedInputTokens: 35,
                totalOutputTokens: 8,
                totalReasoningOutputTokens: 3,
                totalTokens: 196,
                planTypeCounts: [:],
                firstSessionStartedAt: "2026-05-15T09:00:00Z",
                lastSessionUpdatedAt: "2026-05-15T11:00:00Z",
                sourceRootLabel: "Test",
                updatedAt: "2026-05-15T12:00:00Z"
            ),
            sessions: [firstSession, secondSession]
        )

        let trendPoints = CodexDashboardAnalytics.dailyTrendPoints(from: payload)
        let sessionActualTotal = payload.sessions.reduce(0) { $0 + $1.actualTokens }

        XCTAssertEqual(payload.summary.totalActualInputTokens, 115)
        XCTAssertEqual(payload.summary.totalActualTokens, 126)
        XCTAssertEqual(sessionActualTotal, 126)
        XCTAssertEqual(trendPoints.count, 1)
        XCTAssertEqual(trendPoints.first?.sessionCount, 2)
        XCTAssertEqual(trendPoints.first?.actualTokens, 126)
    }

    func testSortSessionsUsesUnifiedActualTokenMath() {
        let lowerNetActualButHigherRaw = makeSession(
            sessionID: "session-a",
            updatedAt: "2026-05-15T09:00:00Z",
            usage: CodexTokenUsage(
                inputTokens: 100,
                cachedInputTokens: 90,
                outputTokens: 0,
                reasoningOutputTokens: 0,
                totalTokens: 100
            )
        )
        let higherNetActualButLowerRaw = makeSession(
            sessionID: "session-b",
            updatedAt: "2026-05-15T11:00:00Z",
            usage: CodexTokenUsage(
                inputTokens: 15,
                cachedInputTokens: 0,
                outputTokens: 0,
                reasoningOutputTokens: 0,
                totalTokens: 15
            )
        )

        let sorted = CodexDashboardAnalytics.sortSessions(
            [lowerNetActualButHigherRaw, higherNetActualButLowerRaw],
            field: .actualTokens,
            direction: .descending
        )

        XCTAssertEqual(sorted.map(\.sessionId), ["session-b", "session-a"])
    }

    func testAppPreferencesDecodeOldConfigDefaultsBillingSelections() throws {
        let data = #"{"language":"zh-Hans","openCodePricingMode":"api"}"#.data(using: .utf8)!
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: data)

        XCTAssertEqual(preferences.language, .zhHans)
        XCTAssertEqual(preferences.resolvedBillingPlan(for: .opencode).monthlyUSD, 10)
        XCTAssertEqual(preferences.resolvedBillingPlan(for: .codex).monthlyUSD, 20)
        XCTAssertEqual(preferences.resolvedBillingPlan(for: .minimax).monthlyUSD ?? 0, 98 / 7.2, accuracy: 0.0001)
        XCTAssertEqual(preferences.resolvedBillingPlan(for: .xiaomiMimo).monthlyUSD ?? 0, 34.9 / 7.2, accuracy: 0.0001)
    }

    func testCustomBillingSelectionOverridesProviderCost() {
        var preferences = AppPreferences()
        preferences.setBillingSelection(
            BillingPlanSelection(
                mode: .customMonthlyUSD,
                presetID: "opencode-go",
                customMonthlyUSD: 15
            ),
            for: .opencode
        )

        XCTAssertEqual(preferences.resolvedBillingPlan(for: .opencode).monthlyUSD, 15)
        XCTAssertEqual(preferences.billingOverridesByProviderKey()["opencode-go"], 15)
    }

    func testSubscriptionPresetsExcludeUsageBasedOptions() {
        let deepSeekPresetIDs = BillingPlanCatalog.subscriptionPresets(for: .deepseek).map(\.id)
        XCTAssertTrue(deepSeekPresetIDs.isEmpty, "DeepSeek has no fixed subscription presets")
        XCTAssertFalse(deepSeekPresetIDs.contains("deepseek-api-paygo"))

        let codexPresetIDs = BillingPlanCatalog.subscriptionPresets(for: .codex).map(\.id)
        XCTAssertTrue(codexPresetIDs.contains("chatgpt-plus"))
        XCTAssertTrue(codexPresetIDs.contains("chatgpt-pro"))
        XCTAssertFalse(codexPresetIDs.contains("chatgpt-business-codex-paygo"))
    }

    func testUsageBasedDeepSeekSelectionControlsCombinedCost() {
        var preferences = AppPreferences()
        for provider in BillingProvider.allCases {
            preferences.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 1_000_000,
                totalActualTokens: 1_000_000,
                totalCacheReadTokens: 0,
                totalCacheWriteTokens: 0,
                totalCacheTokens: 0,
                totalCost: 0,
                totalMessages: 1,
                activeDays: 1,
                dateRange: .init(start: "2026-05-15", end: "2026-05-15"),
                updatedAt: "2026-05-15T12:00:00Z"
            ),
            dailyTotals: [:],
            modelTotals: [:],
            providerCosts: [:],
            providerTotals: [:],
            rawData: [
                DashboardPayload.RawRow(
                    date: "2026-05-15",
                    model: "deepseek-chat",
                    provider: "deepseek",
                    input: 1_000_000,
                    output: 0,
                    reasoning: 0,
                    cacheRead: 0,
                    cacheWrite: 0,
                    cacheWriteMissingCount: 0,
                    cacheWriteReportedCount: 1,
                    total: 1_000_000,
                    cost: 0,
                    msgCount: 1
                )
            ]
        )

        // DeepSeek paygo disabled: API usage counts (DeepSeek has no fixed subscription)
        preferences.setBillingSelection(
            BillingPlanSelection(presetID: "deepseek-api-paygo", isSubscribed: false),
            for: .deepseek
        )
        let disabledCost = preferences.combinedMonthlyCost(payload: payload) ?? 0
        XCTAssertEqual(disabledCost, 0.14, accuracy: 0.0001)

        // DeepSeek: subscription toggle is disabled; subscribed=true is normalized away by AppPreferencesModel guard
        // and by resolve() normalizing usageBased→isSubscribed=false. Combined cost remains API-only.
        preferences.setBillingSelection(
            BillingPlanSelection(presetID: "deepseek-api-paygo", isSubscribed: true),
            for: .deepseek
        )
        let enabledCost = preferences.combinedMonthlyCost(payload: payload) ?? 0
        XCTAssertEqual(enabledCost, 0.14, accuracy: 0.0001)
    }

    func testTotalActualInputTokensSumsRowInputDirectlyWithoutCacheSubtraction() {
        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 200,
                totalActualTokens: 150,
                totalCacheReadTokens: 40,
                totalCacheWriteTokens: 10,
                totalCacheTokens: 50,
                totalCost: 0,
                totalMessages: 2,
                activeDays: 1,
                dateRange: .init(start: "2026-05-15", end: "2026-05-15"),
                updatedAt: "2026-05-15T12:00:00Z"
            ),
            dailyTotals: [:],
            modelTotals: [:],
            providerCosts: [:],
            providerTotals: [:],
            rawData: [
                DashboardPayload.RawRow(
                    date: "2026-05-15",
                    model: "m1",
                    provider: "p1",
                    input: 120,
                    output: 10,
                    reasoning: 0,
                    cacheRead: 30,
                    cacheWrite: 5,
                    cacheWriteMissingCount: 0,
                    cacheWriteReportedCount: 1,
                    total: 135,
                    cost: 0,
                    msgCount: 1
                ),
                DashboardPayload.RawRow(
                    date: "2026-05-15",
                    model: "m2",
                    provider: "p2",
                    input: 80,
                    output: 5,
                    reasoning: 0,
                    cacheRead: 10,
                    cacheWrite: 5,
                    cacheWriteMissingCount: 0,
                    cacheWriteReportedCount: 1,
                    total: 90,
                    cost: 0,
                    msgCount: 1
                )
            ]
        )

        // totalActualInputTokens should sum row.input directly, without subtracting cacheRead or cacheWrite
        XCTAssertEqual(payload.totalActualInputTokens, 200)
    }

    func testDashboardAnalyticsAppliesBillingOverridesWithoutChangingRawRows() {
        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 110,
                totalActualTokens: 110,
                totalCacheReadTokens: 0,
                totalCacheWriteTokens: 0,
                totalCacheTokens: 0,
                totalCost: 1,
                totalMessages: 1,
                activeDays: 1,
                dateRange: .init(start: "2026-05-15", end: "2026-05-15"),
                updatedAt: "2026-05-15T12:00:00Z"
            ),
            dailyTotals: [:],
            modelTotals: [:],
            providerCosts: [:],
            providerTotals: [:],
            rawData: [
                DashboardPayload.RawRow(
                    date: "2026-05-15",
                    model: "minimax-m2.7",
                    provider: "opencode-go",
                    input: 100,
                    output: 10,
                    reasoning: 0,
                    cacheRead: 0,
                    cacheWrite: 0,
                    cacheWriteMissingCount: 0,
                    cacheWriteReportedCount: 1,
                    total: 110,
                    cost: 1,
                    msgCount: 1
                )
            ]
        )

        let analytics = TokenCostDashboardAnalytics(
            payload: payload,
            billingOverridesByProviderKey: ["opencode-go": 15]
        )

        XCTAssertEqual(analytics.overview.totalCost, 15)
        XCTAssertEqual(analytics.sortedDetailRows(sortField: .cost, direction: .descending).first?.cost, 1)
    }

    private func makeSession(
        sessionID: String,
        updatedAt: String,
        usage: CodexTokenUsage
    ) -> CodexSessionSummary {
        CodexSessionSummary(
            sessionID: sessionID,
            label: sessionID,
            agentNickname: nil,
            startedAt: updatedAt,
            updatedAt: updatedAt,
            planType: nil,
            tokenCountEvents: 1,
            validTokenCountEvents: 1,
            usage: usage,
            modelContextWindow: nil
        )
    }

    // MARK: - AppPreferences workspaceID tests

    func testAppPreferencesInitRetainsWorkspaceID() {
        let prefs = AppPreferences(opencodeGoWorkspaceID: "ws-abc-123")
        XCTAssertEqual(prefs.opencodeGoWorkspaceID, "ws-abc-123")
    }

    func testAppPreferencesInitDefaultsToNil() {
        let prefs = AppPreferences()
        XCTAssertNil(prefs.opencodeGoWorkspaceID)
    }

    func testAppPreferencesDecodePreservesWorkspaceID() throws {
        let data = #"{"language":"zh-Hans","openCodePricingMode":"api","opencode_go_workspace_id":"ws-decoded-456"}"#.data(using: .utf8)!
        let prefs = try JSONDecoder().decode(AppPreferences.self, from: data)
        XCTAssertEqual(prefs.opencodeGoWorkspaceID, "ws-decoded-456")
    }

    func testAppPreferencesEncodeIncludesWorkspaceID() throws {
        let prefs = AppPreferences(opencodeGoWorkspaceID: "ws-encode-test")
        let data = try JSONEncoder().encode(prefs)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["opencode_go_workspace_id"] as? String, "ws-encode-test")
    }

    func testAppPreferencesEncodeOmitsNilWorkspaceID() throws {
        let prefs = AppPreferences()
        let data = try JSONEncoder().encode(prefs)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(json["opencode_go_workspace_id"])
    }

    func testAppPreferencesStorePersistsAutomaticSettings() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app_preferences_store_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = AppPreferencesStore(runtimeRoot: tempDir)
        var preferences = AppPreferences(balanceEnabled: true, theme: .violet, displayCurrency: .cny)
        preferences.balanceConfig = BalanceConfiguration(
            enabledBalanceProviders: [.codex, .deepseek],
            allowEnvironmentCredentials: true
        )
        preferences.setBillingSelection(
            BillingPlanSelection(presetID: "opencode-go", isSubscribed: false),
            for: .opencode
        )

        try store.save(preferences)

        let loaded = store.load()
        XCTAssertFalse(loaded.didFallbackToDefaults)
        XCTAssertEqual(loaded.preferences.balanceEnabled, true)
        XCTAssertEqual(loaded.preferences.theme, .violet)
        XCTAssertEqual(loaded.preferences.displayCurrency, .cny)
        XCTAssertEqual(loaded.preferences.balanceConfig, preferences.balanceConfig)
        XCTAssertEqual(loaded.preferences.billingSelection(for: .opencode).isSubscribed, false)
    }

    func testSettingsStorePersistsSourceSettings() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("settings_store_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SettingsStore(runtimeRoot: tempDir)
        let settings = TokenCostSettings(
            sourceRoots: ["/tmp/opencode"],
            manualSourcePaths: ["/tmp/opencode/state.db"],
            selectedSourceID: "selected-source",
            autoRescan: false,
            maxScanDepth: 3,
            maxScanCandidates: 12,
            snapshotRetentionCount: 7,
            theme: .forest,
            showZeroUsageXiaomiProvider: true
        )

        try store.save(settings)

        let loaded = store.load()
        XCTAssertFalse(loaded.didFallbackToDefaults)
        XCTAssertEqual(loaded.settings.sourceRoots, ["/tmp/opencode"])
        XCTAssertEqual(loaded.settings.manualSourcePaths, ["/tmp/opencode/state.db"])
        XCTAssertEqual(loaded.settings.selectedSourceID, "selected-source")
        XCTAssertEqual(loaded.settings.autoRescan, false)
        XCTAssertEqual(loaded.settings.snapshotRetentionCount, 7)
        XCTAssertEqual(loaded.settings.showZeroUsageXiaomiProvider, true)
    }

    // MARK: - SecureCredentialStore workspace-id round trip with isolated service

    func testKeychainReadQueryUsesAuthenticationUISkip() {
        let query = SecureCredentialStore.shared.readQuery(
            account: "workspace-id",
            service: "com.test.read-query"
        )

        XCTAssertEqual(query[kSecUseAuthenticationUI as String] as? String, kSecUseAuthenticationUISkip as String)
        XCTAssertNil(query[kSecUseAuthenticationUISkip as String])
    }

    func testWorkspaceIDRoundTripWithIsolatedService() throws {
        let testService = "com.test.workspace-id-test-\(UUID().uuidString)"
        defer {
            // Clean up test Keychain entries
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: testService
            ]
            SecItemDelete(query as CFDictionary)
        }

        try skipIfIsolatedKeychainUnavailable(service: testService)

        // Initially nil
        XCTAssertNil(SecureCredentialStore.shared.getWorkspaceID(service: testService))

        // Save and read back
        SecureCredentialStore.shared.saveWorkspaceID("test-ws-001", service: testService)
        XCTAssertEqual(SecureCredentialStore.shared.getWorkspaceID(service: testService), "test-ws-001")

        // Overwrite
        SecureCredentialStore.shared.saveWorkspaceID("test-ws-002", service: testService)
        XCTAssertEqual(SecureCredentialStore.shared.getWorkspaceID(service: testService), "test-ws-002")

        // Delete and verify nil
        SecureCredentialStore.shared.deleteWorkspaceID(service: testService)
        XCTAssertNil(SecureCredentialStore.shared.getWorkspaceID(service: testService))
    }

    func testDeleteWorkspaceIDDoesNotAffectOtherAccounts() throws {
        let testService = "com.test.isolated-delete-\(UUID().uuidString)"
        defer {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: testService
            ]
            SecItemDelete(query as CFDictionary)
        }

        try skipIfIsolatedKeychainUnavailable(service: testService)

        // Save both workspace-id and auth-cookie
        SecureCredentialStore.shared.saveWorkspaceID("ws-123", service: testService)
        SecureCredentialStore.shared.saveAuthCookie("cookie-abc", service: testService)

        // Delete only workspace-id
        SecureCredentialStore.shared.deleteWorkspaceID(service: testService)

        // Workspace-id should be gone
        XCTAssertNil(SecureCredentialStore.shared.getWorkspaceID(service: testService))
        // Auth-cookie should still exist
        XCTAssertEqual(SecureCredentialStore.shared.getAuthCookie(service: testService), "cookie-abc")
    }

    func testDiscoverCredentialsIgnoresEnvironmentWhenDisabled() {
        let credentials = SecureCredentialStore.shared.discoverCredentialsForTesting(
            allowEnvironment: false,
            service: "com.test.env-disabled-\(UUID().uuidString)",
            environment: [
                "OPENCODE_GO_WORKSPACE_ID": "wrk_env_disabled",
                "OPENCODE_GO_AUTH_COOKIE": "cookie_env_disabled"
            ]
        )

        XCTAssertNil(credentials.workspaceID)
        XCTAssertNil(credentials.cookie)
    }

    func testDiscoverCredentialsUsesEnvironmentWhenEnabled() {
        let credentials = SecureCredentialStore.shared.discoverCredentialsForTesting(
            allowEnvironment: true,
            service: "com.test.env-enabled-\(UUID().uuidString)",
            environment: [
                "OPENCODE_GO_WORKSPACE_ID": "wrk_env_enabled",
                "OPENCODE_GO_AUTH_COOKIE": "cookie_env_enabled"
            ]
        )

        XCTAssertEqual(credentials.workspaceID, "wrk_env_enabled")
        XCTAssertEqual(credentials.cookie, "cookie_env_enabled")
    }

    // MARK: - ConsumptionRateCalculator

    func testConsumptionRateFallbackUsesWindowStartAndPercentagePoints() {
        ConsumptionRateCalculator.resetHistoryForTesting()
        defer { ConsumptionRateCalculator.resetHistoryForTesting() }

        let windowStart = Date(timeIntervalSince1970: 1_700_000_000)
        let resetAt = windowStart.addingTimeInterval(3_600)
        let snapshot = BalanceSnapshot(
            provider: .opencodeGo,
            fetchedAt: windowStart.addingTimeInterval(900),
            isAvailable: true,
            quotaWindows: [
                BalanceQuotaWindow(
                    label: "5小时",
                    usedRatio: 0.25,
                    remainingRatio: 0.75,
                    resetAt: resetAt,
                    windowSeconds: 3_600
                )
            ]
        )

        let computed = ConsumptionRateCalculator.compute(current: [snapshot])
        let rate = computed.first?.quotaWindows?.first?.consumptionRate

        XCTAssertNotNil(rate)
        XCTAssertEqual(rate?.perHour ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(rate?.perDay ?? 0, 2_400, accuracy: 0.001)
        XCTAssertEqual(rate?.confidence ?? 0, 0.2, accuracy: 0.001)
    }

    func testConsumptionRateUsesPriorHistoryAndCurrentSnapshot() {
        ConsumptionRateCalculator.resetHistoryForTesting()
        defer { ConsumptionRateCalculator.resetHistoryForTesting() }

        let windowStart = Date(timeIntervalSince1970: 1_700_000_000)
        let resetAt = windowStart.addingTimeInterval(3_600)
        let firstSnapshot = BalanceSnapshot(
            provider: .opencodeGo,
            fetchedAt: windowStart.addingTimeInterval(600),
            isAvailable: true,
            quotaWindows: [
                BalanceQuotaWindow(
                    label: "5小时",
                    usedRatio: 0.10,
                    remainingRatio: 0.90,
                    resetAt: resetAt,
                    windowSeconds: 3_600
                )
            ]
        )
        ConsumptionRateCalculator.store([firstSnapshot])

        let secondSnapshot = BalanceSnapshot(
            provider: .opencodeGo,
            fetchedAt: windowStart.addingTimeInterval(1_200),
            isAvailable: true,
            quotaWindows: [
                BalanceQuotaWindow(
                    label: "5小时",
                    usedRatio: 0.20,
                    remainingRatio: 0.80,
                    resetAt: resetAt,
                    windowSeconds: 3_600
                )
            ]
        )

        let computed = ConsumptionRateCalculator.compute(current: [secondSnapshot])
        let rate = computed.first?.quotaWindows?.first?.consumptionRate

        XCTAssertNotNil(rate)
        XCTAssertEqual(rate?.perHour ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(rate?.perDay ?? 0, 1_440, accuracy: 0.001)
        XCTAssertEqual(rate?.confidence ?? 0, 0.4, accuracy: 0.001)
    }

    func testConsumptionRateNilWhenNoUsedRatio() {
        ConsumptionRateCalculator.resetHistoryForTesting()
        defer { ConsumptionRateCalculator.resetHistoryForTesting() }

        let snapshot = BalanceSnapshot(
            provider: .codex,
            fetchedAt: Date(),
            isAvailable: true,
            quotaWindows: [
                BalanceQuotaWindow(
                    label: "窗口",
                    usedRatio: nil,
                    remainingRatio: nil,
                    resetAt: Date().addingTimeInterval(3_600),
                    windowSeconds: 3_600
                )
            ]
        )

        let computed = ConsumptionRateCalculator.compute(current: [snapshot])
        let rate = computed.first?.quotaWindows?.first?.consumptionRate
        XCTAssertNil(rate)
    }

    func testConsumptionRateNilWhenNoResetAt() {
        ConsumptionRateCalculator.resetHistoryForTesting()
        defer { ConsumptionRateCalculator.resetHistoryForTesting() }

        let snapshot = BalanceSnapshot(
            provider: .codex,
            fetchedAt: Date(),
            isAvailable: true,
            quotaWindows: [
                BalanceQuotaWindow(
                    label: "窗口",
                    usedRatio: 0.5,
                    remainingRatio: 0.5,
                    resetAt: nil,
                    windowSeconds: 3_600
                )
            ]
        )

        let computed = ConsumptionRateCalculator.compute(current: [snapshot])
        let rate = computed.first?.quotaWindows?.first?.consumptionRate
        XCTAssertNil(rate)
    }

    func testConsumptionRateWindowResetClearsHistory() {
        ConsumptionRateCalculator.resetHistoryForTesting()
        defer { ConsumptionRateCalculator.resetHistoryForTesting() }

        let oldReset = Date().addingTimeInterval(3_600)
        let oldSnapshot = BalanceSnapshot(
            provider: .opencodeGo,
            fetchedAt: Date().addingTimeInterval(-1_200),
            isAvailable: true,
            quotaWindows: [
                BalanceQuotaWindow(
                    label: "5小时",
                    usedRatio: 0.30,
                    remainingRatio: 0.70,
                    resetAt: oldReset,
                    windowSeconds: 3_600
                )
            ]
        )
        ConsumptionRateCalculator.store([oldSnapshot])

        let newReset = oldReset.addingTimeInterval(3_600)
        let newWindowStart = newReset.addingTimeInterval(-3_600)
        let newSnapshot = BalanceSnapshot(
            provider: .opencodeGo,
            fetchedAt: newWindowStart.addingTimeInterval(900),
            isAvailable: true,
            quotaWindows: [
                BalanceQuotaWindow(
                    label: "5小时",
                    usedRatio: 0.05,
                    remainingRatio: 0.95,
                    resetAt: newReset,
                    windowSeconds: 3_600
                )
            ]
        )

        let computed = ConsumptionRateCalculator.compute(current: [newSnapshot])
        let rate = computed.first?.quotaWindows?.first?.consumptionRate
        XCTAssertNotNil(rate)
        // After reset, old samples have different resetAt → filtered out; only current point → fallback confidence 0.2
        XCTAssertEqual(rate?.confidence ?? 0, 0.2, accuracy: 0.001)
    }

    func testConsumptionRateDebounceMinInterval() {
        ConsumptionRateCalculator.resetHistoryForTesting()
        defer { ConsumptionRateCalculator.resetHistoryForTesting() }

        let now = Date()
        let resetAt = now.addingTimeInterval(3_600)
        let snapshot1 = BalanceSnapshot(
            provider: .opencodeGo,
            fetchedAt: now,
            isAvailable: true,
            quotaWindows: [
                BalanceQuotaWindow(label: "5小时", usedRatio: 0.10, remainingRatio: 0.90, resetAt: resetAt, windowSeconds: 3_600)
            ]
        )
        ConsumptionRateCalculator.store([snapshot1])

        let snapshot2 = BalanceSnapshot(
            provider: .opencodeGo,
            fetchedAt: now.addingTimeInterval(300),
            isAvailable: true,
            quotaWindows: [
                BalanceQuotaWindow(label: "5小时", usedRatio: 0.15, remainingRatio: 0.85, resetAt: resetAt, windowSeconds: 3_600)
            ]
        )
        ConsumptionRateCalculator.store([snapshot2])

        // The second store within 10 minutes should be debounced — only 1 sample in history
        let computed = ConsumptionRateCalculator.compute(current: [snapshot2])
        let rate = computed.first?.quotaWindows?.first?.consumptionRate
        XCTAssertNotNil(rate)
        // 1 stored sample + current snapshot = 2 pairs → confidence 0.4
        XCTAssertEqual(rate?.confidence ?? 0, 0.4, accuracy: 0.001)
    }

    func testConsumptionRateNilForShortHighConsumptionWindow() {
        ConsumptionRateCalculator.resetHistoryForTesting()
        defer { ConsumptionRateCalculator.resetHistoryForTesting() }

        let windowStart = Date(timeIntervalSince1970: 1_700_000_000)
        let resetAt = windowStart.addingTimeInterval(3_600)
        let snapshot = BalanceSnapshot(
            provider: .opencodeGo,
            fetchedAt: windowStart.addingTimeInterval(10),
            isAvailable: true,
            quotaWindows: [
                BalanceQuotaWindow(label: "5小时", usedRatio: 0.50, remainingRatio: 0.50, resetAt: resetAt, windowSeconds: 3_600)
            ]
        )

        let computed = ConsumptionRateCalculator.compute(current: [snapshot])
        let rate = computed.first?.quotaWindows?.first?.consumptionRate

        XCTAssertNil(rate)
    }

    func testConsumptionRateCapsFallbackAtMaxPerHour() {
        ConsumptionRateCalculator.resetHistoryForTesting()
        defer { ConsumptionRateCalculator.resetHistoryForTesting() }

        let windowStart = Date(timeIntervalSince1970: 1_700_000_000)
        let resetAt = windowStart.addingTimeInterval(3_600)
        let snapshot = BalanceSnapshot(
            provider: .opencodeGo,
            fetchedAt: windowStart.addingTimeInterval(300),
            isAvailable: true,
            quotaWindows: [
                BalanceQuotaWindow(label: "5小时", usedRatio: 0.50, remainingRatio: 0.50, resetAt: resetAt, windowSeconds: 3_600)
            ]
        )

        let computed = ConsumptionRateCalculator.compute(current: [snapshot])
        let rate = computed.first?.quotaWindows?.first?.consumptionRate

        XCTAssertNotNil(rate)
        XCTAssertEqual(rate?.perHour ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(rate?.perDay ?? 0, 4_800, accuracy: 0.001)
    }

    func testConsumptionRateCapsRegressionAtMaxPerHour() {
        ConsumptionRateCalculator.resetHistoryForTesting()
        defer { ConsumptionRateCalculator.resetHistoryForTesting() }

        let windowStart = Date(timeIntervalSince1970: 1_700_000_000)
        let resetAt = windowStart.addingTimeInterval(3_600)
        let firstSnapshot = BalanceSnapshot(
            provider: .opencodeGo,
            fetchedAt: windowStart.addingTimeInterval(600),
            isAvailable: true,
            quotaWindows: [
                BalanceQuotaWindow(label: "5小时", usedRatio: 0.10, remainingRatio: 0.90, resetAt: resetAt, windowSeconds: 3_600)
            ]
        )
        ConsumptionRateCalculator.store([firstSnapshot])

        let secondSnapshot = BalanceSnapshot(
            provider: .opencodeGo,
            fetchedAt: windowStart.addingTimeInterval(1_200),
            isAvailable: true,
            quotaWindows: [
                BalanceQuotaWindow(label: "5小时", usedRatio: 0.90, remainingRatio: 0.10, resetAt: resetAt, windowSeconds: 3_600)
            ]
        )

        let computed = ConsumptionRateCalculator.compute(current: [secondSnapshot])
        let rate = computed.first?.quotaWindows?.first?.consumptionRate

        XCTAssertNotNil(rate)
        XCTAssertEqual(rate?.perHour ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(rate?.perDay ?? 0, 4_800, accuracy: 0.001)
    }

    func testBalanceModelsDecodeOldFormat() throws {
        let oldJSON = """
        {"provider":"opencode_go","fetchedAt":1700000000,"isAvailable":true}
        """
        let data = Data(oldJSON.utf8)
        let snapshot = try JSONDecoder().decode(BalanceSnapshot.self, from: data)
        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertNil(snapshot.errorRecoveryHint)
        XCTAssertFalse(snapshot.errorRequiresReimport)
    }

    func testComputePreservesAllSnapshotFields() {
        ConsumptionRateCalculator.resetHistoryForTesting()
        defer { ConsumptionRateCalculator.resetHistoryForTesting() }

        let original = BalanceSnapshot(
            provider: .ollama,
            fetchedAt: Date(),
            isAvailable: true,
            remainingCredits: 100,
            totalCredits: 200,
            usedCredits: 50,
            usagePercent: 0.5,
            planType: "pro",
            primaryWindowLabel: "5h",
            primaryWindowUsagePercent: 0.4,
            primaryWindowResetAt: Date().addingTimeInterval(3600),
            secondaryWindowLabel: "7d",
            secondaryWindowUsagePercent: 0.6,
            secondaryWindowResetAt: Date().addingTimeInterval(86400),
            totalCostUSD: 42.5,
            avgCostPerDayUSD: 1.5,
            quotaWindows: [
                BalanceQuotaWindow(label: "5h", usedRatio: 0.4, remainingRatio: 0.6, resetAt: Date().addingTimeInterval(3600), windowSeconds: 18000)
            ],
            valueEntries: [BalanceValueEntry(label: "余额", currencyCode: "CNY", amount: 100)]
        )

        let computed = ConsumptionRateCalculator.compute(current: [original]).first!

        XCTAssertEqual(computed.provider, original.provider)
        XCTAssertEqual(computed.fetchedAt, original.fetchedAt)
        XCTAssertEqual(computed.isAvailable, original.isAvailable)
        XCTAssertEqual(computed.remainingCredits, original.remainingCredits)
        XCTAssertEqual(computed.totalCredits, original.totalCredits)
        XCTAssertEqual(computed.usedCredits, original.usedCredits)
        XCTAssertEqual(computed.usagePercent, original.usagePercent)
        XCTAssertEqual(computed.planType, original.planType)
        XCTAssertEqual(computed.primaryWindowLabel, original.primaryWindowLabel)
        XCTAssertEqual(computed.primaryWindowUsagePercent, original.primaryWindowUsagePercent)
        XCTAssertEqual(computed.secondaryWindowLabel, original.secondaryWindowLabel)
        XCTAssertEqual(computed.secondaryWindowUsagePercent, original.secondaryWindowUsagePercent)
        XCTAssertEqual(computed.totalCostUSD, original.totalCostUSD)
        XCTAssertEqual(computed.avgCostPerDayUSD, original.avgCostPerDayUSD)
        XCTAssertEqual(computed.valueEntries?.count, original.valueEntries?.count)
    }

    // MARK: - BalanceManager testSnapshot with mock checker

    @MainActor
    func testBalanceManagerInitialConfigurationBuildsExpectedCheckers() {
        let manager = BalanceManager(configuration: BalanceConfiguration(
            enabledBalanceProviders: [.deepseek, .codex],
            allowEnvironmentCredentials: true
        ))

        XCTAssertEqual(manager.activeProviderKinds, [.codex, .deepseek])
        XCTAssertTrue(manager.configuration.allowEnvironmentCredentials)
    }

    @MainActor
    func testBalanceManagerUpdateConfigurationRebuildsCheckers() {
        let manager = BalanceManager()

        manager.updateConfiguration(BalanceConfiguration(
            enabledBalanceProviders: [.deepseek],
            allowEnvironmentCredentials: true
        ))

        XCTAssertEqual(manager.activeProviderKinds, [.deepseek])
        XCTAssertTrue(manager.configuration.allowEnvironmentCredentials)
    }

    @MainActor func testTestSnapshotWithMockChecker() async {
        let expectedSnapshot = BalanceSnapshot(
            provider: .opencodeGo,
            fetchedAt: Date(),
            isAvailable: true,
            usagePercent: 0.42,
            primaryWindowLabel: "5小时",
            primaryWindowUsagePercent: 0.42
        )

        let mockChecker = MockBalanceChecker(
            providerKind: .opencodeGo,
            snapshot: expectedSnapshot
        )

        let manager = BalanceManager()
        let snapshot = await manager.testSnapshot(for: mockChecker, authToken: "test-api-key")

        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.usagePercent, 0.42)
        XCTAssertEqual(snapshot.primaryWindowLabel, "5小时")
        XCTAssertEqual(snapshot.primaryWindowUsagePercent, 0.42)
    }

    @MainActor func testTestSnapshotWithMockFailingChecker() async {
        let mockChecker = MockBalanceChecker(
            providerKind: .opencodeGo,
            errorMessage: "mock fetch failure"
        )

        let manager = BalanceManager()
        let snapshot = await manager.testSnapshot(for: mockChecker, authToken: "test-key")

        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertEqual(snapshot.errorMessage, "mock fetch failure")
    }

    @MainActor func testTestSnapshotBypassesBackoffAndConcurrencyGuard() async {
        let expectedSnapshot = BalanceSnapshot(
            provider: .codex,
            fetchedAt: Date(),
            isAvailable: true,
            remainingCredits: 100
        )

        let mockChecker = MockBalanceChecker(
            providerKind: .codex,
            snapshot: expectedSnapshot
        )

        let manager = BalanceManager()
        // Call twice rapidly — testSnapshot should not be blocked
        let snap1 = await manager.testSnapshot(for: mockChecker, authToken: "k1")
        let snap2 = await manager.testSnapshot(for: mockChecker, authToken: "k2")

        XCTAssertTrue(snap1.isAvailable)
        XCTAssertTrue(snap2.isAvailable)
        XCTAssertEqual(snap1.remainingCredits, 100)
        XCTAssertEqual(snap2.remainingCredits, 100)
    }

    @MainActor func testTestSnapshotPassesAuthTokenToChecker() async {
        // This mock captures the authToken it receives
        let mockChecker = TokenCapturingMockChecker(providerKind: .opencodeGo)

        let manager = BalanceManager()
        _ = await manager.testSnapshot(for: mockChecker, authToken: "secret-token-42")

        XCTAssertEqual(mockChecker.capturedAuthToken, "secret-token-42")
    }

    // MARK: - OpenCodeGoDashboardFetcher parseWindows (SolidJS SSR)

    func testParseWindowsAllThreeSolidJS() {
        let html = """
        <html><body>
        <script>rollingUsage:$R[42]={usagePercent:65,resetInSec:2520};</script>
        <script>weeklyUsage:$R[43]={usagePercent:30,resetInSec:259200};</script>
        <script>monthlyUsage:$R[44]={usagePercent:12,resetInSec:1728000};</script>
        </body></html>
        """

        let usage = OpenCodeGoDashboardFetcher.parseWindows(from: html)
        XCTAssertNotNil(usage)
        XCTAssertEqual(usage?.rolling?.usagePercent, 65)
        XCTAssertEqual(usage?.rolling?.resetInSec, 2520)
        XCTAssertEqual(usage?.weekly?.usagePercent, 30)
        XCTAssertEqual(usage?.weekly?.resetInSec, 259200)
        XCTAssertEqual(usage?.monthly?.usagePercent, 12)
        XCTAssertEqual(usage?.monthly?.resetInSec, 1728000)
    }

    func testParseWindowsFieldOrderSwapped() {
        let html = """
        <script>rollingUsage:$R[42]={resetInSec:3600,usagePercent:80};</script>
        """

        let usage = OpenCodeGoDashboardFetcher.parseWindows(from: html)
        XCTAssertNotNil(usage)
        XCTAssertEqual(usage?.rolling?.usagePercent, 80)
        XCTAssertEqual(usage?.rolling?.resetInSec, 3600)
        XCTAssertNil(usage?.weekly)
        XCTAssertNil(usage?.monthly)
    }

    func testParseWindowsPartialWindowsAvailable() {
        let html = """
        <script>weeklyUsage:$R[43]={usagePercent:55,resetInSec:86400};</script>
        """

        let usage = OpenCodeGoDashboardFetcher.parseWindows(from: html)
        XCTAssertNotNil(usage)
        XCTAssertNil(usage?.rolling)
        XCTAssertEqual(usage?.weekly?.usagePercent, 55)
        XCTAssertEqual(usage?.weekly?.resetInSec, 86400)
        XCTAssertNil(usage?.monthly)
    }

    func testParseWindowsOldFormatReturnsNil() {
        let html = """
        <script>self.__next_f.push([1,"{\\"rollingUsage\\":{\\"usagePercent\\":65,\\"resetInSec\\":2520}}"])</script>
        """

        let usage = OpenCodeGoDashboardFetcher.parseWindows(from: html)
        XCTAssertNil(usage)
    }

    func testParseWindowsDecimalUsagePercent() {
        let html = """
        <script>monthlyUsage:$R[44]={usagePercent:12.5,resetInSec:1728000};</script>
        """

        let usage = OpenCodeGoDashboardFetcher.parseWindows(from: html)
        XCTAssertNotNil(usage)
        XCTAssertEqual(usage?.monthly?.usagePercent, 12.5)
        XCTAssertEqual(usage?.monthly?.resetInSec, 1728000)
    }

    // MARK: - BrowserCookieExtractor

    func testExtractWorkspaceIDFromHistoryURL() {
        let url = "https://opencode.ai/workspace/wrk_01ABCDEF0123456789/go"
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opencode_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("History")
        do {
            var db: OpaquePointer?
            guard sqlite3_open(dbURL.path, &db) == SQLITE_OK, let db else { XCTFail("cannot open db"); return }
            sqlite3_exec(db, "CREATE TABLE urls (url TEXT, last_visit_time INTEGER)", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO urls VALUES ('\(url)', 1)", nil, nil, nil)
            sqlite3_exec(db, "PRAGMA journal_mode=DELETE", nil, nil, nil)
            sqlite3_close(db)
        }

        let result = BrowserCookieExtractor.extractWorkspaceID(historyURL: dbURL)
        XCTAssertEqual(result, "wrk_01ABCDEF0123456789")
    }

    func testExtractWorkspaceIDNoMatchReturnsNil() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opencode_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("History")
        do {
            var db: OpaquePointer?
            guard sqlite3_open(dbURL.path, &db) == SQLITE_OK, let db else { XCTFail("cannot open db"); return }
            sqlite3_exec(db, "CREATE TABLE urls (url TEXT, last_visit_time INTEGER)", nil, nil, nil)
            sqlite3_exec(db, "INSERT INTO urls VALUES ('https://github.com/example', 1)", nil, nil, nil)
            sqlite3_close(db)
        }

        let result = BrowserCookieExtractor.extractWorkspaceID(historyURL: dbURL)
        XCTAssertNil(result)
    }

    func testPBKDF2DerivedKeyCorrectLength() {
        let salt = Array("saltysalt".utf8)
        var dk = [UInt8](repeating: 0, count: 16)
        let pw = "test_password"
        let result = pw.withCString { ptr in
            cc_pbkdf2_sha1(ptr, strlen(ptr), salt, salt.count, 1003, &dk, 16)
        }
        XCTAssertEqual(result, 0)
        XCTAssertEqual(dk.count, 16)
    }

    func testBrowserKindOrderEdgeFirst() {
        let browsers = BrowserKind.allCases
        XCTAssertEqual(browsers.first, .edge)
        XCTAssertEqual(browsers.count, 4)
    }

    // MARK: - Unified billing model

    func testBillingOverridesCoversAllFiveProvidersWhenSubscribed() {
        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "opencode-go", isSubscribed: true),
            for: .opencode
        )
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "chatgpt-plus", isSubscribed: true),
            for: .codex
        )
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "minimax-plus-speed-monthly", isSubscribed: true),
            for: .minimax
        )
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "mimo-current-default", isSubscribed: true),
            for: .xiaomiMimo
        )
        // DeepSeek has no fixed subscription; toggle is disabled.
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "deepseek-api-paygo", isSubscribed: false),
            for: .deepseek
        )

        let overrides = prefs.billingOverridesByProviderKey()
        XCTAssertEqual(overrides["opencode-go"], 10)
        XCTAssertEqual(overrides["openai"], 20)
        XCTAssertGreaterThan(overrides["minimax-cn-coding-plan"] ?? 0, 0)
        XCTAssertGreaterThan(overrides["xiaomi-token-plan-cn"] ?? 0, 0)
        XCTAssertNil(overrides["deepseek-api-cn"], "DeepSeek has no subscription preset")
    }

    func testBillingOverridesExcludesUnsubscribedAndNormalizesUsageBasedSubscriptions() {
        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "opencode-go", isSubscribed: true),
            for: .opencode
        )
        // Codex: subscribed but usage-based gets normalized to the default fixed subscription.
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "chatgpt-business-codex-paygo", isSubscribed: true),
            for: .codex
        )
        // MiniMax: not subscribed
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "minimax-plus-speed-monthly", isSubscribed: false),
            for: .minimax
        )

        let overrides = prefs.billingOverridesByProviderKey()
        XCTAssertEqual(overrides["opencode-go"], 10)
        XCTAssertEqual(overrides["openai"], 20)
        XCTAssertNil(overrides["minimax-cn-coding-plan"])
    }

    func testCombinedMonthlyCostAllSubscribed() {
        let payload = makeTestPayload(provider: "opencode-go", rawCost: 0.01)
        var prefs = AppPreferences()
        for provider in BillingProvider.allCases {
            let presetID = BillingPlanCatalog.defaultSelection(for: provider).presetID
            // DeepSeek has no subscription preset; its defaultSelection is isSubscribed=false
            let isSubscribed = provider != .deepseek
            prefs.setBillingSelection(
                BillingPlanSelection(presetID: presetID, isSubscribed: isSubscribed),
                for: provider
            )
        }

        let total = prefs.combinedMonthlyCost(payload: payload)
        let expected = (prefs.resolvedBillingPlan(for: .opencode).monthlyUSD ?? 0) +
                       (prefs.resolvedBillingPlan(for: .codex).monthlyUSD ?? 0) +
                       (prefs.resolvedBillingPlan(for: .minimax).monthlyUSD ?? 0) +
                       (prefs.resolvedBillingPlan(for: .xiaomiMimo).monthlyUSD ?? 0) +
                       (prefs.resolvedBillingPlan(for: .deepseek).monthlyUSD ?? 0)
        guard let actual = total else { XCTFail("expected non-nil total"); return }
        XCTAssertEqual(actual, expected, accuracy: 0.01)
    }

    func testCombinedMonthlyCostAllUnsubscribedIsNil() {
        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 0, totalActualTokens: 0,
                totalCacheReadTokens: 0, totalCacheWriteTokens: 0, totalCacheTokens: 0,
                totalCost: 0, totalMessages: 0, activeDays: 0,
                dateRange: .init(start: nil, end: nil),
                updatedAt: "2026-05-15T12:00:00Z"
            ),
            dailyTotals: [:], modelTotals: [:], providerCosts: [:], providerTotals: [:],
            rawData: []
        )
        var prefs = AppPreferences()
        for provider in BillingProvider.allCases {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }
        XCTAssertNil(prefs.combinedMonthlyCost(payload: payload))
    }

    func testCombinedMonthlyCostAllUnsubscribedReturnsAPIUsage() {
        let payload = makeTestPayload(provider: "opencode-go", rawCost: 5)
        var prefs = AppPreferences()
        for provider in BillingProvider.allCases {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }
        // All fixed subs disabled but payload has rawCost → API usage cost returned
        guard let cost = prefs.combinedMonthlyCost(payload: payload) else { XCTFail("expected non-nil cost"); return }
        XCTAssertGreaterThan(cost, 0)
    }

    func testCombinedMonthlyCostPartialSubscribed() {
        let payload = makeTestPayload(provider: "opencode-go", rawCost: 5)
        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "opencode-go", isSubscribed: true),
            for: .opencode
        )
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "chatgpt-plus", isSubscribed: true),
            for: .codex
        )
        // Others not subscribed
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "minimax-plus-speed-monthly", isSubscribed: false),
            for: .minimax
        )
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "mimo-current-default", isSubscribed: false),
            for: .xiaomiMimo
        )
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "deepseek-api-paygo", isSubscribed: false),
            for: .deepseek
        )

        guard let total = prefs.combinedMonthlyCost(payload: payload) else { XCTFail("expected non-nil total"); return }
        XCTAssertEqual(total, 30, accuracy: 0.01)
    }

    func testNonCodexMonthlyCostSubtractsCodexFixedSubscription() {
        let payload = makeTestPayload(provider: "deepseek", rawCost: 5)
        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "opencode-go", isSubscribed: true),
            for: .opencode
        )
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "chatgpt-plus", isSubscribed: true),
            for: .codex
        )
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "minimax-plus-speed-monthly", isSubscribed: false),
            for: .minimax
        )
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "mimo-current-default", isSubscribed: false),
            for: .xiaomiMimo
        )
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "deepseek-api-paygo", isSubscribed: false),
            for: .deepseek
        )

        guard let combined = prefs.combinedMonthlyCost(payload: payload) else { XCTFail("expected non-nil total"); return }
        guard let nonCodex = prefs.nonCodexMonthlyCost(payload: payload) else { XCTFail("expected non-nil non-Codex cost"); return }
        XCTAssertEqual(combined, 35, accuracy: 0.01)
        XCTAssertEqual(nonCodex, 15, accuracy: 0.01)
    }

    func testCustomMonthlyCostIsIncluded() {
        let payload = makeTestPayload(provider: "opencode-go", rawCost: 0.01)
        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(mode: .customMonthlyUSD, presetID: "opencode-go", customMonthlyUSD: 25, isSubscribed: true),
            for: .opencode
        )
        // Disable all other providers
        for provider in BillingProvider.allCases where provider != .opencode {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }
        guard let total = prefs.combinedMonthlyCost(payload: payload) else { XCTFail("expected non-nil total"); return }
        XCTAssertEqual(total, 25, accuracy: 0.01)
    }

    func testTokenHeatmapBuilderMergesSourcesAndSortsCellsChronologically() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let referenceDate = try XCTUnwrap(formatter.date(from: "2026-06-04"))

        let data = TokenHeatmapBuilder.build(
            fromOpenCodeDaily: [
                "2026-06-02": 10,
                "2026-06-03": 20
            ],
            codexDaily: [
                "2026-06-03": 5,
                "2026-06-05": 99
            ],
            referenceDate: referenceDate
        )

        XCTAssertEqual(data.rows.count, 7)
        XCTAssertTrue(data.rows.allSatisfy { $0.count == 52 })
        XCTAssertEqual(data.allCells.map(\.date), data.allCells.map(\.date).sorted())
        XCTAssertEqual(data.allCells.last?.dateString, "2026-06-04")
        XCTAssertFalse(data.allCells.contains { $0.dateString == "2026-06-05" })

        let mergedCell = try XCTUnwrap(data.allCells.first { $0.dateString == "2026-06-03" })
        XCTAssertEqual(mergedCell.tokenCount, 25)
    }

    // MARK: - DeepSeek V4 pricing

    func testDeepSeekV4FlashPricing() {
        var prefs = AppPreferences()
        for provider in BillingProvider.allCases {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }
        let payload = makeSingleModelPayload(
            model: "deepseek-chat",
            provider: "deepseek",
            input: 1_000_000,
            output: 1_000_000
        )
        XCTAssertEqual(prefs.combinedMonthlyCost(payload: payload) ?? 0, 0.42, accuracy: 0.0001)
    }

    func testDeepSeekV4ProPricing() {
        var prefs = AppPreferences()
        for provider in BillingProvider.allCases {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }
        let payload = makeSingleModelPayload(
            model: "deepseek-reasoner",
            provider: "deepseek",
            input: 1_000_000,
            output: 1_000_000
        )
        XCTAssertEqual(prefs.combinedMonthlyCost(payload: payload) ?? 0, 1.305, accuracy: 0.0001)
    }

    func testDeepSeekV4FlashCacheReadPricing() {
        var prefs = AppPreferences()
        for provider in BillingProvider.allCases {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }
        let payload = makeSingleModelPayload(
            model: "deepseek-chat",
            provider: "deepseek",
            input: 0,
            output: 0,
            cacheRead: 1_000_000
        )
        XCTAssertEqual(prefs.combinedMonthlyCost(payload: payload) ?? 0, 0.0028, accuracy: 0.0001)
    }

    func testDeepSeekV4ProCacheReadPricing() {
        var prefs = AppPreferences()
        for provider in BillingProvider.allCases {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }
        let payload = makeSingleModelPayload(
            model: "deepseek-reasoner",
            provider: "deepseek",
            input: 0,
            output: 0,
            cacheRead: 1_000_000
        )
        XCTAssertEqual(prefs.combinedMonthlyCost(payload: payload) ?? 0, 0.003625, accuracy: 0.0001)
    }

    // MARK: - Codex JSONL discovery probe

    func testCodexJSONLProbeFirstLineExceeds4KB() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex_probe_4k_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("session.jsonl")
        let largeValue = String(repeating: "x", count: 5000)
        let firstLine = "{\"type\":\"session_meta\",\"payload\":{\"id\":\"s1\",\"large\":\"\(largeValue)\"}}\n"
        let secondLine = "{\"type\":\"event_msg\",\"payload\":{\"total_tokens\":100}}\n"
        try (firstLine + secondLine).write(to: fileURL, atomically: true, encoding: .utf8)

        let service = CodexSessionDiscoveryService()
        XCTAssertTrue(service.probeIsValidCodexJSONL(at: fileURL),
                       "Should detect valid JSONL when first meaningful line exceeds 4KB")
    }

    func testCodexJSONLProbeLeadingBlankLines() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex_probe_blanks_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("session.jsonl")
        let content = "\n\n  \n\n{\"type\":\"session_meta\",\"payload\":{\"id\":\"s1\"}}\n"
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let service = CodexSessionDiscoveryService()
        XCTAssertTrue(service.probeIsValidCodexJSONL(at: fileURL),
                       "Should skip leading blank/whitespace-only lines and detect valid JSON")
    }

    func testCodexJSONLProbeInvalidFirstLineThenValid() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex_probe_invalid_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("session.jsonl")
        let content = "not valid json\n{\"type\":\"session_meta\",\"payload\":{\"id\":\"s1\"}}\n"
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let service = CodexSessionDiscoveryService()
        XCTAssertTrue(service.probeIsValidCodexJSONL(at: fileURL),
                       "Should tolerate invalid first line and continue scanning")
    }

    func testCodexJSONLProbeAllInvalidReturnsFalse() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex_probe_all_invalid_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("session.jsonl")
        let content = "not json\n[1,2,3]\n\"just a string\"\n"
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let service = CodexSessionDiscoveryService()
        XCTAssertFalse(service.probeIsValidCodexJSONL(at: fileURL),
                       "Should reject file with no valid JSON dictionary lines")
    }

    func testCodexJSONLProbeSkipsOversizeLineThenValid() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex_probe_oversize_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("session.jsonl")
        let oversizeLine = String(repeating: "x", count: 64)
        let content = "\(oversizeLine)\n{\"t\":1}\n"
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let service = CodexSessionDiscoveryService()
        XCTAssertTrue(
            service.probeIsValidCodexJSONL(at: fileURL, readChunkSize: 16, maxLineSize: 32),
            "Should discard an oversize line without letting the buffer grow unbounded, then continue scanning"
        )
    }

    func testCodexJSONLUnsupportedSchemaForInvalidReadableFile() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex_unsupported_schema_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("session.jsonl")
        try "not valid json at all\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let service = CodexSessionDiscoveryService()
        XCTAssertEqual(
            service.fileStatusMessageKind(for: fileURL, profile: .codex, status: .unsupported),
            .unsupportedSchema
        )
    }

    // MARK: - Helpers

    private func makeTestPayload(provider: String, rawCost: Double) -> DashboardPayload {
        DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 110,
                totalActualTokens: 110,
                totalCacheReadTokens: 0,
                totalCacheWriteTokens: 0,
                totalCacheTokens: 0,
                totalCost: rawCost,
                totalMessages: 1,
                activeDays: 1,
                dateRange: .init(start: "2026-05-15", end: "2026-05-15"),
                updatedAt: "2026-05-15T12:00:00Z"
            ),
            dailyTotals: [:],
            modelTotals: [:],
            providerCosts: [:],
            providerTotals: [:],
            rawData: [
                DashboardPayload.RawRow(
                    date: "2026-05-15",
                    model: "legacy-model",
                    provider: provider,
                    input: 100000,
                    output: 10000,
                    reasoning: 0,
                    cacheRead: 0,
                    cacheWrite: 0,
                    cacheWriteMissingCount: 0,
                    cacheWriteReportedCount: 1,
                    total: 110000,
                    cost: rawCost,
                    msgCount: 1
                )
            ]
        )
    }

    private func makeSingleModelPayload(
        model: String,
        provider: String,
        input: Double,
        output: Double = 0,
        cacheRead: Double = 0,
        cacheWrite: Double = 0
    ) -> DashboardPayload {
        DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: input + output + cacheRead + cacheWrite,
                totalActualTokens: input + output,
                totalCacheReadTokens: cacheRead,
                totalCacheWriteTokens: cacheWrite,
                totalCacheTokens: cacheRead + cacheWrite,
                totalCost: 0,
                totalMessages: 1,
                activeDays: 1,
                dateRange: .init(start: "2026-06-04", end: "2026-06-04"),
                updatedAt: "2026-06-04T12:00:00Z"
            ),
            dailyTotals: [:],
            modelTotals: [:],
            providerCosts: [:],
            providerTotals: [:],
            rawData: [
                DashboardPayload.RawRow(
                    date: "2026-06-04",
                    model: model,
                    provider: provider,
                    input: input,
                    output: output,
                    reasoning: 0,
                    cacheRead: cacheRead,
                    cacheWrite: cacheWrite,
                    cacheWriteMissingCount: 0,
                    cacheWriteReportedCount: 1,
                    total: input + output + cacheRead + cacheWrite,
                    cost: 0,
                    msgCount: 1
                )
            ]
        )
    }

    private func skipIfIsolatedKeychainUnavailable(service: String) throws {
        SecureCredentialStore.shared.saveWorkspaceID("keychain-probe", service: service)
        defer { SecureCredentialStore.shared.deleteWorkspaceID(service: service) }

        guard SecureCredentialStore.shared.getWorkspaceID(service: service) == "keychain-probe" else {
            throw XCTSkip("Keychain round-trip is unavailable in this test environment")
        }
    }
}

// MARK: - Test Helpers

private struct MockBalanceChecker: BalanceChecker {
    let providerKind: BalanceProviderKind
    private let _snapshot: BalanceSnapshot?
    private let _errorMessage: String?

    init(providerKind: BalanceProviderKind, snapshot: BalanceSnapshot) {
        self.providerKind = providerKind
        self._snapshot = snapshot
        self._errorMessage = nil
    }

    init(providerKind: BalanceProviderKind, errorMessage: String) {
        self.providerKind = providerKind
        self._snapshot = nil
        self._errorMessage = errorMessage
    }

    func fetch(authToken: String) async throws -> BalanceSnapshot {
        if let errorMessage = _errorMessage {
            throw NSError(domain: "MockBalanceChecker", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        return _snapshot!
    }
}

private final class TokenCapturingMockChecker: BalanceChecker, @unchecked Sendable {
    let providerKind: BalanceProviderKind
    private(set) var capturedAuthToken: String?

    init(providerKind: BalanceProviderKind) {
        self.providerKind = providerKind
    }

    func fetch(authToken: String) async throws -> BalanceSnapshot {
        capturedAuthToken = authToken
        return BalanceSnapshot(
            provider: providerKind,
            fetchedAt: Date(),
            isAvailable: true
        )
    }
}

// MARK: - Ollama BalanceProvider tests

@MainActor
final class OllamaBalanceProviderTests: XCTestCase {
    func testOllamaProviderKindRoundtrip() throws {
        XCTAssertEqual(BalanceProviderKind.ollama.rawValue, "ollama")
        XCTAssertEqual(BalanceProviderKind.ollama.displayName, "Ollama Cloud")
        XCTAssertEqual(BalanceProviderKind.ollama.sortOrder, 4)
        let encoded = try JSONEncoder().encode(BalanceProviderKind.ollama)
        let decoded = try JSONDecoder().decode(BalanceProviderKind.self, from: encoded)
        XCTAssertEqual(decoded, .ollama)
    }

    func testOllamaBalanceCheckerNoCookieReturnsUnavailable() async {
        let checker = OllamaBalanceChecker()
        do {
            let snapshot = try await checker.fetch(authToken: "")
            XCTAssertFalse(snapshot.isAvailable)
            XCTAssertEqual(snapshot.provider, .ollama)
            XCTAssertNotNil(snapshot.errorMessage)
        } catch {
            XCTFail("Should return unavailable snapshot, not throw: \(error)")
        }
    }

    func testOllamaHTMLRegexAriaLabel() {
        let html = #"<div data-usage-track aria-label="65%">usage</div>"#
        let pct = Self.extractFirstPercent(from: html, pattern: #"data-usage-track[^>]*aria-label="([^"]*%)""#)
        XCTAssertEqual(pct ?? -1, 0.65, accuracy: 0.001)
    }

    func testOllamaHTMLRegexUsageMeterFill() {
        let html = #"<div class="usage-meter__fill" style="width: 80%"></div>"#
        let pct = Self.extractFirstPercent(from: html, pattern: #"usage-meter__fill[^>]*style="[^"]*width:\s*(\d+(?:\.\d+)?)%""#)
        XCTAssertEqual(pct ?? -1, 0.80, accuracy: 0.001)
    }

    func testOllamaHTMLRegexGenericPercent() {
        let html = #"<span>45% used</span>"#
        let pct = Self.extractFirstPercent(from: html, pattern: #"(\d+(?:\.\d+)?)%\s*(?:used|已用)"#)
        XCTAssertEqual(pct ?? -1, 0.45, accuracy: 0.001)
    }

    func testOllamaHTMLRegexNoDataReturnsNil() {
        let html = "<html><body><h1>Welcome to Ollama</h1></body></html>"
        XCTAssertNil(Self.extractFirstPercent(from: html, pattern: #"data-usage-track[^>]*aria-label="([^"]*%)""#))
    }

    func testOllamaRealHTMLSessionAndWeeklyWithUsedSuffix() {
        let html = """
        <html><body>
        <h2 class="text-xl font-medium flex items-center space-x-2">
            <span>Cloud usage</span>
            <span class="text-xs font-normal px-2 py-0.5 rounded-full bg-neutral-100 text-neutral-600 capitalize">pro</span>
        </h2>
        <div data-usage-track="" aria-label="Session usage 51% used"></div>
        <div data-time="2026-07-03T07:00:00Z"></div>
        <div data-usage-track="" aria-label="Weekly usage 57.3% used"></div>
        <div data-time="2026-07-06T00:00:00Z"></div>
        </body></html>
        """
        let snapshot = OllamaBalanceChecker().parseUsageForTesting(from: html)
        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.primaryWindowUsagePercent ?? -1, 0.51, accuracy: 0.001)
        XCTAssertEqual(snapshot.secondaryWindowUsagePercent ?? -1, 0.573, accuracy: 0.001)
        XCTAssertNotNil(snapshot.primaryWindowResetAt)
        XCTAssertNotNil(snapshot.secondaryWindowResetAt)
    }

    func testOllamaRealHTMLPlanTypePro() {
        let html = #"<h2><span>Cloud usage</span><span class="capitalize">pro</span></h2><div aria-label="Session usage 10% used"></div><div data-time="2026-07-03T07:00:00Z"></div>"#
        let snapshot = OllamaBalanceChecker().parseUsageForTesting(from: html)
        XCTAssertEqual(snapshot.planType, "pro")
    }

    func testOllamaRealHTMLPlanTypeFree() {
        let html = #"<h2><span>Cloud usage</span><span class="capitalize">free</span></h2><div aria-label="Session usage 10% used"></div><div data-time="2026-07-03T07:00:00Z"></div>"#
        let snapshot = OllamaBalanceChecker().parseUsageForTesting(from: html)
        XCTAssertEqual(snapshot.planType, "free")
    }

    func testOllamaRealHTMLPlanTypeMax() {
        let html = #"<h2><span>Cloud usage</span><span class="capitalize">max</span></h2><div aria-label="Session usage 10% used"></div><div data-time="2026-07-03T07:00:00Z"></div>"#
        let snapshot = OllamaBalanceChecker().parseUsageForTesting(from: html)
        XCTAssertEqual(snapshot.planType, "max")
    }

    func testOllamaHTMLWithoutUsedSuffix() {
        let html = """
        <div data-usage-track="" aria-label="Session usage 51%"></div>
        <div data-time="2026-07-03T07:00:00Z"></div>
        <div data-usage-track="" aria-label="Weekly usage 57%"></div>
        <div data-time="2026-07-06T00:00:00Z"></div>
        """
        let snapshot = OllamaBalanceChecker().parseUsageForTesting(from: html)
        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.primaryWindowUsagePercent ?? -1, 0.51, accuracy: 0.001)
        XCTAssertEqual(snapshot.secondaryWindowUsagePercent ?? -1, 0.57, accuracy: 0.001)
    }

    func testOllamaRealHTMLQuotaWindowsComplete() {
        let html = """
        <div data-usage-track="" aria-label="Session usage 51% used"></div>
        <div data-time="2026-07-03T07:00:00Z"></div>
        <div data-usage-track="" aria-label="Weekly usage 57.3% used"></div>
        <div data-time="2026-07-06T00:00:00Z"></div>
        """
        let snapshot = OllamaBalanceChecker().parseUsageForTesting(from: html)
        guard let windows = snapshot.quotaWindows, windows.count == 2 else {
            XCTFail("Expected 2 quota windows, got \(snapshot.quotaWindows?.count ?? 0)")
            return
        }
        XCTAssertEqual(windows[0].usedRatio ?? -1, 0.51, accuracy: 0.001)
        XCTAssertEqual(windows[1].usedRatio ?? -1, 0.573, accuracy: 0.001)
        XCTAssertNotNil(windows[0].resetAt)
        XCTAssertNotNil(windows[1].resetAt)
    }

    func testBalanceManagerWithOllamaRebuilds() {
        let config = BalanceConfiguration(enabledBalanceProviders: [.ollama])
        let manager = BalanceManager(configuration: config)
        XCTAssertEqual(manager.activeProviderKinds, [.ollama])
    }

    func testBalanceManagerEmptyProvidersDoesNotIncrementBackoff() async {
        let manager = BalanceManager(configuration: BalanceConfiguration(
            enabledBalanceProviders: []
        ))
        await manager.refresh()
        XCTAssertNil(manager.lastRefreshTime)
    }

    func testUpsertSnapshotReplacesExistingForSameProvider() {
        let manager = BalanceManager()
        let old = BalanceSnapshot(provider: .ollama, fetchedAt: Date(), isAvailable: true, usagePercent: 0.3)
        let new = BalanceSnapshot(provider: .ollama, fetchedAt: Date(), isAvailable: true, usagePercent: 0.8)

        manager.upsertSnapshot(old)
        manager.upsertSnapshot(new)

        let ollamaSnapshots = manager.snapshots.filter { $0.provider == .ollama }
        XCTAssertEqual(ollamaSnapshots.count, 1)
        XCTAssertEqual(ollamaSnapshots.first?.usagePercent, 0.8)
    }

    func testUpsertSnapshotSortsByProviderSortOrder() {
        let manager = BalanceManager()

        manager.upsertSnapshot(BalanceSnapshot(provider: .ollama, fetchedAt: Date(), isAvailable: true))
        manager.upsertSnapshot(BalanceSnapshot(provider: .codex, fetchedAt: Date(), isAvailable: true))
        manager.upsertSnapshot(BalanceSnapshot(provider: .opencodeGo, fetchedAt: Date(), isAvailable: true))

        XCTAssertEqual(manager.snapshots.map(\.provider), [.opencodeGo, .codex, .ollama])
    }

    func testUpsertSnapshotUpdatesLastRefreshTime() {
        let manager = BalanceManager()
        XCTAssertNil(manager.lastRefreshTime)

        manager.upsertSnapshot(BalanceSnapshot(provider: .ollama, fetchedAt: Date(), isAvailable: true))

        XCTAssertNotNil(manager.lastRefreshTime)
    }

    func testUpsertSnapshotWithFailedSnapshotAlsoWrites() {
        let manager = BalanceManager()
        let failed = BalanceSnapshot.unavailable(.ollama, reason: "test error")

        manager.upsertSnapshot(failed)

        XCTAssertEqual(manager.snapshots.count, 1)
        XCTAssertEqual(manager.snapshots.first?.provider, .ollama)
        XCTAssertFalse(manager.snapshots.first?.isAvailable ?? true)
        XCTAssertEqual(manager.snapshots.first?.errorMessage, "test error")
    }

    func testUpsertSnapshotDoesNotAffectRefreshWithEmptyCheckers() async {
        let manager = BalanceManager(configuration: BalanceConfiguration(enabledBalanceProviders: []))

        manager.upsertSnapshot(BalanceSnapshot(provider: .ollama, fetchedAt: Date(), isAvailable: true))
        await manager.refresh()

        XCTAssertEqual(manager.snapshots.map(\.provider), [.ollama])
    }

    private static func extractFirstPercent(from html: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html)
        else { return nil }
        let captured = String(html[range]).replacingOccurrences(of: "%", with: "")
        guard let value = Double(captured), value.isFinite, value >= 0, value <= 100
        else { return nil }
        return value / 100.0
    }

    // MARK: - Ollama Keychain save / get / delete isolation

    func testOllamaCookieRoundTripWithIsolatedService() throws {
        let testService = "com.test.ollama-cookie-rt-\(UUID().uuidString)"
        defer {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: testService
            ]
            SecItemDelete(query as CFDictionary)
        }

        try skipIfIsolatedOllamaKeychainUnavailable(service: testService)

        XCTAssertNil(SecureCredentialStore.shared.getOllamaCookie(service: testService))

        SecureCredentialStore.shared.saveOllamaCookie("ollama-session-val", service: testService)
        XCTAssertEqual(SecureCredentialStore.shared.getOllamaCookie(service: testService), "ollama-session-val")

        SecureCredentialStore.shared.saveOllamaCookie("ollama-session-updated", service: testService)
        XCTAssertEqual(SecureCredentialStore.shared.getOllamaCookie(service: testService), "ollama-session-updated")

        SecureCredentialStore.shared.deleteOllamaCookie(service: testService)
        XCTAssertNil(SecureCredentialStore.shared.getOllamaCookie(service: testService))
    }

    func testOllamaCookieDeleteDoesNotAffectOtherAccounts() throws {
        let testService = "com.test.ollama-isolate-\(UUID().uuidString)"
        defer {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: testService
            ]
            SecItemDelete(query as CFDictionary)
        }

        try skipIfIsolatedOllamaKeychainUnavailable(service: testService)

        SecureCredentialStore.shared.saveOllamaCookie("ollama-only", service: testService)
        SecureCredentialStore.shared.saveWorkspaceID("ws-other", service: testService)

        SecureCredentialStore.shared.deleteOllamaCookie(service: testService)

        XCTAssertNil(SecureCredentialStore.shared.getOllamaCookie(service: testService))
        XCTAssertEqual(SecureCredentialStore.shared.getWorkspaceID(service: testService), "ws-other",
                       "Deleting the Ollama cookie should not affect the workspace ID entry")
    }

    func testOllamaCookieIsolationBetweenServices() throws {
        let serviceA = "com.test.ollama-iso-a-\(UUID().uuidString)"
        let serviceB = "com.test.ollama-iso-b-\(UUID().uuidString)"
        defer {
            for svc in [serviceA, serviceB] {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: svc
                ]
                SecItemDelete(query as CFDictionary)
            }
        }

        try skipIfIsolatedOllamaKeychainUnavailable(service: serviceA)

        SecureCredentialStore.shared.saveOllamaCookie("value-a", service: serviceA)
        SecureCredentialStore.shared.saveOllamaCookie("value-b", service: serviceB)

        XCTAssertEqual(SecureCredentialStore.shared.getOllamaCookie(service: serviceA), "value-a")
        XCTAssertEqual(SecureCredentialStore.shared.getOllamaCookie(service: serviceB), "value-b")

        SecureCredentialStore.shared.deleteOllamaCookie(service: serviceA)
        XCTAssertNil(SecureCredentialStore.shared.getOllamaCookie(service: serviceA))
        XCTAssertEqual(SecureCredentialStore.shared.getOllamaCookie(service: serviceB), "value-b",
                       "Deleting service A should not affect service B")
    }

    // MARK: - AuthTokenProvider: Keychain-backed (no old-file fallback)

    func testAuthTokenProviderReadsOllamaCookieFromKeychain() throws {
        let testService = "com.test.ollama-provider-\(UUID().uuidString)"
        defer {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: testService
            ]
            SecItemDelete(query as CFDictionary)
        }

        try skipIfIsolatedOllamaKeychainUnavailable(service: testService)

        SecureCredentialStore.shared.saveOllamaCookie("auth=secret-ollama-token", service: testService)

        let result = AuthTokenProvider.readOllamaCookie(service: testService)
        XCTAssertEqual(result, "auth=secret-ollama-token", "Should keep the full name=value Cookie header fragment")
    }

    func testAuthTokenProviderReturnsNilWhenKeychainEmpty() throws {
        let testService = "com.test.ollama-empty-\(UUID().uuidString)"
        defer {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: testService
            ]
            SecItemDelete(query as CFDictionary)
        }

        try skipIfIsolatedOllamaKeychainUnavailable(service: testService)

        XCTAssertNil(AuthTokenProvider.readOllamaCookie(service: testService),
                     "Should return nil when no Ollama cookie is stored in Keychain")
    }

    func testAuthTokenProviderReadsRawCookieValue() throws {
        let testService = "com.test.ollama-raw-\(UUID().uuidString)"
        defer {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: testService
            ]
            SecItemDelete(query as CFDictionary)
        }

        try skipIfIsolatedOllamaKeychainUnavailable(service: testService)

        SecureCredentialStore.shared.saveOllamaCookie("raw-cookie-value-42", service: testService)

        let result = AuthTokenProvider.readOllamaCookie(service: testService)
        XCTAssertEqual(result, "auth=raw-cookie-value-42",
                       "A legacy raw cookie value should be normalized to an auth= fragment")
    }

    // MARK: - Cookie header parsing

    func testAuthTokenProviderParsesCookieHeaderPrefix() throws {
        let testService = "com.test.ollama-header-\(UUID().uuidString)"
        defer {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: testService
            ]
            SecItemDelete(query as CFDictionary)
        }

        try skipIfIsolatedOllamaKeychainUnavailable(service: testService)

        SecureCredentialStore.shared.saveOllamaCookie("Cookie: auth=header-value-123", service: testService)

        let result = AuthTokenProvider.readOllamaCookie(service: testService)
        XCTAssertEqual(result, "auth=header-value-123",
                       "Should strip 'Cookie: ' prefix and keep the first name=value fragment")
    }

    func testAuthTokenProviderParsesCookieHeaderWithPath() throws {
        let testService = "com.test.ollama-path-\(UUID().uuidString)"
        defer {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: testService
            ]
            SecItemDelete(query as CFDictionary)
        }

        try skipIfIsolatedOllamaKeychainUnavailable(service: testService)

        SecureCredentialStore.shared.saveOllamaCookie("auth=val123; path=/; domain=ollama.com", service: testService)

        let result = AuthTokenProvider.readOllamaCookie(service: testService)
        XCTAssertEqual(result, "auth=val123", "Should keep auth name and stop at the first semicolon")
    }

    func testAuthTokenProviderReturnsFullCookieHeaderWhenNoAuthParam() throws {
        let testService = "com.test.ollama-noauth-\(UUID().uuidString)"
        defer {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: testService
            ]
            SecItemDelete(query as CFDictionary)
        }

        try skipIfIsolatedOllamaKeychainUnavailable(service: testService)

        SecureCredentialStore.shared.saveOllamaCookie("session=xyz789", service: testService)

        let result = AuthTokenProvider.readOllamaCookie(service: testService)
        XCTAssertEqual(result, "session=xyz789",
                       "A cookie without 'auth=' should be returned as-is")
    }

    func testAuthTokenProviderPreservesMultipleCookiePairs() throws {
        let testService = "com.test.ollama-multi-\(UUID().uuidString)"
        defer {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: testService
            ]
            SecItemDelete(query as CFDictionary)
        }

        try skipIfIsolatedOllamaKeychainUnavailable(service: testService)

        SecureCredentialStore.shared.saveOllamaCookie("auth=xxx; session=yyy", service: testService)

        let result = AuthTokenProvider.readOllamaCookie(service: testService)
        XCTAssertEqual(result, "auth=xxx; session=yyy",
                       "Multiple name=value pairs in a Cookie header should be preserved")
    }

    func testAuthTokenProviderStripsSetCookieAttributes() throws {
        let testService = "com.test.ollama-attrs-\(UUID().uuidString)"
        defer {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: testService
            ]
            SecItemDelete(query as CFDictionary)
        }

        try skipIfIsolatedOllamaKeychainUnavailable(service: testService)

        SecureCredentialStore.shared.saveOllamaCookie("auth=val123; path=/; domain=ollama.com; expires=Wed, 01 Jan 2027 00:00:00 GMT; Secure; HttpOnly; SameSite=Lax", service: testService)

        let result = AuthTokenProvider.readOllamaCookie(service: testService)
        XCTAssertEqual(result, "auth=val123",
                       "Set-Cookie attributes (path, domain, expires, Secure, HttpOnly, SameSite) should be stripped, leaving only name=value pairs")
    }

    func testAuthTokenProviderPreservesMultiplePairsAndStripsAttributes() throws {
        let testService = "com.test.ollama-mixed-\(UUID().uuidString)"
        defer {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: testService
            ]
            SecItemDelete(query as CFDictionary)
        }

        try skipIfIsolatedOllamaKeychainUnavailable(service: testService)

        SecureCredentialStore.shared.saveOllamaCookie("auth=abc; session=def; path=/; max-age=3600", service: testService)

        let result = AuthTokenProvider.readOllamaCookie(service: testService)
        XCTAssertEqual(result, "auth=abc; session=def",
                       "Should preserve multiple cookie pairs while stripping Set-Cookie attributes")
    }

    func testSaveOllamaCookieReturnsTrueOnSuccess() throws {
        let testService = "com.test.ollama-savebool-\(UUID().uuidString)"
        defer {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: testService
            ]
            SecItemDelete(query as CFDictionary)
        }

        try skipIfIsolatedOllamaKeychainUnavailable(service: testService)

        let saved = SecureCredentialStore.shared.saveOllamaCookie("test-cookie-value", service: testService)
        XCTAssertTrue(saved, "saveOllamaCookie should return true on successful Keychain write")
    }

    // MARK: - BrowserCookieExtractor SQLite (ollama.com)

    func testFindOllamaPlaintextCookieValue() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollama_cookie_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("Cookies")
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK, let db else { XCTFail("cannot open db"); return }
        sqlite3_exec(db, "CREATE TABLE cookies (host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB, last_access_utc INTEGER)", nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO cookies VALUES ('ollama.com', 'auth', 'plaintext-auth-val', X'', 100)", nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO cookies VALUES ('www.ollama.com', 'session', 'plaintext-session-val', X'', 99)", nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO cookies VALUES ('example.com', 'auth', 'noise', X'', 98)", nil, nil, nil)
        sqlite3_close(db)

        let result = BrowserCookieExtractor.findOllamaPlaintextCookieValue(dbURL: dbURL)
        XCTAssertEqual(result, "auth=plaintext-auth-val",
                       "Should find the first ollama.com plaintext cookie with non-empty value")
    }

    func testFindOllamaPlaintextCookieValueNoMatch() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollama_cookie_nomatch_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("Cookies")
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK, let db else { XCTFail("cannot open db"); return }
        sqlite3_exec(db, "CREATE TABLE cookies (host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB, last_access_utc INTEGER)", nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO cookies VALUES ('example.com', 'auth', 'some-val', X'', 100)", nil, nil, nil)
        sqlite3_close(db)

        let result = BrowserCookieExtractor.findOllamaPlaintextCookieValue(dbURL: dbURL)
        XCTAssertNil(result, "Should return nil when no ollama.com cookies exist")
    }

    func testFindOllamaPlaintextCookieValueSkipsEmptyValues() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollama_cookie_empty_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("Cookies")
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK, let db else { XCTFail("cannot open db"); return }
        sqlite3_exec(db, "CREATE TABLE cookies (host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB, last_access_utc INTEGER)", nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO cookies VALUES ('ollama.com', 'auth', '', X'', 100)", nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO cookies VALUES ('ollama.com', 'session', 'real-val', X'', 99)", nil, nil, nil)
        sqlite3_close(db)

        let result = BrowserCookieExtractor.findOllamaPlaintextCookieValue(dbURL: dbURL)
        XCTAssertEqual(result, "session=real-val",
                       "Should skip empty values and find the next non-empty cookie")
    }

    // MARK: - Keychain availability helper

    private func skipIfIsolatedOllamaKeychainUnavailable(service: String) throws {
        SecureCredentialStore.shared.saveOllamaCookie("probe-ollama", service: service)
        defer { SecureCredentialStore.shared.deleteOllamaCookie(service: service) }

        guard SecureCredentialStore.shared.getOllamaCookie(service: service) == "probe-ollama" else {
            throw XCTSkip("Ollama Keychain round-trip is unavailable in this test environment")
        }
    }

    // MARK: - Ollama Session/Weekly window parsing

    func testOllamaHTMLParsesSessionAndWeeklyUsage() {
        let html = """
        <div class="usage-section">
            <div data-usage-track aria-label="Session usage 42%"></div>
            <div data-usage-track aria-label="Weekly usage 65%"></div>
        </div>
        <span data-time="2026-07-02T12:00:00Z">Resets in 3h</span>
        <span data-time="2026-07-09T00:00:00Z">Resets in 7d</span>
        """
        let snapshot = Self.parseOllamaHTML(html)
        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.primaryWindowUsagePercent ?? -1, 0.42, accuracy: 0.001)
        XCTAssertEqual(snapshot.secondaryWindowUsagePercent ?? -1, 0.65, accuracy: 0.001)
        XCTAssertEqual(snapshot.usagePercent ?? -1, 0.65, accuracy: 0.001)
    }

    func testOllamaHTMLParsesResetTimestamps() {
        let html = """
        <div aria-label="Session usage 10%"></div>
        <div aria-label="Weekly usage 20%"></div>
        <span data-time="2026-07-02T12:00:00Z">Resets in 3h</span>
        <span data-time="2026-07-09T00:00:00Z">Resets in 7d</span>
        """
        let snapshot = Self.parseOllamaHTML(html)
        let cal = Calendar(identifier: .gregorian)
        guard let reset = snapshot.primaryWindowResetAt else {
            XCTFail("primaryWindowResetAt should not be nil")
            return
        }
        XCTAssertEqual(cal.component(.year, from: reset), 2026)
        XCTAssertEqual(cal.component(.month, from: reset), 7)
        XCTAssertEqual(cal.component(.day, from: reset), 2)
        XCTAssertNotNil(snapshot.secondaryWindowResetAt)
    }

    func testOllamaHTMLSessionOnlyWithoutWeekly() {
        let html = """
        <div aria-label="Session usage 30%"></div>
        <span data-time="2026-07-02T12:00:00Z">Resets in 3h</span>
        """
        let snapshot = Self.parseOllamaHTML(html)
        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.primaryWindowUsagePercent ?? -1, 0.30, accuracy: 0.001)
        XCTAssertNil(snapshot.secondaryWindowUsagePercent)
        XCTAssertEqual(snapshot.usagePercent ?? -1, 0.30, accuracy: 0.001)
        XCTAssertNotNil(snapshot.primaryWindowResetAt)
        XCTAssertNil(snapshot.secondaryWindowResetAt)
    }

    func testOllamaHTMLLegacyFallbackDataUsageTrack() {
        let html = #"<div data-usage-track aria-label="55%">usage</div>"#
        let snapshot = Self.parseOllamaHTML(html)
        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.usagePercent ?? -1, 0.55, accuracy: 0.001)
        XCTAssertNil(snapshot.primaryWindowUsagePercent)
        XCTAssertNil(snapshot.secondaryWindowUsagePercent)
    }

    func testOllamaHTMLLegacyFallbackUsageMeterFill() {
        let html = #"<div class="usage-meter__fill" style="width: 75%"></div>"#
        let snapshot = Self.parseOllamaHTML(html)
        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.usagePercent ?? -1, 0.75, accuracy: 0.001)
    }

    func testOllamaHTMLNoUsageDataReturnsUnavailable() {
        let html = "<html><body><h1>Welcome to Ollama</h1></body></html>"
        let snapshot = Self.parseOllamaHTML(html)
        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertNotNil(snapshot.errorMessage)
    }

    func testOllamaHTMLQuotaWindowsContainSessionAndWeekly() {
        let html = """
        <div aria-label="Session usage 40%"></div>
        <div aria-label="Weekly usage 55%"></div>
        <span data-time="2026-07-02T12:00:00Z"></span>
        <span data-time="2026-07-09T00:00:00Z"></span>
        """
        let snapshot = Self.parseOllamaHTML(html)
        guard let windows = snapshot.quotaWindows else {
            XCTFail("quotaWindows should not be nil")
            return
        }
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].usedRatio ?? -1, 0.40, accuracy: 0.001)
        XCTAssertEqual(windows[1].usedRatio ?? -1, 0.55, accuracy: 0.001)
        XCTAssertNotNil(windows[0].resetAt)
        XCTAssertNotNil(windows[1].resetAt)
        XCTAssertEqual(windows[0].windowSeconds, 18_000)
        XCTAssertEqual(windows[1].windowSeconds, 604_800)
    }

    private static func parseOllamaHTML(_ html: String) -> BalanceSnapshot {
        let checker = OllamaBalanceChecker()
        return checker.parseUsageForTesting(from: html)
    }
}
