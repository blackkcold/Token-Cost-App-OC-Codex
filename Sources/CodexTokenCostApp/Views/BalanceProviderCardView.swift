import SwiftUI
import CodexTokenCostCore

struct BalanceProviderCardView: View {
    let snapshot: BalanceSnapshot
    let palette: TokenCostPalette
    let displayMode: BalanceDisplayMode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric private var criticalPercentFontSize: CGFloat = 12
    @State private var hasAppeared = false

    private var cornerRadius: CGFloat {
        BalanceFloatingPanelLayout.tileCornerRadius
    }

    private var contentSpacing: CGFloat {
        BalanceFloatingPanelLayout.sectionSpacing
    }

    private var cardPadding: CGFloat {
        BalanceFloatingPanelLayout.tilePaddingNormal
    }

    private var stateLabel: String {
        if !snapshot.isAvailable {
            return AppLocalization.text("balance.unavailable")
        }
        if snapshot.usagePercent == nil && snapshot.totalCostUSD != nil {
            return AppLocalization.text("balance.balance")
        }
        if let windows = snapshot.quotaWindows, !windows.isEmpty {
            return snapshot.gradient.label
        }
        if snapshot.valueEntries?.isEmpty == false {
            return AppLocalization.text("balance.balance")
        }
        if snapshot.usagePercent != nil {
            return snapshot.gradient.label
        }
        return snapshot.planType ?? snapshot.provider.displayName
    }

    private var hasQuotaWindows: Bool {
        snapshot.quotaWindows?.isEmpty == false
    }

    private var hasLegacyWindows: Bool {
        snapshot.primaryWindowUsagePercent != nil
            || snapshot.secondaryWindowUsagePercent != nil
            || snapshot.tertiaryWindowUsagePercent != nil
    }

    private var showCostOnly: Bool {
        snapshot.usagePercent == nil && snapshot.totalCostUSD != nil
    }

    private var hasValueEntries: Bool {
        snapshot.valueEntries?.isEmpty == false
    }

    private var accessibilitySummary: String {
        if !snapshot.isAvailable {
            return unavailableAccessibilitySummary
        }

        if let windows = snapshot.quotaWindows, !windows.isEmpty {
            return windows
                .map { quotaWindowAccessibilitySummary(label: $0.label, window: $0) }
                .joined(separator: " · ")
        }

        if hasLegacyWindows {
            return legacyWindowsAccessibilitySummary
        }

        if let cost = snapshot.totalCostUSD {
            return costAccessibilitySummary(cost: cost, avg: snapshot.avgCostPerDayUSD)
        }

        if let entries = snapshot.valueEntries, !entries.isEmpty {
            return entries
                .map { valueEntryAccessibilitySummary($0) }
                .joined(separator: " · ")
        }

        if let pct = snapshot.usagePercent {
            return quotaWindowAccessibilitySummary(label: nil, usedRatio: pct)
        }

        return AppLocalization.text("balance.unavailable")
    }

    private var accessibilityHelp: String {
        accessibilitySummary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            header

            if snapshot.isAvailable {
                availableContent
            } else {
                unavailableContent
            }
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(BalanceProviderCardSurface(
            palette: palette,
            cornerRadius: cornerRadius
        ))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(snapshot.provider.displayName))
        .accessibilityValue(Text(accessibilitySummary))
        .accessibilityHint(Text(accessibilityHelp))
        .help(accessibilityHelp)
        .onAppear { hasAppeared = true }
    }

    @ViewBuilder
    private var header: some View {
        if palette.usesWorkshopStyle {
            HStack(alignment: .center, spacing: 11) {
                WorkshopBalanceProviderMark(
                    provider: snapshot.provider,
                    palette: palette,
                    size: 21,
                    plateSize: 38
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.provider.displayName.uppercased())
                        .font(TokenTypography.metric(size: 13, weight: .black, palette: palette))
                        .foregroundStyle(palette.title)
                        .lineLimit(1)
                        .minimumScaleFactor(BalanceFloatingPanelLayout.providerNameScaleFactor)

                    if let planType = snapshot.planType, !planType.isEmpty {
                        Text(planType)
                            .font(TokenTypography.caption2(weight: .semibold, palette: palette))
                            .foregroundStyle(palette.subtitle)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                WorkshopBalanceStatusStamp(
                    title: stateLabel,
                    tint: workshopStateTint,
                    palette: palette
                )
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                ProviderLogoMark(provider: snapshot.provider, size: 22, tint: palette.accent)
                    .frame(width: 28, height: 28)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(palette.accentSoft)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(snapshot.provider.displayName)
                            .font(TokenTypography.headline(weight: .bold, palette: palette))
                            .foregroundStyle(palette.title)
                            .lineLimit(1)
                            .minimumScaleFactor(BalanceFloatingPanelLayout.providerNameScaleFactor)

                        Spacer(minLength: 8)

                        Text(stateLabel)
                            .font(TokenTypography.caption2(weight: .bold, palette: palette))
                            .foregroundStyle(snapshot.isAvailable ? palette.accent : .red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill((snapshot.isAvailable ? palette.accent : Color.red).opacity(0.12))
                            )
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var workshopStateTint: Color {
        guard snapshot.isAvailable else { return palette.danger }

        switch snapshot.gradient {
        case .unused, .low:
            return palette.accentSecondary
        case .moderate, .high:
            return palette.warning
        case .critical, .exceeded:
            return palette.danger
        case .unknown:
            return palette.accent
        }
    }

    @ViewBuilder
    private var availableContent: some View {
        if hasQuotaWindows, let windows = snapshot.quotaWindows {
            quotaWindowsView(windows)
        } else if hasLegacyWindows {
            legacyWindowsView
        } else if showCostOnly {
            costOnlyView
        } else if hasValueEntries {
            valueEntriesView
        } else if let pct = snapshot.usagePercent {
            usageView(pct: pct)
        } else {
            fallbackEmptyView
        }
    }

    @ViewBuilder
    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if palette.usesWorkshopStyle {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.black))
                    Text(AppLocalization.text("balance.unavailable").uppercased())
                        .font(TokenTypography.caption2(weight: .black, palette: palette))
                }
                .foregroundStyle(palette.danger)
            }

            if let message = snapshot.errorMessage, !message.isEmpty {
                Text(message)
                    .font(TokenTypography.caption(weight: palette.usesWorkshopStyle ? .semibold : .regular, palette: palette))
                    .foregroundStyle(palette.title)
                    .lineLimit(2)
            }

            if let hint = snapshot.errorRecoveryHint, !hint.isEmpty {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
                    .lineLimit(2)
            }

            if snapshot.errorRequiresReimport {
                Text(AppLocalization.text("balance.error.reimport"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(palette.accentSoft)
                    )
                    .lineLimit(1)
            }
        }
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

    private func quotaWindowsView(_ windows: [BalanceQuotaWindow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(windows) { window in
                quotaWindowRow(
                    label: window.label,
                    usedRatio: window.usedRatio,
                    remainingRatio: window.remainingRatio,
                    resetAt: window.resetAt,
                    windowSeconds: window.windowSeconds,
                    consumptionRate: window.consumptionRate
                )
            }
        }
    }

    private var legacyWindowsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let pct = snapshot.primaryWindowUsagePercent {
                quotaWindowRow(label: snapshot.primaryWindowLabel, usedRatio: pct, remainingRatio: nil, resetAt: snapshot.primaryWindowResetAt)
            }
            if let pct = snapshot.secondaryWindowUsagePercent {
                quotaWindowRow(label: snapshot.secondaryWindowLabel, usedRatio: pct, remainingRatio: nil, resetAt: snapshot.secondaryWindowResetAt)
            }
            if let pct = snapshot.tertiaryWindowUsagePercent {
                quotaWindowRow(label: snapshot.tertiaryWindowLabel, usedRatio: pct, remainingRatio: nil, resetAt: snapshot.tertiaryWindowResetAt)
            }
        }
    }

    private var costOnlyView: some View {
        Group {
            if palette.usesWorkshopStyle {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let cost = snapshot.totalCostUSD {
                            Text(AppLocalization.format("balance.total90Days", TokenCostFormatters.currency(cost)))
                                .font(TokenTypography.metric(size: 13, weight: .black, palette: palette))
                                .foregroundStyle(palette.title)
                                .lineLimit(2)
                        }

                        if let avg = snapshot.avgCostPerDayUSD {
                            Text(AppLocalization.format("balance.dailyAverage", TokenCostFormatters.currency(avg)))
                                .font(TokenTypography.caption2(weight: .semibold, palette: palette))
                                .foregroundStyle(palette.subtitle)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 4)

                    WorkshopBalanceCurrencyStamp(
                        symbols: BalanceFloatingPanelLayout.currencyDensitySymbols(for: snapshot),
                        palette: palette
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if let cost = snapshot.totalCostUSD {
                        Text(AppLocalization.format("balance.total90Days", TokenCostFormatters.currency(cost)))
                            .font(.callout)
                            .foregroundStyle(palette.title)
                            .lineLimit(2)
                    }

                    if let avg = snapshot.avgCostPerDayUSD {
                        Text(AppLocalization.format("balance.dailyAverage", TokenCostFormatters.currency(avg)))
                            .font(.caption)
                            .foregroundStyle(palette.subtitle)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private var valueEntriesView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let entries = snapshot.valueEntries {
                ForEach(entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if palette.usesWorkshopStyle {
                            Rectangle()
                                .fill(palette.accent)
                                .frame(width: 4, height: 26)
                                .accessibilityHidden(true)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.label)
                                .font(TokenTypography.caption(
                                    weight: palette.usesWorkshopStyle ? .bold : .medium,
                                    palette: palette
                                ))
                                .foregroundStyle(palette.title)
                                .lineLimit(2)

                            if let currencyCode = entry.currencyCode, !currencyCode.isEmpty {
                                Text(currencyCode)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(palette.subtitle)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 8)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(BalanceMenuBarExtraSupport.amountText(for: entry))
                                .font(TokenTypography.caption(
                                    weight: palette.usesWorkshopStyle ? .black : .semibold,
                                    palette: palette
                                ))
                                .foregroundStyle(palette.usesWorkshopStyle ? palette.title : palette.accent)

                            if let burnRateText = BalanceMenuBarExtraSupport.burnRateText(for: entry) {
                                Text(burnRateText)
                                    .font(.caption2)
                                    .foregroundStyle(palette.accent.opacity(0.8))
                                    .lineLimit(1)
                            }

                            if let granted = entry.grantedAmount {
                                Text(AppLocalization.format("balance.value.grantedShort", String(format: "%.2f", granted)))
                                    .font(.caption2)
                                    .foregroundStyle(palette.subtitle)
                            }
                        }

                        if palette.usesWorkshopStyle {
                            WorkshopBalanceCurrencyStamp(
                                symbols: BalanceFloatingPanelLayout.currencyDensitySymbols(for: [entry]),
                                palette: palette
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func usageView(pct: Double) -> some View {
        quotaWindowRow(label: nil, usedRatio: pct, remainingRatio: nil, resetAt: nil)
    }

    private var fallbackEmptyView: some View {
        Text(AppLocalization.text("common.unavailable"))
            .font(.caption)
            .foregroundStyle(palette.subtitle)
    }

    private func quotaWindowAccessibilitySummary(label: String?, window: BalanceQuotaWindow) -> String {
        let usedRatio = window.usedRatio ?? (window.remainingRatio.map { 1.0 - $0 }) ?? 0
        return quotaWindowAccessibilitySummary(label: label, usedRatio: usedRatio)
    }

    private func quotaWindowAccessibilitySummary(label: String?, usedRatio: Double) -> String {
        let ratio = BalanceMenuBarExtraSupport.displayRatio(for: usedRatio, displayMode: displayMode)
        return quotaWindowAccessibilitySummary(label: label, displayRatio: ratio)
    }

    private func quotaWindowAccessibilitySummary(label: String?, displayRatio: Double) -> String {
        [
            label,
            BalanceMenuBarExtraSupport.displayModeLabel(for: displayMode),
            TokenCostFormatters.percent(min(max(displayRatio, 0), 1))
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private var legacyWindowsAccessibilitySummary: String {
        var parts: [String] = []

        if let pct = snapshot.primaryWindowUsagePercent {
            parts.append(quotaWindowAccessibilitySummary(label: snapshot.primaryWindowLabel, usedRatio: pct))
        }
        if let pct = snapshot.secondaryWindowUsagePercent {
            parts.append(quotaWindowAccessibilitySummary(label: snapshot.secondaryWindowLabel, usedRatio: pct))
        }
        if let pct = snapshot.tertiaryWindowUsagePercent {
            parts.append(quotaWindowAccessibilitySummary(label: snapshot.tertiaryWindowLabel, usedRatio: pct))
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
        var parts: [String] = [entry.label]

        if let currencyCode = entry.currencyCode, !currencyCode.isEmpty {
            parts.append(String(format: "%.2f %@", entry.amount, currencyCode.uppercased()))
        } else {
            parts.append(String(format: "%.2f", entry.amount))
        }

        if let burnRateText = BalanceMenuBarExtraSupport.burnRateAccessibilityText(for: entry) {
            parts.append(burnRateText)
        }

        if let granted = entry.grantedAmount {
            parts.append(AppLocalization.format("balance.value.grantedShort", String(format: "%.2f", granted)))
        }

        return parts.joined(separator: " ")
    }

    private func quotaWindowRow(
        label: String?,
        usedRatio: Double?,
        remainingRatio: Double?,
        resetAt: Date?,
        windowSeconds: Int? = nil,
        consumptionRate: ConsumptionRate? = nil
    ) -> some View {
        let displayRatioValue: Double
        if let used = usedRatio {
            displayRatioValue = BalanceMenuBarExtraSupport.displayRatio(for: used, displayMode: displayMode)
        } else if let remaining = remainingRatio {
            displayRatioValue = BalanceMenuBarExtraSupport.displayRatio(for: 1.0 - remaining, displayMode: displayMode)
        } else {
            displayRatioValue = 0
        }
        let normalizedPct = max(0, min(displayRatioValue, 1))
        let color = BalanceMenuBarExtraSupport.quotaColor(
            forDisplayRatio: normalizedPct,
            displayMode: displayMode,
            palette: palette
        )
        let countdownText = countdownText(resetAt: resetAt, windowSeconds: windowSeconds)
        let rateText = rateText(windowSeconds: windowSeconds, consumptionRate: consumptionRate)
        let showPending = consumptionRate == nil || consumptionRate?.confidence == 0

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let label, !label.isEmpty {
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(palette.subtitle)
                        .frame(minWidth: 36, alignment: .leading)
                }

                if palette.usesWorkshopStyle {
                    WorkshopBalanceQuotaMeter(
                        value: normalizedPct,
                        tint: color,
                        palette: palette,
                        segmentCount: BalanceWorkshopChartLayout.normalSegmentCount,
                        height: 9
                    )
                    .frame(height: 9)
                } else {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(palette.trackBackground.opacity(0.95))
                                .frame(height: 6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .strokeBorder(palette.surfaceAccessibleStroke.opacity(0.42), lineWidth: 0.7)
                                )

                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(color)
                                .frame(width: geo.size.width * normalizedPct, height: 6)
                                .animation(reduceMotion ? nil : (hasAppeared ? .easeOut(duration: 0.3) : nil), value: normalizedPct)
                        }
                    }
                    .frame(height: 6)
                }

                Text(TokenCostFormatters.percent(normalizedPct))
                    .font(TokenTypography.metric(
                        size: criticalPercentFontSize,
                        weight: palette.usesWorkshopStyle ? .black : .semibold,
                        palette: palette
                    ))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(palette.usesWorkshopStyle ? color : palette.subtitle)
                    .frame(width: 44, alignment: .trailing)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    if let countdownText {
                        Text(countdownText)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(palette.subtitle.opacity(0.8))
                            .lineLimit(1)
                    }

                    if let rateText {
                        Text(rateText)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(palette.accent.opacity(0.8))
                            .lineLimit(1)
                    } else if showPending {
                        Text(AppLocalization.text("balance.rate.pending"))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(palette.subtitle.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                .padding(.leading, label != nil ? 42 : 0)

                EmptyView()
            }
        }
    }

    private func countdownText(resetAt: Date?, windowSeconds: Int?) -> String? {
        guard let resetAt, windowSeconds != nil else { return nil }

        let remaining = max(0, resetAt.timeIntervalSinceNow)
        if remaining <= 0 {
            return AppLocalization.text("balance.rate.countdownSoon")
        }
        if remaining < 60 {
            return "<1m"
        }

        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 {
            return AppLocalization.format("balance.rate.countdown", "\(hours)h\(minutes)m")
        }
        return AppLocalization.format("balance.rate.countdown", "\(minutes)m")
    }

    private func rateText(windowSeconds: Int?, consumptionRate: ConsumptionRate?) -> String? {
        guard let rate = consumptionRate, rate.confidence > 0 else { return nil }

        if let windowSeconds, windowSeconds >= 86_400 {
            return AppLocalization.format("balance.rate.perDay", rate.perDay)
        }
        return AppLocalization.format("balance.rate.perHour", rate.perHour)
    }
}

private struct BalanceProviderCardSurface: ViewModifier {
    let palette: TokenCostPalette
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if palette.usesWorkshopStyle {
            content.background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.surfaceSecondarySolidFill.opacity(0.92))
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 4) {
                            Rectangle()
                                .fill(palette.accent)
                                .frame(width: 46, height: 5)
                            Rectangle()
                                .fill(palette.accentSecondary)
                                .frame(width: 22, height: 5)
                        }
                        .padding(.leading, 12)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(palette.surfaceAccessibleStroke, lineWidth: 2.2)
                    )
                    .shadow(color: palette.surfaceShadow.opacity(0.72), radius: 0, x: 4, y: 4)
            }
        } else {
            content.modifier(LiquidGlassTileBackground(
                palette: palette,
                cornerRadius: cornerRadius,
                accentSoft: palette.accentSoft
            ))
        }
    }
}
