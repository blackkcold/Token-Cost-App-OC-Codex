import SwiftUI
import CodexTokenCostCore

struct BillingSectionView: View {
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    let palette: TokenCostPalette
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsSurfaceCard(
            title: AppLocalization.text("settings.billing.title"),
            subtitle: AppLocalization.text("settings.billing.subtitle"),
            role: .primary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 12) {
                reportingRangeSection()

                ForEach(BillingProvider.allCases) { provider in
                    providerCard(provider)
                }

                Divider().opacity(0.3)

                Button {
                    WindowOpeningSupport.openWindow(id: "pricing-doc", openWindow: openWindow)
                } label: {
                    Label(
                        AppLocalization.text("settings.billing.viewPricingDoc"),
                        systemImage: "doc.text"
                    )
                }
                .settingsGlassButtonStyle(prominent: false)
                .controlSize(.small)
            }
        }
    }

    private func reportingRangeSection() -> some View {
        let mode = appPreferencesModel.preferences.reportingRangeMode
        let bounds = appPreferencesModel.preferences.reportingRangeCustomBounds

        return SettingsSurfaceCard(
            title: AppLocalization.text("settings.billing.reportingRange.title"),
            subtitle: AppLocalization.text("settings.billing.reportingRange.subtitle"),
            role: .secondary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalization.text("settings.billing.reportingRange.scopeHint"))
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)

                SettingsControlGrid(minimumWidth: 220) {
                    SettingsControlTile(palette: palette, minHeight: 62) {
                        SettingsInlineControlRow(
                            title: AppLocalization.text("settings.billing.reportingRange.mode"),
                            palette: palette
                        ) {
                            Picker("", selection: appPreferencesModel.reportingRangeModeBinding) {
                                ForEach(ReportingRangeMode.allCases, id: \.self) { rangeMode in
                                    Text(rangeMode.displayName).tag(rangeMode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 240)
                            .accessibilityIdentifier("billing.reportingRange.modePicker")
                            .accessibilityLabel(AppLocalization.text("settings.billing.reportingRange.mode"))
                        }
                    }

                    SettingsControlTile(palette: palette, minHeight: 74) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reportingRangeSummaryTitle(mode: mode, bounds: bounds))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.title)
                            Text(reportingRangeSummaryDetail(mode: mode, bounds: bounds))
                                .font(.caption)
                                .foregroundStyle(mode == .custom && !reportingRangeCustomBoundsAreValid(bounds) ? .orange : palette.subtitle)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                if mode == .custom {
                    ReportingRangePickerPanel(appPreferencesModel: appPreferencesModel, palette: palette)
                }
            }
        }
    }

    private func reportingRangeSummaryTitle(mode: ReportingRangeMode, bounds: ReportingRangeCustomBounds) -> String {
        switch mode {
        case .allAvailable:
            return AppLocalization.text("settings.billing.reportingRange.summary.allAvailable")
        case .currentMonth:
            return AppLocalization.text("settings.billing.reportingRange.summary.currentMonth")
        case .last30Days:
            return AppLocalization.text("settings.billing.reportingRange.summary.last30Days")
        case .custom:
            guard reportingRangeCustomBoundsAreValid(bounds),
                  let start = bounds.start,
                  let end = bounds.end else {
                return AppLocalization.text("settings.billing.reportingRange.summary.customUnset")
            }
            return String(
                format: AppLocalization.text("settings.billing.reportingRange.summary.customValid"),
                start.formatted(date: .abbreviated, time: .omitted),
                end.formatted(date: .abbreviated, time: .omitted)
            )
        }
    }

    private func reportingRangeSummaryDetail(mode: ReportingRangeMode, bounds: ReportingRangeCustomBounds) -> String {
        switch mode {
        case .allAvailable:
            return AppLocalization.text("settings.billing.reportingRange.summaryDetail.allAvailable")
        case .currentMonth:
            return AppLocalization.text("settings.billing.reportingRange.summaryDetail.currentMonth")
        case .last30Days:
            return AppLocalization.text("settings.billing.reportingRange.summaryDetail.last30Days")
        case .custom:
            if reportingRangeCustomBoundsAreValid(bounds) {
                return AppLocalization.text("settings.billing.reportingRange.summaryDetail.customValid")
            }
            return AppLocalization.text("settings.billing.reportingRange.summaryDetail.customUnset")
        }
    }

    private func reportingRangeCustomBoundsAreValid(_ bounds: ReportingRangeCustomBounds) -> Bool {
        guard let start = bounds.start, let end = bounds.end else { return false }
        return start <= end
    }

    private func providerCard(_ provider: BillingProvider) -> some View {
        let selection = appPreferencesModel.preferences.billingSelection(for: provider)
        let resolved = BillingPlanCatalog.resolve(provider: provider, selection: selection)
        let presets = BillingPlanCatalog.subscriptionPresets(for: provider)

        return HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(resolved.isSubscribed ? palette.accent : palette.subtitle.opacity(0.3))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 0) {
                providerHeader(provider: provider, resolved: resolved)

                Divider().opacity(0.25).padding(.vertical, 8)

                SettingsControlGrid(minimumWidth: 220) {
                    SettingsControlTile(palette: palette, minHeight: 62) {
                        SettingsInlineControlRow(
                            title: AppLocalization.text("settings.billing.subscribed"),
                            palette: palette
                        ) {
                            Toggle("", isOn: appPreferencesModel.subscribedBinding(for: provider))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .accessibilityLabel(AppLocalization.text("settings.billing.subscribed"))
                        }
                    }

                    if !presets.isEmpty {
                        SettingsControlTile(palette: palette, minHeight: 62) {
                            SettingsInlineControlRow(
                                title: resolved.displayName,
                                palette: palette
                            ) {
                                Picker(
                                    "",
                                    selection: appPreferencesModel.billingPlanOptionBinding(for: provider)
                                ) {
                                    ForEach(presets) { preset in
                                        Text("\(preset.name) — \(preset.displayPrice)").tag(preset.id)
                                    }
                                    Text(AppLocalization.text("settings.billing.customPlan"))
                                        .tag(BillingPlanCatalog.customOptionID)
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: 220)
                                .accessibilityLabel(resolved.displayName)
                            }
                        }
                    }

                    if selection.mode == .customMonthlyUSD {
                        SettingsControlTile(palette: palette, minHeight: 62) {
                            SettingsInlineControlRow(
                                title: AppLocalization.text("settings.billing.customCost"),
                                palette: palette
                            ) {
                                TextField(
                                    "",
                                    value: appPreferencesModel.customBillingCostBinding(for: provider),
                                    format: .number.precision(.fractionLength(2))
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 120)
                                .monospacedDigit()
                                .accessibilityLabel(AppLocalization.text("settings.billing.customCost"))
                            }
                        }
                    }
                }

                if resolved.isSubscribed, resolved.isFixedCost {
                    periodTrackingSection(provider: provider, selection: selection)
                }
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.surfaceSecondaryFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.surfaceStroke.opacity(0.5), lineWidth: 0.8)
        )
    }

    private func providerHeader(provider: BillingProvider, resolved: ResolvedBillingPlan) -> some View {
        HStack(spacing: 8) {
            Image(systemName: provider.systemImage)
                .font(.subheadline)
                .foregroundStyle(resolved.isSubscribed ? palette.accent : palette.subtitle)
                .frame(width: 18)

            Text(provider.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.title)

            if resolved.isSubscribed {
                Text("·")
                    .foregroundStyle(palette.subtitle)
                Text(resolved.priceDescription)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.accent)
            }

            Spacer()

            if resolved.isSubscribed, let cost = resolved.monthlyUSD {
                let dc = appPreferencesModel.preferences.displayCurrency
                let converted = TokenCostCurrencyService.convert(cost, from: .usd, to: dc)
                let formatted = TokenCostCurrencyService.format(converted, currency: dc)
                Text(formatted)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(palette.accent)
            } else if !resolved.isSubscribed {
                Text(AppLocalization.text("settings.billing.notSubscribed"))
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
            }
        }
    }

    private func periodTrackingSection(provider: BillingProvider, selection: BillingPlanSelection) -> some View {
        let periodCost = appPreferencesModel.preferences.periodTotalCost(for: provider)
        let displayCurrency = appPreferencesModel.preferences.displayCurrency
        let trackingOff = selection.hasPeriodTracking == false
        let summaryTitle = trackingOff
            ? AppLocalization.text("settings.billing.periodSummaryMonthlyFallback")
            : AppLocalization.text("settings.billing.periodSummary")
        let summaryNote = trackingOff
            ? AppLocalization.text("settings.billing.periodSummaryTrackingOff")
            : String(
                format: AppLocalization.text("settings.billing.periodSummaryPreset"),
                selection.periodPreset?.displayName ?? AppLocalization.text("settings.billing.periodPreset.custom")
            )
        let nextDateText: String = {
            guard selection.hasPeriodTracking else {
                return AppLocalization.text("settings.billing.periodSummaryTrackingOff")
            }
            guard let end = selection.periodEnd else {
                return AppLocalization.text("settings.billing.periodCustomEmpty")
            }
            return end.formatted(date: .abbreviated, time: .omitted)
        }()
        let costText: String = {
            guard let cost = periodCost else {
                return AppLocalization.text("common.unavailable")
            }
            let converted = TokenCostCurrencyService.convert(cost, from: .usd, to: displayCurrency)
            return TokenCostCurrencyService.format(converted, currency: displayCurrency)
        }()

        return VStack(alignment: .leading, spacing: 10) {
            SettingsControlGrid(minimumWidth: 220) {
                SettingsControlTile(palette: palette, minHeight: 74) {
                    VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: appPreferencesModel.hasPeriodTrackingBinding(for: provider)) {
                                Text(AppLocalization.text("settings.billing.periodTracking"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(palette.title)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .accessibilityIdentifier("billing.\(provider.rawValue).periodTrackingToggle")
                            .accessibilityHint(AppLocalization.text("settings.billing.periodTrackingHint"))

                        Text(AppLocalization.text("settings.billing.periodTrackingHint"))
                            .font(.caption)
                            .foregroundStyle(palette.subtitle)
                    }
                }

                SettingsControlTile(palette: palette, minHeight: 74) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summaryTitle)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(palette.title)
                                Text(summaryNote)
                                    .font(.caption2)
                                    .foregroundStyle(palette.subtitle)
                            }

                            Spacer(minLength: 12)

                            Text(costText)
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(palette.accent)
                        }

                        HStack(spacing: 8) {
                            Text(AppLocalization.text("settings.billing.periodSummaryNextDate"))
                                .font(.caption2)
                                .foregroundStyle(palette.subtitle)
                            Spacer(minLength: 12)
                            Text(nextDateText)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(palette.title)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                if selection.hasPeriodTracking {
                    SettingsControlTile(palette: palette, minHeight: 62) {
                        SettingsInlineControlRow(
                            title: AppLocalization.text("settings.billing.periodPreset"),
                            palette: palette
                        ) {
                            Picker(
                                "",
                                selection: appPreferencesModel.periodPresetBinding(for: provider)
                            ) {
                                Text(AppLocalization.text("settings.billing.periodPreset.monthly"))
                                    .tag(PeriodPreset.monthly as PeriodPreset?)
                                Text(AppLocalization.text("settings.billing.periodPreset.quarterly"))
                                    .tag(PeriodPreset.quarterly as PeriodPreset?)
                                Text(AppLocalization.text("settings.billing.periodPreset.yearly"))
                                    .tag(PeriodPreset.yearly as PeriodPreset?)
                                Text(AppLocalization.text("settings.billing.periodPreset.custom"))
                                    .tag(nil as PeriodPreset?)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 420)
                            .accessibilityIdentifier("billing.\(provider.rawValue).periodPresetPicker")
                            .accessibilityLabel(AppLocalization.text("settings.billing.periodPreset"))
                        }
                    }

                    if selection.periodPreset == nil {
                        customPeriodEditors(provider: provider, selection: selection)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func customPeriodEditors(provider: BillingProvider, selection: BillingPlanSelection) -> some View {
        let start = selection.periodStart
        let end = selection.periodEnd

        VStack(alignment: .leading, spacing: 10) {
            SettingsControlTile(palette: palette, minHeight: 72) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.text("settings.billing.periodCustomHelper"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.title)
                    Text(AppLocalization.text("settings.billing.periodCustomRangeHint"))
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                }
                .accessibilityElement(children: .combine)
            }

            SettingsControlGrid(minimumWidth: 200) {
                if let end {
                    SettingsControlTile(palette: palette, minHeight: 62) {
                        SettingsInlineControlRow(
                            title: AppLocalization.text("settings.billing.periodStart"),
                            palette: palette
                        ) {
                            DatePicker(
                                "",
                                selection: appPreferencesModel.periodStartBinding(for: provider),
                                in: ...end,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .frame(maxWidth: 200)
                            .accessibilityIdentifier("billing.\(provider.rawValue).periodStartDatePicker")
                            .accessibilityLabel(AppLocalization.text("settings.billing.periodStart"))
                            .accessibilityHint(AppLocalization.text("settings.billing.periodCustomRangeHint"))
                        }
                    }
                }

                if let start {
                    SettingsControlTile(palette: palette, minHeight: 62) {
                        SettingsInlineControlRow(
                            title: AppLocalization.text("settings.billing.periodEnd"),
                            palette: palette
                        ) {
                            DatePicker(
                                "",
                                selection: appPreferencesModel.periodEndBinding(for: provider),
                                in: start...,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .frame(maxWidth: 200)
                            .accessibilityIdentifier("billing.\(provider.rawValue).periodEndDatePicker")
                            .accessibilityLabel(AppLocalization.text("settings.billing.periodEnd"))
                            .accessibilityHint(AppLocalization.text("settings.billing.periodCustomRangeHint"))
                        }
                    }
                }

                if start == nil || end == nil {
                    SettingsControlTile(palette: palette, minHeight: 62) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AppLocalization.text("settings.billing.periodCustomEmpty"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.title)
                            Text(AppLocalization.text("settings.billing.periodCustomHelper"))
                                .font(.caption)
                            .foregroundStyle(palette.subtitle)
                        }
                    }
                }

                SettingsControlTile(palette: palette, minHeight: 62) {
                    SettingsInlineControlRow(
                        title: AppLocalization.text("settings.billing.periodGranularity"),
                        palette: palette
                    ) {
                        Picker("", selection: appPreferencesModel.periodGranularityBinding(for: provider)) {
                            Text(AppLocalization.text("settings.billing.granularity.month")).tag(PeriodGranularity.month)
                            Text(AppLocalization.text("settings.billing.granularity.day")).tag(PeriodGranularity.day)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 200)
                        .accessibilityIdentifier("billing.\(provider.rawValue).periodGranularityPicker")
                        .accessibilityLabel(AppLocalization.text("settings.billing.periodGranularity"))
                    }
                }
            }
        }
    }
}

private extension BillingProvider {
    var systemImage: String {
        switch self {
        case .opencode: return "square.grid.3x3.topleft.filled"
        case .codex: return "brain.head.profile"
        case .minimax: return "sparkles"
        case .xiaomiMimo: return "leaf"
        case .deepseek: return "magnifyingglass"
        case .ollama: return "cloud"
        }
    }
}

private extension PeriodPreset {
    var displayName: String {
        switch self {
        case .monthly: return AppLocalization.text("settings.billing.periodPreset.monthly")
        case .quarterly: return AppLocalization.text("settings.billing.periodPreset.quarterly")
        case .yearly: return AppLocalization.text("settings.billing.periodPreset.yearly")
        }
    }
}

private extension ReportingRangeMode {
    var displayName: String {
        switch self {
        case .allAvailable: return AppLocalization.text("settings.billing.reportingRange.mode.allAvailable")
        case .currentMonth: return AppLocalization.text("settings.billing.reportingRange.mode.currentMonth")
        case .last30Days: return AppLocalization.text("settings.billing.reportingRange.mode.last30Days")
        case .custom: return AppLocalization.text("settings.billing.reportingRange.mode.custom")
        }
    }
}
