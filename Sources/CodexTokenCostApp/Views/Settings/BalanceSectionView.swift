import SwiftUI
import CodexTokenCostCore

struct BalanceSectionView: View {
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    @ObservedObject var balanceManager: BalanceManager
    let palette: TokenCostPalette
    @Binding var showBalanceNetworkAlert: Bool
    @Binding var goCookieInput: String
    @Binding var goCookieSaved: Bool
    @Binding var isTestingGoConnection: Bool
    @Binding var showGoTestResultAlert: Bool
    @Binding var goTestResultAlertTitle: String
    @Binding var goTestResultAlertMessage: String
    @Binding var showBrowserImportAlert: Bool
    @Binding var browserImportMessage: String?
    @Binding var isImportingFromBrowser: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            balanceToggleCard
            goCredentialsCard
            providerStatusCard
        }
    }

    // MARK: - Balance toggle card

    private var balanceToggleCard: some View {
        SettingsSurfaceCard(
            title: "settings.balance.title".localized,
            subtitle: "settings.balance.subtitle".localized,
            role: .primary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsControlGrid(minimumWidth: 220) {
                    SettingsControlTile(palette: palette, minHeight: 54) {
                        Toggle("settings.balance.enable".localized, isOn: appPreferencesModel.balanceEnabledBinding)
                    }

                    SettingsControlTile(palette: palette, minHeight: 54) {
                        SettingsInlineControlRow(
                            title: "settings.balance.refreshInterval".localized,
                            palette: palette
                        ) {
                            Picker("", selection: appPreferencesModel.balanceRefreshSecondsBinding) {
                                ForEach([30, 60, 300, 600, 900, 1800, 3600], id: \.self) { interval in
                                    Text(BalanceSectionView.formatRefreshInterval(interval))
                                        .tag(interval)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 160)
                        }
                    }
                }

                if appPreferencesModel.preferences.balanceEnabled {
                    Divider().opacity(0.3)

                    HStack(spacing: 10) {
                        Button {
                            Task { await balanceManager.refresh() }
                        } label: {
                            Label("settings.balance.refreshNow".localized, systemImage: "arrow.clockwise")
                        }
                        .settingsGlassButtonStyle(prominent: true)
                        .controlSize(.small)
                        .disabled(balanceManager.isRefreshing)

                        if balanceManager.isRefreshing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 20, height: 20)
                        }

                        if let lastRefresh = balanceManager.lastRefreshTime {
                            Text("\("settings.balance.lastRefreshAt".localized): \(formattedTime(lastRefresh))")
                                .font(.caption2)
                                .foregroundStyle(palette.subtitle)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Go credentials card

    private var goCredentialsCard: some View {
        SettingsSurfaceCard(
            title: "settings.opencodeGo.credentials.title".localized,
            subtitle: nil,
            role: .secondary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("settings.opencodeGo.credentials.workspaceID".localized)
                        .font(.caption)
                        .foregroundStyle(palette.title)
                        .frame(width: 100, alignment: .leading)
                    TextField(
                        AppLocalization.text("settings.opencodeGo.credentials.workspaceID"),
                        text: appPreferencesModel.opencodeGoWorkspaceIDBinding
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                }

                HStack(spacing: 8) {
                    Text("settings.opencodeGo.credentials.authCookie".localized)
                        .font(.caption)
                        .foregroundStyle(palette.title)
                        .frame(width: 100, alignment: .leading)
                    SecureField(
                        AppLocalization.text("settings.opencodeGo.credentials.authCookie"),
                        text: $goCookieInput
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                }

                if goCookieSaved {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text("settings.opencodeGo.credentials.saved".localized)
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        isTestingGoConnection = true
                    } label: {
                        Label("settings.action.testConnection".localized, systemImage: "network")
                    }
                    .settingsGlassButtonStyle(prominent: true)
                    .controlSize(.small)
                    .disabled(isTestingGoConnection)

                    Button {
                        showBrowserImportAlert = true
                    } label: {
                        Label("settings.opencodeGo.importFromBrowser".localized, systemImage: "safari")
                    }
                    .settingsGlassButtonStyle(prominent: false)
                    .controlSize(.small)
                    .disabled(isImportingFromBrowser)

                    if isImportingFromBrowser {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 20, height: 20)
                    }
                }

                if let importMsg = browserImportMessage {
                    Text(verbatim: importMsg)
                        .font(.caption2)
                        .foregroundStyle(palette.subtitle)
                        .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Provider status card

    private var providerStatusCard: some View {
        let snapshots = balanceManager.snapshots

        return SettingsSurfaceCard(
            title: "settings.balance.providerToggles".localized,
            subtitle: nil,
            role: .secondary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if snapshots.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(palette.subtitle)
                        Text("settings.balance.networkNotice".localized)
                            .font(.caption)
                            .foregroundStyle(palette.subtitle)
                    }
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                } else {
                    ForEach(snapshots) { snapshot in
                        providerSnapshotRow(snapshot)
                    }
                }

                if appPreferencesModel.preferences.balanceEnabled {
                    Divider().opacity(0.3)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(BalanceProviderKind.allCases, id: \.self) { kind in
                            let enabled = appPreferencesModel.preferences.balanceConfig?.enabledBalanceProviders.contains(kind) ?? (kind != .deepseek)
                            HStack(spacing: 8) {
                                Toggle("", isOn: Binding(
                                    get: { enabled },
                                    set: { newValue in
                                        appPreferencesModel.updateBalanceConfiguration { config in
                                            if newValue {
                                                if !config.enabledBalanceProviders.contains(kind) {
                                                    config.enabledBalanceProviders.append(kind)
                                                }
                                            } else {
                                                config.enabledBalanceProviders.removeAll { $0 == kind }
                                            }
                                        }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .labelsHidden()

                                Text(verbatim: kind.displayName)
                                    .font(.caption)
                                    .foregroundStyle(palette.title)

                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }

    private func providerSnapshotRow(_ snapshot: BalanceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: snapshot.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(snapshot.isAvailable ? .green : .red)

                Text(verbatim: snapshot.provider.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.title)

                Spacer()

                if snapshot.isAvailable {
                    if let pct = snapshot.usagePercent {
                        Text("\(Int(pct * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(usageColor(pct))
                    } else if let remaining = snapshot.remainingCredits {
                        let dc = appPreferencesModel.preferences.displayCurrency
                        let converted = TokenCostCurrencyService.convert(remaining, from: .usd, to: dc)
                        Text(TokenCostCurrencyService.format(converted, currency: dc))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                }
            }

            if snapshot.isAvailable {
                if let planType = snapshot.planType {
                    HStack(spacing: 4) {
                        Text(verbatim: planType)
                            .font(.system(size: 9))
                            .foregroundStyle(palette.subtitle)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(palette.accent.opacity(0.12)))
                    }
                    .padding(.leading, 20)
                }

                if let used = snapshot.usedCredits, let total = snapshot.totalCredits {
                    HStack(spacing: 4) {
                        let dc = appPreferencesModel.preferences.displayCurrency
                        let usedStr = TokenCostCurrencyService.format(TokenCostCurrencyService.convert(used, from: .usd, to: dc), currency: dc)
                        let totalStr = TokenCostCurrencyService.format(TokenCostCurrencyService.convert(total, from: .usd, to: dc), currency: dc)
                        Text("\(usedStr) / \(totalStr)")
                            .font(.caption2)
                            .foregroundStyle(palette.subtitle)
                    }
                    .padding(.leading, 20)
                }

                if let primaryLabel = snapshot.primaryWindowLabel, let primaryPct = snapshot.primaryWindowUsagePercent {
                    HStack(spacing: 4) {
                        Circle().fill(usageColor(primaryPct)).frame(width: 5, height: 5)
                        Text(verbatim: "\(primaryLabel): \(Int(primaryPct * 100))%")
                            .font(.system(size: 9))
                            .foregroundStyle(palette.subtitle)

                        if let resetAt = snapshot.primaryWindowResetAt {
                            Text("(\(formattedTime(resetAt)))")
                                .font(.system(size: 8))
                                .foregroundStyle(palette.subtitle.opacity(0.6))
                        }
                    }
                    .padding(.leading, 20)
                }

                if let quotaWindows = snapshot.quotaWindows {
                    ForEach(quotaWindows) { window in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(window.usedRatio.map(usageColor) ?? palette.subtitle)
                                .frame(width: 5, height: 5)
                            Text(verbatim: window.label)
                                .font(.system(size: 9))
                                .foregroundStyle(palette.subtitle)
                            if let used = window.usedRatio {
                                Text("\(Int(used * 100))%")
                                    .font(.system(size: 9).monospacedDigit())
                                    .foregroundStyle(usageColor(used))
                            }
                        }
                        .padding(.leading, 20)
                    }
                }

                if let valueEntries = snapshot.valueEntries {
                    ForEach(valueEntries) { entry in
                        HStack(spacing: 4) {
                            Text(verbatim: "\(entry.label):")
                                .font(.caption2)
                                .foregroundStyle(palette.subtitle)
                            Text(verbatim: "\(entry.currencyCode ?? "") \(String(format: "%.2f", entry.amount))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(palette.title)
                            if let granted = entry.grantedAmount {
                                Text(verbatim: " (+\(String(format: "%.2f", granted)))")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.leading, 20)
                    }
                }
            } else if let error = snapshot.errorMessage {
                Text(verbatim: error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.leading, 20)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.05)))
    }

    // MARK: - Helpers

    private func usageColor(_ pct: Double) -> Color {
        switch pct {
        case ..<0.50: return .green
        case ..<0.80: return .yellow
        case ..<0.95: return .orange
        default: return .red
        }
    }

    static func formatRefreshInterval(_ seconds: Int) -> String {
        if seconds < 60 {
            return AppLocalization.format("settings.balance.refreshIntervalSeconds", seconds)
        } else {
            let minutes = seconds / 60
            return AppLocalization.format("settings.balance.refreshIntervalOption", minutes)
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private extension String {
    var localized: String {
        AppLocalization.text(self)
    }
}
