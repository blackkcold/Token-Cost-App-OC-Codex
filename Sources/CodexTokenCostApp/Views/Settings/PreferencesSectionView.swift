import SwiftUI
import CodexTokenCostCore

struct PreferencesSectionView: View {
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    let palette: TokenCostPalette

    var body: some View {
        SettingsSurfaceCard(
            title: AppLocalization.text("settings.appPreferences.title"),
            subtitle: AppLocalization.text("settings.appPreferences.subtitle"),
            role: .primary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsControlGrid(minimumWidth: 220) {
                    SettingsControlTile(palette: palette, minHeight: 54) {
                        SettingsInlineControlRow(
                            title: AppLocalization.text("settings.language"),
                            palette: palette
                        ) {
                            Picker("", selection: appPreferencesModel.languageBinding) {
                                ForEach(AppDisplayLanguage.allCases) { language in
                                    Text(language.displayName).tag(language)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 200)
                        }
                    }
                    SettingsControlTile(palette: palette, minHeight: 54) {
                        SettingsInlineControlRow(
                            title: AppLocalization.text("settings.currency.title"),
                            palette: palette
                        ) {
                            Picker("", selection: appPreferencesModel.displayCurrencyBinding) {
                                ForEach(DisplayCurrency.allCases) { currency in
                                    Text(currency.displayName).tag(currency)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 200)
                        }
                    }
                }

                appearancePickerSection
                accentPalettePickerSection
            }
        }
    }

    private var appearancePickerSection: some View {
        SettingsControlTile(palette: palette, minHeight: 64) {
            SettingsInlineControlRow(
                title: AppLocalization.text("settings.appearance.title"),
                palette: palette
            ) {
                Picker("", selection: appPreferencesModel.appearanceModeBinding) {
                    ForEach(TokenCostAppearanceMode.allCases) { mode in
                        Label(mode.displayName, systemImage: appearanceIcon(for: mode))
                            .tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .accessibilityLabel(Text(AppLocalization.text("settings.appearance.title")))
            }
        }
    }

    private var accentPalettePickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.text("settings.accentPalette.title"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.subtitle)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(TokenCostAccentPalette.allCases) { accentPalette in
                    let previewPalette = TokenCostPalette(accentPalette: accentPalette)
                    let isSelected = appPreferencesModel.preferences.accentPalette == accentPalette
                    Button {
                        appPreferencesModel.accentPaletteBinding.wrappedValue = accentPalette
                    } label: {
                        VStack(spacing: 6) {
                            themePreview(
                                accentPalette: accentPalette,
                                previewPalette: previewPalette,
                                isSelected: isSelected
                            )

                            Text(accentPalette.displayName)
                                .font(.caption2)
                                .foregroundStyle(isSelected ? palette.title : palette.subtitle)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? previewPalette.accent.opacity(0.10) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(accentPalette.displayName))
                    .accessibilityValue(Text(isSelected ? AppLocalization.text("common.selected") : AppLocalization.text("common.notSelected")))
                    .accessibilityHint(Text(accentPalette.summary))
                }
            }
        }
        .padding(.top, 4)
    }

    private func themePreview(
        accentPalette: TokenCostAccentPalette,
        previewPalette: TokenCostPalette,
        isSelected: Bool
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if accentPalette == .workshop {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(previewPalette.accentSecondary)
                        .frame(width: 28, height: 22)
                        .offset(x: 5, y: -4)

                    RoundedRectangle(cornerRadius: 5)
                        .fill(previewPalette.accent)
                        .frame(width: 28, height: 22)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(previewPalette.cardStroke, lineWidth: 2)
                        )
                        .shadow(color: previewPalette.cardShadow, radius: 0, x: 3, y: 3)
                }
            } else {
                Circle()
                    .fill(previewPalette.accent.gradient)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .strokeBorder(isSelected ? palette.title : Color.clear, lineWidth: 2)
                    )
                    .shadow(
                        color: previewPalette.accent.opacity(isSelected ? 0.4 : 0.15),
                        radius: isSelected ? 6 : 3
                    )
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2.weight(.bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, previewPalette.accent)
                    .offset(x: 4, y: 4)
            }
        }
        .frame(width: 38, height: 34)
    }

    private func appearanceIcon(for mode: TokenCostAppearanceMode) -> String {
        switch mode {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

private extension String {
    var localized: String {
        AppLocalization.text(self)
    }
}
