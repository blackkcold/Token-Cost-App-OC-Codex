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

    // MARK: - AppPreferences credentialSourceMode tests

    func testAppPreferencesInitDefaultsToAutoBrowser() {
        let prefs = AppPreferences()
        XCTAssertEqual(prefs.credentialSourceMode, .autoBrowser)
    }

    func testAppPreferencesInitRetainsKeychainOnly() {
        let prefs = AppPreferences(credentialSourceMode: .keychainOnly)
        XCTAssertEqual(prefs.credentialSourceMode, .keychainOnly)
    }

    func testAppPreferencesDecodePreservesCredentialSourceMode() throws {
        let data = #"{"language":"zh-Hans","credential_source_mode":"keychainOnly"}"#.data(using: .utf8)!
        let prefs = try JSONDecoder().decode(AppPreferences.self, from: data)
        XCTAssertEqual(prefs.credentialSourceMode, .keychainOnly)
    }

    func testAppPreferencesDecodeMissingCredentialSourceModeDefaultsToAutoBrowser() throws {
        let data = #"{"language":"zh-Hans"}"#.data(using: .utf8)!
        let prefs = try JSONDecoder().decode(AppPreferences.self, from: data)
        XCTAssertEqual(prefs.credentialSourceMode, .autoBrowser)
    }

    func testAppPreferencesEncodeIncludesCredentialSourceMode() throws {
        let prefs = AppPreferences(credentialSourceMode: .keychainOnly)
        let data = try JSONEncoder().encode(prefs)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["credential_source_mode"] as? String, "keychainOnly")
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

    // MARK: - BalanceManager refresh cancellation vs timeout regression

    @MainActor
    func testRefreshCancellationDistinctFromTimeoutWhenProviderThrowsCancellationError() async {
        let successSnapshot = BalanceSnapshot(
            provider: .codex, fetchedAt: Date(), isAvailable: true, remainingCredits: 100
        )

        let normal = MockBalanceChecker(providerKind: .codex, snapshot: successSnapshot)
        let cancelling = CancellingMockChecker(providerKind: .deepseek)

        let mgr = BalanceManager(
            checkers: [normal, cancelling],
            timeoutNanos: 2_000_000_000
        )
        await mgr.refresh()

        let returned = mgr.snapshots
        XCTAssertFalse(mgr.isRefreshing)
        XCTAssertFalse(mgr.lastRefreshDidTimeout)
        let hasCodex = returned.contains { $0.provider == .codex && $0.isAvailable }
        XCTAssertTrue(hasCodex)
        let hasDeepSeek = returned.contains { $0.provider == .deepseek }
        if hasDeepSeek {
            XCTAssertFalse(returned.first { $0.provider == .deepseek }?.isAvailable ?? true)
        }
    }

    @MainActor
    func testRefreshTimeoutDeliversPartialResultsFromFastProviders() async {
        let fastSnapshot = BalanceSnapshot(
            provider: .codex, fetchedAt: Date(), isAvailable: true, remainingCredits: 100
        )
        let normal = MockBalanceChecker(providerKind: .codex, snapshot: fastSnapshot)
        let slow = SleepingMockChecker(providerKind: .deepseek, sleepNanos: 3_000_000_000)

        let mgr = BalanceManager(
            checkers: [normal, slow],
            timeoutNanos: 500_000_000
        )
        await mgr.refresh()

        let returned = mgr.snapshots
        XCTAssertFalse(mgr.isRefreshing)
        XCTAssertTrue(mgr.lastRefreshDidTimeout)
        let hasCodex = returned.contains { $0.provider == .codex && $0.isAvailable }
        XCTAssertTrue(hasCodex)
        let hasDeepSeekAvailable = returned.contains { $0.provider == .deepseek && $0.isAvailable }
        XCTAssertFalse(hasDeepSeekAvailable)
    }

    @MainActor
    func testRefreshFullyCompletedNotClassifiedAsTimeout() async {
        let s1 = BalanceSnapshot(provider: .codex, fetchedAt: Date(), isAvailable: true, remainingCredits: 100)
        let s2 = BalanceSnapshot(provider: .deepseek, fetchedAt: Date(), isAvailable: true, remainingCredits: 50)

        let c1 = MockBalanceChecker(providerKind: .codex, snapshot: s1)
        let c2 = MockBalanceChecker(providerKind: .deepseek, snapshot: s2)

        let mgr = BalanceManager(checkers: [c1, c2], timeoutNanos: 2_000_000_000)
        await mgr.refresh()

        XCTAssertFalse(mgr.isRefreshing)
        XCTAssertFalse(mgr.lastRefreshDidTimeout, "Fully completed refresh must not report timeout")
        XCTAssertEqual(mgr.snapshots.count, 2)
        XCTAssertTrue(mgr.snapshots.allSatisfy(\.isAvailable))
    }

    @MainActor
    func testRefreshSinglePublicationSnapshotsAssignedExactlyOnce() async {
        let s1 = BalanceSnapshot(provider: .codex, fetchedAt: Date(), isAvailable: true, remainingCredits: 42)
        let s2 = BalanceSnapshot(provider: .deepseek, fetchedAt: Date(), isAvailable: true, remainingCredits: 99)
        let s3 = BalanceSnapshot(provider: .opencodeGo, fetchedAt: Date(), isAvailable: true, remainingCredits: 11)

        let c1 = MockBalanceChecker(providerKind: .codex, snapshot: s1)
        let c2 = MockBalanceChecker(providerKind: .deepseek, snapshot: s2)
        let c3 = MockBalanceChecker(providerKind: .opencodeGo, snapshot: s3)

        let mgr = BalanceManager(checkers: [c1, c2, c3], timeoutNanos: 2_000_000_000)
        var snapshotChangeCount = 0

        let sink = mgr.$snapshots.sink { _ in snapshotChangeCount += 1 }
        defer { sink.cancel() }

        await mgr.refresh()

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertLessThanOrEqual(snapshotChangeCount, 2, "Snapshots should change ≤2 times (initial empty + single final assign)")
        XCTAssertEqual(mgr.snapshots.count, 3)
    }

    // MARK: - Stale key pruning regression

    func testConsumptionRateStorePrunesKeysForDisabledProviders() {
        ConsumptionRateCalculator.resetHistoryForTesting()
        defer { ConsumptionRateCalculator.resetHistoryForTesting() }

        let goSnapshot = BalanceSnapshot(
            provider: .opencodeGo,
            fetchedAt: Date(),
            isAvailable: true,
            quotaWindows: [
                BalanceQuotaWindow(label: "5h", usedRatio: 0.1, remainingRatio: 0.9,
                                   resetAt: Date().addingTimeInterval(3600), windowSeconds: 18000)
            ]
        )
        ConsumptionRateCalculator.store([goSnapshot],
                                        activeProviderKinds: [.opencodeGo, .codex])

        let codexSnapshot = BalanceSnapshot(
            provider: .codex,
            fetchedAt: Date(),
            isAvailable: true,
            quotaWindows: [
                BalanceQuotaWindow(label: "7d", usedRatio: 0.2, remainingRatio: 0.8,
                                   resetAt: Date().addingTimeInterval(86400), windowSeconds: 604800)
            ]
        )
        ConsumptionRateCalculator.store([codexSnapshot],
                                        activeProviderKinds: [.opencodeGo, .codex])

        let codexFresh = BalanceSnapshot(
            provider: .codex,
            fetchedAt: Date().addingTimeInterval(700),
            isAvailable: true,
            quotaWindows: [
                BalanceQuotaWindow(label: "7d", usedRatio: 0.3, remainingRatio: 0.7,
                                   resetAt: Date().addingTimeInterval(86400), windowSeconds: 604800)
            ]
        )
        ConsumptionRateCalculator.store([codexFresh],
                                        activeProviderKinds: [.codex])

        let computed = ConsumptionRateCalculator.compute(current: [codexFresh])
        XCTAssertNotNil(computed.first?.quotaWindows?.first?.consumptionRate)

        let goFresh = BalanceSnapshot(
            provider: .opencodeGo,
            fetchedAt: Date().addingTimeInterval(1400),
            isAvailable: true,
            quotaWindows: [
                BalanceQuotaWindow(label: "5h", usedRatio: 0.15, remainingRatio: 0.85,
                                   resetAt: Date().addingTimeInterval(3600), windowSeconds: 18000)
            ]
        )
        ConsumptionRateCalculator.store([goFresh],
                                        activeProviderKinds: [.opencodeGo])
        let goComputed = ConsumptionRateCalculator.compute(current: [goFresh])
        XCTAssertEqual(goComputed.first?.quotaWindows?.first?.consumptionRate?.confidence ?? 0,
                       0.2, accuracy: 0.001)
    }

    func testAmountConsumptionRateStorePrunesKeysForDisabledProviders() {
        AmountConsumptionRateCalculator.resetHistoryForTesting()
        defer { AmountConsumptionRateCalculator.resetHistoryForTesting() }

        let goEntry = BalanceValueEntry(label: "余额", currencyCode: "CNY", amount: 100)
        let goSnapshot = BalanceSnapshot(
            provider: .opencodeGo,
            fetchedAt: Date(),
            isAvailable: true,
            valueEntries: [goEntry]
        )
        AmountConsumptionRateCalculator.store([goSnapshot],
                                              activeProviderKinds: [.opencodeGo, .codex])

        let codexEntry = BalanceValueEntry(label: "Grants", currencyCode: "USD", amount: 50)
        let codexSnapshot = BalanceSnapshot(
            provider: .codex,
            fetchedAt: Date(),
            isAvailable: true,
            valueEntries: [codexEntry]
        )
        AmountConsumptionRateCalculator.store([codexSnapshot],
                                              activeProviderKinds: [.opencodeGo, .codex])

        let codexFresh = BalanceSnapshot(
            provider: .codex,
            fetchedAt: Date().addingTimeInterval(700),
            isAvailable: true,
            valueEntries: [BalanceValueEntry(label: "Grants", currencyCode: "USD", amount: 45)]
        )
        AmountConsumptionRateCalculator.store([codexFresh],
                                              activeProviderKinds: [.codex])

        let computed = AmountConsumptionRateCalculator.compute(current: [codexFresh])
        XCTAssertNotNil(computed.first?.valueEntries?.first?.amountConsumptionRate)

        let goFresh = BalanceSnapshot(
            provider: .opencodeGo,
            fetchedAt: Date().addingTimeInterval(1400),
            isAvailable: true,
            valueEntries: [BalanceValueEntry(label: "余额", currencyCode: "CNY", amount: 95)]
        )
        AmountConsumptionRateCalculator.store([goFresh],
                                              activeProviderKinds: [.opencodeGo])
        let goComputed = AmountConsumptionRateCalculator.compute(current: [goFresh])
        XCTAssertNil(goComputed.first?.valueEntries?.first?.amountConsumptionRate)
    }

    func testConsumptionRateStoreEnforcesGlobalMaxKeyCount() {
        ConsumptionRateCalculator.resetHistoryForTesting()
        defer { ConsumptionRateCalculator.resetHistoryForTesting() }

        let provider = BalanceProviderKind.codex
        let base = Date()
        let manyLabels = (0 ..< 10).map { "window-\($0)" }
        for (i, label) in manyLabels.enumerated() {
            let snapshot = BalanceSnapshot(
                provider: provider,
                fetchedAt: base.addingTimeInterval(TimeInterval(700 * i)),
                isAvailable: true,
                quotaWindows: [
                    BalanceQuotaWindow(label: label, usedRatio: 0.1, remainingRatio: 0.9,
                                       resetAt: base.addingTimeInterval(3600), windowSeconds: 18000)
                ]
            )
            ConsumptionRateCalculator.store([snapshot], activeProviderKinds: [provider])
        }
        let computed = ConsumptionRateCalculator.compute(current: [BalanceSnapshot(
            provider: provider, fetchedAt: base.addingTimeInterval(7000), isAvailable: true,
            quotaWindows: [BalanceQuotaWindow(label: "window-0", usedRatio: 0.2, remainingRatio: 0.8,
                                               resetAt: base.addingTimeInterval(3600), windowSeconds: 18000)]
        )])
        XCTAssertNotNil(computed.first?.quotaWindows?.first?.consumptionRate)
    }

    func testAmountConsumptionRateStoreEnforcesGlobalMaxKeyCount() {
        AmountConsumptionRateCalculator.resetHistoryForTesting()
        defer { AmountConsumptionRateCalculator.resetHistoryForTesting() }

        let provider = BalanceProviderKind.codex
        let base = Date()
        let manyCurrencies = (0 ..< 10).map { "CCY-\($0)" }
        for (i, currency) in manyCurrencies.enumerated() {
            let snapshot = BalanceSnapshot(
                provider: provider,
                fetchedAt: base.addingTimeInterval(TimeInterval(700 * i)),
                isAvailable: true,
                valueEntries: [BalanceValueEntry(label: "余额", currencyCode: currency, amount: Double(100 - i))]
            )
            AmountConsumptionRateCalculator.store([snapshot], activeProviderKinds: [provider])
        }
        let computed = AmountConsumptionRateCalculator.compute(current: [BalanceSnapshot(
            provider: provider, fetchedAt: base.addingTimeInterval(7000), isAvailable: true,
            valueEntries: [BalanceValueEntry(label: "余额", currencyCode: "CCY-0", amount: 90)]
        )])
        XCTAssertNotNil(computed.first?.valueEntries?.first?.amountConsumptionRate)
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

    // MARK: - Unified Reporting-Range Cost Model

    func testReportingRangeDerivesInclusiveWholeDayFromRawData() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let payload = makeMultiDatePayload(dates: ["2026-06-01", "2026-06-03", "2026-06-05"])
        let range = try XCTUnwrap(AppPreferences.reportingRange(from: payload))

        let calendar = Calendar.autoupdatingCurrent
        let expectedStart = try XCTUnwrap(formatter.date(from: "2026-06-01"))
        let expectedEnd = try XCTUnwrap(formatter.date(from: "2026-06-05"))
        let expectedEndOfDay = try XCTUnwrap(
            calendar.date(byAdding: DateComponents(day: 1, second: -1),
                          to: calendar.startOfDay(for: expectedEnd))
        )

        XCTAssertEqual(calendar.startOfDay(for: range.start), calendar.startOfDay(for: expectedStart))
        XCTAssertEqual(range.end, expectedEndOfDay)
    }

    func testReportingRangeNilWhenEmptyRawData() {
        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 0, totalActualTokens: 0,
                totalCacheReadTokens: 0, totalCacheWriteTokens: 0, totalCacheTokens: 0,
                totalCost: 0, totalMessages: 0, activeDays: 0,
                dateRange: .init(start: nil, end: nil),
                updatedAt: "2026-06-01T12:00:00Z"
            ),
            dailyTotals: [:], modelTotals: [:], providerCosts: [:], providerTotals: [:],
            rawData: []
        )
        XCTAssertNil(AppPreferences.reportingRange(from: payload))
    }

    func testReportingCostBreakdownAllocatesCycleAmountByOverlapProportion() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        // Cycle: June 1 – July 1 inclusive = 31 days
        let periodStart = try XCTUnwrap(formatter.date(from: "2026-06-01"))
        let periodEnd = try XCTUnwrap(formatter.date(from: "2026-07-01"))
        // Reporting: June 1 – June 16 inclusive day boundaries
        let reportingStart = try XCTUnwrap(formatter.date(from: "2026-06-01"))
        let reportingEnd = try XCTUnwrap(formatter.date(from: "2026-06-16"))

        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "opencode-go", isSubscribed: true,
                periodGranularity: .day,
                periodStart: periodStart, periodEnd: periodEnd,
                hasPeriodTracking: true
            ),
            for: .opencode
        )
        for provider in BillingProvider.allCases where provider != .opencode {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        let payload = makeTestPayload(provider: "unused", rawCost: 0)
        let breakdown = prefs.reportingCostBreakdown(
            payload: payload, reportingStart: reportingStart, reportingEnd: reportingEnd
        )

        XCTAssertTrue(breakdown.hasCost)
        // cycleTotalCost = ($10 / 30.4375) * 31 ≈ $10.1848
        // overlapIncludedDays = 16, cycleIncludedDays = 31
        // cost = $10.1848 * 16 / 31 ≈ $5.2567
        let cycleTotalCost = (10.0 / 30.4375) * 31.0
        let expectedAllocated = cycleTotalCost * 16.0 / 31.0
        XCTAssertEqual(breakdown.totalCost, expectedAllocated, accuracy: 0.01)
        XCTAssertEqual(breakdown.fixedCostByProvider[.opencode] ?? 0, expectedAllocated, accuracy: 0.01)
        XCTAssertTrue(breakdown.uncoveredUsageByProviderKey.isEmpty)
    }

    func testReportingCostBreakdownFallbackNoPeriodDates() {
        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "opencode-go", isSubscribed: true),
            for: .opencode
        )
        for provider in BillingProvider.allCases where provider != .opencode {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        let payload = makeTestPayload(provider: "unused", rawCost: 0)
        let now = Date()
        let breakdown = prefs.reportingCostBreakdown(
            payload: payload,
            reportingStart: Calendar.autoupdatingCurrent.date(byAdding: .day, value: -30, to: now)!,
            reportingEnd: now
        )

        XCTAssertTrue(breakdown.hasCost)
        XCTAssertEqual(breakdown.totalCost, 10, accuracy: 0.01)
        XCTAssertEqual(breakdown.fixedCostByProvider[.opencode], 10)
    }

    func testReportingCostBreakdownIncludesUncoveredUsage() throws {
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

        let payload = makeTestPayload(provider: "deepseek", rawCost: 5)
        let range = try XCTUnwrap(AppPreferences.reportingRange(from: payload))
        let breakdown = prefs.reportingCostBreakdown(
            payload: payload,
            reportingStart: range.start,
            reportingEnd: range.end
        )

        XCTAssertTrue(breakdown.hasCost)
        XCTAssertTrue(breakdown.fixedCostByProvider.isEmpty)
        XCTAssertFalse(breakdown.uncoveredUsageByProviderKey.isEmpty)
        XCTAssertGreaterThan(breakdown.totalCost, 0)
    }

    func testReportingCostBreakdownNoDoubleCounting() {
        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "opencode-go", isSubscribed: true),
            for: .opencode
        )
        for provider in BillingProvider.allCases where provider != .opencode {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        // Payload has API usage matching the subscribed provider key
        let payload = makeTestPayload(provider: "opencode-go", rawCost: 5)
        let now = Date()
        let breakdown = prefs.reportingCostBreakdown(
            payload: payload,
            reportingStart: Calendar.autoupdatingCurrent.date(byAdding: .day, value: -30, to: now)!,
            reportingEnd: now
        )

        XCTAssertTrue(breakdown.hasCost)
        // Total should be exactly the subscription cost, NOT subscription + API
        XCTAssertEqual(breakdown.totalCost, 10, accuracy: 0.01)
        XCTAssertEqual(breakdown.fixedCostByProvider[.opencode], 10)
        // uncoveredUsage should not include opencode-go since it's covered
        let uncoveredKeys = breakdown.uncoveredUsageByProviderKey.keys.map {
            $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        XCTAssertFalse(uncoveredKeys.contains("opencode-go"))
        XCTAssertFalse(uncoveredKeys.contains("opencode"))
    }

    func testReportingCostBreakdownCombinedFixedAndUncovered() throws {
        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "opencode-go", isSubscribed: true),
            for: .opencode
        )
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "deepseek-api-paygo", isSubscribed: false),
            for: .deepseek
        )
        // Other providers unsubscribed to keep test focused
        for provider in BillingProvider.allCases where provider != .opencode && provider != .deepseek {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        // Payload has API usage from deepseek (uncovered) but opencode-go row (covered)
        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 2_000_000, totalActualTokens: 1_000_000,
                totalCacheReadTokens: 0, totalCacheWriteTokens: 0, totalCacheTokens: 0,
                totalCost: 0.14 + 5, totalMessages: 2, activeDays: 1,
                dateRange: .init(start: "2026-06-15", end: "2026-06-15"),
                updatedAt: "2026-06-15T12:00:00Z"
            ),
            dailyTotals: [:], modelTotals: [:], providerCosts: [:], providerTotals: [:],
            rawData: [
                DashboardPayload.RawRow(
                    date: "2026-06-15", model: "minimax-m2.7", provider: "opencode-go",
                    input: 500_000, output: 10_000, reasoning: 0,
                    cacheRead: 0, cacheWrite: 0,
                    cacheWriteMissingCount: 0, cacheWriteReportedCount: 1,
                    total: 510_000, cost: 5, msgCount: 1
                ),
                DashboardPayload.RawRow(
                    date: "2026-06-15", model: "deepseek-chat", provider: "deepseek",
                    input: 1_000_000, output: 0, reasoning: 0,
                    cacheRead: 0, cacheWrite: 0,
                    cacheWriteMissingCount: 0, cacheWriteReportedCount: 0,
                    total: 1_000_000, cost: 0, msgCount: 1
                )
            ]
        )

        let range = try XCTUnwrap(AppPreferences.reportingRange(from: payload))
        let breakdown = prefs.reportingCostBreakdown(
            payload: payload,
            reportingStart: range.start,
            reportingEnd: range.end
        )

        XCTAssertTrue(breakdown.hasCost)
        // fixed: opencode $10 + uncovered: deepseek API ~$0.14
        XCTAssertEqual(breakdown.fixedCostByProvider[.opencode], 10)
        let uncoveredDeepseek = breakdown.uncoveredUsageByProviderKey["deepseek"] ?? 0
        XCTAssertGreaterThan(uncoveredDeepseek, 0)
        let expectedTotal = 10.0 + uncoveredDeepseek
        XCTAssertEqual(breakdown.totalCost, expectedTotal, accuracy: 0.01)
    }

    func testReportingCostBreakdownZeroOverlapReturnsZero() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        // Period: May 1–31, Reporting: June 1–30 (zero overlap)
        let periodStart = try XCTUnwrap(formatter.date(from: "2026-05-01"))
        let periodEnd = try XCTUnwrap(formatter.date(from: "2026-05-31"))
        let reportingStart = try XCTUnwrap(formatter.date(from: "2026-06-01"))
        let reportingEnd = try XCTUnwrap(formatter.date(from: "2026-06-30"))

        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "opencode-go", isSubscribed: true,
                periodStart: periodStart, periodEnd: periodEnd,
                hasPeriodTracking: true
            ),
            for: .opencode
        )
        for provider in BillingProvider.allCases where provider != .opencode {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        let payload = makeTestPayload(provider: "unused", rawCost: 0)
        let breakdown = prefs.reportingCostBreakdown(
            payload: payload, reportingStart: reportingStart, reportingEnd: reportingEnd
        )

        // Zero overlap → cost = 0 (not fallback to monthly)
        XCTAssertFalse(breakdown.hasCost)
        XCTAssertEqual(breakdown.totalCost, 0, accuracy: 0.01)
        XCTAssertNil(breakdown.fixedCostByProvider[.opencode])
    }

    func testCombinedTotalCostUsesReportingRangeWhenPeriodEnabled() {
        let payload = makeTestPayload(provider: "deepseek", rawCost: 0.14)
        var prefs = AppPreferences(periodTotalCostEnabled: true)
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "opencode-go", isSubscribed: true),
            for: .opencode
        )
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "deepseek-api-paygo", isSubscribed: false),
            for: .deepseek
        )
        for provider in BillingProvider.allCases where provider != .opencode && provider != .deepseek {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        guard let total = prefs.combinedTotalCost(payload: payload) else {
            XCTFail("expected non-nil total"); return
        }
        XCTAssertGreaterThan(total, 10, "Canonical breakdown should include uncovered API usage")
        XCTAssertLessThan(total, 20, "Should be close to $10 + small API usage")
    }

    func testCombinedTotalCostUsesReportingRangeWhenLegacyFlagFalse() {
        let payload = makeTestPayload(provider: "deepseek", rawCost: 0.14)
        var prefs = AppPreferences(periodTotalCostEnabled: false)
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "opencode-go", isSubscribed: true),
            for: .opencode
        )
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "deepseek-api-paygo", isSubscribed: false),
            for: .deepseek
        )
        for provider in BillingProvider.allCases where provider != .opencode && provider != .deepseek {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        guard let total = prefs.combinedTotalCost(payload: payload) else {
            XCTFail("expected non-nil total"); return
        }
        // Legacy flag false must NOT suppress canonical reporting — same behavior as flag true
        XCTAssertGreaterThan(total, 10, "Legacy flag false should still use canonical breakdown")
        XCTAssertLessThan(total, 20, "Should be close to $10 + small API usage")
    }

    func testCombinedTotalCostRegressionSameTotalRegardlessOfLegacyFlag() {
        let payload = makeTestPayload(provider: "deepseek", rawCost: 0.14)
        func makePrefs(flag: Bool) -> AppPreferences {
            var prefs = AppPreferences(periodTotalCostEnabled: flag)
            prefs.setBillingSelection(
                BillingPlanSelection(presetID: "opencode-go", isSubscribed: true),
                for: .opencode
            )
            prefs.setBillingSelection(
                BillingPlanSelection(presetID: "deepseek-api-paygo", isSubscribed: false),
                for: .deepseek
            )
            for provider in BillingProvider.allCases where provider != .opencode && provider != .deepseek {
                prefs.setBillingSelection(
                    BillingPlanSelection(
                        presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                        isSubscribed: false
                    ),
                    for: provider
                )
            }
            return prefs
        }
        let prefsTrue = makePrefs(flag: true)
        let prefsFalse = makePrefs(flag: false)

        let totalTrue = prefsTrue.combinedTotalCost(payload: payload)
        let totalFalse = prefsFalse.combinedTotalCost(payload: payload)

        XCTAssertNotNil(totalTrue)
        XCTAssertNotNil(totalFalse)
        XCTAssertEqual(totalTrue, totalFalse,
                       "Same reporting mode must produce identical combined total regardless of legacy flag")
    }

    // MARK: - P1: combinedTotalCost zero-total breakdown must not fall back to monthly

    func testCombinedTotalCostZeroOverlapReturnsZeroNotMonthlyFallback() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        // Subscription period: May 1–31. Reporting range will be derived from payload dates in June.
        let periodStart = try XCTUnwrap(formatter.date(from: "2026-05-01"))
        let periodEnd = try XCTUnwrap(formatter.date(from: "2026-05-31"))

        var prefs = AppPreferences(reportingRangeMode: .allAvailable)
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "opencode-go", isSubscribed: true,
                periodGranularity: .day,
                periodStart: periodStart, periodEnd: periodEnd,
                hasPeriodTracking: true
            ),
            for: .opencode
        )
        for provider in BillingProvider.allCases where provider != .opencode {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        // Payload date in June — outside the May subscription period (zero overlap).
        // No API cost rows, so uncovered usage is also zero.
        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 0, totalActualTokens: 0,
                totalCacheReadTokens: 0, totalCacheWriteTokens: 0, totalCacheTokens: 0,
                totalCost: 0, totalMessages: 0, activeDays: 1,
                dateRange: .init(start: "2026-06-15", end: "2026-06-15"),
                updatedAt: "2026-06-15T12:00:00Z"
            ),
            dailyTotals: [:], modelTotals: [:], providerCosts: [:], providerTotals: [:],
            rawData: [
                DashboardPayload.RawRow(
                    date: "2026-06-15", model: "unused", provider: "unused",
                    input: 0, output: 0, reasoning: 0,
                    cacheRead: 0, cacheWrite: 0,
                    cacheWriteMissingCount: 0, cacheWriteReportedCount: 0,
                    total: 0, cost: 0, msgCount: 1
                )
            ]
        )

        let total = prefs.combinedTotalCost(payload: payload)

        // Before the P1 fix, hasCost=false caused fallback to combinedMonthlyCost ($10).
        // After the fix, a resolved reporting range with zero cost must return 0.
        XCTAssertNotNil(total, "A valid reporting range should produce a result")
        XCTAssertEqual(total ?? -1, 0, accuracy: 0.01,
                       "Zero-overlap zero-usage breakdown must return 0, not fall back to monthly $10")
    }

    // MARK: - Canonical per-provider billing-cycle allocation

    func testProviderIsolationIndependentCycleAllocation() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let reportingStart = try XCTUnwrap(formatter.date(from: "2026-06-01"))
        let reportingEnd = try XCTUnwrap(formatter.date(from: "2026-06-30"))

        var prefs = AppPreferences()
        // OpenCode: June 1–30 (full overlap with reporting)
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "opencode-go", isSubscribed: true,
                periodGranularity: .day,
                periodStart: try XCTUnwrap(formatter.date(from: "2026-06-01")),
                periodEnd: try XCTUnwrap(formatter.date(from: "2026-06-30")),
                hasPeriodTracking: true
            ),
            for: .opencode
        )
        // Codex: May 1–31 (zero overlap)
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "chatgpt-plus", isSubscribed: true,
                periodGranularity: .day,
                periodStart: try XCTUnwrap(formatter.date(from: "2026-05-01")),
                periodEnd: try XCTUnwrap(formatter.date(from: "2026-05-31")),
                hasPeriodTracking: true
            ),
            for: .codex
        )
        // Other providers unsubscribed
        for provider in BillingProvider.allCases where provider != .opencode && provider != .codex {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        let payload = makeTestPayload(provider: "unused", rawCost: 0)
        let breakdown = prefs.reportingCostBreakdown(
            payload: payload, reportingStart: reportingStart, reportingEnd: reportingEnd
        )

        XCTAssertTrue(breakdown.hasCost)
        // OpenCode: 30/30 overlap → full cycle cost
        let openCodeCycleDays = 30.0
        let openCodeCycleCost = (10.0 / 30.4375) * openCodeCycleDays
        XCTAssertEqual(breakdown.fixedCostByProvider[.opencode] ?? 0, openCodeCycleCost, accuracy: 0.01)
        // Codex: 0/31 overlap → cost = 0 (not in fixedCostByProvider)
        XCTAssertNil(breakdown.fixedCostByProvider[.codex])
        // Total = opencode only
        XCTAssertEqual(breakdown.totalCost, openCodeCycleCost, accuracy: 0.01)
    }

    func testInclusiveMonthEndAllocation() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        // Full month cycle: June 1–30 inclusive = 30 days
        let periodStart = try XCTUnwrap(formatter.date(from: "2026-06-01"))
        let periodEnd = try XCTUnwrap(formatter.date(from: "2026-06-30"))
        // Reporting last 10 days: June 21–30 inclusive = 10 days
        let reportingStart = try XCTUnwrap(formatter.date(from: "2026-06-21"))
        let reportingEnd = try XCTUnwrap(formatter.date(from: "2026-06-30"))

        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "opencode-go", isSubscribed: true,
                periodGranularity: .day,
                periodStart: periodStart, periodEnd: periodEnd,
                hasPeriodTracking: true
            ),
            for: .opencode
        )
        for provider in BillingProvider.allCases where provider != .opencode {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        let payload = makeTestPayload(provider: "unused", rawCost: 0)
        let breakdown = prefs.reportingCostBreakdown(
            payload: payload, reportingStart: reportingStart, reportingEnd: reportingEnd
        )

        XCTAssertTrue(breakdown.hasCost)
        // cycleTotal = ($10 / 30.4375) * 30 ≈ $9.856
        // allocation = $9.856 * 10/30 ≈ $3.285
        let cycleTotal = (10.0 / 30.4375) * 30.0
        let expected = cycleTotal * 10.0 / 30.0
        XCTAssertEqual(breakdown.totalCost, expected, accuracy: 0.01)
        XCTAssertEqual(breakdown.fixedCostByProvider[.opencode] ?? 0, expected, accuracy: 0.01)
    }

    func testPartialOverlapAllocationWithinReportingRange() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        // Cycle: June 1–30 (30 days)
        let periodStart = try XCTUnwrap(formatter.date(from: "2026-06-01"))
        let periodEnd = try XCTUnwrap(formatter.date(from: "2026-06-30"))
        // Reporting: June 10–20 (11 days overlap)
        let reportingStart = try XCTUnwrap(formatter.date(from: "2026-06-10"))
        let reportingEnd = try XCTUnwrap(formatter.date(from: "2026-06-20"))

        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "opencode-go", isSubscribed: true,
                periodGranularity: .day,
                periodStart: periodStart, periodEnd: periodEnd,
                hasPeriodTracking: true
            ),
            for: .opencode
        )
        for provider in BillingProvider.allCases where provider != .opencode {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        let payload = makeTestPayload(provider: "unused", rawCost: 0)
        let breakdown = prefs.reportingCostBreakdown(
            payload: payload, reportingStart: reportingStart, reportingEnd: reportingEnd
        )

        XCTAssertTrue(breakdown.hasCost)
        // Overlap: June 10–20 = 11 included days
        // cycleTotal = ($10 / 30.4375) * 30 ≈ $9.856
        // allocation = $9.856 * 11/30 ≈ $3.614
        let cycleTotal = (10.0 / 30.4375) * 30.0
        let expected = cycleTotal * 11.0 / 30.0
        XCTAssertEqual(breakdown.totalCost, expected, accuracy: 0.01)
    }

    func testZeroOverlapProviderContributesZero() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let reportingStart = try XCTUnwrap(formatter.date(from: "2026-06-01"))
        let reportingEnd = try XCTUnwrap(formatter.date(from: "2026-06-30"))

        var prefs = AppPreferences()
        // Two providers with zero-overlap cycles
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "opencode-go", isSubscribed: true,
                periodGranularity: .day,
                periodStart: try XCTUnwrap(formatter.date(from: "2026-04-01")),
                periodEnd: try XCTUnwrap(formatter.date(from: "2026-04-30")),
                hasPeriodTracking: true
            ),
            for: .opencode
        )
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "chatgpt-plus", isSubscribed: true,
                periodGranularity: .day,
                periodStart: try XCTUnwrap(formatter.date(from: "2026-07-01")),
                periodEnd: try XCTUnwrap(formatter.date(from: "2026-07-31")),
                hasPeriodTracking: true
            ),
            for: .codex
        )
        for provider in BillingProvider.allCases where provider != .opencode && provider != .codex {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        let payload = makeTestPayload(provider: "unused", rawCost: 0)
        let breakdown = prefs.reportingCostBreakdown(
            payload: payload, reportingStart: reportingStart, reportingEnd: reportingEnd
        )

        // Both providers have zero overlap → total = 0
        XCTAssertFalse(breakdown.hasCost)
        XCTAssertEqual(breakdown.totalCost, 0, accuracy: 0.01)
        XCTAssertNil(breakdown.fixedCostByProvider[.opencode])
        XCTAssertNil(breakdown.fixedCostByProvider[.codex])
    }

    func testFallbackToMonthlyWhenTrackingDisabled() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        // Period dates set but tracking disabled → fallback to monthly
        let periodStart = try XCTUnwrap(formatter.date(from: "2026-06-01"))
        let periodEnd = try XCTUnwrap(formatter.date(from: "2026-06-30"))
        let reportingStart = try XCTUnwrap(formatter.date(from: "2026-06-01"))
        let reportingEnd = try XCTUnwrap(formatter.date(from: "2026-06-16"))

        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "opencode-go", isSubscribed: true,
                periodGranularity: .day,
                periodStart: periodStart, periodEnd: periodEnd,
                hasPeriodTracking: false
            ),
            for: .opencode
        )
        for provider in BillingProvider.allCases where provider != .opencode {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        let payload = makeTestPayload(provider: "unused", rawCost: 0)
        let breakdown = prefs.reportingCostBreakdown(
            payload: payload, reportingStart: reportingStart, reportingEnd: reportingEnd
        )

        XCTAssertTrue(breakdown.hasCost)
        XCTAssertEqual(breakdown.totalCost, 10, accuracy: 0.01)
        XCTAssertEqual(breakdown.fixedCostByProvider[.opencode], 10)
    }

    func testNoDoubleCountingWithPerProviderTracking() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let periodStart = try XCTUnwrap(formatter.date(from: "2026-06-01"))
        let periodEnd = try XCTUnwrap(formatter.date(from: "2026-06-30"))

        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "opencode-go", isSubscribed: true,
                periodGranularity: .day,
                periodStart: periodStart, periodEnd: periodEnd,
                hasPeriodTracking: true
            ),
            for: .opencode
        )
        for provider in BillingProvider.allCases where provider != .opencode {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        // Payload has opencode-go API usage — should be suppressed (covered by fixed sub)
        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 110, totalActualTokens: 110,
                totalCacheReadTokens: 0, totalCacheWriteTokens: 0, totalCacheTokens: 0,
                totalCost: 5, totalMessages: 1, activeDays: 1,
                dateRange: .init(start: "2026-06-15", end: "2026-06-15"),
                updatedAt: "2026-06-15T12:00:00Z"
            ),
            dailyTotals: [:], modelTotals: [:], providerCosts: [:], providerTotals: [:],
            rawData: [
                DashboardPayload.RawRow(
                    date: "2026-06-15", model: "test-model", provider: "opencode-go",
                    input: 100_000, output: 10_000, reasoning: 0,
                    cacheRead: 0, cacheWrite: 0,
                    cacheWriteMissingCount: 0, cacheWriteReportedCount: 1,
                    total: 110_000, cost: 5, msgCount: 1
                )
            ]
        )
        let range = try XCTUnwrap(AppPreferences.reportingRange(from: payload))

        let breakdown = prefs.reportingCostBreakdown(
            payload: payload,
            reportingStart: range.start,
            reportingEnd: range.end
        )

        XCTAssertTrue(breakdown.hasCost)
        // opencode-go API usage is covered → not in uncoveredUsage
        let uncoveredKeys = breakdown.uncoveredUsageByProviderKey.keys.map {
            $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        XCTAssertFalse(uncoveredKeys.contains("opencode-go"))
        XCTAssertFalse(uncoveredKeys.contains("opencode"))
        // Total = prorated cycle cost only, not + API
        let cycleTotal = (10.0 / 30.4375) * 30.0
        let overlapDays = 1.0  // single-day payload
        let expectedFixed = cycleTotal * overlapDays / 30.0
        XCTAssertEqual(breakdown.totalCost, expectedFixed, accuracy: 0.01)
    }

    // MARK: - Month-granularity exact cycle regression

    func testMonthGranularityFullQuarterYieldsExactThreeMonths() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        // Jan 1 – Mar 31 inclusive must be exactly 3 monthly units
        let start = try XCTUnwrap(formatter.date(from: "2026-01-01"))
        let end = try XCTUnwrap(formatter.date(from: "2026-03-31"))

        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "opencode-go", isSubscribed: true,
                periodGranularity: .month,
                periodStart: start, periodEnd: end,
                hasPeriodTracking: true
            ),
            for: .opencode
        )
        for provider in BillingProvider.allCases where provider != .opencode {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        let cost = try XCTUnwrap(prefs.periodTotalCost(for: .opencode))
        // 3 full calendar months × $10 = $30 (not 2 + 90/31 ≈ $49)
        XCTAssertEqual(cost, 30, accuracy: 0.01,
                       "Full quarter must be exactly 3 × monthlyUSD, not overcounted")
    }

    func testMonthGranularitySameMonthInclusiveEndUsesFraction() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        // Jan 1 – Jan 15 inclusive: exclusive end = Jan 16 → months=0, days=15
        let start = try XCTUnwrap(formatter.date(from: "2026-01-01"))
        let end = try XCTUnwrap(formatter.date(from: "2026-01-15"))

        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "opencode-go", isSubscribed: true,
                periodGranularity: .month,
                periodStart: start, periodEnd: end,
                hasPeriodTracking: true
            ),
            for: .opencode
        )
        for provider in BillingProvider.allCases where provider != .opencode {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        let cost = try XCTUnwrap(prefs.periodTotalCost(for: .opencode))
        // 15 days / 31 days in January × $10 ≈ $4.84
        let expected = 10.0 * 15.0 / 31.0
        XCTAssertEqual(cost, expected, accuracy: 0.01,
                       "15-day partial month must be 15/31 of monthlyUSD")
    }

    // MARK: - Codable migration for BillingPlanSelection period fields

    func testBillingPlanSelectionCodableRoundTripWithPeriodDates() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let start = try XCTUnwrap(formatter.date(from: "2026-01-01"))
        let end = try XCTUnwrap(formatter.date(from: "2026-12-31"))

        let original = BillingPlanSelection(
            mode: .preset,
            presetID: "opencode-go",
            customMonthlyUSD: nil,
            isSubscribed: true,
            periodGranularity: .day,
            periodStart: start,
            periodEnd: end,
            periodPreset: .yearly
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BillingPlanSelection.self, from: data)

        XCTAssertEqual(decoded.mode, .preset)
        XCTAssertEqual(decoded.presetID, "opencode-go")
        XCTAssertNil(decoded.customMonthlyUSD)
        XCTAssertTrue(decoded.isSubscribed)
        XCTAssertEqual(decoded.periodGranularity, .day)
        let decodedStartDay = decoded.periodStart.map { Calendar.autoupdatingCurrent.startOfDay(for: $0) }
        let expectedStartDay = Calendar.autoupdatingCurrent.startOfDay(for: start)
        XCTAssertEqual(decodedStartDay, expectedStartDay)
        let decodedEndDay = decoded.periodEnd.map { Calendar.autoupdatingCurrent.startOfDay(for: $0) }
        let expectedEndDay = Calendar.autoupdatingCurrent.startOfDay(for: end)
        XCTAssertEqual(decodedEndDay, expectedEndDay)
        XCTAssertEqual(decoded.periodPreset, .yearly)
    }

    func testBillingPlanSelectionDecodeOldFormatDefaultsPeriodFields() throws {
        let json = """
        {"mode":"preset","presetId":"opencode-go","isSubscribed":true}
        """
        let data = json.data(using: .utf8)!
        let selection = try JSONDecoder().decode(BillingPlanSelection.self, from: data)

        XCTAssertEqual(selection.mode, .preset)
        XCTAssertEqual(selection.presetID, "opencode-go")
        XCTAssertTrue(selection.isSubscribed)
        XCTAssertEqual(selection.periodGranularity, .month)
        XCTAssertNil(selection.periodStart)
        XCTAssertNil(selection.periodEnd)
        XCTAssertNil(selection.periodPreset)
    }

    func testBillingPlanSelectionEncodeOmitsNilPeriodDates() throws {
        let selection = BillingPlanSelection(
            presetID: "opencode-go",
            isSubscribed: true,
            periodGranularity: .month,
            periodStart: nil,
            periodEnd: nil,
            periodPreset: nil
        )
        let data = try JSONEncoder().encode(selection)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNil(json["period_start"])
        XCTAssertNil(json["period_end"])
        XCTAssertNil(json["period_preset"])
        XCTAssertEqual(json["period_granularity"] as? String, "month")
    }

    // MARK: - hasPeriodTracking migration and behavior

    func testHasPeriodTrackingDefaultsToFalse() {
        let selection = BillingPlanSelection(presetID: "opencode-go")
        XCTAssertFalse(selection.hasPeriodTracking)
    }

    func testHasPeriodTrackingExplicitInitTrue() {
        let selection = BillingPlanSelection(presetID: "opencode-go", hasPeriodTracking: true)
        XCTAssertTrue(selection.hasPeriodTracking)
    }

    func testOldDataWithPeriodDatesDecodesTrackingTrue() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        // Old JSON with both period dates but no period_tracking key
        let json = """
        {"mode":"preset","presetId":"opencode-go","isSubscribed":true,"period_start":728956800,"period_end":733622400,"period_granularity":"day"}
        """
        let data = json.data(using: .utf8)!
        let selection = try JSONDecoder().decode(BillingPlanSelection.self, from: data)

        XCTAssertNotNil(selection.periodStart)
        XCTAssertNotNil(selection.periodEnd)
        XCTAssertTrue(selection.hasPeriodTracking,
                       "Old data with both period dates should decode hasPeriodTracking=true")
    }

    func testOldDataWithoutPeriodDatesDecodesTrackingFalse() throws {
        let json = """
        {"mode":"preset","presetId":"opencode-go","isSubscribed":true}
        """
        let data = json.data(using: .utf8)!
        let selection = try JSONDecoder().decode(BillingPlanSelection.self, from: data)

        XCTAssertNil(selection.periodStart)
        XCTAssertNil(selection.periodEnd)
        XCTAssertFalse(selection.hasPeriodTracking)
    }

    func testOldDataWithOnlyOnePeriodDateDecodesTrackingFalse() throws {
        let json = """
        {"mode":"preset","presetId":"opencode-go","isSubscribed":true,"period_start":728956800,"period_granularity":"day"}
        """
        let data = json.data(using: .utf8)!
        let selection = try JSONDecoder().decode(BillingPlanSelection.self, from: data)

        XCTAssertNotNil(selection.periodStart)
        XCTAssertNil(selection.periodEnd)
        XCTAssertFalse(selection.hasPeriodTracking,
                        "Only one period date should NOT trigger hasPeriodTracking=true")
    }

    func testExplicitTrackingFalseOverridesAutoTrue() throws {
        let json = """
        {"mode":"preset","presetId":"opencode-go","isSubscribed":true,"period_start":728956800,"period_end":733622400,"period_tracking":false}
        """
        let data = json.data(using: .utf8)!
        let selection = try JSONDecoder().decode(BillingPlanSelection.self, from: data)

        XCTAssertNotNil(selection.periodStart)
        XCTAssertNotNil(selection.periodEnd)
        XCTAssertFalse(selection.hasPeriodTracking,
                        "Explicit period_tracking:false should not be overridden")
    }

    func testDisabledTrackingFallsBackToMonthlyInReportingBreakdown() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let periodStart = try XCTUnwrap(formatter.date(from: "2026-06-01"))
        let periodEnd = try XCTUnwrap(formatter.date(from: "2026-07-01"))

        var prefs = AppPreferences()
        // hasPeriodTracking=false even though dates are set
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "opencode-go", isSubscribed: true,
                periodGranularity: .day,
                periodStart: periodStart, periodEnd: periodEnd,
                hasPeriodTracking: false
            ),
            for: .opencode
        )
        for provider in BillingProvider.allCases where provider != .opencode {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        let payload = makeTestPayload(provider: "unused", rawCost: 0)
        let reportingStart = try XCTUnwrap(formatter.date(from: "2026-06-01"))
        let reportingEnd = try XCTUnwrap(formatter.date(from: "2026-06-16"))

        let breakdown = prefs.reportingCostBreakdown(
            payload: payload, reportingStart: reportingStart, reportingEnd: reportingEnd
        )

        XCTAssertTrue(breakdown.hasCost)
        // Should be full monthly USD ($10), NOT prorated
        XCTAssertEqual(breakdown.totalCost, 10, accuracy: 0.01)
        XCTAssertEqual(breakdown.fixedCostByProvider[.opencode], 10)
    }

    func testEnabledTrackingWithInvalidDatesFallsBackToMonthly() {
        var prefs = AppPreferences()
        // hasPeriodTracking=true but periodStart/periodEnd are nil
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "opencode-go", isSubscribed: true,
                hasPeriodTracking: true
            ),
            for: .opencode
        )
        for provider in BillingProvider.allCases where provider != .opencode {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        let payload = makeTestPayload(provider: "unused", rawCost: 0)
        let now = Date()
        let breakdown = prefs.reportingCostBreakdown(
            payload: payload,
            reportingStart: Calendar.autoupdatingCurrent.date(byAdding: .day, value: -30, to: now)!,
            reportingEnd: now
        )

        XCTAssertTrue(breakdown.hasCost)
        // Safe fallback: no valid dates → monthly USD
        XCTAssertEqual(breakdown.totalCost, 10, accuracy: 0.01)
        XCTAssertEqual(breakdown.fixedCostByProvider[.opencode], 10)
    }

    func testEnabledTrackingWithSameDayTreatsAsOneDay() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let sameDate = try XCTUnwrap(formatter.date(from: "2026-06-15"))

        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "opencode-go", isSubscribed: true,
                periodStart: sameDate, periodEnd: sameDate,
                hasPeriodTracking: true
            ),
            for: .opencode
        )
        for provider in BillingProvider.allCases where provider != .opencode {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        let payload = makeTestPayload(provider: "unused", rawCost: 0)
        let now = Date()
        let breakdown = prefs.reportingCostBreakdown(
            payload: payload,
            reportingStart: Calendar.autoupdatingCurrent.date(byAdding: .day, value: -30, to: now)!,
            reportingEnd: now
        )

        // Same-day cycle = 1 included day → proportional allocation, not full monthly fallback
        // 1 day within a 30-day month at $10 = ~$0.33 with .month granularity
        // Overlap with 30-day window may be 1 day → cost ≈ $0.33
        if breakdown.hasCost {
            XCTAssertLessThan(breakdown.totalCost, 10, "Same-day should not fall back to full monthly")
            if let fixedCost = breakdown.fixedCostByProvider[.opencode] {
                XCTAssertLessThan(fixedCost, 10, "Same-day fixed cost should be prorated, not full monthly")
            }
        }
    }

    func testPeriodTotalCostRespectsTrackingFlag() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "opencode-go", isSubscribed: true,
                periodStart: formatter.date(from: "2026-01-01"),
                periodEnd: formatter.date(from: "2026-12-31"),
                hasPeriodTracking: false
            ),
            for: .opencode
        )

        // With tracking disabled, periodTotalCost should return full monthlyUSD ($10)
        let cost = prefs.periodTotalCost(for: .opencode)
        XCTAssertEqual(cost ?? 0, 10, accuracy: 0.01)
    }

    func testHasPeriodTrackingCodableRoundTrip() throws {
        let original = BillingPlanSelection(
            presetID: "chatgpt-plus",
            isSubscribed: true,
            hasPeriodTracking: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BillingPlanSelection.self, from: data)

        XCTAssertTrue(decoded.hasPeriodTracking)
        XCTAssertEqual(decoded.presetID, "chatgpt-plus")

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["period_tracking"] as? Bool, true)
    }

    // MARK: - ReportingRangeMode tests

    func testReportingRangeModeDefaultsToAllAvailable() {
        let prefs = AppPreferences()
        XCTAssertEqual(prefs.reportingRangeMode, .allAvailable)
    }

    func testReportingRangeModeAllAvailableResolvesPayloadDates() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let payload = makeMultiDatePayload(dates: ["2026-06-01", "2026-06-05"])
        let range = try XCTUnwrap(AppPreferences.resolveReportingRange(
            mode: .allAvailable, customBounds: ReportingRangeCustomBounds(), payload: payload
        ))
        let calendar = Calendar.autoupdatingCurrent
        let expectedStart = try XCTUnwrap(formatter.date(from: "2026-06-01"))
        XCTAssertEqual(calendar.startOfDay(for: range.start), calendar.startOfDay(for: expectedStart))
    }

    func testReportingRangeModeCurrentMonthStartsAtMonthBegin() {
        let payload = makeTestPayload(provider: "test", rawCost: 0)
        let range = AppPreferences.resolveReportingRange(
            mode: .currentMonth, customBounds: ReportingRangeCustomBounds(), payload: payload
        )
        XCTAssertNotNil(range)
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
        XCTAssertEqual(calendar.startOfDay(for: range!.start), monthStart)
    }

    func testReportingRangeModeLast30DaysSpans30Days() {
        let payload = makeTestPayload(provider: "test", rawCost: 0)
        let range = AppPreferences.resolveReportingRange(
            mode: .last30Days, customBounds: ReportingRangeCustomBounds(), payload: payload
        )
        XCTAssertNotNil(range)
        let calendar = Calendar.autoupdatingCurrent
        let expectedStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -30, to: Date())!)
        XCTAssertEqual(calendar.startOfDay(for: range!.start), expectedStart)
    }

    func testReportingRangeModeCustomWithValidBounds() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let start = try XCTUnwrap(formatter.date(from: "2026-03-01"))
        let end = try XCTUnwrap(formatter.date(from: "2026-03-31"))
        let customBounds = ReportingRangeCustomBounds(start: start, end: end)

        let payload = makeTestPayload(provider: "test", rawCost: 0)
        let range = try XCTUnwrap(AppPreferences.resolveReportingRange(
            mode: .custom, customBounds: customBounds, payload: payload
        ))

        let calendar = Calendar.autoupdatingCurrent
        XCTAssertEqual(calendar.startOfDay(for: range.start), calendar.startOfDay(for: start))
    }

    func testReportingRangeModeCustomFallsBackOnMissingBounds() {
        let payload = makeTestPayload(provider: "test", rawCost: 0)
        let range = AppPreferences.resolveReportingRange(
            mode: .custom, customBounds: ReportingRangeCustomBounds(start: nil, end: nil),
            payload: payload
        )
        // Should fall back to allAvailable (payload-derived range)
        XCTAssertNotNil(range)
    }

    func testReportingRangeModeCustomFallsBackOnInvalidBounds() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let start = try XCTUnwrap(formatter.date(from: "2026-12-31"))
        let end = try XCTUnwrap(formatter.date(from: "2026-01-01"))
        let invalidBounds = ReportingRangeCustomBounds(start: start, end: end)

        let payload = makeTestPayload(provider: "test", rawCost: 0)
        let range = AppPreferences.resolveReportingRange(
            mode: .custom, customBounds: invalidBounds, payload: payload
        )
        // start > end is invalid → falls back to allAvailable
        XCTAssertNotNil(range)
    }

    func testFilteredUncoveredUsageOnlyIncludesInRangeRows() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let reportingStart = try XCTUnwrap(formatter.date(from: "2026-06-03"))
        let reportingEnd = try XCTUnwrap(formatter.date(from: "2026-06-05"))

        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 3_300, totalActualTokens: 3_300,
                totalCacheReadTokens: 0, totalCacheWriteTokens: 0, totalCacheTokens: 0,
                totalCost: 0, totalMessages: 3, activeDays: 3,
                dateRange: .init(start: "2026-06-01", end: "2026-06-07"),
                updatedAt: "2026-06-07T12:00:00Z"
            ),
            dailyTotals: [:], modelTotals: [:], providerCosts: [:], providerTotals: [:],
            rawData: [
                DashboardPayload.RawRow(
                    date: "2026-06-01", model: "test", provider: "deepseek",
                    input: 1_000_000, output: 0, reasoning: 0,
                    cacheRead: 0, cacheWrite: 0,
                    cacheWriteMissingCount: 0, cacheWriteReportedCount: 0,
                    total: 1_100, cost: 100, msgCount: 1
                ),
                DashboardPayload.RawRow(
                    date: "2026-06-04", model: "test", provider: "deepseek",
                    input: 1_000_000, output: 0, reasoning: 0,
                    cacheRead: 0, cacheWrite: 0,
                    cacheWriteMissingCount: 0, cacheWriteReportedCount: 0,
                    total: 1_100, cost: 200, msgCount: 1
                ),
                DashboardPayload.RawRow(
                    date: "2026-06-07", model: "test", provider: "deepseek",
                    input: 1_000_000, output: 0, reasoning: 0,
                    cacheRead: 0, cacheWrite: 0,
                    cacheWriteMissingCount: 0, cacheWriteReportedCount: 0,
                    total: 1_100, cost: 300, msgCount: 1
                )
            ]
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

        let breakdown = prefs.reportingCostBreakdown(
            payload: payload, reportingStart: reportingStart, reportingEnd: reportingEnd
        )

        // Only the June 4 row (cost=200) should be included; June 1 and June 7 should be excluded
        XCTAssertTrue(breakdown.hasCost)
        // Raw cost from June 4 row: 200
        // Synthetic cost for 1M input tokens via deepseek-chat (~$0.14)
        // Cost = max(raw=200, synthetic=0.14) = 200 (raw > synthetic)
        XCTAssertEqual(breakdown.totalCost, 200, accuracy: 0.5)
    }

    func testLegacyPreferencesDecodeDefaultsReportRangeToAllAvailable() throws {
        let json = """
        {"language":"zh-Hans","openCodePricingMode":"api"}
        """
        let data = json.data(using: .utf8)!
        let prefs = try JSONDecoder().decode(AppPreferences.self, from: data)

        XCTAssertEqual(prefs.reportingRangeMode, .allAvailable)
        XCTAssertEqual(prefs.reportingRangeCustomBounds.start, nil)
        XCTAssertEqual(prefs.reportingRangeCustomBounds.end, nil)
    }

    func testReportingRangeModeCodableRoundTrip() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let start = try XCTUnwrap(formatter.date(from: "2026-02-01"))
        let end = try XCTUnwrap(formatter.date(from: "2026-02-28"))
        let originalBounds = ReportingRangeCustomBounds(start: start, end: end)

        let prefs = AppPreferences(
            reportingRangeMode: .custom,
            reportingRangeCustomBounds: originalBounds
        )
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)

        XCTAssertEqual(decoded.reportingRangeMode, .custom)
        XCTAssertEqual(
            decoded.reportingRangeCustomBounds.start.map { Calendar.autoupdatingCurrent.startOfDay(for: $0) },
            Calendar.autoupdatingCurrent.startOfDay(for: start)
        )
        XCTAssertEqual(
            decoded.reportingRangeCustomBounds.end.map { Calendar.autoupdatingCurrent.startOfDay(for: $0) },
            Calendar.autoupdatingCurrent.startOfDay(for: end)
        )
    }

    func testCombinedTotalCostRespectsRangeMode() {
        let payload = makeTestPayload(provider: "deepseek", rawCost: 5)
        var prefsAll = AppPreferences(
            periodTotalCostEnabled: true,
            reportingRangeMode: .allAvailable
        )
        var prefsMonth = AppPreferences(
            periodTotalCostEnabled: true,
            reportingRangeMode: .currentMonth
        )
        func configure(_ prefs: inout AppPreferences) {
            prefs.setBillingSelection(
                BillingPlanSelection(presetID: "opencode-go", isSubscribed: true),
                for: .opencode
            )
            for provider in BillingProvider.allCases where provider != .opencode {
                prefs.setBillingSelection(
                    BillingPlanSelection(
                        presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                        isSubscribed: false
                    ),
                    for: provider
                )
            }
        }
        configure(&prefsAll)
        configure(&prefsMonth)

        let allCost = prefsAll.combinedTotalCost(payload: payload)
        XCTAssertNotNil(allCost)
        let monthCost = prefsMonth.combinedTotalCost(payload: payload)
        XCTAssertNotNil(monthCost)
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

    // MARK: - filteredPayloadWithReportingOverrides

    func testFilteredPayloadWithReportingOverridesReturnsNilForEmptyPayload() {
        var prefs = AppPreferences()
        prefs.reportingRangeMode = .allAvailable
        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 0, totalActualTokens: 0,
                totalCacheReadTokens: 0, totalCacheWriteTokens: 0, totalCacheTokens: 0,
                totalCost: 0, totalMessages: 0, activeDays: 0,
                dateRange: .init(start: nil, end: nil),
                updatedAt: "2026-07-01T12:00:00Z"
            ),
            dailyTotals: [:], modelTotals: [:], providerCosts: [:], providerTotals: [:],
            rawData: []
        )
        let result = prefs.filteredPayloadWithReportingOverrides(
            payload: payload, mode: .allAvailable
        )
        XCTAssertNil(result)
    }

    func testFilteredPayloadExcludesRowsOutsideRange() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let row1 = DashboardPayload.RawRow(
            date: "2026-06-01", model: "m1", provider: "p1",
            input: 1000, output: 100, reasoning: 0,
            cacheRead: 50, cacheWrite: 25,
            cacheWriteMissingCount: 1, cacheWriteReportedCount: 2,
            total: 1100, cost: 0.5, msgCount: 3
        )
        let row2 = DashboardPayload.RawRow(
            date: "2026-06-15", model: "m2", provider: "p2",
            input: 2000, output: 200, reasoning: 0,
            cacheRead: 100, cacheWrite: 50,
            cacheWriteMissingCount: 2, cacheWriteReportedCount: 3,
            total: 2200, cost: 1.0, msgCount: 5
        )
        let row3outside = DashboardPayload.RawRow(
            date: "2026-07-02", model: "m3", provider: "p3",
            input: 500, output: 50, reasoning: 0,
            cacheRead: 10, cacheWrite: 5,
            cacheWriteMissingCount: 0, cacheWriteReportedCount: 0,
            total: 550, cost: 0.2, msgCount: 1
        )

        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 3850, totalActualTokens: 3850,
                totalCacheReadTokens: 160, totalCacheWriteTokens: 80,
                totalCacheTokens: 240, totalCost: 1.7,
                totalMessages: 9, activeDays: 3,
                dateRange: .init(start: "2026-06-01", end: "2026-07-02"),
                updatedAt: "2026-07-01T12:00:00Z"
            ),
            dailyTotals: [:], modelTotals: [:], providerCosts: [:], providerTotals: [:],
            rawData: [row1, row2, row3outside]
        )

        var prefs = AppPreferences()
        let customStart = try XCTUnwrap(formatter.date(from: "2026-06-01"))
        let customEnd = try XCTUnwrap(formatter.date(from: "2026-06-30"))
        prefs.reportingRangeMode = .custom
        prefs.reportingRangeCustomBounds = ReportingRangeCustomBounds(start: customStart, end: customEnd)

        let result = try XCTUnwrap(prefs.filteredPayloadWithReportingOverrides(
            payload: payload,
            mode: prefs.reportingRangeMode,
            customBounds: prefs.reportingRangeCustomBounds
        ))
        let filtered = result.payload

        XCTAssertEqual(filtered.rawData.count, 2, "Row outside range (July 2) should be excluded")
        let dates = Set(filtered.rawData.map(\.date))
        XCTAssertTrue(dates.contains("2026-06-01"))
        XCTAssertTrue(dates.contains("2026-06-15"))
        XCTAssertFalse(dates.contains("2026-07-02"))
    }

    func testFilteredPayloadRecalculatesSummaryFromFilteredRows() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let row1 = DashboardPayload.RawRow(
            date: "2026-06-10", model: "m1", provider: "p1",
            input: 1000, output: 200, reasoning: 0,
            cacheRead: 30, cacheWrite: 10,
            cacheWriteMissingCount: 0, cacheWriteReportedCount: 1,
            total: 1200, cost: 0.8, msgCount: 2
        )
        let row2 = DashboardPayload.RawRow(
            date: "2026-06-10", model: "m2", provider: "p2",
            input: 500, output: 100, reasoning: 50,
            cacheRead: 20, cacheWrite: 5,
            cacheWriteMissingCount: 1, cacheWriteReportedCount: 2,
            total: 650, cost: 0.3, msgCount: 1
        )
        let rowOutside = DashboardPayload.RawRow(
            date: "2026-05-15", model: "m3", provider: "p3",
            input: 300, output: 50, reasoning: 0,
            cacheRead: 5, cacheWrite: 0,
            cacheWriteMissingCount: 0, cacheWriteReportedCount: 0,
            total: 350, cost: 0.1, msgCount: 1
        )

        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 2200, totalActualTokens: 2200,
                totalCacheReadTokens: 55, totalCacheWriteTokens: 15,
                totalCacheTokens: 70, totalCost: 1.2,
                totalMessages: 4, activeDays: 2,
                dateRange: .init(start: "2026-05-15", end: "2026-06-10"),
                updatedAt: "2026-07-01T12:00:00Z"
            ),
            dailyTotals: [:], modelTotals: [:], providerCosts: [:], providerTotals: [:],
            rawData: [row1, row2, rowOutside]
        )

        var prefs = AppPreferences()
        let customStart = try XCTUnwrap(formatter.date(from: "2026-06-01"))
        let customEnd = try XCTUnwrap(formatter.date(from: "2026-06-30"))
        prefs.reportingRangeMode = .custom
        prefs.reportingRangeCustomBounds = ReportingRangeCustomBounds(start: customStart, end: customEnd)

        let result = try XCTUnwrap(prefs.filteredPayloadWithReportingOverrides(
            payload: payload,
            mode: prefs.reportingRangeMode,
            customBounds: prefs.reportingRangeCustomBounds
        ))
        let filtered = result.payload

        XCTAssertEqual(filtered.rawData.count, 2)
        XCTAssertEqual(filtered.summary.totalTokens, 1200 + 650)
        XCTAssertEqual(filtered.summary.totalActualTokens, 1000 + 200 + 500 + 100 + 50)
        XCTAssertEqual(filtered.summary.totalCacheReadTokens, 30 + 20)
        XCTAssertEqual(filtered.summary.totalCacheWriteTokens, 10 + 5)
        XCTAssertEqual(filtered.summary.totalCost, 0.8 + 0.3)
        XCTAssertEqual(filtered.summary.totalMessages, 2 + 1)
        XCTAssertEqual(filtered.summary.activeDays, 1)
        XCTAssertEqual(filtered.summary.dateRange.start, "2026-06-10")
        XCTAssertEqual(filtered.summary.dateRange.end, "2026-06-10")

        // dailyTotals
        XCTAssertEqual(filtered.dailyTotals["2026-06-10"], 1200 + 650)
        // modelTotals
        XCTAssertEqual(filtered.modelTotals["m1"], 1200)
        XCTAssertEqual(filtered.modelTotals["m2"], 650)
        // providerCosts
        XCTAssertEqual(filtered.providerCosts["p1"], 0.8)
        XCTAssertEqual(filtered.providerCosts["p2"], 0.3)
        // providerTotals
        let p1Total = try XCTUnwrap(filtered.providerTotals["p1"])
        XCTAssertEqual(p1Total.input, 1000)
        XCTAssertEqual(p1Total.output, 200)
        XCTAssertEqual(p1Total.cacheRead, 30)
        XCTAssertEqual(p1Total.cacheWrite, 10)
        XCTAssertEqual(p1Total.total, 1200)
        XCTAssertEqual(p1Total.cost, 0.8)
        XCTAssertEqual(p1Total.messages, 2)
    }

    func testFilteredPayloadOverridesIncludeBothRawAndLegacyKeys() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let row = DashboardPayload.RawRow(
            date: "2026-06-15", model: "deepseek-chat", provider: "deepseek",
            input: 1_000_000, output: 0, reasoning: 0,
            cacheRead: 0, cacheWrite: 0,
            cacheWriteMissingCount: 0, cacheWriteReportedCount: 0,
            total: 1_000_000, cost: 0.14, msgCount: 1
        )

        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 1_000_000, totalActualTokens: 1_000_000,
                totalCacheReadTokens: 0, totalCacheWriteTokens: 0,
                totalCacheTokens: 0, totalCost: 0.14,
                totalMessages: 1, activeDays: 1,
                dateRange: .init(start: "2026-06-15", end: "2026-06-15"),
                updatedAt: "2026-07-01T12:00:00Z"
            ),
            dailyTotals: [:], modelTotals: [:], providerCosts: [:], providerTotals: [:],
            rawData: [row]
        )

        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "opencode-go", isSubscribed: true),
            for: .opencode
        )
        prefs.setBillingSelection(
            BillingPlanSelection(presetID: "mimo-current-default", isSubscribed: true),
            for: .xiaomiMimo
        )
        for provider in BillingProvider.allCases where provider != .opencode && provider != .xiaomiMimo {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }
        prefs.reportingRangeMode = .allAvailable

        let result = try XCTUnwrap(prefs.filteredPayloadWithReportingOverrides(
            payload: payload, mode: .allAvailable
        ))

        // Verify both raw and legacy keys exist
        XCTAssertGreaterThan(result.overrides["opencode"] ?? 0, 0, "Should include raw key 'opencode'")
        XCTAssertGreaterThan(result.overrides["opencode-go"] ?? 0, 0, "Should include legacy key 'opencode-go'")
        XCTAssertGreaterThan(result.overrides["xiaomi-mimo"] ?? 0, 0, "Should include raw key 'xiaomi-mimo'")
        XCTAssertGreaterThan(result.overrides["xiaomi-token-plan-cn"] ?? 0, 0, "Should include legacy key 'xiaomi-token-plan-cn'")
        // Same cost for both keys
        XCTAssertEqual(result.overrides["opencode"], result.overrides["opencode-go"])
        XCTAssertEqual(result.overrides["xiaomi-mimo"], result.overrides["xiaomi-token-plan-cn"])
    }

    // MARK: - P0: Zero-overlap subscription must not suppress API costs (§5.3)

    func testReportingCostBreakdownZeroOverlapIncludesUncoveredAPIUsage() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        // Opencode subscription: May 1–31. Reporting range: June 1–30 (zero overlap).
        let periodStart = try XCTUnwrap(formatter.date(from: "2026-05-01"))
        let periodEnd = try XCTUnwrap(formatter.date(from: "2026-05-31"))
        let reportingStart = try XCTUnwrap(formatter.date(from: "2026-06-01"))
        let reportingEnd = try XCTUnwrap(formatter.date(from: "2026-06-30"))

        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "opencode-go", isSubscribed: true,
                periodStart: periodStart, periodEnd: periodEnd,
                hasPeriodTracking: true
            ),
            for: .opencode
        )
        for provider in BillingProvider.allCases where provider != .opencode {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        // Build a payload with date inside the reporting range (June).
        let date = "2026-06-15"
        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 110000, totalActualTokens: 110000,
                totalCacheReadTokens: 0, totalCacheWriteTokens: 0, totalCacheTokens: 0,
                totalCost: 5.0, totalMessages: 1, activeDays: 1,
                dateRange: .init(start: date, end: date),
                updatedAt: "2026-06-15T12:00:00Z"
            ),
            dailyTotals: [:], modelTotals: [:], providerCosts: [:], providerTotals: [:],
            rawData: [
                DashboardPayload.RawRow(
                    date: date, model: "gpt-5.4", provider: "opencode-go",
                    input: 100000, output: 10000, reasoning: 0,
                    cacheRead: 0, cacheWrite: 0,
                    cacheWriteMissingCount: 0, cacheWriteReportedCount: 1,
                    total: 110000, cost: 5.0, msgCount: 1
                )
            ]
        )
        let breakdown = prefs.reportingCostBreakdown(
            payload: payload, reportingStart: reportingStart, reportingEnd: reportingEnd
        )

        // Zero overlap → fixed subscription cost = 0 per §5.3.
        XCTAssertEqual(breakdown.fixedCostByProvider[.opencode] ?? 0, 0, accuracy: 0.01)
        // API usage must be included since subscription contributed $0.
        XCTAssertGreaterThan(breakdown.totalCost, 0, "Zero-overlap subscription must not suppress API usage")
        let uncovered = breakdown.uncoveredUsageByProviderKey
        let opencodeCost = uncovered["opencode-go"] ?? uncovered["opencode"] ?? 0
        XCTAssertGreaterThan(opencodeCost, 0, "Uncovered API usage should be charged")
    }

    func testReportingCostBreakdownOverlapBillingBlocksAPIUsage() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        // Both period and reporting cover May (full overlap).
        let periodStart = try XCTUnwrap(formatter.date(from: "2026-05-01"))
        let periodEnd = try XCTUnwrap(formatter.date(from: "2026-05-31"))
        let reportingStart = try XCTUnwrap(formatter.date(from: "2026-05-01"))
        let reportingEnd = try XCTUnwrap(formatter.date(from: "2026-05-31"))

        var prefs = AppPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "opencode-go", isSubscribed: true,
                periodStart: periodStart, periodEnd: periodEnd,
                hasPeriodTracking: true
            ),
            for: .opencode
        )
        for provider in BillingProvider.allCases where provider != .opencode {
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: BillingPlanCatalog.defaultSelection(for: provider).presetID,
                    isSubscribed: false
                ),
                for: provider
            )
        }

        let date = "2026-05-15"
        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 110000, totalActualTokens: 110000,
                totalCacheReadTokens: 0, totalCacheWriteTokens: 0, totalCacheTokens: 0,
                totalCost: 5.0, totalMessages: 1, activeDays: 1,
                dateRange: .init(start: date, end: date),
                updatedAt: "2026-05-15T12:00:00Z"
            ),
            dailyTotals: [:], modelTotals: [:], providerCosts: [:], providerTotals: [:],
            rawData: [
                DashboardPayload.RawRow(
                    date: date, model: "gpt-5.4", provider: "opencode-go",
                    input: 100000, output: 10000, reasoning: 0,
                    cacheRead: 0, cacheWrite: 0,
                    cacheWriteMissingCount: 0, cacheWriteReportedCount: 1,
                    total: 110000, cost: 5.0, msgCount: 1
                )
            ]
        )
        // Full overlap: subscription period covers the reporting range. Fixed subscription contributes.
        let breakdown = prefs.reportingCostBreakdown(
            payload: payload, reportingStart: reportingStart, reportingEnd: reportingEnd
        )

        XCTAssertGreaterThan(breakdown.fixedCostByProvider[.opencode] ?? 0, 0)
        XCTAssertEqual(breakdown.uncoveredUsageByProviderKey["opencode-go"] ?? 0.0, 0.0, accuracy: 0.0)
    }

    // MARK: - Cache hit-rate denominator uses input + cacheRead

    func testCacheHitRateDenominatorUsesInputPlusCacheRead() {
        let rows: [DashboardPayload.RawRow] = [
            DashboardPayload.RawRow(
                date: "2026-07-01", model: "gpt-5.4", provider: "openai",
                input: 200, output: 50, reasoning: 0,
                cacheRead: 100, cacheWrite: 0,
                cacheWriteMissingCount: 0, cacheWriteReportedCount: 1,
                total: 350, cost: 0, msgCount: 1
            )
        ]
        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 350, totalActualTokens: 250, totalCacheReadTokens: 100,
                totalCacheWriteTokens: 0, totalCacheTokens: 100, totalCost: 0,
                totalMessages: 1, activeDays: 1,
                dateRange: .init(start: "2026-07-01", end: "2026-07-01"),
                updatedAt: "2026-07-01T12:00:00Z"
            ),
            dailyTotals: ["2026-07-01": 350],
            modelTotals: ["gpt-5.4": 350],
            providerCosts: ["openai": 0],
            providerTotals: [:],
            rawData: rows
        )

        let analytics = TokenCostDashboardAnalytics(payload: payload)

        // Denominator = input + cacheRead = 200 + 100 = 300
        // rate = 100 / 300 ≈ 0.333
        let expectedRate = 100.0 / (200.0 + 100.0)
        XCTAssertEqual(analytics.cache.cacheHitRate, expectedRate, accuracy: 0.001,
                       "Aggregate cache hit rate must use input+cacheRead denominator")

        guard let openaiRow = analytics.providerCacheRows.first(where: { $0.key == "openai" }) else {
            XCTFail("Expected openai provider cache row"); return
        }
        XCTAssertEqual(openaiRow.cacheRate, expectedRate, accuracy: 0.001,
                       "Per-provider cache rate must use input+cacheRead denominator")
    }

    func testCacheHitRateWithOutputDoesNotInflateDenominator() {
        // High output should not inflate the denominator — only input matters.
        let rows: [DashboardPayload.RawRow] = [
            DashboardPayload.RawRow(
                date: "2026-07-01", model: "gpt-5.4", provider: "deepseek-api-cn",
                input: 100, output: 900, reasoning: 0,
                cacheRead: 50, cacheWrite: 0,
                cacheWriteMissingCount: 0, cacheWriteReportedCount: 1,
                total: 1050, cost: 0, msgCount: 1
            )
        ]
        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 1050, totalActualTokens: 1000, totalCacheReadTokens: 50,
                totalCacheWriteTokens: 0, totalCacheTokens: 50, totalCost: 0,
                totalMessages: 1, activeDays: 1,
                dateRange: .init(start: "2026-07-01", end: "2026-07-01"),
                updatedAt: "2026-07-01T12:00:00Z"
            ),
            dailyTotals: ["2026-07-01": 1050],
            modelTotals: ["gpt-5.4": 1050],
            providerCosts: ["deepseek-api-cn": 0],
            providerTotals: [:],
            rawData: rows
        )

        let analytics = TokenCostDashboardAnalytics(payload: payload)

        // With old denominator (actualTokens + cacheRead = 1000 + 50 = 1050), rate = 50/1050 ≈ 0.0476
        // With new denominator (input + cacheRead = 100 + 50 = 150), rate = 50/150 ≈ 0.333
        let expectedRate = 50.0 / 150.0
        XCTAssertEqual(analytics.cache.cacheHitRate, expectedRate, accuracy: 0.001,
                       "Cache hit rate denominator must exclude output tokens")
        XCTAssertGreaterThan(analytics.cache.cacheHitRate, 0.3,
                            "High output should not dilute cache hit rate")

        guard let dsRow = analytics.providerCacheRows.first(where: { $0.key == "deepseek-api-cn" }) else {
            XCTFail("Expected deepseek provider cache row"); return
        }
        XCTAssertEqual(dsRow.cacheRate, expectedRate, accuracy: 0.001)
    }

    // MARK: - Ollama cache estimates do not alter billing/cost

    func testOllamaEstimatesNeverLeakToActualOrCost() {
        // Ollama cloud row with cacheRead=0 triggers estimation.
        let rows: [DashboardPayload.RawRow] = [
            DashboardPayload.RawRow(
                date: "2026-07-01", model: "deepseek-v4-flash", provider: "ollama-cloud",
                input: 1000, output: 100, reasoning: 0,
                cacheRead: 0, cacheWrite: 0,
                cacheWriteMissingCount: 0, cacheWriteReportedCount: 0,
                total: 1100, cost: 0.05, msgCount: 1
            )
        ]
        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 1100, totalActualTokens: 1100, totalCacheReadTokens: 0,
                totalCacheWriteTokens: 0, totalCacheTokens: 0, totalCost: 0.05,
                totalMessages: 1, activeDays: 1,
                dateRange: .init(start: "2026-07-01", end: "2026-07-01"),
                updatedAt: "2026-07-01T12:00:00Z"
            ),
            dailyTotals: ["2026-07-01": 1100],
            modelTotals: ["deepseek-v4-flash": 1100],
            providerCosts: ["ollama-cloud": 0.05],
            providerTotals: [:],
            rawData: rows
        )

        let analytics = TokenCostDashboardAnalytics(payload: payload)

        // actualTokens must remain unchanged (estimation does not affect billing).
        XCTAssertEqual(analytics.overview.totalActualTokens, 1100, accuracy: 0.01,
                       "Ollama cache estimation must not alter actual/billed tokens")

        // Estimated cache read should be present in cache summary.
        XCTAssertGreaterThan(analytics.cache.estimatedCacheReadTokens, 0,
                            "Estimated cache read should be present")
        XCTAssertTrue(analytics.cache.hasEstimates)

        // cacheSavedCost must NOT be inflated by estimates (only uses real cacheRead).
        XCTAssertEqual(analytics.cache.cacheSavedCost, 0, accuracy: 0.001,
                       "cacheSavedCost must use only real cacheRead")
    }

    // MARK: - Unknown model/provider rows are retained

    func testDashboardPayloadRetainsUnknownModelAndProvider() {
        let rows: [DashboardPayload.RawRow] = [
            DashboardPayload.RawRow(
                date: "2026-07-01", model: "unknown", provider: "unknown",
                input: 100, output: 50, reasoning: 0,
                cacheRead: 0, cacheWrite: 0,
                cacheWriteMissingCount: 1, cacheWriteReportedCount: 0,
                total: 150, cost: 0, msgCount: 2
            ),
            DashboardPayload.RawRow(
                date: "2026-07-01", model: "gpt-5.4", provider: "openai",
                input: 200, output: 100, reasoning: 0,
                cacheRead: 10, cacheWrite: 5,
                cacheWriteMissingCount: 0, cacheWriteReportedCount: 2,
                total: 315, cost: 0, msgCount: 3
            )
        ]
        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 465, totalActualTokens: 450, totalCacheReadTokens: 10,
                totalCacheWriteTokens: 5, totalCacheTokens: 15, totalCost: 0,
                totalMessages: 5, activeDays: 1,
                dateRange: .init(start: "2026-07-01", end: "2026-07-01"),
                updatedAt: "2026-07-01T12:00:00Z"
            ),
            dailyTotals: ["2026-07-01": 465],
            modelTotals: ["unknown": 150, "gpt-5.4": 315],
            providerCosts: ["unknown": 0, "openai": 0],
            providerTotals: [:],
            rawData: rows
        )

        // Both rows must be present.
        XCTAssertEqual(payload.rawData.count, 2)
        XCTAssertTrue(payload.rawData.contains(where: { $0.model == "unknown" && $0.provider == "unknown" }),
                      "Rows with unknown model/provider must be retained")
        XCTAssertTrue(payload.rawData.contains(where: { $0.model == "gpt-5.4" && $0.provider == "openai" }))

        // Total tokens count both rows.
        XCTAssertEqual(payload.totalInputTokens, 300, accuracy: 0.01)
        XCTAssertEqual(payload.totalActualInputTokens, 300, accuracy: 0.01)

        // Analytics must include the unknown provider.
        let analytics = TokenCostDashboardAnalytics(payload: payload)
        XCTAssertTrue(analytics.providerCacheRows.contains(where: { $0.key == "unknown" }),
                      "Analytics must include rows with unknown provider")
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

    private func makeMultiDatePayload(dates: [String]) -> DashboardPayload {
        let rows: [DashboardPayload.RawRow] = dates.map { date in
            DashboardPayload.RawRow(
                date: date, model: "test-model", provider: "test-provider",
                input: 1000, output: 100, reasoning: 0,
                cacheRead: 0, cacheWrite: 0,
                cacheWriteMissingCount: 0, cacheWriteReportedCount: 0,
                total: 1100, cost: 0, msgCount: 1
            )
        }
        let sorted = dates.sorted()
        return DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: Double(rows.count) * 1100,
                totalActualTokens: Double(rows.count) * 1100,
                totalCacheReadTokens: 0, totalCacheWriteTokens: 0, totalCacheTokens: 0,
                totalCost: 0, totalMessages: rows.count, activeDays: dates.count,
                dateRange: .init(start: sorted.first, end: sorted.last),
                updatedAt: "2026-06-15T12:00:00Z"
            ),
            dailyTotals: [:], modelTotals: [:], providerCosts: [:], providerTotals: [:],
            rawData: rows
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

    // MARK: — Ollama Cloud DeepSeek V4 cache-read estimation

    func testOllamaDeepSeekFlashEstimationViaAlias() {
        let payload = makeOllamaDeepSeekPayload(model: "deepseek-chat", input: 1_000_000)
        let analytics = TokenCostDashboardAnalytics(payload: payload)

        XCTAssertTrue(analytics.cache.hasEstimates)
        XCTAssertGreaterThan(analytics.cache.estimatedCacheReadTokens, 0)
        // multiplier = rate/(1-rate), rate = 553686784/600792157
        // expected = 1_000_000 * 553686784 / (600792157 - 553686784)
        let expectedMultiplier = 553_686_784.0 / (600_792_157.0 - 553_686_784.0)
        let expectedEstimated = 1_000_000.0 * expectedMultiplier
        XCTAssertEqual(analytics.cache.estimatedCacheReadTokens, expectedEstimated, accuracy: 1.0)
        // displayed cacheRead = real(0) + estimated
        XCTAssertEqual(analytics.cache.cacheReadTokens, expectedEstimated, accuracy: 1.0)

        guard let ollamaRow = analytics.providerCacheRows.first(where: { $0.key == "ollama-cloud" }) else {
            XCTFail("Expected ollama-cloud provider row"); return
        }
        XCTAssertTrue(ollamaRow.hasEstimates)
        XCTAssertEqual(ollamaRow.estimatedCacheReadTokens, expectedEstimated, accuracy: 1.0)
        XCTAssertEqual(ollamaRow.inputTokens, 1_000_000, accuracy: 0.5)
    }

    func testOllamaDeepSeekProEstimationViaAlias() {
        let payload = makeOllamaDeepSeekPayload(model: "deepseek-reasoner", input: 500_000)
        let analytics = TokenCostDashboardAnalytics(payload: payload)

        XCTAssertTrue(analytics.cache.hasEstimates)
        // multiplier for pro: rate = 1476491904/1550614127
        let expectedMultiplier = 1_476_491_904.0 / (1_550_614_127.0 - 1_476_491_904.0)
        let expectedEstimated = 500_000.0 * expectedMultiplier
        XCTAssertEqual(analytics.cache.estimatedCacheReadTokens, expectedEstimated, accuracy: 1.0)

        guard let ollamaRow = analytics.providerCacheRows.first(where: { $0.key == "ollama-cloud" }) else {
            XCTFail("Expected ollama-cloud provider row"); return
        }
        XCTAssertTrue(ollamaRow.hasEstimates)
        XCTAssertEqual(ollamaRow.estimatedCacheReadTokens, expectedEstimated, accuracy: 1.0)
    }

    func testNonOllamaProviderNoEstimation() {
        let payload = makeSingleModelPayload(
            model: "deepseek-chat", provider: "deepseek", input: 1_000_000
        )
        let analytics = TokenCostDashboardAnalytics(payload: payload)

        XCTAssertFalse(analytics.cache.hasEstimates)
        XCTAssertEqual(analytics.cache.estimatedCacheReadTokens, 0)
        // displayed cacheRead stays real-only (0 here)
        XCTAssertEqual(analytics.cache.cacheReadTokens, 0)

        if let deepseekRow = analytics.providerCacheRows.first(where: { $0.key == "deepseek" }) {
            XCTAssertFalse(deepseekRow.hasEstimates)
            XCTAssertEqual(deepseekRow.estimatedCacheReadTokens, 0)
        }
    }

    func testOllamaNonDeepSeekModelNoEstimation() {
        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 1_000_000, totalActualTokens: 1_000_000,
                totalCacheReadTokens: 0, totalCacheWriteTokens: 0, totalCacheTokens: 0,
                totalCost: 0, totalMessages: 1, activeDays: 1,
                dateRange: .init(start: "2026-06-04", end: "2026-06-04"),
                updatedAt: "2026-06-04T12:00:00Z"
            ),
            dailyTotals: [:], modelTotals: [:], providerCosts: [:], providerTotals: [:],
            rawData: [
                DashboardPayload.RawRow(
                    date: "2026-06-04", model: "gpt-5.4", provider: "ollama-cloud",
                    input: 1_000_000, output: 0, reasoning: 0,
                    cacheRead: 0, cacheWrite: 0,
                    cacheWriteMissingCount: 0, cacheWriteReportedCount: 0,
                    total: 1_000_000, cost: 0, msgCount: 1
                )
            ]
        )
        let analytics = TokenCostDashboardAnalytics(payload: payload)

        XCTAssertFalse(analytics.cache.hasEstimates)
        XCTAssertEqual(analytics.cache.estimatedCacheReadTokens, 0)
    }

    func testOllamaDeepSeekWithRealCacheReadNoEstimation() {
        let payload = makeOllamaDeepSeekPayload(
            model: "deepseek-chat", input: 1_000_000, cacheRead: 50_000
        )
        let analytics = TokenCostDashboardAnalytics(payload: payload)

        XCTAssertFalse(analytics.cache.hasEstimates)
        XCTAssertEqual(analytics.cache.estimatedCacheReadTokens, 0)
        XCTAssertEqual(analytics.cache.cacheReadTokens, 50_000, accuracy: 0.5)
    }

    func testOllamaDeepSeekZeroInputNoEstimation() {
        let payload = makeOllamaDeepSeekPayload(model: "deepseek-chat", input: 0, output: 1000)
        let analytics = TokenCostDashboardAnalytics(payload: payload)

        XCTAssertFalse(analytics.cache.hasEstimates)
        XCTAssertEqual(analytics.cache.estimatedCacheReadTokens, 0)
    }

    func testCacheSummaryEstimatedFields() {
        let payload = makeOllamaDeepSeekPayload(model: "deepseek-chat", input: 1_000)
        let analytics = TokenCostDashboardAnalytics(payload: payload)

        XCTAssertTrue(analytics.cache.hasEstimates)
        XCTAssertGreaterThan(analytics.cache.estimatedCacheReadTokens, 0)
        // cacheHitRate uses displayed (real+estimated) cacheRead
        XCTAssertGreaterThan(analytics.cache.cacheHitRate, 0)
        // totalCacheTokens includes estimated
        XCTAssertGreaterThan(analytics.cache.totalCacheTokens, 0)
    }

    func testOllamaCacheRateUsesEstimatedFormula() {
        let payload = makeOllamaDeepSeekPayload(model: "deepseek-chat", input: 1_000_000)
        let analytics = TokenCostDashboardAnalytics(payload: payload)

        guard let ollamaRow = analytics.providerCacheRows.first(where: { $0.key == "ollama-cloud" }) else {
            XCTFail("Expected ollama-cloud provider row"); return
        }
        XCTAssertTrue(ollamaRow.hasEstimates)
        // Ollama rate = (real+estimated) / (input+real+estimated)
        // real = cacheRead = 0
        let expectedRate = ollamaRow.estimatedCacheReadTokens / (ollamaRow.inputTokens + ollamaRow.estimatedCacheReadTokens)
        XCTAssertEqual(ollamaRow.cacheRate, expectedRate, accuracy: 0.0001)
        // The rate should equal the snapshot rate (since real cacheRead==0)
        let flashRate = 553_686_784.0 / 600_792_157.0
        XCTAssertEqual(ollamaRow.cacheRate, flashRate, accuracy: 0.0001)
    }

    func testNonOllamaCacheRateUsesExistingFormula() {
        let payload = makeSingleModelPayload(
            model: "deepseek-chat", provider: "deepseek",
            input: 1_000_000, cacheRead: 200_000
        )
        let analytics = TokenCostDashboardAnalytics(payload: payload)

        guard let dsRow = analytics.providerCacheRows.first(where: { $0.key == "deepseek" }) else {
            XCTFail("Expected deepseek provider row"); return
        }
        XCTAssertFalse(dsRow.hasEstimates)
        // existing formula: cacheRead / (actualTokens + cacheRead)
        // actualTokens = input + output = 1_000_000
        let expectedRate = 200_000.0 / (1_000_000.0 + 200_000.0)
        XCTAssertEqual(dsRow.cacheRate, expectedRate, accuracy: 0.0001)
    }

    func testTrendPointEstimatedField() {
        let payload = makeOllamaDeepSeekPayload(model: "deepseek-chat", input: 1_000_000)
        let analytics = TokenCostDashboardAnalytics(payload: payload)

        XCTAssertEqual(analytics.trendPoints.count, 1)
        guard let point = analytics.trendPoints.first else { XCTFail("Expected trend point"); return }

        let expectedMultiplier = 553_686_784.0 / (600_792_157.0 - 553_686_784.0)
        let expectedEstimated = 1_000_000.0 * expectedMultiplier
        XCTAssertEqual(point.estimatedCacheReadTokens, expectedEstimated, accuracy: 1.0)
        // displayed cacheRead = real(0) + estimated
        XCTAssertEqual(point.cacheReadTokens, expectedEstimated, accuracy: 1.0)
    }

    func testProviderRankRowRealOnlyNoEstimates() {
        let payload = makeOllamaDeepSeekPayload(model: "deepseek-chat", input: 1000)
        let analytics = TokenCostDashboardAnalytics(payload: payload)

        guard let ollamaRank = analytics.providerRankRows.first(where: { $0.providerKey == "ollama-cloud" }) else {
            XCTFail("Expected ollama-cloud rank row"); return
        }
        // cacheReadTokens on rank row stays real-only (0)
        XCTAssertEqual(ollamaRank.cacheReadTokens, 0)
        // actualTokens stays real-only
        XCTAssertEqual(ollamaRank.actualTokens, 1000, accuracy: 0.5)
    }

    func testProviderCacheRowSortingRealOnly() {
        // ollama with estimated reads should NOT outrank deepseek just because of estimates
        let ollamaPayload = makeOllamaDeepSeekPayload(model: "deepseek-chat", input: 100, output: 50)
        let deepseekPayload = makeSingleModelPayload(
            model: "deepseek-chat", provider: "deepseek",
            input: 200, output: 100
        )

        let merged = mergePayloads(ollamaPayload, deepseekPayload)
        let analytics = TokenCostDashboardAnalytics(payload: merged)

        // deepseek has more real usage (300 actual vs ollama's 150 actual)
        // sorting desc by usageTokens (real-only) should put deepseek first
        let rows = analytics.providerCacheRows
        XCTAssertGreaterThanOrEqual(rows.count, 2)

        guard let dsIndex = rows.firstIndex(where: { $0.key == "deepseek" }),
              let ollamaIndex = rows.firstIndex(where: { $0.key == "ollama-cloud" }) else {
            XCTFail("Missing expected provider rows"); return
        }
        // deepseek usageTokens = 300 real tokens, ollama = 150 real tokens + estimates (not counted)
        XCTAssertLessThan(dsIndex, ollamaIndex, "deepseek should rank above ollama on real usage")
    }

    func testCacheSavedCostUsesPricingCatalogOnly() {
        // Use a model with no pricing → cacheSavedCost should be 0
        let payloadNoPricing = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 1_000_000, totalActualTokens: 1_000_000,
                totalCacheReadTokens: 1_000_000, totalCacheWriteTokens: 0, totalCacheTokens: 1_000_000,
                totalCost: 10, totalMessages: 1, activeDays: 1,
                dateRange: .init(start: "2026-06-04", end: "2026-06-04"),
                updatedAt: "2026-06-04T12:00:00Z"
            ),
            dailyTotals: [:], modelTotals: [:], providerCosts: [:], providerTotals: [:],
            rawData: [
                DashboardPayload.RawRow(
                    date: "2026-06-04", model: "no-such-model", provider: "openai",
                    input: 0, output: 0, reasoning: 0,
                    cacheRead: 1_000_000, cacheWrite: 0,
                    cacheWriteMissingCount: 0, cacheWriteReportedCount: 0,
                    total: 1_000_000, cost: 0, msgCount: 1
                )
            ]
        )
        let analyticsNoPrice = TokenCostDashboardAnalytics(payload: payloadNoPricing)
        XCTAssertEqual(analyticsNoPrice.cache.cacheSavedCost, 0, "No pricing → zero saved cost")

        // Use deepseek with known pricing
        let payloadWithPrice = makeSingleModelPayload(
            model: "deepseek-chat", provider: "deepseek",
            input: 0, output: 0, cacheRead: 1_000_000
        )
        let analyticsWithPrice = TokenCostDashboardAnalytics(payload: payloadWithPrice)
        // savings = cacheRead * (inputPrice - cacheReadPrice) / 1M
        // deepseek-v4-flash: 0.14 - 0.0028 = 0.1372 per 1M cache tokens
        let expectedSaved = 1_000_000.0 * (0.14 - 0.0028) / 1_000_000.0
        XCTAssertEqual(analyticsWithPrice.cache.cacheSavedCost, expectedSaved, accuracy: 0.0001)
    }

    func testCacheSavedCostExcludesEstimates() {
        // Ollama + deepseek with cacheRead==0 → estimation runs
        let payload = makeOllamaDeepSeekPayload(model: "deepseek-chat", input: 10_000_000)
        let analytics = TokenCostDashboardAnalytics(payload: payload)

        // Estimates are non-zero but cacheSavedCost should be 0 (no REAL cache reads)
        XCTAssertTrue(analytics.cache.hasEstimates)
        XCTAssertGreaterThan(analytics.cache.estimatedCacheReadTokens, 0)
        XCTAssertEqual(analytics.cache.cacheSavedCost, 0, "Estimated reads do not contribute to saved cost")
    }

    func testCacheSavedCostAccumulatesAcrossMultipleRows() {
        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 2_000_000, totalActualTokens: 0,
                totalCacheReadTokens: 2_000_000, totalCacheWriteTokens: 0, totalCacheTokens: 2_000_000,
                totalCost: 0, totalMessages: 2, activeDays: 1,
                dateRange: .init(start: "2026-06-04", end: "2026-06-04"),
                updatedAt: "2026-06-04T12:00:00Z"
            ),
            dailyTotals: [:], modelTotals: [:], providerCosts: [:], providerTotals: [:],
            rawData: [
                DashboardPayload.RawRow(
                    date: "2026-06-04", model: "deepseek-chat", provider: "deepseek",
                    input: 0, output: 0, reasoning: 0,
                    cacheRead: 1_000_000, cacheWrite: 0,
                    cacheWriteMissingCount: 0, cacheWriteReportedCount: 0,
                    total: 1_000_000, cost: 0, msgCount: 1
                ),
                DashboardPayload.RawRow(
                    date: "2026-06-04", model: "deepseek-reasoner", provider: "deepseek",
                    input: 0, output: 0, reasoning: 0,
                    cacheRead: 1_000_000, cacheWrite: 0,
                    cacheWriteMissingCount: 0, cacheWriteReportedCount: 0,
                    total: 1_000_000, cost: 0, msgCount: 1
                )
            ]
        )
        let analytics = TokenCostDashboardAnalytics(payload: payload)
        // flash: 1M × (0.14−0.0028)/1M + pro: 1M × (0.435−0.003625)/1M
        let expectedTotal = (0.14 - 0.0028) + (0.435 - 0.003625)
        XCTAssertEqual(analytics.cache.cacheSavedCost, expectedTotal, accuracy: 0.0001)
    }

    func testOllamaProviderInputTokensField() {
        let payload = makeOllamaDeepSeekPayload(model: "deepseek-chat", input: 500_000)
        let analytics = TokenCostDashboardAnalytics(payload: payload)

        guard let row = analytics.providerCacheRows.first(where: { $0.key == "ollama-cloud" }) else {
            XCTFail("Expected ollama-cloud row"); return
        }
        XCTAssertEqual(row.inputTokens, 500_000, accuracy: 0.5)
    }

    func testOllamaMixedRealAndEstimatedCacheRead() {
        // One row with real cacheRead, one without (gets estimated)
        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 2_500_000, totalActualTokens: 2_000_000,
                totalCacheReadTokens: 500_000, totalCacheWriteTokens: 0, totalCacheTokens: 500_000,
                totalCost: 0, totalMessages: 2, activeDays: 1,
                dateRange: .init(start: "2026-06-04", end: "2026-06-04"),
                updatedAt: "2026-06-04T12:00:00Z"
            ),
            dailyTotals: [:], modelTotals: [:], providerCosts: [:], providerTotals: [:],
            rawData: [
                DashboardPayload.RawRow(
                    date: "2026-06-04", model: "deepseek-chat", provider: "ollama-cloud",
                    input: 1_000_000, output: 0, reasoning: 0,
                    cacheRead: 500_000, cacheWrite: 0,
                    cacheWriteMissingCount: 0, cacheWriteReportedCount: 1,
                    total: 1_500_000, cost: 0, msgCount: 1
                ),
                DashboardPayload.RawRow(
                    date: "2026-06-04", model: "deepseek-chat", provider: "ollama-cloud",
                    input: 1_000_000, output: 0, reasoning: 0,
                    cacheRead: 0, cacheWrite: 0,
                    cacheWriteMissingCount: 0, cacheWriteReportedCount: 0,
                    total: 1_000_000, cost: 0, msgCount: 1
                )
            ]
        )
        let analytics = TokenCostDashboardAnalytics(payload: payload)

        XCTAssertTrue(analytics.cache.hasEstimates)
        guard let row = analytics.providerCacheRows.first(where: { $0.key == "ollama-cloud" }) else {
            XCTFail("Expected ollama-cloud row"); return
        }

        let expectedMultiplier = 553_686_784.0 / (600_792_157.0 - 553_686_784.0)
        let expectedEstimated = 1_000_000.0 * expectedMultiplier

        // estimatedCacheReadTokens = just the estimate from row with cacheRead==0
        XCTAssertEqual(row.estimatedCacheReadTokens, expectedEstimated, accuracy: 1.0)
        // cacheReadTokens (displayed) = real(500k) + estimated
        let expectedDisplayed = 500_000.0 + expectedEstimated
        XCTAssertEqual(row.cacheReadTokens, expectedDisplayed, accuracy: 1.0)
        // hasEstimates = true because at least one row was estimated
        XCTAssertTrue(row.hasEstimates)

        // Ollama rate = (real+estimated) / (input+real+estimated)
        let totalInput = 2_000_000.0
        let totalReal = 500_000.0
        let totalEstimated = expectedEstimated
        let expectedRate = (totalReal + totalEstimated) / (totalInput + totalReal + totalEstimated)
        XCTAssertEqual(row.cacheRate, expectedRate, accuracy: 0.0001)

        // usageTokens = real-only (actualTokens + real cacheRead + real cacheWrite)
        // actualTokens = 2 rows * 1M input = 2M
        let expectedUsage = 2_000_000.0 + 500_000.0  // + 0 cacheWrite
        XCTAssertEqual(row.usageTokens, expectedUsage, accuracy: 1.0)

        // cacheSavedCost only from real reads
        // savings = cacheRead × (inputPrice − cacheReadPrice) / 1M
        // deepseek-v4-flash: 500k × (0.14 − 0.0028) / 1M = 0.0686
        let expectedSaved = 500_000.0 * (0.14 - 0.0028) / 1_000_000.0
        XCTAssertEqual(analytics.cache.cacheSavedCost, expectedSaved, accuracy: 0.0001)
    }

    // MARK: — Test helpers for cache-read estimation

    private func makeOllamaDeepSeekPayload(
        model: String, input: Double, output: Double = 0, cacheRead: Double = 0
    ) -> DashboardPayload {
        makeSingleModelPayload(
            model: model, provider: "ollama-cloud",
            input: input, output: output, cacheRead: cacheRead
        )
    }

    private func mergePayloads(_ a: DashboardPayload, _ b: DashboardPayload) -> DashboardPayload {
        var merged = a
        merged.rawData.append(contentsOf: b.rawData)
        return merged
    }

    // MARK: — Local calendar day regression (date-only keys must not shift)

    func testDateOnlyKeyPreservesLocalCalendarDay() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let dateString = "2026-07-20"
        let parsed = try XCTUnwrap(formatter.date(from: dateString))
        let calendar = Calendar.autoupdatingCurrent
        let dayStart = calendar.startOfDay(for: parsed)

        let components = calendar.dateComponents([.year, .month, .day], from: dayStart)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 20)
    }

    func testReportingRangePreservesAllLocalDayKeys() throws {
        let dates = ["2026-07-18", "2026-07-19", "2026-07-20"]
        let payload = makeMultiDatePayload(dates: dates)
        let range = try XCTUnwrap(AppPreferences.reportingRange(from: payload))

        let calendar = Calendar.autoupdatingCurrent
        let rangeStartDay = calendar.startOfDay(for: range.start)
        let rangeEndDay = calendar.startOfDay(for: range.end)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for date in dates {
            guard let parsed = formatter.date(from: date) else {
                XCTFail("Could not parse \(date)")
                return
            }
            let localDay = calendar.startOfDay(for: parsed)
            XCTAssertGreaterThanOrEqual(localDay, rangeStartDay, "\(date) should be >= range start")
            XCTAssertLessThanOrEqual(localDay, rangeEndDay, "\(date) should be <= range end")
        }
    }

    func testChartTrendPointsPreserveLocalCalendarDay() {
        let row = DashboardPayload.RawRow(
            date: "2026-07-20", model: "test", provider: "test",
            input: 100, output: 10, reasoning: 0,
            cacheRead: 0, cacheWrite: 0,
            cacheWriteMissingCount: 0, cacheWriteReportedCount: 0,
            total: 110, cost: 0, msgCount: 1
        )
        let payload = DashboardPayload(
            summary: DashboardPayload.Summary(
                totalTokens: 110, totalActualTokens: 110,
                totalCacheReadTokens: 0, totalCacheWriteTokens: 0, totalCacheTokens: 0,
                totalCost: 0, totalMessages: 1, activeDays: 1,
                dateRange: .init(start: "2026-07-20", end: "2026-07-20"),
                updatedAt: "2026-07-20T12:00:00Z"
            ),
            dailyTotals: [:], modelTotals: [:], providerCosts: [:], providerTotals: [:],
            rawData: [row]
        )
        let analytics = TokenCostDashboardAnalytics(payload: payload)
        XCTAssertEqual(analytics.trendPoints.count, 1)
        guard let point = analytics.trendPoints.first else {
            XCTFail("Expected one trend point")
            return
        }
        let calendar = Calendar.autoupdatingCurrent
        let components = calendar.dateComponents([.year, .month, .day], from: point.date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 20)
    }

    // MARK: - AmountConsumptionRateCalculator

    func testAmountRateFirstSampleIsPending() {
        AmountConsumptionRateCalculator.resetHistoryForTesting()
        defer { AmountConsumptionRateCalculator.resetHistoryForTesting() }

        let snapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: Date(),
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(label: "CNY", currencyCode: "CNY", amount: 14.0)
            ]
        )

        let computed = AmountConsumptionRateCalculator.compute(current: [snapshot])
        let rate = computed.first?.valueEntries?.first?.amountConsumptionRate
        XCTAssertNil(rate, "First sample with no history should return nil")
    }

    func testAmountRateDecreasingAmountYieldsPositiveBurn() {
        AmountConsumptionRateCalculator.resetHistoryForTesting()
        defer { AmountConsumptionRateCalculator.resetHistoryForTesting() }

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

        let firstSnapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseTime,
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(label: "CNY", currencyCode: "CNY", amount: 14.0)
            ]
        )
        AmountConsumptionRateCalculator.store([firstSnapshot])

        let secondSnapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseTime.addingTimeInterval(720),
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(label: "CNY", currencyCode: "CNY", amount: 10.0)
            ]
        )

        let computed = AmountConsumptionRateCalculator.compute(current: [secondSnapshot])
        let rate = computed.first?.valueEntries?.first?.amountConsumptionRate

        XCTAssertNotNil(rate)
        XCTAssertGreaterThan(rate?.perHour ?? 0, 0, "Decreasing amount should yield positive burn rate")
        XCTAssertEqual(rate?.perDay ?? 0, (rate?.perHour ?? 0) * 24, accuracy: 0.001)
        XCTAssertGreaterThan(rate?.confidence ?? 0, 0)
    }

    func testAmountRateUnchangedAmountYieldsZero() {
        AmountConsumptionRateCalculator.resetHistoryForTesting()
        defer { AmountConsumptionRateCalculator.resetHistoryForTesting() }

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

        let firstSnapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseTime,
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(label: "CNY", currencyCode: "CNY", amount: 14.0)
            ]
        )
        AmountConsumptionRateCalculator.store([firstSnapshot])

        let secondSnapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseTime.addingTimeInterval(720),
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(label: "CNY", currencyCode: "CNY", amount: 14.0)
            ]
        )

        let computed = AmountConsumptionRateCalculator.compute(current: [secondSnapshot])
        let rate = computed.first?.valueEntries?.first?.amountConsumptionRate

        XCTAssertNotNil(rate)
        XCTAssertEqual(rate?.perHour ?? -1, 0, accuracy: 0.001, "Unchanged amount should yield zero burn rate")
        XCTAssertEqual(rate?.perDay ?? -1, 0, accuracy: 0.001)
    }

    func testAmountRateReplenishmentReturnsNil() {
        AmountConsumptionRateCalculator.resetHistoryForTesting()
        defer { AmountConsumptionRateCalculator.resetHistoryForTesting() }

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

        let firstSnapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseTime,
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(label: "CNY", currencyCode: "CNY", amount: 10.0)
            ]
        )
        AmountConsumptionRateCalculator.store([firstSnapshot])

        let secondSnapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseTime.addingTimeInterval(720),
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(label: "CNY", currencyCode: "CNY", amount: 14.0)
            ]
        )

        let computed = AmountConsumptionRateCalculator.compute(current: [secondSnapshot])
        let rate = computed.first?.valueEntries?.first?.amountConsumptionRate

        XCTAssertNil(rate, "Replenishment (increase) should return nil, not compute a burn rate")
    }

    func testAmountRateReplenishmentResetsHistory() {
        AmountConsumptionRateCalculator.resetHistoryForTesting()
        defer { AmountConsumptionRateCalculator.resetHistoryForTesting() }

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

        let firstSnapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseTime,
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(label: "CNY", currencyCode: "CNY", amount: 10.0)
            ]
        )
        AmountConsumptionRateCalculator.store([firstSnapshot])

        let replenishSnapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseTime.addingTimeInterval(720),
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(label: "CNY", currencyCode: "CNY", amount: 14.0)
            ]
        )
        AmountConsumptionRateCalculator.store([replenishSnapshot])

        let thirdSnapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseTime.addingTimeInterval(1440),
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(label: "CNY", currencyCode: "CNY", amount: 12.0)
            ]
        )

        let computed = AmountConsumptionRateCalculator.compute(current: [thirdSnapshot])
        let rate = computed.first?.valueEntries?.first?.amountConsumptionRate

        XCTAssertNotNil(rate, "After replenishment reset, stored baseline + declining current yields valid rate")
        XCTAssertGreaterThan(rate?.perHour ?? 0, 0, "Decline from replenished baseline should yield positive burn")
        // 14→12 over 720s: perHour = (2/720) * 3600 = 10
        XCTAssertEqual(rate?.perHour ?? 0, 10, accuracy: 0.001)
    }

    func testAmountRateCurrenciesIsolated() {
        AmountConsumptionRateCalculator.resetHistoryForTesting()
        defer { AmountConsumptionRateCalculator.resetHistoryForTesting() }

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

        let firstSnapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseTime,
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(label: "CNY", currencyCode: "CNY", amount: 14.0),
                BalanceValueEntry(label: "USD", currencyCode: "USD", amount: 2.0)
            ]
        )
        AmountConsumptionRateCalculator.store([firstSnapshot])

        let secondSnapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseTime.addingTimeInterval(720),
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(label: "CNY", currencyCode: "CNY", amount: 10.0),
                BalanceValueEntry(label: "USD", currencyCode: "USD", amount: 2.0)
            ]
        )

        let computed = AmountConsumptionRateCalculator.compute(current: [secondSnapshot])
        let cnyRate = computed.first?.valueEntries?.first?.amountConsumptionRate
        let usdRate = computed.first?.valueEntries?.last?.amountConsumptionRate

        XCTAssertNotNil(cnyRate)
        XCTAssertGreaterThan(cnyRate?.perHour ?? 0, 0, "CNY decreasing → positive burn")
        XCTAssertNotNil(usdRate)
        XCTAssertEqual(usdRate?.perHour ?? -1, 0, accuracy: 0.001, "USD unchanged → zero burn")
    }

    func testAmountRateEffectiveSpanTooShortReturnsNil() {
        AmountConsumptionRateCalculator.resetHistoryForTesting()
        defer { AmountConsumptionRateCalculator.resetHistoryForTesting() }

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

        let firstSnapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseTime,
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(label: "CNY", currencyCode: "CNY", amount: 14.0)
            ]
        )
        AmountConsumptionRateCalculator.store([firstSnapshot])

        let secondSnapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseTime.addingTimeInterval(120),
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(label: "CNY", currencyCode: "CNY", amount: 13.0)
            ]
        )

        let computed = AmountConsumptionRateCalculator.compute(current: [secondSnapshot])
        let rate = computed.first?.valueEntries?.first?.amountConsumptionRate

        XCTAssertNil(rate, "Effective span under 5 min should return nil")
    }

    func testAmountRateOldSnapshotDecodePreservesNilRate() throws {
        let oldJSON = """
        {"label":"CNY","currency_code":"CNY","amount":14.0}
        """
        let data = Data(oldJSON.utf8)
        let entry = try JSONDecoder().decode(BalanceValueEntry.self, from: data)
        XCTAssertEqual(entry.amount, 14.0)
        XCTAssertNil(entry.amountConsumptionRate, "Old snapshots without amountConsumptionRate should decode as nil")
    }

    func testAmountRateCodableRoundTrip() throws {
        let entry = BalanceValueEntry(
            label: "CNY",
            currencyCode: "CNY",
            amount: 10.0,
            grantedAmount: 5.0,
            toppedUpAmount: 2.0,
            amountConsumptionRate: BalanceAmountConsumptionRate(perHour: 1.5, perDay: 36.0, confidence: 0.8)
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(BalanceValueEntry.self, from: data)

        XCTAssertEqual(decoded.amount, 10.0)
        XCTAssertEqual(decoded.grantedAmount, 5.0)
        XCTAssertEqual(decoded.toppedUpAmount, 2.0)
        XCTAssertEqual(decoded.amountConsumptionRate?.perHour, 1.5)
        XCTAssertEqual(decoded.amountConsumptionRate?.perDay, 36.0)
        XCTAssertEqual(decoded.amountConsumptionRate?.confidence, 0.8)
    }

    func testAmountRateComputePreservesQuotaWindows() {
        AmountConsumptionRateCalculator.resetHistoryForTesting()
        defer { AmountConsumptionRateCalculator.resetHistoryForTesting() }

        let original = BalanceSnapshot(
            provider: .codex,
            fetchedAt: Date(),
            isAvailable: true,
            usagePercent: 0.5,
            quotaWindows: [
                BalanceQuotaWindow(label: "5h", usedRatio: 0.4, remainingRatio: 0.6, resetAt: Date().addingTimeInterval(3600))
            ],
            valueEntries: [BalanceValueEntry(label: "余额", currencyCode: "CNY", amount: 100)]
        )

        let computed = AmountConsumptionRateCalculator.compute(current: [original]).first!

        XCTAssertEqual(computed.provider, original.provider)
        XCTAssertEqual(computed.usagePercent, original.usagePercent)
        XCTAssertEqual(computed.quotaWindows?.count, 1)
        XCTAssertEqual(computed.quotaWindows?.first?.usedRatio, 0.4)
        XCTAssertEqual(computed.valueEntries?.count, 1)
        XCTAssertEqual(computed.valueEntries?.first?.amount, 100)
    }

    func testAmountRateWithoutValueEntriesReturnsUnchanged() {
        AmountConsumptionRateCalculator.resetHistoryForTesting()
        defer { AmountConsumptionRateCalculator.resetHistoryForTesting() }

        let snapshot = BalanceSnapshot(
            provider: .codex,
            fetchedAt: Date(),
            isAvailable: true,
            usagePercent: 0.3
        )

        let computed = AmountConsumptionRateCalculator.compute(current: [snapshot]).first!
        XCTAssertEqual(computed.usagePercent, 0.3)
        XCTAssertNil(computed.valueEntries)
    }

    func testAmountRateCaseInsensitiveCurrencyCode() {
        AmountConsumptionRateCalculator.resetHistoryForTesting()
        defer { AmountConsumptionRateCalculator.resetHistoryForTesting() }

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

        let firstSnapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseTime,
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(label: "余额", currencyCode: "cny", amount: 14.0)
            ]
        )
        AmountConsumptionRateCalculator.store([firstSnapshot])

        let secondSnapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseTime.addingTimeInterval(720),
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(label: "余额", currencyCode: "CNY", amount: 10.0)
            ]
        )

        let computed = AmountConsumptionRateCalculator.compute(current: [secondSnapshot])
        let rate = computed.first?.valueEntries?.first?.amountConsumptionRate

        XCTAssertNotNil(rate, "CNY and cny should share the same history key")
        XCTAssertGreaterThan(rate?.perHour ?? 0, 0, "Shared history should produce a burn rate")
    }

    func testAmountRateReplenishmentWithinDebounceResetsHistory() {
        AmountConsumptionRateCalculator.resetHistoryForTesting()
        defer { AmountConsumptionRateCalculator.resetHistoryForTesting() }

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

        // First sample: baseline at 10.0
        let firstSnapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseTime,
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(label: "CNY", currencyCode: "CNY", amount: 10.0)
            ]
        )
        AmountConsumptionRateCalculator.store([firstSnapshot])

        // Replenishment within debounce (only 5s since last sample, well under 600s)
        let replenishSnapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseTime.addingTimeInterval(5),
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(label: "CNY", currencyCode: "CNY", amount: 20.0)
            ]
        )
        AmountConsumptionRateCalculator.store([replenishSnapshot])

        // Third sample: decline from new baseline after debounce
        let thirdSnapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseTime.addingTimeInterval(720),
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(label: "CNY", currencyCode: "CNY", amount: 18.0)
            ]
        )

        let computed = AmountConsumptionRateCalculator.compute(current: [thirdSnapshot])
        let rate = computed.first?.valueEntries?.first?.amountConsumptionRate

        XCTAssertNotNil(rate, "After within-debounce replenishment reset, baseline should be 20→18")
        // 20→18 over (720-5)s: perHour = (2/715) * 3600 ≈ 10.0699
        XCTAssertEqual(rate?.perHour ?? 0, 10.0699, accuracy: 0.1)
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

private final class CancellingMockChecker: BalanceChecker, @unchecked Sendable {
    let providerKind: BalanceProviderKind

    init(providerKind: BalanceProviderKind) {
        self.providerKind = providerKind
    }

    func fetch(authToken: String) async throws -> BalanceSnapshot {
        throw CancellationError()
    }
}

private final class SleepingMockChecker: BalanceChecker, @unchecked Sendable {
    let providerKind: BalanceProviderKind
    let sleepNanos: UInt64

    init(providerKind: BalanceProviderKind, sleepNanos: UInt64) {
        self.providerKind = providerKind
        self.sleepNanos = sleepNanos
    }

    func fetch(authToken: String) async throws -> BalanceSnapshot {
        try await Task.sleep(nanoseconds: sleepNanos)
        return BalanceSnapshot(provider: providerKind, fetchedAt: Date(), isAvailable: true)
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
