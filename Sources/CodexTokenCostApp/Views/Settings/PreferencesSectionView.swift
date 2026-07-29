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

                themePickerSection
            }
        }
    }

    private var themePickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.text("settings.theme.title"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.subtitle)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                ForEach(TokenCostThemeChoice.allCases, id: \.rawValue) { theme in
                    let themePalette = TokenCostPalette(theme: theme)
                    let isSelected = appPreferencesModel.preferences.theme == theme
                    Button {
                        appPreferencesModel.themeBinding.wrappedValue = theme
                    } label: {
                        VStack(spacing: 6) {
                            if theme == .system {
                                Image(systemName: "circle.lefthalf.filled")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(palette.title)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Circle()
                                            .fill(themePalette.accent.opacity(isSelected ? 0.25 : 0.10))
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(isSelected ? palette.title : Color.clear, lineWidth: 2)
                                    )
                            } else {
                                Circle()
                                    .fill(themePalette.accent.gradient)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(isSelected ? palette.title : Color.clear, lineWidth: 2)
                                    )
                                    .shadow(color: themePalette.accent.opacity(isSelected ? 0.4 : 0.15), radius: isSelected ? 6 : 3)
                            }

                            Text(theme.displayName)
                                .font(.caption2)
                                .foregroundStyle(isSelected ? palette.title : palette.subtitle)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? themePalette.accent.opacity(0.10) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 4)
    }
}

private extension String {
    var localized: String {
        AppLocalization.text(self)
    }
}
