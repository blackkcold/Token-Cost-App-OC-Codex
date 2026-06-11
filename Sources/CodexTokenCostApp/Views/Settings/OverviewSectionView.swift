import SwiftUI
import CodexTokenCostCore

struct OverviewSectionView: View {
    @ObservedObject var openCodeModel: TokenCostModel
    @ObservedObject var codexModel: CodexSessionModel
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    @ObservedObject var balanceManager: BalanceManager
    let palette: TokenCostPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            summaryCard
            dataSourceStatusCard
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        SettingsSurfaceCard(
            title: AppLocalization.text("overview.settings.title"),
            subtitle: AppLocalization.text("overview.settings.subtitle"),
            role: .primary,
            palette: palette
        ) {
            let payload = openCodeModel.selectedPayload

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 4),
                alignment: .leading,
                spacing: 10
            ) {
                SettingsSummaryCard(
                    title: "overview.monthlyCost".localized,
                    value: monthlyCostText(payload: payload),
                    subtitle: "",
                    systemImage: "dollarsign.circle",
                    tint: palette.accent,
                    palette: palette
                )
                SettingsSummaryCard(
                    title: "overview.opencodeTokens".localized,
                    value: openCodeTokensText,
                    subtitle: "",
                    systemImage: "text.word.spacing",
                    tint: palette.accentSecondary,
                    palette: palette
                )
                SettingsSummaryCard(
                    title: "overview.codexSessions".localized,
                    value: codexSessionsText,
                    subtitle: "",
                    systemImage: "rectangle.stack",
                    tint: .green,
                    palette: palette
                )
                SettingsSummaryCard(
                    title: "overview.balanceProviders".localized,
                    value: "\(balanceManager.snapshots.count)",
                    subtitle: "",
                    systemImage: "chart.bar",
                    tint: .orange,
                    palette: palette
                )
            }
        }
    }

    // MARK: - Data Source Status Card

    private var dataSourceStatusCard: some View {
        SettingsSurfaceCard(
            title: "overview.dataSourceStatus".localized,
            subtitle: "overview.dataSourceStatusSubtitle".localized,
            role: .secondary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 8) {
                dataSourceRow(
                    label: AppLocalization.text("source.family.opencode"),
                    status: openCodeModel.statusMessage,
                    hasSources: openCodeModel.hasSources,
                    isRefreshing: openCodeModel.isRefreshing
                )
                Divider().opacity(0.3)
                dataSourceRow(
                    label: AppLocalization.text("source.family.codex"),
                    status: codexModel.statusMessage,
                    hasSources: !codexModel.discoverySources.isEmpty,
                    isRefreshing: codexModel.isRefreshing
                )
                Divider().opacity(0.3)
                dataSourceRow(
                    label: AppLocalization.text("settings.balance.title"),
                    status: balanceManager.snapshots.isEmpty
                        ? "overview.balanceNotRefreshed".localized
                        : "overview.balanceLastRefresh".localized,
                    hasSources: !balanceManager.snapshots.isEmpty,
                    isRefreshing: balanceManager.isRefreshing
                )
            }
        }
    }

    private func dataSourceRow(label: String, status: String, hasSources: Bool, isRefreshing: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(hasSources ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.title)
                .frame(width: 120, alignment: .leading)
            Text(status)
                .font(.caption2)
                .foregroundStyle(palette.subtitle)
                .lineLimit(1)
            Spacer()
            if isRefreshing {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            }
        }
    }

    // MARK: - Value Formatters

    private func monthlyCostText(payload: DashboardPayload?) -> String {
        guard let payload,
              let cost = appPreferencesModel.preferences.combinedMonthlyCost(payload: payload) else {
            return "--"
        }
        return TokenCostCurrencyService.format(
            TokenCostCurrencyService.convert(cost, from: .usd, to: appPreferencesModel.preferences.displayCurrency),
            currency: appPreferencesModel.preferences.displayCurrency
        )
    }

    private var openCodeTokensText: String {
        guard let total = openCodeModel.selectedPayload?.summary.totalTokens, total > 0 else {
            return "--"
        }
        return TokenCostFormatters.tokens(total)
    }

    private var codexSessionsText: String {
        guard let count = codexModel.payload?.summary.sessionCount, count > 0 else {
            return "--"
        }
        return "\(count)"
    }
}

private extension String {
    var localized: String {
        AppLocalization.text(self)
    }
}
