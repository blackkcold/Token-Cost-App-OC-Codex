import XCTest
@testable import CodexTokenCostApp
@testable import CodexTokenCostCore

final class BalanceFloatingPanelLayoutTests: XCTestCase {
    func testPanelConstantsMatchConfirmedSpec() {
        XCTAssertEqual(BalanceFloatingPanelLayout.panelDefaultSize, CGSize(width: 480, height: 320))
        XCTAssertEqual(BalanceFloatingPanelLayout.panelMinimumSize, CGSize(width: 480, height: 320))
        XCTAssertEqual(BalanceFloatingPanelLayout.minimumPanelSize, CGSize(width: 480, height: 320))
        XCTAssertEqual(BalanceFloatingPanelLayout.minimalPanelMinimumWidth, 220)
        XCTAssertEqual(BalanceFloatingPanelLayout.minimalPanelMaximumWidth, 380)
        XCTAssertEqual(BalanceFloatingPanelLayout.minimalPanelTargetHeight, 156)
        XCTAssertEqual(BalanceFloatingPanelLayout.panelOuterInset, 12)
        XCTAssertEqual(BalanceFloatingPanelLayout.contentPadding, 12)
        XCTAssertEqual(BalanceFloatingPanelLayout.gridGap, 10)
        XCTAssertEqual(BalanceFloatingPanelLayout.tileSpacing, 10)
        XCTAssertEqual(BalanceFloatingPanelLayout.normalCardMinimumWidth, 210)
        XCTAssertEqual(BalanceFloatingPanelLayout.normalTileMinimumWidth, 210)
        XCTAssertEqual(BalanceFloatingPanelLayout.minimalTileMinimumWidth, 64)
        XCTAssertEqual(BalanceFloatingPanelLayout.minimalTileHeight, 100)
        XCTAssertEqual(BalanceFloatingPanelLayout.minimalTileSpacing, 8)
    }

    func testResponsiveColumnCountsRespectUsableWidthAndProviderFloor() {
        XCTAssertEqual(BalanceFloatingPanelLayout.usableWidth(for: 480), 456)
        XCTAssertEqual(BalanceFloatingPanelLayout.usableWidth(for: 320), 296)

        XCTAssertEqual(BalanceFloatingPanelLayout.normalColumnCount(fullWidth: 480, providerCount: 5), 2)
        XCTAssertEqual(BalanceFloatingPanelLayout.minimalColumnCount(fullWidth: 320, providerCount: 5), 4)

        XCTAssertEqual(BalanceFloatingPanelLayout.normalColumnCount(fullWidth: 893, providerCount: 5), 3)
        XCTAssertEqual(BalanceFloatingPanelLayout.normalColumnCount(fullWidth: 894, providerCount: 5), 4)

        XCTAssertEqual(BalanceFloatingPanelLayout.minimalColumnCount(fullWidth: 380, providerCount: 5), 5)

        XCTAssertEqual(BalanceFloatingPanelLayout.normalColumnCount(fullWidth: 1600, providerCount: 1), 1)
        XCTAssertEqual(BalanceFloatingPanelLayout.minimalColumnCount(fullWidth: 1600, providerCount: 0), 1)

        XCTAssertEqual(BalanceFloatingPanelLayout.columnCount(for: 480, providerCount: 5, displayMode: .normal), 2)
        XCTAssertEqual(BalanceFloatingPanelLayout.columnCount(for: 320, providerCount: 5, displayMode: .minimal), 4)
        XCTAssertEqual(BalanceFloatingPanelLayout.gridColumns(for: 894, providerCount: 5, displayMode: .normal).count, 4)
        XCTAssertEqual(BalanceFloatingPanelLayout.gridColumns(for: 380, providerCount: 5, displayMode: .minimal).count, 5)
    }

    func testPanelSizeTracksDisplayModeAndProviderCount() {
        XCTAssertEqual(BalanceFloatingPanelLayout.panelSize(for: .normal, providerCount: 0), CGSize(width: 480, height: 320))
        XCTAssertEqual(BalanceFloatingPanelLayout.panelSize(for: .normal, providerCount: 5), CGSize(width: 480, height: 320))

        XCTAssertEqual(BalanceFloatingPanelLayout.panelSize(for: .minimal, providerCount: 0), CGSize(width: 220, height: 156))
        XCTAssertEqual(BalanceFloatingPanelLayout.panelSize(for: .minimal, providerCount: 1), CGSize(width: 220, height: 156))
        XCTAssertEqual(BalanceFloatingPanelLayout.panelSize(for: .minimal, providerCount: 2), CGSize(width: 220, height: 156))
        XCTAssertEqual(BalanceFloatingPanelLayout.panelSize(for: .minimal, providerCount: 3), CGSize(width: 232, height: 156))
        XCTAssertEqual(BalanceFloatingPanelLayout.panelSize(for: .minimal, providerCount: 4), CGSize(width: 304, height: 156))
        XCTAssertEqual(BalanceFloatingPanelLayout.panelSize(for: .minimal, providerCount: 5), CGSize(width: 376, height: 156))
        XCTAssertEqual(BalanceFloatingPanelLayout.panelSize(for: .minimal, providerCount: 8), CGSize(width: 380, height: 156))
    }

    func testMinimalQuotaTrackUsesFullTileContentWidth() {
        XCTAssertEqual(BalanceMinimalTileQuotaLayout.defaultContentWidth, 48)
        XCTAssertEqual(
            BalanceMinimalTileQuotaLayout.contentWidth(
                tileWidth: BalanceFloatingPanelLayout.minimalTileWidth,
                horizontalPadding: BalanceFloatingPanelLayout.compactTilePadding
            ),
            48
        )
        XCTAssertEqual(BalanceFloatingPanelLayout.trackHeight, 6)
        XCTAssertEqual(BalanceMinimalTileQuotaLayout.segmentCount, 5)
        XCTAssertEqual(BalanceMinimalTileQuotaLayout.segmentGap, 1)
        XCTAssertEqual(BalanceMinimalTileQuotaLayout.segmentWidth, 8.8, accuracy: 0.000_001)
    }

    func testMinimalQuotaSegmentFillsZeroAndBoundaries() {
        XCTAssertEqual(
            BalanceMinimalTileQuotaLayout.segmentFills(for: 0),
            [
                SegmentFill(index: 0, ratio: 0),
                SegmentFill(index: 1, ratio: 0),
                SegmentFill(index: 2, ratio: 0),
                SegmentFill(index: 3, ratio: 0),
                SegmentFill(index: 4, ratio: 0)
            ]
        )

        XCTAssertEqual(
            BalanceMinimalTileQuotaLayout.segmentFills(for: 0.2),
            [
                SegmentFill(index: 0, ratio: 1),
                SegmentFill(index: 1, ratio: 0),
                SegmentFill(index: 2, ratio: 0),
                SegmentFill(index: 3, ratio: 0),
                SegmentFill(index: 4, ratio: 0)
            ]
        )

        XCTAssertEqual(
            BalanceMinimalTileQuotaLayout.segmentFills(for: 0.4),
            [
                SegmentFill(index: 0, ratio: 1),
                SegmentFill(index: 1, ratio: 1),
                SegmentFill(index: 2, ratio: 0),
                SegmentFill(index: 3, ratio: 0),
                SegmentFill(index: 4, ratio: 0)
            ]
        )

        XCTAssertEqual(
            BalanceMinimalTileQuotaLayout.segmentFills(for: 0.8),
            [
                SegmentFill(index: 0, ratio: 1),
                SegmentFill(index: 1, ratio: 1),
                SegmentFill(index: 2, ratio: 1),
                SegmentFill(index: 3, ratio: 1),
                SegmentFill(index: 4, ratio: 0)
            ]
        )
    }

    func testMinimalQuotaSegmentFillsPreservePartialProgress() {
        let fills = BalanceMinimalTileQuotaLayout.segmentFills(for: 0.67)

        XCTAssertEqual(fills.count, 5)
        XCTAssertEqual(fills[0], SegmentFill(index: 0, ratio: 1))
        XCTAssertEqual(fills[1], SegmentFill(index: 1, ratio: 1))
        XCTAssertEqual(fills[2], SegmentFill(index: 2, ratio: 1))
        XCTAssertEqual(fills[3].index, 3)
        XCTAssertEqual(fills[3].ratio, 0.35, accuracy: 0.000_001)
        XCTAssertEqual(fills[4], SegmentFill(index: 4, ratio: 0))
    }

    func testMinimalQuotaSegmentFillsFullAndClamping() {
        let full = [
            SegmentFill(index: 0, ratio: 1),
            SegmentFill(index: 1, ratio: 1),
            SegmentFill(index: 2, ratio: 1),
            SegmentFill(index: 3, ratio: 1),
            SegmentFill(index: 4, ratio: 1)
        ]
        let empty = [
            SegmentFill(index: 0, ratio: 0),
            SegmentFill(index: 1, ratio: 0),
            SegmentFill(index: 2, ratio: 0),
            SegmentFill(index: 3, ratio: 0),
            SegmentFill(index: 4, ratio: 0)
        ]

        XCTAssertEqual(BalanceMinimalTileQuotaLayout.segmentFills(for: 1), full)
        XCTAssertEqual(BalanceMinimalTileQuotaLayout.segmentFills(for: 1.8), full)
        XCTAssertEqual(BalanceMinimalTileQuotaLayout.segmentFills(for: -0.3), empty)
        XCTAssertEqual(BalanceMinimalTileQuotaLayout.segmentFills(for: .nan), empty)
        XCTAssertEqual(BalanceMinimalTileQuotaLayout.segmentFills(for: .infinity), empty)
    }

    func testMinimalQuotaRatioFallsBackFromRemainingForDisplayOnly() {
        XCTAssertEqual(BalanceMinimalTileQuotaLayout.usedRatio(usedRatio: 0.42, remainingRatio: 0.9), 0.42)
        XCTAssertEqual(BalanceMinimalTileQuotaLayout.usedRatio(usedRatio: nil, remainingRatio: 0.25), 0.75)
        XCTAssertEqual(BalanceMinimalTileQuotaLayout.usedRatio(usedRatio: .nan, remainingRatio: 0.4), 0.6)
        XCTAssertNil(BalanceMinimalTileQuotaLayout.usedRatio(usedRatio: nil, remainingRatio: nil))
        XCTAssertNil(BalanceMinimalTileQuotaLayout.usedRatio(usedRatio: .infinity, remainingRatio: .nan))
    }

    func testWorkshopChartNormalizationClampsAndRejectsNonFiniteValues() {
        XCTAssertEqual(BalanceWorkshopChartLayout.normalized(-0.2), 0)
        XCTAssertEqual(BalanceWorkshopChartLayout.normalized(0.42), 0.42)
        XCTAssertEqual(BalanceWorkshopChartLayout.normalized(1.4), 1)
        XCTAssertEqual(BalanceWorkshopChartLayout.normalized(.nan), 0)
        XCTAssertEqual(BalanceWorkshopChartLayout.normalized(.infinity), 0)
    }

    func testWorkshopChartSegmentFillsUseNormalAndCompactDensities() {
        let normal = BalanceWorkshopChartLayout.segmentFills(
            for: 0.36,
            segmentCount: BalanceWorkshopChartLayout.normalSegmentCount
        )
        XCTAssertEqual(normal.count, 10)
        XCTAssertEqual(normal[0], SegmentFill(index: 0, ratio: 1))
        XCTAssertEqual(normal[1], SegmentFill(index: 1, ratio: 1))
        XCTAssertEqual(normal[2], SegmentFill(index: 2, ratio: 1))
        XCTAssertEqual(normal[3].index, 3)
        XCTAssertEqual(normal[3].ratio, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(normal[4], SegmentFill(index: 4, ratio: 0))

        let compact = BalanceWorkshopChartLayout.segmentFills(
            for: 0.5,
            segmentCount: BalanceWorkshopChartLayout.compactSegmentCount
        )
        XCTAssertEqual(compact.count, 5)
        XCTAssertEqual(compact[0], SegmentFill(index: 0, ratio: 1))
        XCTAssertEqual(compact[1], SegmentFill(index: 1, ratio: 1))
        XCTAssertEqual(compact[2], SegmentFill(index: 2, ratio: 0.5))
        XCTAssertEqual(compact[3], SegmentFill(index: 3, ratio: 0))
        XCTAssertEqual(compact[4], SegmentFill(index: 4, ratio: 0))
    }

    func testWorkshopChartSegmentFillsHandleInvalidCountAndBounds() {
        XCTAssertTrue(BalanceWorkshopChartLayout.segmentFills(for: 0.5, segmentCount: 0).isEmpty)

        let full = BalanceWorkshopChartLayout.segmentFills(for: 2, segmentCount: 3)
        XCTAssertEqual(full, [
            SegmentFill(index: 0, ratio: 1),
            SegmentFill(index: 1, ratio: 1),
            SegmentFill(index: 2, ratio: 1)
        ])

        let empty = BalanceWorkshopChartLayout.segmentFills(for: -.infinity, segmentCount: 3)
        XCTAssertEqual(empty, [
            SegmentFill(index: 0, ratio: 0),
            SegmentFill(index: 1, ratio: 0),
            SegmentFill(index: 2, ratio: 0)
        ])
    }

    func testCurrencyDensitySymbolsAreAmountTiered() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let lowCostSnapshot = BalanceSnapshot(
            provider: .codex,
            fetchedAt: baseDate,
            isAvailable: true,
            totalCostUSD: 3
        )

        let midCostSnapshot = BalanceSnapshot(
            provider: .codex,
            fetchedAt: baseDate,
            isAvailable: true,
            totalCostUSD: 25
        )

        let highCostSnapshot = BalanceSnapshot(
            provider: .codex,
            fetchedAt: baseDate,
            isAvailable: true,
            totalCostUSD: 250
        )

        XCTAssertEqual(BalanceFloatingPanelLayout.currencyDensitySymbols(for: lowCostSnapshot), "$")
        XCTAssertEqual(BalanceFloatingPanelLayout.currencyDensitySymbols(for: midCostSnapshot), "$$")
        XCTAssertEqual(BalanceFloatingPanelLayout.currencyDensitySymbols(for: highCostSnapshot), "$$$")

        XCTAssertEqual(BalanceFloatingPanelLayout.currencyDensitySummary(for: lowCostSnapshot), "$")
        XCTAssertEqual(BalanceFloatingPanelLayout.currencyDensitySummary(for: BalanceSnapshot(provider: .codex, fetchedAt: baseDate, isAvailable: true)), "¤")

        let usdLow = BalanceFloatingPanelLayout.currencyDensitySymbols(for: [
            BalanceValueEntry(label: "USD", currencyCode: "usd", amount: 3)
        ])
        XCTAssertEqual(usdLow, "$")

        let usdMid = BalanceFloatingPanelLayout.currencyDensitySymbols(for: [
            BalanceValueEntry(label: "USD", currencyCode: "usd", amount: 25)
        ])
        XCTAssertEqual(usdMid, "$$")

        let usdHigh = BalanceFloatingPanelLayout.currencyDensitySymbols(for: [
            BalanceValueEntry(label: "USD", currencyCode: "usd", amount: 250)
        ])
        XCTAssertEqual(usdHigh, "$$$")

        let cnyLow = BalanceFloatingPanelLayout.currencyDensitySymbols(for: [
            BalanceValueEntry(label: "CNY", currencyCode: "cny", amount: 30)
        ])
        XCTAssertEqual(cnyLow, "¥")

        let cnyMid = BalanceFloatingPanelLayout.currencyDensitySymbols(for: [
            BalanceValueEntry(label: "CNY", currencyCode: "cny", amount: 300)
        ])
        XCTAssertEqual(cnyMid, "¥¥")

        let cnyHigh = BalanceFloatingPanelLayout.currencyDensitySymbols(for: [
            BalanceValueEntry(label: "JPY", currencyCode: "jpy", amount: 3_000)
        ])
        XCTAssertEqual(cnyHigh, "¥¥¥")

        let grantedLow = BalanceFloatingPanelLayout.currencyDensitySymbols(for: [
            BalanceValueEntry(label: "granted-low", currencyCode: "usd", amount: 20, grantedAmount: 100)
        ])
        let grantedMid = BalanceFloatingPanelLayout.currencyDensitySymbols(for: [
            BalanceValueEntry(label: "granted-mid", currencyCode: "usd", amount: 50, grantedAmount: 100)
        ])
        let grantedHigh = BalanceFloatingPanelLayout.currencyDensitySymbols(for: [
            BalanceValueEntry(label: "granted-high", currencyCode: "usd", amount: 90, grantedAmount: 100)
        ])
        XCTAssertEqual(grantedLow, "$")
        XCTAssertEqual(grantedMid, "$$")
        XCTAssertEqual(grantedHigh, "$$$")

        let firstDisplayableOnly = BalanceFloatingPanelLayout.currencyDensitySymbols(for: [
            BalanceValueEntry(label: "missing-code", currencyCode: nil, amount: 250),
            BalanceValueEntry(label: "later-usd", currencyCode: "usd", amount: 3)
        ])
        XCTAssertEqual(firstDisplayableOnly, "¤¤¤")

        let emptyEntries = BalanceFloatingPanelLayout.currencyDensitySymbols(for: [])
        XCTAssertEqual(emptyEntries, "¤")

        for label in [
            "$$$",
            usdLow,
            usdMid,
            usdHigh,
            cnyLow,
            cnyMid,
            cnyHigh,
            grantedLow,
            grantedMid,
            grantedHigh,
            firstDisplayableOnly,
            emptyEntries
        ] {
            XCTAssertFalse(label.contains("%"))
            XCTAssertFalse(label.localizedCaseInsensitiveContains("healthy"))
        }
    }
}
