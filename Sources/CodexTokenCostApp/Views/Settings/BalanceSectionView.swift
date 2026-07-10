import SwiftUI
import CodexTokenCostCore

struct BalanceSectionView: View {
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    @ObservedObject var balanceManager: BalanceManager
    let palette: TokenCostPalette
    @Binding var showBalanceNetworkAlert: Bool
    @Binding var goWorkspaceIDInput: String
    @Binding var goCookieInput: String
    @Binding var goCookieSaved: Bool
    @Binding var isTestingGoConnection: Bool
    @Binding var isTestingOllamaConnection: Bool
    @Binding var showBrowserImportAlert: Bool
    @Binding var browserImportMessage: String?
    @Binding var isImportingFromBrowser: Bool
    @Binding var showOllamaBrowserImportAlert: Bool
    @Binding var ollamaBrowserImportMessage: String?
    @Binding var isImportingOllamaFromBrowser: Bool
    @Binding var ollamaCookieInput: String
    @Binding var ollamaCookieSaved: Bool

    @State private var expandedCredentialFor: BalanceProviderKind?
    @State private var showLegacyKeychainImportAlert = false
    @State private var legacyKeychainImportMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            balanceToggleCard
            balanceOrderCard
            providerStatusCard
        }
        .confirmationDialog(
            AppLocalization.text("settings.balance.importLegacyKeychain.title"),
            isPresented: $showLegacyKeychainImportAlert,
            titleVisibility: .visible
        ) {
            Button(AppLocalization.text("settings.action.continueImport")) {
                showLegacyKeychainImportAlert = false
                importLegacyKeychainCredentials()
            }
            Button(AppLocalization.text("settings.action.cancel"), role: .cancel) {}
        } message: {
            Text(AppLocalization.text("settings.balance.importLegacyKeychain.message"))
        }
    }

    private var balanceProviderOrder: [BalanceProviderKind] {
        appPreferencesModel.normalizedBalanceProviderOrder()
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

                    SettingsControlTile(palette: palette, minHeight: 54) {
                        SettingsInlineControlRow(
                            title: "settings.balance.menuBarDisplayMode".localized,
                            palette: palette
                        ) {
                            Picker("", selection: appPreferencesModel.balanceDisplayModeBinding) {
                                Text("settings.balance.displayMode.used".localized)
                                    .tag(BalanceDisplayMode.used)
                                Text("settings.balance.displayMode.remaining".localized)
                                    .tag(BalanceDisplayMode.remaining)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 160)
                        }
                    }

                    SettingsControlTile(palette: palette, minHeight: 54) {
                        SettingsInlineControlRow(
                            title: "settings.balance.credentialSource".localized,
                            palette: palette
                        ) {
                            Picker("", selection: appPreferencesModel.credentialSourceModeBinding) {
                                Text(CredentialSourceMode.autoBrowser.displayName)
                                    .tag(CredentialSourceMode.autoBrowser)
                                Text(CredentialSourceMode.keychainOnly.displayName)
                                    .tag(CredentialSourceMode.keychainOnly)
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

    // MARK: - Balance ordering card

    private var balanceOrderCard: some View {
        SettingsSurfaceCard(
            title: "settings.balance.order.title".localized,
            subtitle: "settings.balance.order.subtitle".localized,
            role: .secondary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle(
                        "settings.balance.order.locked".localized,
                        isOn: appPreferencesModel.balanceOrderLockedBinding
                    )
                    .font(.subheadline)
                    .foregroundStyle(palette.title)

                    Spacer()

                    Button {
                        appPreferencesModel.resetBalanceCustomOrder()
                    } label: {
                        Label("settings.balance.order.reset".localized, systemImage: "arrow.counterclockwise")
                    }
                    .settingsGlassButtonStyle(prominent: false)
                    .controlSize(.small)
                }

                if !appPreferencesModel.preferences.balanceOrderLocked {
                    List {
                        ForEach(balanceProviderOrder, id: \.self) { kind in
                            HStack(spacing: 8) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.caption2)
                                    .foregroundStyle(palette.subtitle)
                                Text(verbatim: kind.displayName)
                                    .font(.caption)
                                    .foregroundStyle(palette.title)
                            }
                            .padding(.vertical, 2)
                        }
                        .onMove { offsets, target in
                            var order = balanceProviderOrder
                            order.move(fromOffsets: offsets, toOffset: target)
                            appPreferencesModel.balanceCustomOrderBinding.wrappedValue = order
                        }
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 180, maxHeight: 300)
                    .scrollContentBackground(.hidden)
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
                            if kind == .ollama,
                               !appPreferencesModel.preferences.developerMode.ollamaUsageTrackingEnabled {
                                EmptyView()
                            } else {
                                providerToggleRow(for: kind)
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
                    let dedupLabels: Set<String> = [
                        snapshot.primaryWindowLabel,
                        snapshot.secondaryWindowLabel,
                        snapshot.tertiaryWindowLabel
                    ].compactMap { $0 }.reduce(into: Set<String>()) { $0.insert($1) }

                    ForEach(quotaWindows) { window in
                        if dedupLabels.contains(window.label) { EmptyView() } else {
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
                                if let resetAt = window.resetAt {
                                    Text("(\(formattedTime(resetAt)))")
                                        .font(.system(size: 8))
                                        .foregroundStyle(palette.subtitle.opacity(0.6))
                                }
                            }
                            .padding(.leading, 20)
                        }
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

    // MARK: - Provider toggle row (with collapsible credential input)

    @ViewBuilder
    private func providerToggleRow(for kind: BalanceProviderKind) -> some View {
        let defaultEnabled = BalanceConfiguration().enabledBalanceProviders
        let enabled = appPreferencesModel.preferences.balanceConfig?.enabledBalanceProviders.contains(kind)
            ?? defaultEnabled.contains(kind)
        let hasCredentialInput = kind == .opencodeGo || kind == .ollama

        VStack(alignment: .leading, spacing: 4) {
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

                if hasCredentialInput {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedCredentialFor = expandedCredentialFor == kind ? nil : kind
                        }
                    } label: {
                        Image(systemName: expandedCredentialFor == kind ? "chevron.up" : "key.fill")
                            .font(.caption2)
                            .foregroundStyle(palette.accent)
                    }
                    .buttonStyle(.plain)
                    .help(kind == .opencodeGo
                          ? "settings.opencodeGo.help.configure".localized
                          : "settings.ollama.help.configure".localized)
                }
            }

            if hasCredentialInput, expandedCredentialFor == kind {
                if kind == .opencodeGo {
                    goCredentialInputArea
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else if kind == .ollama {
                    ollamaCredentialInputArea
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - OpenCode Go credential input (collapsible)

    private var goCredentialInputArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("settings.opencodeGo.credentials.workspaceID".localized)
                    .font(.caption)
                    .foregroundStyle(palette.title)
                    .frame(width: 100, alignment: .leading)
                TextField(
                    AppLocalization.text("settings.opencodeGo.credentials.workspaceID"),
                    text: $goWorkspaceIDInput
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

            SettingsActionWrap(minimumWidth: 150, spacing: 10) {
                Button {
                    saveGoCredentials()
                } label: {
                    Label("settings.action.save".localized, systemImage: "checkmark.circle")
                }
                .settingsGlassButtonStyle(prominent: true)
                .controlSize(.small)

                Button {
                    clearGoCookie()
                } label: {
                    Label("settings.action.delete".localized, systemImage: "trash")
                }
                .settingsGlassButtonStyle(prominent: false)
                .controlSize(.small)

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

                Button {
                    showLegacyKeychainImportAlert = true
                } label: {
                    Label("settings.balance.importLegacyKeychain".localized, systemImage: "key.fill")
                }
                .settingsGlassButtonStyle(prominent: false)
                .controlSize(.small)

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

            if let legacyKeychainImportMessage {
                Text(verbatim: legacyKeychainImportMessage)
                    .font(.caption2)
                    .foregroundStyle(palette.subtitle)
                    .padding(.top, 2)
            }
        }
        .padding(.leading, 28)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.05)))
    }

    // MARK: - Ollama credential input (collapsible)

    private var ollamaCredentialInputArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(palette.accent)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings.ollama.credentials.title".localized)
                        .font(.caption)
                        .foregroundStyle(palette.title)
                    Text("settings.ollama.credentials.subtitle".localized)
                        .font(.caption2)
                        .foregroundStyle(palette.subtitle)
                }
            }

            HStack(spacing: 8) {
                Text("settings.ollama.credentials.cookieLabel".localized)
                    .font(.caption)
                    .foregroundStyle(palette.title)
                    .frame(width: 50, alignment: .leading)
                SecureField(
                    AppLocalization.text("settings.ollama.credentials.placeholder"),
                    text: $ollamaCookieInput
                )
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            }

            if ollamaCookieSaved {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("settings.ollama.credentials.saved".localized)
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }

            SettingsActionWrap(minimumWidth: 150, spacing: 10) {
                Button {
                    saveOllamaCookie()
                } label: {
                    Label("settings.action.save".localized, systemImage: "checkmark.circle")
                }
                .settingsGlassButtonStyle(prominent: true)
                .controlSize(.small)

                Button {
                    clearOllamaCookie()
                } label: {
                    Label("settings.action.delete".localized, systemImage: "trash")
                }
                .settingsGlassButtonStyle(prominent: false)
                .controlSize(.small)

                Button {
                    isTestingOllamaConnection = true
                } label: {
                    Label("settings.action.testConnection".localized, systemImage: "network")
                }
                .settingsGlassButtonStyle(prominent: true)
                .controlSize(.small)
                .disabled(isTestingOllamaConnection || balanceManager.isRefreshing)

                Button {
                    showOllamaBrowserImportAlert = true
                } label: {
                    Label("settings.opencodeGo.importFromBrowser".localized, systemImage: "safari")
                }
                .settingsGlassButtonStyle(prominent: false)
                .controlSize(.small)
                .disabled(isImportingOllamaFromBrowser)

                if balanceManager.isRefreshing || isTestingOllamaConnection || isImportingOllamaFromBrowser {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 20, height: 20)
                }
            }

            if let importMsg = ollamaBrowserImportMessage {
                Text(verbatim: importMsg)
                    .font(.caption2)
                    .foregroundStyle(palette.subtitle)
                    .padding(.top, 2)
            }

            if let ollamaSnapshot = balanceManager.snapshots.first(where: { $0.provider == .ollama }) {
                if !ollamaSnapshot.isAvailable, let error = ollamaSnapshot.errorMessage {
                    Text(verbatim: error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else if ollamaSnapshot.isAvailable {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            if let pct = ollamaSnapshot.usagePercent {
                                Text(String(format: "settings.ollama.status.used".localized, Int(pct * 100)))
                                    .font(.caption2)
                                    .foregroundStyle(usageColor(pct))
                            } else {
                                Text("settings.ollama.status.connected".localized)
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }

                        if let windows = ollamaSnapshot.quotaWindows, !windows.isEmpty {
                            ForEach(windows) { window in
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
                                    if let resetAt = window.resetAt {
                                        Text("(\(formattedTime(resetAt)))")
                                            .font(.system(size: 8))
                                            .foregroundStyle(palette.subtitle.opacity(0.6))
                                    }
                                }
                                .padding(.leading, 20)
                            }
                        }
                    }
                }
            }
        }
        .padding(.leading, 28)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.05)))
    }

    private func saveGoCredentials() {
        let workspaceID = goWorkspaceIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let cookie = goCookieInput.trimmingCharacters(in: .whitespacesAndNewlines)
        appPreferencesModel.saveLocalGoCredentials(
            workspaceID: workspaceID.isEmpty ? nil : workspaceID,
            cookie: cookie.isEmpty ? nil : cookie
        )
        reloadLocalCredentialFields()
        legacyKeychainImportMessage = nil
        browserImportMessage = nil
    }

    private func clearGoCookie() {
        appPreferencesModel.clearLocalGoCookiePreservingWorkspaceID()
        reloadLocalCredentialFields()
        legacyKeychainImportMessage = nil
        browserImportMessage = AppLocalization.text("settings.opencodeGo.credentials.cleared")
    }

    private func saveOllamaCookie() {
        let cookie = ollamaCookieInput.trimmingCharacters(in: .whitespacesAndNewlines)
        appPreferencesModel.saveLocalOllamaCookie(cookie.isEmpty ? nil : cookie)
        reloadLocalCredentialFields()
        legacyKeychainImportMessage = nil
        ollamaBrowserImportMessage = nil
    }

    private func clearOllamaCookie() {
        appPreferencesModel.clearLocalOllamaCookie()
        reloadLocalCredentialFields()
        legacyKeychainImportMessage = nil
        ollamaBrowserImportMessage = AppLocalization.text("settings.ollama.credentials.deleted")
    }

    private func reloadLocalCredentialFields() {
        let snapshot = appPreferencesModel.localCredentialSnapshot()
        goWorkspaceIDInput = snapshot.workspaceID ?? ""
        goCookieInput = snapshot.goCookie ?? ""
        goCookieSaved = !(snapshot.goCookie?.isEmpty ?? true)
        ollamaCookieInput = snapshot.ollamaCookie ?? ""
        ollamaCookieSaved = !(snapshot.ollamaCookie?.isEmpty ?? true)
    }

    private func syncBootstrapCache(with snapshot: AppPreferencesModel.LocalCredentialSnapshot) {
        let workspaceID = snapshot.workspaceID?.isEmpty == false ? snapshot.workspaceID : nil
        let goCookie = snapshot.goCookie?.isEmpty == false ? snapshot.goCookie : nil
        if workspaceID != nil || goCookie != nil {
            CredentialBootstrapService.shared.updateCachedGoCookie(
                goCookie,
                workspaceID: workspaceID
            )
        }
        if let ollamaCookie = snapshot.ollamaCookie {
            CredentialBootstrapService.shared.updateCachedOllamaCookie(
                ollamaCookie.isEmpty ? nil : ollamaCookie
            )
        }
    }

    private func importLegacyKeychainCredentials() {
        let result = LocalCredentialService.shared.importLegacyKeychainCredentials()
        let snapshot = appPreferencesModel.localCredentialSnapshot()
        syncBootstrapCache(with: snapshot)
        reloadLocalCredentialFields()
        if result.didCopy {
            legacyKeychainImportMessage = AppLocalization.format(
                "settings.balance.importLegacyKeychain.success",
                result.copiedFields.count
            )
        } else {
            legacyKeychainImportMessage = AppLocalization.text("settings.balance.importLegacyKeychain.none")
        }
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
