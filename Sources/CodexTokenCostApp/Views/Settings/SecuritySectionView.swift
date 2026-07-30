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
            title: AppLocalization.text("settings.security.title"),
            subtitle: AppLocalization.text("settings.security.subtitle"),
            role: .primary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.title2)
                        .foregroundStyle(palette.accent)

                    Text(AppLocalization.text("settings.security.body"))
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
                            text: AppLocalization.text("settings.security.body")
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
            title: AppLocalization.text("settings.warning.title"),
            subtitle: AppLocalization.text("settings.warning.subtitle"),
            role: .warning,
            palette: palette
        ) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(palette.warning)
                Text(verbatim: message)
                    .font(.caption)
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    private func securityDetailRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(palette.accentSecondary)
                .frame(width: 16)
            Text(verbatim: text)
                .font(.caption)
                .foregroundStyle(palette.subtitle)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsInsetSurface(
            in: RoundedRectangle(cornerRadius: 10, style: .continuous),
            palette: palette
        )
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
        AppLocalization.text("settings.security.body")
    }
}
