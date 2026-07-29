import XCTest
@testable import CodexTokenCostApp
@testable import CodexTokenCostCore

final class DetailAndTotalViewLogicTests: XCTestCase {
    func testDetailRowsUseFullFilteredDatasetForCostSorting() {
        let analytics = makeAnalytics(rows: makeRows(count: 101))

        let rows = detailRows(from: analytics, sortField: .cost, direction: .descending)

        XCTAssertEqual(rows.count, 101)
        XCTAssertEqual(rows.first?.cost, 101)
        XCTAssertEqual(rows.last?.cost, 1)
    }

    func testStackedWindowUsesFullFilteredDataset() {
        let analytics = makeAnalytics(rows: makeRows(count: 101))

        let window = stackedWindow(from: analytics)

        XCTAssertEqual(window.dates.count, 101)
        XCTAssertEqual(window.series.count, 1)
        XCTAssertEqual(window.series.first?.total, (1...101).reduce(0) { $0 + Double($1) })
    }

    func testOllamaEstimateNoticeRequiresEligibleDeepSeekModels() {
        let eligible = DashboardPayload.RawRow(
            date: "2026-01-01",
            model: "deepseek-v4-flash",
            provider: "ollama-cloud",
            input: 12,
            output: 1,
            reasoning: 0,
            cacheRead: 0,
            cacheWrite: 0,
            cacheWriteMissingCount: 0,
            cacheWriteReportedCount: 0,
            total: 13,
            cost: 0,
            msgCount: 1
        )

        let unsupportedModel = DashboardPayload.RawRow(
            date: "2026-01-02",
            model: "gpt-4o",
            provider: "ollama-cloud",
            input: 12,
            output: 1,
            reasoning: 0,
            cacheRead: 0,
            cacheWrite: 0,
            cacheWriteMissingCount: 0,
            cacheWriteReportedCount: 0,
            total: 13,
            cost: 0,
            msgCount: 1
        )

        let cachedRow = DashboardPayload.RawRow(
            date: "2026-01-03",
            model: "deepseek-v4-pro",
            provider: "ollama-cloud",
            input: 12,
            output: 1,
            reasoning: 0,
            cacheRead: 2,
            cacheWrite: 0,
            cacheWriteMissingCount: 0,
            cacheWriteReportedCount: 0,
            total: 15,
            cost: 0,
            msgCount: 1
        )

        let otherProvider = DashboardPayload.RawRow(
            date: "2026-01-04",
            model: "deepseek-v4-pro",
            provider: "opencode",
            input: 12,
            output: 1,
            reasoning: 0,
            cacheRead: 0,
            cacheWrite: 0,
            cacheWriteMissingCount: 0,
            cacheWriteReportedCount: 0,
            total: 13,
            cost: 0,
            msgCount: 1
        )

        XCTAssertTrue(hasEligibleOllamaCloudEstimate(rows: [eligible]))
        XCTAssertFalse(hasEligibleOllamaCloudEstimate(rows: [unsupportedModel]))
        XCTAssertFalse(hasEligibleOllamaCloudEstimate(rows: [cachedRow]))
        XCTAssertFalse(hasEligibleOllamaCloudEstimate(rows: [otherProvider]))
    }

    func testDetailReportingTotalCostKeepsValidZeroCostBreakdown() throws {
        let payload = DashboardPayload.empty()
        let reportingStart = try XCTUnwrap(Self.dateFormatter.date(from: "2026-06-01"))
        let reportingEnd = try XCTUnwrap(Self.dateFormatter.date(from: "2026-06-30"))
        let periodStart = try XCTUnwrap(Self.dateFormatter.date(from: "2026-05-01"))
        let periodEnd = try XCTUnwrap(Self.dateFormatter.date(from: "2026-05-31"))

        var prefs = makeAllProvidersUnsubscribedPreferences()
        prefs.setBillingSelection(
            BillingPlanSelection(
                presetID: "opencode-go",
                isSubscribed: true,
                periodStart: periodStart,
                periodEnd: periodEnd,
                hasPeriodTracking: true
            ),
            for: .opencode
        )
        prefs.reportingRangeMode = .custom
        prefs.reportingRangeCustomBounds = ReportingRangeCustomBounds(start: reportingStart, end: reportingEnd)

        let breakdown = prefs.reportingCostBreakdown(
            payload: payload,
            reportingStart: reportingStart,
            reportingEnd: reportingEnd
        )
        let monthlyFallback = prefs.combinedMonthlyCost(payload: payload)

        XCTAssertEqual(breakdown.totalCost, 0, accuracy: 0.0001)
        XCTAssertNotNil(monthlyFallback)
        XCTAssertGreaterThan(monthlyFallback ?? 0, 0)
    }

    func testDetailReportingTotalCostFallsBackOnlyWhenRangeCannotResolve() {
        let payload = DashboardPayload.empty()
        let prefs = makeAllProvidersSubscribedPreferences()

        let breakdown = prefs.reportingCostBreakdown(payload: payload, mode: .allAvailable, customBounds: .init())
        let monthlyFallback = prefs.combinedMonthlyCost(payload: payload)

        XCTAssertNil(breakdown)
        XCTAssertGreaterThan(monthlyFallback ?? 0, 0)
    }

    func testDetailCacheDistributionTotalUsesInputPlusDisplayedCacheRead() {
        let nonOllamaRow = TokenCostDashboardAnalytics.ProviderCacheRow(
            key: "opencode",
            displayName: "OpenCode",
            usageTokens: 999,
            actualTokens: 777,
            cacheReadTokens: 123,
            cacheWriteTokens: 45,
            cacheWriteLabel: "45",
            cacheRate: 0.55,
            colorKey: "opencode",
            inputTokens: 321,
            estimatedCacheReadTokens: 0,
            hasEstimates: false
        )

        let ollamaEstimatedRow = TokenCostDashboardAnalytics.ProviderCacheRow(
            key: "ollama-cloud",
            displayName: "Ollama Cloud",
            usageTokens: 999,
            actualTokens: 777,
            cacheReadTokens: 160,
            cacheWriteTokens: 45,
            cacheWriteLabel: "45",
            cacheRate: 0.61,
            colorKey: "ollama-cloud",
            inputTokens: 100,
            estimatedCacheReadTokens: 60,
            hasEstimates: true
        )

        XCTAssertEqual(nonOllamaRow.inputTokens + nonOllamaRow.cacheReadTokens, 444)
        XCTAssertNotEqual(nonOllamaRow.actualTokens + nonOllamaRow.cacheReadTokens, 444)
        XCTAssertEqual(ollamaEstimatedRow.inputTokens + ollamaEstimatedRow.cacheReadTokens, 260)
    }

    private func makeAnalytics(rows: [DashboardPayload.RawRow]) -> TokenCostDashboardAnalytics {
        var payload = DashboardPayload.empty()
        payload.rawData = rows
        return TokenCostDashboardAnalytics(
            payload: payload,
            showZeroUsageXiaomiProvider: false,
            billingOverridesByProviderKey: [:]
        )
    }

    private func makeRows(count: Int) -> [DashboardPayload.RawRow] {
        let calendar = Calendar(identifier: .gregorian)
        let formatter = Self.dateFormatter
        let baseDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!

        return (0..<count).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: baseDate)!
            return DashboardPayload.RawRow(
                date: formatter.string(from: date),
                model: "deepseek-v4-flash",
                provider: "ollama-cloud",
                input: Double(offset + 1),
                output: 0,
                reasoning: 0,
                cacheRead: 0,
                cacheWrite: 0,
                cacheWriteMissingCount: 0,
                cacheWriteReportedCount: 0,
                total: Double(count - offset),
                cost: Double(count - offset),
                msgCount: 1
            )
        }
    }

    private func makeAllProvidersUnsubscribedPreferences() -> AppPreferences {
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
        return prefs
    }

    private func makeAllProvidersSubscribedPreferences() -> AppPreferences {
        var prefs = AppPreferences()
        for provider in BillingProvider.allCases {
            let defaultSelection = BillingPlanCatalog.defaultSelection(for: provider)
            prefs.setBillingSelection(
                BillingPlanSelection(
                    presetID: defaultSelection.presetID,
                    isSubscribed: true
                ),
                for: provider
            )
        }
        return prefs
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
