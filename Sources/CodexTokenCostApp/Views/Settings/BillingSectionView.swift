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
            VStack(alignment: .leading, spacing: 10) {
                ForEach(BillingProvider.allCases) { provider in
                    providerCard(provider)
                }

                Divider().opacity(0.3)

                Button {
                    WindowOpeningSupport.openSingletonWindow(id: "pricing-doc", openWindow: openWindow)
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

    // MARK: - Provider Card

    private func providerCard(_ provider: BillingProvider) -> some View {
        let selection = appPreferencesModel.preferences.billingSelection(for: provider)
        let resolved = BillingPlanCatalog.resolve(provider: provider, selection: selection)
        let presets = BillingPlanCatalog.subscriptionPresets(for: provider)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(provider.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.title)
                Spacer()
                if resolved.isSubscribed, let cost = resolved.monthlyUSD {
                    let dc = appPreferencesModel.preferences.displayCurrency
                    let converted = TokenCostCurrencyService.convert(cost, from: .usd, to: dc)
                    Text(TokenCostCurrencyService.format(converted, currency: dc))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.accent)
                } else if !resolved.isSubscribed {
                    Text(AppLocalization.text("settings.billing.notSubscribed"))
                        .font(.caption2)
                        .foregroundStyle(palette.subtitle)
                }
            }

            Divider().opacity(0.3)

            SettingsControlGrid(minimumWidth: 180) {
                SettingsControlTile(palette: palette, minHeight: 54) {
                    SettingsInlineControlRow(
                        title: AppLocalization.text("settings.billing.subscribed"),
                        palette: palette
                    ) {
                        Toggle("", isOn: appPreferencesModel.subscribedBinding(for: provider))
                            .labelsHidden()
                    }
                }

                if !presets.isEmpty {
                    SettingsControlTile(palette: palette, minHeight: 54) {
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
                            .frame(maxWidth: 200)
                        }
                    }
                }

                if selection.mode == .customMonthlyUSD {
                    SettingsControlTile(palette: palette, minHeight: 54) {
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
                        }
                    }
                }
            }
        }
        .padding(10)
        .settingsInsetSurface(in: RoundedRectangle(cornerRadius: 10), palette: palette)
    }
}

private extension String {
    var localized: String {
        AppLocalization.text(self)
    }
}
