import SwiftUI
import CodexTokenCostCore

struct SegmentFill: Equatable {
    let index: Int
    let ratio: Double
}

struct BalanceMinimalProviderTile: View {
    let snapshot: BalanceSnapshot
    let palette: TokenCostPalette
    let displayMode: BalanceDisplayMode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric private var secondaryFontSize: CGFloat = 9
    @ScaledMetric private var percentFontSize: CGFloat = 10
    @State private var hasAppeared = false

    private var displayedQuotaWindows: [QuotaWindowDisplay] {
        let unifiedWindows = snapshot.quotaWindows?.enumerated().compactMap { offset, window -> QuotaWindowDisplay? in
            guard let usedRatio = BalanceMinimalTileQuotaLayout.usedRatio(
                usedRatio: window.usedRatio,
                remainingRatio: window.remainingRatio
            ) else {
                return nil
            }

            return QuotaWindowDisplay(
                sourceIndex: offset,
                label: windowDisplayLabel(label: window.label, windowSeconds: window.windowSeconds),
                usedRatio: usedRatio,
                remainingRatio: window.remainingRatio,
                windowSeconds: window.windowSeconds,
                consumptionRate: window.consumptionRate
            )
        } ?? []

        if !unifiedWindows.isEmpty {
            return selectedQuotaWindows(from: unifiedWindows)
        }

        let legacyWindows = [
            QuotaWindowDisplay(sourceIndex: 0, label: snapshot.primaryWindowLabel, usedRatio: snapshot.primaryWindowUsagePercent, remainingRatio: nil),
            QuotaWindowDisplay(sourceIndex: 1, label: snapshot.secondaryWindowLabel, usedRatio: snapshot.secondaryWindowUsagePercent, remainingRatio: nil),
            QuotaWindowDisplay(sourceIndex: 2, label: snapshot.tertiaryWindowLabel, usedRatio: snapshot.tertiaryWindowUsagePercent, remainingRatio: nil),
            QuotaWindowDisplay(sourceIndex: 3, label: snapshot.gradient.label, usedRatio: snapshot.usagePercent, remainingRatio: nil)
        ]
        .compactMap { $0 }

        return legacyWindows.max(by: { $0.usedRatio < $1.usedRatio }).map { [$0] } ?? []
    }

    private var primaryValueEntry: BalanceValueEntry? {
        snapshot.valueEntries?.first { $0.amount.isFinite && !$0.amount.isNaN }
    }

    private var accessibilitySummary: String {
        if !snapshot.isAvailable {
            return unavailableAccessibilitySummary
        }

        let quotaWindows = displayedQuotaWindows
        if !quotaWindows.isEmpty {
            return quotaWindows
                .enumerated()
                .map { offset, window in
                    quotaWindowAccessibilitySummary(window: window, includesRate: offset == 0)
                }
                .joined(separator: " · ")
        }

        if let entry = primaryValueEntry {
            return monetaryAccessibilitySummary(entry)
        }

        if let cost = snapshot.totalCostUSD {
            return costAccessibilitySummary(cost: cost, avg: snapshot.avgCostPerDayUSD)
        }

        if let entries = snapshot.valueEntries, !entries.isEmpty {
            return entries
                .map { valueEntryAccessibilitySummary($0) }
                .joined(separator: " · ")
        }

        return AppLocalization.text("balance.unavailable")
    }

    private var unavailableAccessibilitySummary: String {
        var parts: [String] = [AppLocalization.text("balance.unavailable")]

        if let message = snapshot.errorMessage, !message.isEmpty {
            parts.append(message)
        }

        if let hint = snapshot.errorRecoveryHint, !hint.isEmpty {
            parts.append(hint)
        }

        if snapshot.errorRequiresReimport {
            parts.append(AppLocalization.text("balance.error.reimport"))
        }

        return parts.joined(separator: " · ")
    }

    var body: some View {
        tileContent
        .padding(BalanceFloatingPanelLayout.compactTilePadding)
        .frame(width: BalanceFloatingPanelLayout.minimalTileWidth, height: BalanceFloatingPanelLayout.minimalTileHeight, alignment: .center)
        .background {
            compactTileBackground()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(snapshot.provider.displayName))
        .accessibilityValue(Text(accessibilitySummary))
        .accessibilityHint(Text(accessibilitySummary))
        .help(accessibilitySummary)
        .onAppear { hasAppeared = true }
    }

    @ViewBuilder
    private var tileContent: some View {
        let quotaWindows = displayedQuotaWindows
        if snapshot.isAvailable, !quotaWindows.isEmpty {
            VStack(alignment: .center, spacing: 4) {
                header
                quotaProgressBody(windows: quotaWindows)
            }
        } else if snapshot.isAvailable, let entry = primaryValueEntry {
            VStack(alignment: .center, spacing: 4) {
                header
                valueEntryBody(entry)
            }
        } else if snapshot.isAvailable, let cost = snapshot.totalCostUSD {
            VStack(alignment: .center, spacing: 4) {
                header
                costBody(cost: cost, avg: snapshot.avgCostPerDayUSD)
            }
        } else if snapshot.isAvailable {
            header
                .frame(maxHeight: .infinity, alignment: .center)
        } else {
            unavailableBody
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            ProviderLogoMark(
                provider: snapshot.provider,
                size: BalanceFloatingPanelLayout.compactTileLogoSize,
                tint: palette.accent
            )
                .frame(
                    width: BalanceFloatingPanelLayout.compactTileLogoBackgroundSize - 6,
                    height: BalanceFloatingPanelLayout.compactTileLogoBackgroundSize - 6
                )
                .padding(3)
                .background(
                    Circle()
                        .fill(palette.accentSoft.opacity(0.72))
                )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func quotaProgressBody(windows: [QuotaWindowDisplay]) -> some View {
        ViewThatFits(in: .vertical) {
            VStack(alignment: .center, spacing: 3) {
                ForEach(windows) { window in
                    quotaProgressRow(window: window, isCompact: false)
                }
            }

            VStack(alignment: .center, spacing: 2) {
                ForEach(windows) { window in
                    quotaProgressRow(window: window, isCompact: true)
                }
            }
        }
    }

    private func quotaProgressRow(window: QuotaWindowDisplay, isCompact: Bool) -> some View {
        let usedRatio = window.clampedUsedRatio
        let displayRatioValue = BalanceMenuBarExtraSupport.displayRatio(for: usedRatio, displayMode: displayMode)
        let normalized = max(0, min(displayRatioValue, 1))
        let color = BalanceMenuBarExtraSupport.quotaColor(
            forDisplayRatio: normalized,
            displayMode: displayMode,
            palette: palette
        )
        let progressAnimation: Animation? = reduceMotion ? nil : (hasAppeared ? .easeOut(duration: 0.35) : nil)
        let segmentFills = BalanceMinimalTileQuotaLayout.segmentFills(for: normalized)

        return VStack(alignment: .center, spacing: isCompact ? 1 : 2) {
            Text(window.label)
                .font(.system(size: secondaryFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .frame(maxWidth: .infinity, alignment: .leading)
            .frame(width: BalanceMinimalTileQuotaLayout.defaultContentWidth)

            HStack(spacing: BalanceMinimalTileQuotaLayout.segmentGap) {
                ForEach(segmentFills, id: \.index) { segment in
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(palette.trackBackground.opacity(0.95))

                            Capsule(style: .continuous)
                                .fill(color)
                                .frame(width: hasAppeared ? geo.size.width * segment.ratio : 0)
                                .animation(progressAnimation, value: segment.ratio)
                        }
                    }
                    .frame(width: BalanceMinimalTileQuotaLayout.segmentWidth)
                }
            }
            .frame(
                width: BalanceMinimalTileQuotaLayout.defaultContentWidth,
                height: BalanceFloatingPanelLayout.trackHeight
            )
        }
        .frame(width: BalanceMinimalTileQuotaLayout.defaultContentWidth)
    }

    private func valueEntryBody(_ entry: BalanceValueEntry) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(BalanceMenuBarExtraSupport.amountText(for: entry))
                .font(.system(size: percentFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.title)
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            if let burnRateText = BalanceMenuBarExtraSupport.burnRateText(for: entry) {
                Text(burnRateText)
                    .font(.system(size: secondaryFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.accent.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
        }
    }

    private func costBody(cost: Double, avg: Double?) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(TokenCostFormatters.currency(cost))
                .font(.system(size: percentFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.title)
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            if let avg {
                Text(AppLocalization.format("balance.dailyAverage", TokenCostFormatters.currency(avg)))
                    .font(.system(size: secondaryFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.accent.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
        }
    }

    private var unavailableBody: some View {
        VStack(alignment: .center, spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)

            Text(AppLocalization.text("balance.unavailable"))
                .font(.system(size: secondaryFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(palette.subtitle)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func quotaWindowAccessibilitySummary(window: QuotaWindowDisplay, includesRate: Bool) -> String {
        let displayRatioValue = BalanceMenuBarExtraSupport.displayRatio(for: window.clampedUsedRatio, displayMode: displayMode)
        var parts = [
            window.label,
            BalanceMenuBarExtraSupport.displayModeLabel(for: displayMode),
            TokenCostFormatters.percent(min(max(displayRatioValue, 0), 1))
        ]

        if includesRate, let rateText = rateText(windowSeconds: window.windowSeconds, consumptionRate: window.consumptionRate) {
            parts.append(rateText)
        }

        return parts
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private func monetaryAccessibilitySummary(_ entry: BalanceValueEntry) -> String {
        var parts: [String] = [entry.label, BalanceMenuBarExtraSupport.amountText(for: entry)]

        if let burnText = BalanceMenuBarExtraSupport.burnRateText(for: entry) {
            parts.append(burnText)
        }

        if let granted = entry.grantedAmount {
            parts.append(AppLocalization.format("balance.value.grantedShort", String(format: "%.2f", granted)))
        }

        return parts.joined(separator: " · ")
    }

    private func costAccessibilitySummary(cost: Double, avg: Double?) -> String {
        var parts: [String] = [AppLocalization.format("balance.total90Days", TokenCostFormatters.currency(cost))]

        if let avg {
            parts.append(AppLocalization.format("balance.dailyAverage", TokenCostFormatters.currency(avg)))
        }

        return parts.joined(separator: " · ")
    }

    private func valueEntryAccessibilitySummary(_ entry: BalanceValueEntry) -> String {
        var parts: [String] = [entry.label, BalanceMenuBarExtraSupport.amountText(for: entry)]

        if let granted = entry.grantedAmount {
            parts.append(AppLocalization.format("balance.value.grantedShort", String(format: "%.2f", granted)))
        }

        return parts.joined(separator: " ")
    }

    private func compactTileBackground() -> some View {
        Group {
            if #available(macOS 26, *) {
                RoundedRectangle(cornerRadius: BalanceFloatingPanelLayout.compactTileCornerRadius, style: .continuous)
                    .fill(.clear)
                    .glassEffect(
                        .regular.tint(palette.accentSoft.opacity(0.72)),
                        in: .rect(cornerRadius: BalanceFloatingPanelLayout.compactTileCornerRadius)
                    )
            } else {
                RoundedRectangle(cornerRadius: BalanceFloatingPanelLayout.compactTileCornerRadius, style: .continuous)
                    .fill(palette.surfaceSolidFill.opacity(0.92))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: BalanceFloatingPanelLayout.compactTileCornerRadius, style: .continuous)
                .strokeBorder(palette.surfaceStroke.opacity(0.72), lineWidth: 0.8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BalanceFloatingPanelLayout.compactTileCornerRadius, style: .continuous)
                .strokeBorder(palette.surfaceAccessibleStroke.opacity(0.28), lineWidth: 0.5)
        )
        .shadow(
            color: palette.surfaceShadow.opacity(0.55),
            radius: BalanceFloatingPanelLayout.compactTileShadowRadius,
            x: 0,
            y: BalanceFloatingPanelLayout.compactTileShadowYOffset
        )
    }

    private func selectedQuotaWindows(from windows: [QuotaWindowDisplay]) -> [QuotaWindowDisplay] {
        guard let shortest = windows.sorted(by: quotaWindowLengthSort).first else { return [] }
        let highUsageWindow = windows
            .filter { $0.distinctKey != shortest.distinctKey && $0.usedRatio >= 0.80 }
            .max(by: quotaWindowUsageSort)

        if let highUsageWindow {
            return [shortest, highUsageWindow]
        }
        return [shortest]
    }

    private func quotaWindowLengthSort(_ lhs: QuotaWindowDisplay, _ rhs: QuotaWindowDisplay) -> Bool {
        switch (lhs.windowSeconds, rhs.windowSeconds) {
        case let (lhsSeconds?, rhsSeconds?) where lhsSeconds != rhsSeconds:
            return lhsSeconds < rhsSeconds
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.sourceIndex < rhs.sourceIndex
        }
    }

    private func quotaWindowUsageSort(_ lhs: QuotaWindowDisplay, _ rhs: QuotaWindowDisplay) -> Bool {
        if lhs.usedRatio != rhs.usedRatio {
            return lhs.usedRatio < rhs.usedRatio
        }
        return quotaWindowLengthSort(rhs, lhs)
    }

    private func rateText(windowSeconds: Int?, consumptionRate: ConsumptionRate?) -> String? {
        guard let rate = consumptionRate, rate.confidence > 0 else { return nil }

        if let windowSeconds, windowSeconds >= 86_400 {
            return AppLocalization.format("balance.rate.perDay", rate.perDay)
        }
        return AppLocalization.format("balance.rate.perHour", rate.perHour)
    }

    private func windowDisplayLabel(label: String, windowSeconds: Int?) -> String {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLabel.isEmpty {
            return trimmedLabel
        }

        return windowSeconds.map(windowDurationLabel) ?? snapshot.gradient.label
    }

    private func windowDurationLabel(seconds: Int) -> String {
        let day = 86_400
        let hour = 3_600

        if seconds >= day, seconds % day == 0 {
            return "\(seconds / day)d"
        }

        if seconds >= hour, seconds % hour == 0 {
            return "\(seconds / hour)h"
        }

        return "\(seconds)s"
    }

    private struct QuotaWindowDisplay: Identifiable {
        let sourceIndex: Int
        let label: String
        let usedRatio: Double
        let remainingRatio: Double?
        let windowSeconds: Int?
        let consumptionRate: ConsumptionRate?

        var id: String {
            "\(sourceIndex)-\(distinctKey)"
        }

        var distinctKey: String {
            "\(label.lowercased())-\(windowSeconds.map(String.init) ?? "nil")"
        }

        init?(sourceIndex: Int, label: String?, usedRatio: Double?, remainingRatio: Double?) {
            guard let usedRatio, usedRatio.isFinite, !usedRatio.isNaN else {
                return nil
            }

            let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.sourceIndex = sourceIndex
            self.label = trimmedLabel.isEmpty ? "Quota" : trimmedLabel
            self.usedRatio = usedRatio
            self.remainingRatio = remainingRatio
            self.windowSeconds = nil
            self.consumptionRate = nil
        }

        init(
            sourceIndex: Int,
            label: String,
            usedRatio: Double,
            remainingRatio: Double?,
            windowSeconds: Int?,
            consumptionRate: ConsumptionRate?
        ) {
            self.sourceIndex = sourceIndex
            self.label = label
            self.usedRatio = usedRatio
            self.remainingRatio = remainingRatio
            self.windowSeconds = windowSeconds
            self.consumptionRate = consumptionRate
        }

        var clampedUsedRatio: Double {
            min(max(usedRatio, 0), 1)
        }

        var clampedRemainingRatio: Double {
            if let remainingRatio, remainingRatio.isFinite, !remainingRatio.isNaN {
                return min(max(remainingRatio, 0), 1)
            }

            return min(max(1 - usedRatio, 0), 1)
        }
    }

}

enum BalanceMinimalTileQuotaLayout {
    static let segmentCount = 5
    static let segmentGap: CGFloat = 1

    static var defaultContentWidth: CGFloat {
        contentWidth(
            tileWidth: BalanceFloatingPanelLayout.minimalTileWidth,
            horizontalPadding: BalanceFloatingPanelLayout.compactTilePadding
        )
    }

    static var segmentWidth: CGFloat {
        let totalGapWidth = CGFloat(segmentCount - 1) * segmentGap
        return max(0, (defaultContentWidth - totalGapWidth) / CGFloat(segmentCount))
    }

    static func contentWidth(tileWidth: CGFloat, horizontalPadding: CGFloat) -> CGFloat {
        max(0, tileWidth - (horizontalPadding * 2))
    }

    static func usedRatio(usedRatio: Double?, remainingRatio: Double?) -> Double? {
        if let usedRatio, usedRatio.isFinite, !usedRatio.isNaN {
            return usedRatio
        }

        if let remainingRatio, remainingRatio.isFinite, !remainingRatio.isNaN {
            return 1.0 - remainingRatio
        }

        return nil
    }

    static func segmentFills(for progress: Double, segmentCount: Int = segmentCount) -> [SegmentFill] {
        guard segmentCount > 0 else { return [] }

        let clampedProgress = progress.isFinite ? min(max(progress, 0), 1) : 0
        let scaledProgress = clampedProgress * Double(segmentCount)

        return (0..<segmentCount).map { index in
            let ratio = min(max(scaledProgress - Double(index), 0), 1)
            return SegmentFill(index: index, ratio: ratio)
        }
    }
}
