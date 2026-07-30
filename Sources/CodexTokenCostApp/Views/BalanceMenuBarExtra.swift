import SwiftUI
import CodexTokenCostCore

struct BalanceMenuBarExtraSelection: Equatable {
    enum Kind: Equatable {
        case empty
        case unavailable
        case quota
        case amount
    }

    enum Tone: Equatable {
        case neutral
        case low
        case moderate
        case high
        case critical
        case unavailable
    }

    let kind: Kind
    let titleText: String
    let valueText: String
    let compactValueText: String
    let detailText: String?
    let accessibilityLabel: String
    let accessibilityValue: String
    let tone: Tone

    var helpText: String {
        [titleText, valueText, detailText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

extension BalanceMenuBarExtraSelection {
    static var emptySelection: BalanceMenuBarExtraSelection {
        BalanceMenuBarExtraSelection(
            kind: .empty,
            titleText: AppLocalization.text("balance.title"),
            valueText: AppLocalization.text("common.unavailable"),
            compactValueText: AppLocalization.text("common.unavailable"),
            detailText: nil,
            accessibilityLabel: AppLocalization.text("balance.title"),
            accessibilityValue: AppLocalization.text("common.unavailable"),
            tone: .neutral
        )
    }
}

enum BalanceMenuBarExtraSupport {
    static func selection(
        for sortedSnapshots: [BalanceSnapshot],
        displayMode: BalanceDisplayMode,
        displayCurrency: DisplayCurrency
    ) -> BalanceMenuBarExtraSelection {
        guard !sortedSnapshots.isEmpty else {
            return .emptySelection
        }

        let availableSnapshots = sortedSnapshots.filter(\.isAvailable)

        if let quotaSelection = mostAtRiskQuotaSelection(
            from: availableSnapshots,
            displayMode: displayMode
        ) {
            return quotaSelection
        }

        if let amountSelection = firstAmountSelection(
            from: availableSnapshots,
            displayCurrency: displayCurrency
        ) {
            return amountSelection
        }

        if let unavailable = sortedSnapshots.first(where: { !$0.isAvailable }) {
            return unavailableSelection(for: unavailable)
        }

        return .emptySelection
    }

    static func amountText(for entry: BalanceValueEntry) -> String {
        amountText(for: entry.amount, currencyCode: entry.currencyCode)
    }

    static func amountText(for amount: Double, currencyCode: String?) -> String {
        let formattedAmount = String(format: "%.2f", amount)
        if let code = currencyCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
            return "\(code.uppercased()) \(formattedAmount)"
        }
        return formattedAmount
    }

    static func burnRateText(for entry: BalanceValueEntry) -> String? {
        guard let rate = entry.amountConsumptionRate, rate.confidence > 0 else {
            return AppLocalization.text("balance.value.rate.pending")
        }
        return AppLocalization.format("balance.value.rate.perDay", amountText(for: rate.perDay, currencyCode: entry.currencyCode))
    }

    static func burnRateAccessibilityText(for entry: BalanceValueEntry) -> String? {
        burnRateText(for: entry)
    }

    static func displayRatio(
        for window: BalanceQuotaWindow,
        displayMode: BalanceDisplayMode
    ) -> Double {
        switch displayMode {
        case .used:
            return window.usedRatio ?? (1.0 - (window.remainingRatio ?? 0))
        case .remaining:
            return window.remainingRatio ?? (1.0 - (window.usedRatio ?? 0))
        }
    }

    static func displayRatio(
        for legacyPercent: Double,
        displayMode: BalanceDisplayMode
    ) -> Double {
        switch displayMode {
        case .used:
            return legacyPercent
        case .remaining:
            return 1.0 - legacyPercent
        }
    }

    /// Mode-aware quota color matching MenuBarView's exact thresholds.
    /// `.used`: high ratio = red (at risk). `.remaining`: high ratio = green (healthy).
    static func quotaColor(
        forDisplayRatio displayRatio: Double,
        displayMode: BalanceDisplayMode,
        palette: TokenCostPalette
    ) -> Color {
        let clamped = min(max(displayRatio, 0), 1)
        switch displayMode {
        case .used:
            switch clamped {
            case ..<0.5: return palette.accentSecondary
            case ..<0.8: return palette.accent
            case ..<0.95: return palette.warning
            default: return palette.danger
            }
        case .remaining:
            if clamped > 0.5 { return palette.accentSecondary }
            if clamped > 0.2 { return palette.accent }
            if clamped > 0.05 { return palette.warning }
            return palette.danger
        }
    }

    /// Localized label naming the active display mode for accessibility/percent text.
    static func displayModeLabel(for mode: BalanceDisplayMode) -> String {
        switch mode {
        case .used:
            return AppLocalization.text("balance.display.used")
        case .remaining:
            return AppLocalization.text("balance.display.remaining")
        }
    }

    private static func mostAtRiskQuotaSelection(
        from snapshots: [BalanceSnapshot],
        displayMode: BalanceDisplayMode
    ) -> BalanceMenuBarExtraSelection? {
        let candidates = snapshots.enumerated().compactMap { offset, snapshot -> (offset: Int, snapshot: BalanceSnapshot, displayRatio: Double, riskScore: Double, detailText: String?)? in
            if let windows = snapshot.quotaWindows, !windows.isEmpty {
                let window = windows.max { lhs, rhs in
                    quotaRiskScore(for: lhs) < quotaRiskScore(for: rhs)
                } ?? windows[0]
                let riskScore = quotaRiskScore(for: window)
                return (
                    offset: offset,
                    snapshot: snapshot,
                    displayRatio: displayRatio(for: window, displayMode: displayMode),
                    riskScore: riskScore,
                    detailText: window.label
                )
            }

            if let percent = snapshot.primaryWindowUsagePercent {
                return (
                    offset: offset,
                    snapshot: snapshot,
                    displayRatio: displayRatio(for: percent, displayMode: displayMode),
                    riskScore: percent,
                    detailText: snapshot.primaryWindowLabel
                )
            }

            if let percent = snapshot.secondaryWindowUsagePercent {
                return (
                    offset: offset,
                    snapshot: snapshot,
                    displayRatio: displayRatio(for: percent, displayMode: displayMode),
                    riskScore: percent,
                    detailText: snapshot.secondaryWindowLabel
                )
            }

            if let percent = snapshot.tertiaryWindowUsagePercent {
                return (
                    offset: offset,
                    snapshot: snapshot,
                    displayRatio: displayRatio(for: percent, displayMode: displayMode),
                    riskScore: percent,
                    detailText: snapshot.tertiaryWindowLabel
                )
            }

            if let percent = snapshot.usagePercent {
                return (
                    offset: offset,
                    snapshot: snapshot,
                    displayRatio: displayRatio(for: percent, displayMode: displayMode),
                    riskScore: percent,
                    detailText: snapshot.planType
                )
            }

            return nil
        }

        guard let selected = candidates.max(by: candidateComparator(_:_:)) else { return nil }

        let title = selected.snapshot.provider.displayName
        let valueText = TokenCostFormatters.percent(min(max(selected.displayRatio, 0), 1))
        let detailText = selected.detailText
        let accessibilityLabel = AppLocalization.text("balance.title")
        let accessibilityValue = [title, valueText, detailText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        return BalanceMenuBarExtraSelection(
            kind: .quota,
            titleText: title,
            valueText: valueText,
            compactValueText: valueText,
            detailText: detailText,
            accessibilityLabel: accessibilityLabel,
            accessibilityValue: accessibilityValue,
            tone: tone(forRiskScore: selected.riskScore)
        )
    }

    private static func firstAmountSelection(
        from snapshots: [BalanceSnapshot],
        displayCurrency: DisplayCurrency
    ) -> BalanceMenuBarExtraSelection? {
        guard let snapshot = snapshots.first(where: { $0.isBalanceType }) else { return nil }

        if let entry = firstDisplayableEntry(in: snapshot.valueEntries) {
            let valueText = amountText(for: entry)
            let detailText = burnRateText(for: entry) ?? grantedAmountText(for: entry)
            let accessibilityValue = [snapshot.provider.displayName, valueText, detailText]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")

            return BalanceMenuBarExtraSelection(
                kind: .amount,
                titleText: snapshot.provider.displayName,
                valueText: valueText,
                compactValueText: compactAmountText(for: entry),
                detailText: detailText,
                accessibilityLabel: AppLocalization.text("balance.title"),
                accessibilityValue: accessibilityValue,
                tone: .low
            )
        }

        if let cost = snapshot.totalCostUSD {
            let valueText = TokenCostFormatters.currency(cost, displayCurrency: displayCurrency)
            let detailText = snapshot.avgCostPerDayUSD.map {
                AppLocalization.format("balance.dailyAverage", TokenCostFormatters.currency($0, displayCurrency: displayCurrency))
            }
            let accessibilityValue = [snapshot.provider.displayName, valueText, detailText]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")

            return BalanceMenuBarExtraSelection(
                kind: .amount,
                titleText: snapshot.provider.displayName,
                valueText: valueText,
                compactValueText: compactAmountText(for: cost, displayCurrency: displayCurrency),
                detailText: detailText,
                accessibilityLabel: AppLocalization.text("balance.title"),
                accessibilityValue: accessibilityValue,
                tone: .low
            )
        }

        return nil
    }

    private static func unavailableSelection(for snapshot: BalanceSnapshot) -> BalanceMenuBarExtraSelection {
        let title = snapshot.provider.displayName
        let valueText = AppLocalization.text("balance.unavailable")
        let detailText = [snapshot.errorMessage, snapshot.errorRecoveryHint]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .first

        return BalanceMenuBarExtraSelection(
            kind: .unavailable,
            titleText: title,
            valueText: valueText,
            compactValueText: valueText,
            detailText: detailText,
            accessibilityLabel: AppLocalization.text("balance.title"),
            accessibilityValue: [title, valueText, detailText]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · "),
            tone: .unavailable
        )
    }

    private static func quotaRiskScore(for window: BalanceQuotaWindow) -> Double {
        if let used = window.usedRatio {
            return used
        }
        if let remaining = window.remainingRatio {
            return 1.0 - remaining
        }
        return 0
    }

    private static func candidateComparator(
        _ lhs: (offset: Int, snapshot: BalanceSnapshot, displayRatio: Double, riskScore: Double, detailText: String?),
        _ rhs: (offset: Int, snapshot: BalanceSnapshot, displayRatio: Double, riskScore: Double, detailText: String?)
    ) -> Bool {
        if lhs.riskScore != rhs.riskScore { return lhs.riskScore < rhs.riskScore }
        return lhs.offset > rhs.offset
    }

    private static func firstDisplayableEntry(in entries: [BalanceValueEntry]?) -> BalanceValueEntry? {
        entries?.first { $0.amount.isFinite && !$0.amount.isNaN }
    }

    private static func grantedAmountText(for entry: BalanceValueEntry) -> String? {
        guard let granted = entry.grantedAmount else { return nil }
        return AppLocalization.format("balance.value.grantedShort", String(format: "%.2f", granted))
    }

    private static func compactAmountText(for entry: BalanceValueEntry) -> String {
        compactAmountText(for: entry.amount, currencyCode: entry.currencyCode)
    }

    private static func compactAmountText(for amount: Double, displayCurrency: DisplayCurrency) -> String {
        let prefix = displayCurrency == .cny ? "¥" : "$"
        return compactCurrencyAmountText(amount: amount, prefix: prefix)
    }

    private static func compactAmountText(for amount: Double, currencyCode: String?) -> String {
        let normalizedCode = currencyCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let prefix: String
        switch normalizedCode {
        case "USD":
            prefix = "$"
        case "CNY", "RMB", "CNH", "JPY":
            prefix = "¥"
        case "EUR":
            prefix = "€"
        case let code? where !code.isEmpty:
            prefix = "\(String(code.prefix(3))) "
        default:
            prefix = ""
        }
        return compactCurrencyAmountText(amount: amount, prefix: prefix)
    }

    private static func compactCurrencyAmountText(amount: Double, prefix: String) -> String {
        let absoluteAmount = abs(amount)
        if absoluteAmount < 10_000 {
            return "\(prefix)\(String(format: "%.2f", amount))"
        }

        let compactAmount: String
        switch absoluteAmount {
        case 1_000_000_000...:
            compactAmount = String(format: "%.2fB", amount / 1_000_000_000)
        case 1_000_000...:
            compactAmount = String(format: "%.2fM", amount / 1_000_000)
        case 1_000...:
            compactAmount = String(format: "%.2fK", amount / 1_000)
        default:
            compactAmount = String(format: "%.2f", amount)
        }

        return "\(prefix)\(compactAmount)"
    }

    static func pinFloatingPanelLabel(isEnabled: Bool) -> String {
        AppLocalization.text(isEnabled ? "balance.menu.unpinFloatingPanel" : "balance.menu.pinFloatingPanel")
    }

    static func pinFloatingPanelHint(isEnabled: Bool) -> String {
        AppLocalization.text(isEnabled ? "balance.menu.unpinFloatingPanel.hint" : "balance.menu.pinFloatingPanel.hint")
    }

    private static func tone(forRiskScore riskScore: Double) -> BalanceMenuBarExtraSelection.Tone {
        switch min(max(riskScore, 0), 1) {
        case ..<0.5:
            return .low
        case ..<0.8:
            return .moderate
        case ..<0.95:
            return .high
        default:
            return .critical
        }
    }
}

struct BalanceMenuBarExtraLabelView: View {
    let selection: BalanceMenuBarExtraSelection
    let palette: TokenCostPalette

    private let valueSlotWidth: CGFloat = 58

    private var tint: Color {
        switch selection.tone {
        case .neutral:
            return palette.subtitle.opacity(0.7)
        case .low:
            return palette.accentSecondary
        case .moderate:
            return palette.accent
        case .high:
            return palette.warning
        case .critical:
            return palette.danger
        case .unavailable:
            return palette.subtitle.opacity(0.55)
        }
    }

    private var valueForeground: Color {
        selection.tone == .unavailable ? palette.subtitle.opacity(0.7) : palette.title
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge")
                .font(.system(size: 11, weight: palette.usesWorkshopStyle ? .black : .semibold))
                .foregroundStyle(tint)

            Text(selection.compactValueText)
                .font(TokenTypography.caption(weight: .bold, palette: palette))
                .monospacedDigit()
                .foregroundStyle(valueForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: valueSlotWidth, alignment: .trailing)
        }
        .help(selection.helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(selection.accessibilityLabel))
        .accessibilityValue(Text(selection.accessibilityValue))
    }
}

struct BalanceMenuBarPopoverView: View {
    @ObservedObject var balanceManager: BalanceManager
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    let balanceFloatingPanelCoordinator: BalanceFloatingPanelCoordinator
    let palette: TokenCostPalette

    private var sortedSnapshots: [BalanceSnapshot] {
        appPreferencesModel.sortBalanceSnapshots(balanceManager.snapshots)
    }

    private var selection: BalanceMenuBarExtraSelection {
        BalanceMenuBarExtraSupport.selection(
            for: sortedSnapshots,
            displayMode: appPreferencesModel.preferences.balanceDisplayMode,
            displayCurrency: appPreferencesModel.preferences.displayCurrency
        )
    }

    private var lastRefreshText: String {
        balanceManager.lastRefreshTime.map {
            AppLocalization.format("balance.lastRefresh", TokenCostFormatters.localDateTime($0))
        } ?? AppLocalization.text("balance.notRefreshed")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if sortedSnapshots.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sortedSnapshots) { snapshot in
                            if appPreferencesModel.preferences.balanceFloatingPanelDisplayMode == .normal {
                                BalanceProviderCardView(snapshot: snapshot, palette: palette, displayMode: appPreferencesModel.preferences.balanceDisplayMode)
                            } else {
                                BalanceMinimalProviderTile(snapshot: snapshot, palette: palette, displayMode: appPreferencesModel.preferences.balanceDisplayMode)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 320)
            }

            TokenThemedDivider(palette: palette)

            controls
        }
        .frame(width: 350)
        .padding(TokenSpacing.control)
        .background {
            if palette.usesWorkshopStyle {
                palette.pageBackground
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle()
                        .fill(palette.accent)
                        .frame(width: 7, height: 7)

                    Text(selection.titleText)
                        .font(TokenTypography.subheadline(weight: .bold, palette: palette))
                        .foregroundStyle(palette.title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(selection.valueText)
                        .font(TokenTypography.metric(size: 20, weight: .bold, palette: palette))
                        .foregroundStyle(selection.tone == .critical ? .red : palette.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    if let detailText = selection.detailText, !detailText.isEmpty {
                        Text(detailText)
                            .font(TokenTypography.caption(palette: palette))
                            .foregroundStyle(palette.subtitle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                Text(lastRefreshText)
                    .font(TokenTypography.caption(palette: palette))
                    .foregroundStyle(palette.subtitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }

            Spacer(minLength: 8)

            Button {
                Task { await balanceManager.refresh(force: true) }
            } label: {
                if balanceManager.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .dashboardButtonStyle(palette: palette, compact: true, fallback: .plain)
            .foregroundStyle(balanceManager.isRefreshing ? palette.subtitle : palette.accent)
            .disabled(balanceManager.isRefreshing)
            .help(AppLocalization.text("menu.refreshBalance"))
            .accessibilityLabel(Text(AppLocalization.text("menu.refreshBalance")))
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                balanceFloatingPanelCoordinator.toggleFromMenuBar()
            } label: {
                Label(
                    appPreferencesModel.preferences.balanceFloatingPanelEnabled
                    ? AppLocalization.text("menu.balanceFloatingPanel.hide")
                    : AppLocalization.text("menu.balanceFloatingPanel.show"),
                    systemImage: "rectangle.on.rectangle"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .dashboardButtonStyle(
                palette: palette,
                compact: true,
                fallback: appPreferencesModel.preferences.balanceFloatingPanelEnabled
                    ? .settingsGlassProminent
                    : .settingsGlass
            )
            .controlSize(.small)
            .help(
                appPreferencesModel.preferences.balanceFloatingPanelEnabled
                ? AppLocalization.text("menu.balanceFloatingPanel.hide")
                : AppLocalization.text("menu.balanceFloatingPanel.show")
            )
            .accessibilityLabel(
                Text(
                    appPreferencesModel.preferences.balanceFloatingPanelEnabled
                    ? AppLocalization.text("menu.balanceFloatingPanel.hide")
                    : AppLocalization.text("menu.balanceFloatingPanel.show")
                )
            )

            pinFloatingPanelToggle
        }
    }

    @ViewBuilder
    private var pinFloatingPanelToggle: some View {
        let label = BalanceMenuBarExtraSupport.pinFloatingPanelLabel(
            isEnabled: appPreferencesModel.preferences.balanceFloatingPanelAlwaysOnTop
        )
        let hint = BalanceMenuBarExtraSupport.pinFloatingPanelHint(
            isEnabled: appPreferencesModel.preferences.balanceFloatingPanelAlwaysOnTop
        )

        if palette.usesWorkshopStyle {
            Toggle(isOn: appPreferencesModel.balanceFloatingPanelAlwaysOnTopBinding) {
                Label(
                    label,
                    systemImage: appPreferencesModel.preferences.balanceFloatingPanelAlwaysOnTop ? "pin.fill" : "pin"
                )
            }
            .toggleStyle(WorkshopToggleStyle(palette: palette))
            .help(hint)
            .accessibilityLabel(Text(label))
            .accessibilityHint(Text(hint))
        } else {
            Toggle(isOn: appPreferencesModel.balanceFloatingPanelAlwaysOnTopBinding) {
                Label(
                    label,
                    systemImage: appPreferencesModel.preferences.balanceFloatingPanelAlwaysOnTop ? "pin.fill" : "pin"
                )
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .help(hint)
            .accessibilityLabel(Text(label))
            .accessibilityHint(Text(hint))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppLocalization.text("balance.empty.title"))
                .font(TokenTypography.subheadline(weight: .bold, palette: palette))
                .foregroundStyle(palette.title)
            Text(AppLocalization.text("balance.empty.body"))
                .font(TokenTypography.caption(palette: palette))
                .foregroundStyle(palette.subtitle)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
