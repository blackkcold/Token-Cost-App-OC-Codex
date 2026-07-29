import SwiftUI
import CodexTokenCostCore

struct SkillsSectionView: View {
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    let palette: TokenCostPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSurfaceCard(
                title: "settings.skills.title".localized,
                subtitle: "settings.skills.subtitle".localized,
                role: .primary,
                palette: palette
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("settings.skills.helperText".localized)
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)

                    SettingsControlGrid(minimumWidth: 220) {
                        SettingsControlTile(palette: palette, minHeight: 54) {
                            Toggle("settings.skills.showSourceBadges".localized, isOn: Binding(
                                get: { appPreferencesModel.preferences.skillsPanel.showSourceColumn },
                                set: { v in appPreferencesModel.updateSkillsPanel(showSource: v) }
                            ))
                        }

                        SettingsControlTile(palette: palette, minHeight: 54) {
                            Toggle("settings.skills.showStateIndicators".localized, isOn: Binding(
                                get: { appPreferencesModel.preferences.skillsPanel.showStateColumn },
                                set: { v in appPreferencesModel.updateSkillsPanel(showState: v) }
                            ))
                        }

                        SettingsControlTile(palette: palette, minHeight: 54) {
                            Toggle("settings.skills.showTagBadges".localized, isOn: Binding(
                                get: { appPreferencesModel.preferences.skillsPanel.showTagsColumn },
                                set: { v in appPreferencesModel.updateSkillsPanel(showTags: v) }
                            ))
                        }

                        SettingsControlTile(palette: palette, minHeight: 54) {
                            SettingsInlineControlRow(
                                title: "settings.skills.previewLength".localized,
                                palette: palette
                            ) {
                                HStack(spacing: 6) {
                                    Stepper("", value: Binding(
                                        get: { appPreferencesModel.preferences.skillsPanel.previewLength },
                                        set: { v in appPreferencesModel.updateSkillsPanel(previewLength: v) }
                                    ), in: 100...2000, step: 50)
                                    .labelsHidden()
                                    Text("\(appPreferencesModel.preferences.skillsPanel.previewLength)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(palette.title)
                                        .frame(minWidth: 36)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private extension String {
    var localized: String {
        AppLocalization.text(self)
    }
}
