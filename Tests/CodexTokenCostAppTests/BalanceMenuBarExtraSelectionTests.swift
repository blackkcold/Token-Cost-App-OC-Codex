import XCTest
@testable import CodexTokenCostApp
@testable import CodexTokenCostCore

final class BalanceMenuBarExtraSelectionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppLocalization.setLanguage(.zhHans)
    }

    func testQuotaSelectionUsesMostAtRiskSnapshotAndDisplayMode() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let lowerRisk = BalanceSnapshot(
            provider: .opencodeGo,
            fetchedAt: baseDate,
            isAvailable: true,
            quotaWindows: [BalanceQuotaWindow(label: "5h", usedRatio: 0.35, remainingRatio: 0.65)]
        )
        let higherRisk = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseDate,
            isAvailable: true,
            quotaWindows: [BalanceQuotaWindow(label: "monthly", usedRatio: 0.92, remainingRatio: 0.08)]
        )

        let usedSelection = BalanceMenuBarExtraSupport.selection(
            for: [lowerRisk, higherRisk],
            displayMode: .used,
            displayCurrency: .usd
        )
        XCTAssertEqual(usedSelection.kind, .quota)
        XCTAssertEqual(usedSelection.titleText, higherRisk.provider.displayName)
        XCTAssertEqual(usedSelection.valueText, TokenCostFormatters.percent(0.92))
        XCTAssertEqual(usedSelection.compactValueText, usedSelection.valueText)
        XCTAssertEqual(usedSelection.detailText, "monthly")
        XCTAssertEqual(usedSelection.accessibilityLabel, AppLocalization.text("balance.title"))
        XCTAssertTrue(usedSelection.accessibilityValue.contains(higherRisk.provider.displayName))

        let remainingSelection = BalanceMenuBarExtraSupport.selection(
            for: [lowerRisk, higherRisk],
            displayMode: .remaining,
            displayCurrency: .usd
        )
        XCTAssertEqual(remainingSelection.kind, .quota)
        XCTAssertEqual(remainingSelection.titleText, higherRisk.provider.displayName)
        XCTAssertEqual(remainingSelection.valueText, TokenCostFormatters.percent(0.08))
        XCTAssertEqual(remainingSelection.detailText, "monthly")
        XCTAssertEqual(remainingSelection.compactValueText, remainingSelection.valueText)
    }

    func testAmountSelectionShowsFormattedAmountAndPerDayBurn() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = BalanceSnapshot(
            provider: .deepseek,
            fetchedAt: baseDate,
            isAvailable: true,
            valueEntries: [
                BalanceValueEntry(
                    label: "DeepSeek CNY",
                    currencyCode: "cny",
                    amount: 12.34,
                    grantedAmount: 100,
                    amountConsumptionRate: BalanceAmountConsumptionRate(perHour: 1.2, perDay: 28.8, confidence: 0.9)
                )
            ]
        )

        let selection = BalanceMenuBarExtraSupport.selection(
            for: [snapshot],
            displayMode: .used,
            displayCurrency: .usd
        )

        XCTAssertEqual(selection.kind, .amount)
        XCTAssertEqual(selection.titleText, snapshot.provider.displayName)
        XCTAssertEqual(selection.valueText, BalanceMenuBarExtraSupport.amountText(for: snapshot.valueEntries![0]))
        XCTAssertEqual(selection.compactValueText, "¥12.34")
        XCTAssertNotNil(selection.detailText)
        XCTAssertEqual(selection.detailText, BalanceMenuBarExtraSupport.burnRateText(for: snapshot.valueEntries![0]))
        XCTAssertFalse(selection.detailText?.contains("%") ?? true)
        XCTAssertEqual(selection.accessibilityLabel, AppLocalization.text("balance.title"))
        XCTAssertTrue(selection.accessibilityValue.contains(snapshot.provider.displayName))
        XCTAssertTrue(selection.helpText.contains(snapshot.provider.displayName))
    }

    func testCompactAmountSelectionPreservesUsdCentsAndCompactsLargeValues() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        let usdSelection = BalanceMenuBarExtraSupport.selection(
            for: [BalanceSnapshot(provider: .opencodeZen, fetchedAt: baseDate, isAvailable: true, totalCostUSD: 3.5)],
            displayMode: .used,
            displayCurrency: .usd
        )
        XCTAssertEqual(usdSelection.kind, .amount)
        XCTAssertEqual(usdSelection.compactValueText, "$3.50")

        let largeSelection = BalanceMenuBarExtraSupport.selection(
            for: [BalanceSnapshot(provider: .codex, fetchedAt: baseDate, isAvailable: true, totalCostUSD: 1_234_567.89)],
            displayMode: .used,
            displayCurrency: .usd
        )
        XCTAssertEqual(largeSelection.kind, .amount)
        XCTAssertEqual(largeSelection.compactValueText, "$1.23M")
    }

    func testSelectionFallsBackToUnavailableAndEmptyDeterministically() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let unavailable = BalanceSnapshot.unavailable(.codex, reason: "network down")
        let noDataSelection = BalanceMenuBarExtraSupport.selection(
            for: [],
            displayMode: .used,
            displayCurrency: .usd
        )

        XCTAssertEqual(noDataSelection.kind, .empty)
        XCTAssertEqual(noDataSelection.titleText, AppLocalization.text("balance.title"))
        XCTAssertEqual(noDataSelection.valueText, AppLocalization.text("common.unavailable"))
        XCTAssertEqual(noDataSelection.compactValueText, AppLocalization.text("common.unavailable"))

        let unavailableOnlySelection = BalanceMenuBarExtraSupport.selection(
            for: [unavailable],
            displayMode: .used,
            displayCurrency: .usd
        )
        XCTAssertEqual(unavailableOnlySelection.kind, .unavailable)
        XCTAssertEqual(unavailableOnlySelection.titleText, unavailable.provider.displayName)
        XCTAssertEqual(unavailableOnlySelection.compactValueText, AppLocalization.text("balance.unavailable"))
        XCTAssertTrue(unavailableOnlySelection.accessibilityValue.contains("network down"))

        let unavailableSelection = BalanceMenuBarExtraSupport.selection(
            for: [unavailable, BalanceSnapshot(provider: .opencodeZen, fetchedAt: baseDate, isAvailable: true, totalCostUSD: 4.25)],
            displayMode: .used,
            displayCurrency: .usd
        )

        XCTAssertEqual(unavailableSelection.kind, .amount)
        XCTAssertEqual(unavailableSelection.titleText, BalanceProviderKind.opencodeZen.displayName)
        XCTAssertEqual(unavailableSelection.valueText, TokenCostFormatters.currency(4.25, displayCurrency: .usd))
    }

    func testBurnRateHelperUsesPerDayTextWhenAvailable() {
        let entry = BalanceValueEntry(
            label: "DeepSeek",
            currencyCode: "usd",
            amount: 3.5,
            amountConsumptionRate: BalanceAmountConsumptionRate(perHour: 0.5, perDay: 12.0, confidence: 1)
        )

        XCTAssertEqual(BalanceMenuBarExtraSupport.amountText(for: entry), "USD 3.50")
        XCTAssertEqual(BalanceMenuBarExtraSupport.burnRateText(for: entry), "USD 12.00/天")
        XCTAssertFalse(BalanceMenuBarExtraSupport.burnRateText(for: entry)?.contains("%") ?? true)
    }

    func testPendingBurnRateIsDeterministic() {
        let entry = BalanceValueEntry(label: "DeepSeek", currencyCode: "usd", amount: 3.5)

        XCTAssertEqual(BalanceMenuBarExtraSupport.burnRateText(for: entry), AppLocalization.text("balance.value.rate.pending"))

        let pendingEntry = BalanceValueEntry(
            label: "DeepSeek",
            currencyCode: "usd",
            amount: 3.5,
            amountConsumptionRate: BalanceAmountConsumptionRate(perHour: 0, perDay: 0, confidence: 0)
        )
        XCTAssertEqual(BalanceMenuBarExtraSupport.burnRateText(for: pendingEntry), AppLocalization.text("balance.value.rate.pending"))
    }
}
