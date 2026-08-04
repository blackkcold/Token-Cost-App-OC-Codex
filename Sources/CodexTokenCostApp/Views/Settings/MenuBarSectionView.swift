import SwiftUI
import CodexTokenCostCore

struct MenuBarSectionView: View {
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    let palette: TokenCostPalette

    var body: some View {
        SettingsSurfaceCard(
            title: AppLocalization.text("settings.menuBar.title"),
            subtitle: AppLocalization.text("settings.menuBar.subtitle"),
            role: .primary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsControlGrid(minimumWidth: 220) {
                    SettingsControlTile(palette: palette, minHeight: 54) {
                        SettingsInlineControlRow(
                            title: AppLocalization.text("settings.menuBar.chartStyle"),
                            palette: palette
                        ) {
                            Picker("", selection: appPreferencesModel.menuBarChartStyleBinding) {
                                ForEach(MenuBarChartStyle.allCases) { style in
                                    Text(chartStyleLabel(style)).tag(style)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 240)
                            .accessibilityLabel(Text(AppLocalization.text("settings.menuBar.chartStyle")))
                        }
                    }
                }
            }
        }
    }

    private func chartStyleLabel(_ style: MenuBarChartStyle) -> String {
        switch style {
        case .sparkline:
            return AppLocalization.text("settings.menuBar.chartStyle.sparkline")
        case .matrix:
            return AppLocalization.text("settings.menuBar.chartStyle.matrix")
        }
    }
}
