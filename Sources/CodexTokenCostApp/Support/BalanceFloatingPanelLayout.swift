import SwiftUI
import CodexTokenCostCore

enum BalanceFloatingPanelLayout {
    static let panelDefaultSize = CGSize(width: 480, height: 320)
    static let panelMinimumSize = panelDefaultSize
    static let minimumPanelSize = panelMinimumSize

    static let minimalPanelMinimumWidth: CGFloat = 220
    static let minimalPanelMaximumWidth: CGFloat = 380
    static let minimalPanelTargetHeight: CGFloat = 156
    static let minimalTileWidth: CGFloat = 64
    static let minimalTileHeight: CGFloat = 100
    static let minimalTileSpacing: CGFloat = 8
    static let minimalPanelHeaderSpacing: CGFloat = 8
    static let minimalPanelButtonSize: CGFloat = 24
    static let panelActionButtonSize: CGFloat = 28
    static let minimalPanelTitleFontSize: CGFloat = 12

    static let panelOuterInset: CGFloat = 12
    static let contentPadding = panelOuterInset

    static let gridGap: CGFloat = 10
    static let tileSpacing = gridGap

    static let normalCardMinimumWidth: CGFloat = 210
    static let normalTileMinimumWidth = normalCardMinimumWidth
    static let minimalTileMinimumWidth = minimalTileWidth

    static let maximumColumnCount: Int = 4
    static let minimalMaximumColumnCount: Int = 5

    static let shellCornerRadius: CGFloat = 24
    static let shellStrokeWidth: CGFloat = 1
    static let sectionSpacing: CGFloat = 12
    static let headerSpacing: CGFloat = 12
    static let tileCornerRadius: CGFloat = 18
    static let tilePaddingNormal: CGFloat = 12
    static let tilePaddingMinimal: CGFloat = 10
    static let buttonSize: CGFloat = 28
    static let buttonCornerRadius: CGFloat = 9
    static let providerNameScaleFactor: CGFloat = 0.88
    static let criticalPercentFontSize: CGFloat = 12
    static let trackHeight: CGFloat = 6
    static let trackCornerRadius: CGFloat = 3

    static let compactTileCornerRadius: CGFloat = 14
    static let compactTilePadding: CGFloat = 8
    static let compactTileLogoBackgroundSize: CGFloat = 24
    static let compactTileLogoSize: CGFloat = 18
    static let compactTileRingSize: CGFloat = 54
    static let compactTileRingLineWidth: CGFloat = 5
    static let compactTileShadowRadius: CGFloat = 6
    static let compactTileShadowYOffset: CGFloat = 3

    static func usableWidth(for fullWidth: CGFloat) -> CGFloat {
        max(0, fullWidth - (contentPadding * 2))
    }

    static func normalColumnCount(fullWidth: CGFloat, providerCount: Int) -> Int {
        configuredColumnCount(fullWidth: fullWidth, providerCount: providerCount, displayMode: .normal)
    }

    static func minimalColumnCount(fullWidth: CGFloat, providerCount: Int) -> Int {
        configuredColumnCount(fullWidth: fullWidth, providerCount: providerCount, displayMode: .minimal)
    }

    static func columnCount(for width: CGFloat, providerCount: Int, displayMode: BalanceFloatingPanelDisplayMode) -> Int {
        configuredColumnCount(fullWidth: width, providerCount: providerCount, displayMode: displayMode)
    }

    static func columnCount(for displayMode: BalanceFloatingPanelDisplayMode, fullWidth: CGFloat, providerCount: Int) -> Int {
        configuredColumnCount(fullWidth: fullWidth, providerCount: providerCount, displayMode: displayMode)
    }

    static func panelSize(for displayMode: BalanceFloatingPanelDisplayMode, providerCount: Int) -> CGSize {
        switch displayMode {
        case .normal:
            return panelDefaultSize
        case .minimal:
            return minimalPanelSize(providerCount: providerCount)
        }
    }

    static func minimalPanelSize(providerCount: Int) -> CGSize {
        let cardCount = max(providerCount, 1)
        let contentWidth = (contentPadding * 2)
            + (CGFloat(cardCount) * minimalTileWidth)
            + (CGFloat(max(cardCount - 1, 0)) * minimalTileSpacing)

        return CGSize(
            width: min(max(contentWidth, minimalPanelMinimumWidth), minimalPanelMaximumWidth),
            height: minimalPanelTargetHeight
        )
    }

    static func gridColumns(
        for width: CGFloat,
        providerCount: Int,
        displayMode: BalanceFloatingPanelDisplayMode
    ) -> [GridItem] {
        let minimumWidth = displayMode == .minimal ? minimalTileMinimumWidth : normalTileMinimumWidth
        let spacing = displayMode == .minimal ? minimalTileSpacing : tileSpacing
        return Array(
            repeating: GridItem(.flexible(minimum: minimumWidth), spacing: spacing, alignment: .top),
            count: columnCount(for: width, providerCount: providerCount, displayMode: displayMode)
        )
    }

    static func currencyDensitySymbols(for snapshot: BalanceSnapshot) -> String {
        if let totalCostUSD = snapshot.totalCostUSD {
            return currencyDensitySymbols(forAmount: totalCostUSD, family: .usd)
        }

        guard let entry = firstDisplayableValueEntry(in: snapshot.valueEntries) else {
            return String(repeating: CurrencyFamily.fallback.glyph, count: 1)
        }

        return currencyDensitySymbols(for: entry)
    }

    static func currencyDensitySymbols(for valueEntries: [BalanceValueEntry]) -> String {
        guard let entry = firstDisplayableValueEntry(in: valueEntries) else {
            return String(repeating: CurrencyFamily.fallback.glyph, count: 1)
        }

        return currencyDensitySymbols(for: entry)
    }

    static func currencyDensitySummary(for snapshot: BalanceSnapshot) -> String {
        currencyDensitySymbols(for: snapshot)
    }

    static func currencyDensitySummary(for valueEntries: [BalanceValueEntry]) -> String {
        currencyDensitySymbols(for: valueEntries)
    }

    private static func configuredColumnCount(fullWidth: CGFloat, providerCount: Int, displayMode: BalanceFloatingPanelDisplayMode) -> Int {
        guard providerCount > 0 else { return 1 }

        let minimumWidth = displayMode == .minimal ? minimalTileMinimumWidth : normalTileMinimumWidth
        let spacing = displayMode == .minimal ? minimalTileSpacing : tileSpacing
        let maximumCount = displayMode == .minimal ? minimalMaximumColumnCount : maximumColumnCount
        let usableWidth = Self.usableWidth(for: fullWidth)
        let columnsThatFit = Int((usableWidth + spacing) / (minimumWidth + spacing))
        let widthBasedCount = max(1, min(maximumCount, columnsThatFit))

        return max(1, min(providerCount, widthBasedCount))
    }

    private static func firstDisplayableValueEntry(in entries: [BalanceValueEntry]?) -> BalanceValueEntry? {
        entries?.first { $0.amount.isFinite && !$0.amount.isNaN }
    }

    private static func currencyDensitySymbols(for entry: BalanceValueEntry) -> String {
        let family = currencyFamily(for: entry.currencyCode)
        let tier = entry.grantedAmount.flatMap { granted in
            Self.tier(forRemainingRatio: entry.amount / granted)
        } ?? Self.tier(forAmount: entry.amount, family: family)

        return String(repeating: family.glyph, count: tier)
    }

    private static func currencyDensitySymbols(forAmount amount: Double, family: CurrencyFamily) -> String {
        String(repeating: family.glyph, count: Self.tier(forAmount: amount, family: family))
    }

    private static func tier(forRemainingRatio ratio: Double) -> Int {
        guard ratio.isFinite else { return 1 }
        if ratio <= 0.33 { return 1 }
        if ratio <= 0.66 { return 2 }
        return 3
    }

    private static func tier(forAmount amount: Double, family: CurrencyFamily) -> Int {
        guard amount.isFinite, !amount.isNaN else { return 1 }

        switch family {
        case .usd:
            if amount < 10 { return 1 }
            if amount < 100 { return 2 }
            return 3
        case .cnyStyle:
            if amount < 100 { return 1 }
            if amount < 1000 { return 2 }
            return 3
        case .fallback:
            if amount < 10 { return 1 }
            if amount < 100 { return 2 }
            return 3
        }
    }

    private static func currencyFamily(for code: String?) -> CurrencyFamily {
        switch code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "USD":
            return .usd
        case "CNY", "RMB", "CNH", "JPY":
            return .cnyStyle
        case nil, "":
            return .fallback
        default:
            return .fallback
        }
    }

    private enum CurrencyFamily {
        case usd
        case cnyStyle
        case fallback

        var glyph: String {
            switch self {
            case .usd: return "$"
            case .cnyStyle: return "¥"
            case .fallback: return "¤"
            }
        }
    }

}
