import SwiftUI
import CodexTokenCostCore

struct SecuritySectionView: View {
    @ObservedObject var openCodeModel: TokenCostModel
    let palette: TokenCostPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            securityInfoCard
            if let warning = openCodeModel.settingsLoadWarningMessage, !warning.isEmpty {
                warningCard(warning)
            }
        }
    }

    private var securityInfoCard: some View {
        SettingsSurfaceCard(
            title: "settings.security.title".localized,
            subtitle: "settings.security.subtitle".localized,
            role: .primary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.title2)
                        .foregroundStyle(palette.accent)

                    Text("settings.security.body".localized)
                        .font(.caption)
                        .foregroundStyle(palette.title)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().opacity(0.3)

                VStack(alignment: .leading, spacing: 8) {
                    SettingsControlGrid(minimumWidth: 280) {
                        securityDetailRow(
                            icon: "house",
                            text: sourceLocationsSummary
                        )
                        securityDetailRow(
                            icon: "lock.doc",
                            text: "settings.security.body".localized
                        )
                        securityDetailRow(
                            icon: "antenna.radiowaves.left.and.right",
                            text: networkUsageSummary
                        )
                    }
                }
            }
        }
    }

    private func warningCard(_ message: String) -> some View {
        SettingsSurfaceCard(
            title: "settings.warning.title".localized,
            subtitle: "settings.warning.subtitle".localized,
            role: .warning,
            palette: palette
        ) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(verbatim: message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    private func securityDetailRow(icon: String, text: String) -> some View {
        SettingsControlTile(palette: palette, minHeight: 60) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(palette.accentSecondary)
                    .frame(width: 16)
                Text(verbatim: text)
                    .font(.caption2)
                    .foregroundStyle(palette.subtitle)
                    .lineLimit(3)
            }
        }
    }

    private var sourceLocationsSummary: String {
        let roots = openCodeModel.settings.effectiveSourceRoots
        let manual = openCodeModel.settings.effectiveManualSourcePaths
        let total = roots.count + manual.count
        if total == 0 {
            return AppLocalization.text("settings.security.body")
        }
        let available = openCodeModel.sources.filter(\.isAvailable).count
        return AppLocalization.format(
            "pagination.summary",
            available, total, total, 1, total
        )
    }

    private var networkUsageSummary: String {
        "settings.security.body".localized
    }
}

private extension String {
    var localized: String {
        AppLocalization.text(self)
    }
}
