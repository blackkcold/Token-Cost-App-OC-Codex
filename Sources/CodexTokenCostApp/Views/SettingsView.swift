import SwiftUI
import CodexTokenCostCore

struct SettingsView: View {
    @ObservedObject var openCodeModel: TokenCostModel
    @ObservedObject var codexModel: CodexSessionModel
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    @ObservedObject var balanceManager: BalanceManager
    @Environment(\.dismiss) private var dismiss

    @State private var isPricingDocPresented = false
    @State private var isAppPreferencesExpanded = true
    @State private var isBillingExpanded = false
    @State private var isBalanceExpanded = false
    @State private var isOpenCodeExpanded = false
    @State private var isOpenCodeScanRootsExpanded = false
    @State private var isOpenCodeManualDatabaseExpanded = false
    @State private var isCodexExpanded = false
    @State private var isCodexRootsExpanded = false
    @State private var isCodexManualExpanded = false
    @State private var isSkillsExpanded = false
    @State private var isSafetyExpanded = true

    @State private var scanRootsPageIndex = 0
    @State private var manualDatabasePageIndex = 0
    @State private var codexDiscoveryPageIndex = 0
    @State private var codexRootsPageIndex = 0
    @State private var codexManualPageIndex = 0
    @State private var showBalanceNetworkAlert = false
    @State private var goCookieInput: String = ""
    @State private var goCookieSaved: Bool = false
    @State private var isTestingGoConnection = false
    @State private var showGoTestResultAlert = false
    @State private var goTestResultAlertTitle = ""
    @State private var goTestResultAlertMessage = ""
    @State private var showBrowserImportAlert = false
    @State private var browserImportMessage: String?
    @State private var isImportingFromBrowser = false

    private let listPageSize = 10

    private var palette: TokenCostPalette {
        TokenCostPalette(theme: appPreferencesModel.preferences.theme)
    }

    var body: some View {
        ZStack {
            palette.pageBackground
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    settingsHeader
                    if !warningMessages.isEmpty {
                        settingsWarningSection
                    }
                    appPreferencesSection
                    billingPlanSection
                    balanceMonitorSection
                    openCodeModuleSection
                    codexModuleSection
                    skillsPanelSection
                    safetySection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var warningMessages: [(title: String, message: String)] {
        var messages: [(String, String)] = []
        if let message = openCodeModel.settingsLoadWarningMessage {
            messages.append((AppLocalization.text("source.family.opencode"), message))
        }
        if let message = codexModel.settingsLoadWarningMessage {
            messages.append((AppLocalization.text("source.family.codex"), message))
        }
        if let message = appPreferencesModel.loadWarningMessage {
            messages.append((AppLocalization.text("settings.appPreferences.title"), message))
        }
        return messages
    }

    private var settingsWarningSection: some View {
        TokenSectionCard(
            title: AppLocalization.text("settings.warning.title"),
            subtitle: AppLocalization.text("settings.warning.subtitle"),
            trailing: nil,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(warningMessages.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .frame(width: 64, alignment: .leading)

                        Text(item.message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.text("settings.title"))
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(palette.title)

            Text(AppLocalization.text("settings.subtitle"))
                .font(.callout)
                .foregroundStyle(palette.subtitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appPreferencesSection: some View {
        TokenCollapsibleSectionCard(
            title: AppLocalization.text("settings.appPreferences.title"),
            subtitle: AppLocalization.text("settings.appPreferences.subtitle"),
            isExpanded: $isAppPreferencesExpanded,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsControlGrid(minimumWidth: 260) {
                    SettingsControlTile(
                        title: AppLocalization.text("settings.language"),
                        palette: palette,
                        minHeight: 74
                    ) {
                        Picker("", selection: appPreferencesModel.languageBinding) {
                            ForEach(AppDisplayLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    SettingsControlTile(
                        title: AppLocalization.text("settings.currency.title"),
                        palette: palette,
                        minHeight: 74
                    ) {
                        Picker("", selection: appPreferencesModel.displayCurrencyBinding) {
                            ForEach(DisplayCurrency.allCases) { currency in
                                Text(currency.displayName).tag(currency)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    ForEach(TokenCostThemeChoice.allCases, id: \.self) { choice in
                        ThemeChoiceCard(
                            choice: choice,
                            isSelected: appPreferencesModel.preferences.theme == choice
                        ) {
                            appPreferencesModel.themeBinding.wrappedValue = choice
                        }
                    }
                }
            }
        }
    }

    private var billingPlanSection: some View {
        TokenCollapsibleSectionCard(
            title: AppLocalization.text("settings.billing.title"),
            subtitle: AppLocalization.text("settings.billing.subtitle"),
            trailing: AnyView(
                Button {
                    isPricingDocPresented = true
                } label: {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent)
            ),
            isExpanded: $isBillingExpanded,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    ForEach(BillingProvider.allCases.filter {
                        !BillingPlanCatalog.subscriptionPresets(for: $0).isEmpty
                    }) { provider in
                        BillingProviderPlanCard(
                            provider: provider,
                            appPreferencesModel: appPreferencesModel,
                            palette: palette
                        )
                    }
                }

                Text(AppLocalization.text("settings.billing.customCostHint"))
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
                Text(AppLocalization.text("settings.billing.apiOnlyProviders"))
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
            }
        }
        .sheet(isPresented: $isPricingDocPresented) {
            PricingDocView(palette: palette)
        }
    }

    private var codexHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.text("settings.codex.body"))
                .font(.callout)
                .foregroundStyle(palette.subtitle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var openCodeModuleSection: some View {
        TokenCollapsibleSectionCard(
            title: AppLocalization.text("settings.opencode.title"),
            subtitle: AppLocalization.text("settings.opencode.subtitle"),
            isExpanded: $isOpenCodeExpanded,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 12) {
                sourceSection
                scanRootsSection
                manualDatabaseSection
            }
        }
    }

    private var codexModuleSection: some View {
        TokenCollapsibleSectionCard(
            title: AppLocalization.text("settings.codex.title"),
            subtitle: AppLocalization.text("settings.codex.subtitle"),
            isExpanded: $isCodexExpanded,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 12) {
                codexHeader
                codexDiscoverySection
                codexSection
                codexRootsSection
                codexManualSection
            }
        }
    }

    private var codexDiscoverySection: some View {
        TokenSectionCard(
            title: AppLocalization.text("settings.codex.discovery.title"),
            subtitle: codexModel.shouldPromptForSourceConfirmation ? AppLocalization.text("settings.codex.discovery.prompt") : AppLocalization.text("settings.codex.discovery.ready"),
            trailing: nil,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(AppLocalization.text("settings.codex.discovery.body"))
                    .font(.callout)
                    .foregroundStyle(palette.subtitle)
                    .fixedSize(horizontal: false, vertical: true)

                if codexModel.discoverySources.isEmpty {
                    emptySettingsState(AppLocalization.text("settings.codex.discovery.empty"))
                } else {
                    let bounds = paginationBounds(
                        itemCount: codexModel.discoverySources.count,
                        pageIndex: codexDiscoveryPageIndex,
                        pageSize: listPageSize
                    )
                    let visibleSources = Array(codexModel.discoverySources[bounds.startIndex..<bounds.endIndex])

                    VStack(spacing: 8) {
                        ForEach(visibleSources) { source in
                            CodexDiscoveryRow(source: source, palette: palette)
                        }
                    }

                    if codexModel.discoverySources.count > listPageSize {
                        PaginationControls(
                            pageIndex: $codexDiscoveryPageIndex,
                            itemCount: codexModel.discoverySources.count,
                            pageSize: listPageSize,
                            palette: palette,
                            title: AppLocalization.text("settings.pagination.discoverySources")
                        )
                    }
                }

                SettingsActionWrap {
                    Button {
                        codexModel.refresh()
                    } label: {
                        Label(AppLocalization.text("settings.action.rescan"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        codexModel.addSourceRoot()
                    } label: {
                        Label(AppLocalization.text("settings.action.selectDirectory"), systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        codexModel.addSourceFile()
                    } label: {
                        Label(AppLocalization.text("settings.action.selectFile"), systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        dismiss()
                    } label: {
                        Label(AppLocalization.text("settings.action.close"), systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var sourceSection: some View {
        TokenSectionCard(
            title: AppLocalization.text("settings.source.title"),
            subtitle: AppLocalization.text("settings.source.subtitle"),
            trailing: nil,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsControlGrid {
                    SettingsControlTile(palette: palette, minHeight: 54) {
                        Toggle(AppLocalization.text("settings.source.autoRescan"), isOn: binding(\.autoRescan))
                    }

                    SettingsControlTile(palette: palette, minHeight: 54) {
                        Toggle(AppLocalization.text("settings.source.showZeroUsageProvider"), isOn: binding(\.showZeroUsageXiaomiProvider))
                    }

                    SettingsControlTile(palette: palette, minHeight: 62) {
                        Stepper(value: binding(\.maxScanDepth), in: 1...8) {
                            Text(AppLocalization.format("settings.source.scanDepth", openCodeModel.settings.maxScanDepth))
                        }
                    }

                    SettingsControlTile(palette: palette, minHeight: 62) {
                        Stepper(value: binding(\.snapshotRetentionCount), in: 1...20) {
                            Text(AppLocalization.format("settings.source.snapshotRetention", openCodeModel.settings.snapshotRetentionCount))
                        }
                    }
                }

                SettingsActionWrap {
                    Button {
                        openCodeModel.addScanRoot()
                    } label: {
                        Label(AppLocalization.text("settings.action.addInstallDirectory"), systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        openCodeModel.addDatabaseFile()
                    } label: {
                        Label(AppLocalization.text("settings.action.addDatabaseFile"), systemImage: "externaldrive.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        openCodeModel.rescanSources()
                    } label: {
                        Label(AppLocalization.text("settings.action.rescan"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var scanRootsSection: some View {
        TokenCollapsibleSectionCard(
            title: AppLocalization.text("settings.scanRoots.title"),
            subtitle: AppLocalization.text("settings.scanRoots.subtitle"),
            isExpanded: $isOpenCodeScanRootsExpanded,
            palette: palette
        ) {
            if openCodeModel.settings.scanRoots.isEmpty {
                emptySettingsState(AppLocalization.text("settings.empty.scanRoots"))
            } else {
                let bounds = paginationBounds(
                    itemCount: openCodeModel.settings.scanRoots.count,
                    pageIndex: scanRootsPageIndex,
                    pageSize: listPageSize
                )
                let visibleRoots = Array(openCodeModel.settings.scanRoots[bounds.startIndex..<bounds.endIndex])

                VStack(spacing: 8) {
                    ForEach(Array(visibleRoots.enumerated()), id: \.offset) { offset, path in
                        let index = bounds.startIndex + offset
                        SettingsPathRow(
                            path: path,
                            palette: palette
                        ) {
                            openCodeModel.removeScanRoot(at: IndexSet(integer: index))
                        }
                    }
                }

                if openCodeModel.settings.scanRoots.count > listPageSize {
                    PaginationControls(
                        pageIndex: $scanRootsPageIndex,
                        itemCount: openCodeModel.settings.scanRoots.count,
                        pageSize: listPageSize,
                        palette: palette,
                        title: AppLocalization.text("settings.pagination.installRoots")
                    )
                }
            }
        }
    }

    private var manualDatabaseSection: some View {
        TokenCollapsibleSectionCard(
            title: AppLocalization.text("settings.manualDatabase.title"),
            subtitle: AppLocalization.text("settings.manualDatabase.subtitle"),
            isExpanded: $isOpenCodeManualDatabaseExpanded,
            palette: palette
        ) {
            if openCodeModel.settings.manualDatabasePaths.isEmpty {
                emptySettingsState(AppLocalization.text("settings.empty.manualDatabase"))
            } else {
                let bounds = paginationBounds(
                    itemCount: openCodeModel.settings.manualDatabasePaths.count,
                    pageIndex: manualDatabasePageIndex,
                    pageSize: listPageSize
                )
                let visiblePaths = Array(openCodeModel.settings.manualDatabasePaths[bounds.startIndex..<bounds.endIndex])

                VStack(spacing: 8) {
                    ForEach(Array(visiblePaths.enumerated()), id: \.offset) { offset, path in
                        let index = bounds.startIndex + offset
                        SettingsPathRow(
                            path: path,
                            palette: palette
                        ) {
                            openCodeModel.removeDatabasePath(at: IndexSet(integer: index))
                        }
                    }
                }

                if openCodeModel.settings.manualDatabasePaths.count > listPageSize {
                    PaginationControls(
                        pageIndex: $manualDatabasePageIndex,
                        itemCount: openCodeModel.settings.manualDatabasePaths.count,
                        pageSize: listPageSize,
                        palette: palette,
                        title: AppLocalization.text("settings.pagination.manualDatabase")
                    )
                }
            }
        }
    }

    private var balanceMonitorSection: some View {
        TokenCollapsibleSectionCard(
            title: AppLocalization.text("settings.balance.title"),
            subtitle: AppLocalization.text("settings.balance.subtitle"),
            isExpanded: $isBalanceExpanded,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsControlGrid {
                    SettingsControlTile(palette: palette, minHeight: 54) {
                        Toggle(AppLocalization.text("settings.balance.enable"), isOn: balanceEnabledBinding)
                    }

                    if appPreferencesModel.preferences.balanceEnabled {
                        SettingsControlTile(palette: palette, minHeight: 74) {
                            SettingsInlineControlRow(
                                title: AppLocalization.text("settings.balance.refreshInterval"),
                                palette: palette
                            ) {
                                Picker("", selection: appPreferencesModel.balanceRefreshMinutesBinding) {
                                    Text(AppLocalization.format("settings.balance.refreshIntervalOption", 5)).tag(5)
                                    Text(AppLocalization.format("settings.balance.refreshIntervalOption", 10)).tag(10)
                                    Text(AppLocalization.format("settings.balance.refreshIntervalOption", 15)).tag(15)
                                    Text(AppLocalization.format("settings.balance.refreshIntervalOption", 30)).tag(30)
                                    Text(AppLocalization.format("settings.balance.refreshIntervalOption", 60)).tag(60)
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 120)
                            }
                        }

                        SettingsControlTile(palette: palette, minHeight: 74) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Button {
                                        Task { await balanceManager.refresh() }
                                    } label: {
                                        Label(AppLocalization.text("settings.balance.refreshNow"), systemImage: "arrow.clockwise")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(balanceManager.isRefreshing)

                                    if balanceManager.isRefreshing {
                                        smallInlineProgressIndicator
                                    }
                                }

                                if let lastRefresh = balanceManager.lastRefreshTime {
                                    Text(AppLocalization.format(
                                        "settings.balance.lastRefreshAt",
                                        TokenCostFormatters.localDateTime(ISO8601DateFormatter().string(from: lastRefresh))
                                    ))
                                        .font(.caption2)
                                        .foregroundStyle(palette.subtitle)
                                }
                            }
                        }
                    }
                }

                if appPreferencesModel.preferences.balanceEnabled {
                    Text(AppLocalization.text("settings.balance.networkNotice"))
                        .font(.caption2)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppLocalization.text("settings.balance.providerToggles"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.subtitle)

                        SettingsControlGrid {
                            ForEach(modelSelectableProviders, id: \.self) { provider in
                                SettingsControlTile(palette: palette, minHeight: 54) {
                                    Toggle(isOn: providerBinding(for: provider)) {
                                        Text(provider.displayName)
                                            .font(.caption)
                                    }
                                    .toggleStyle(.switch)
                                }
                            }

                            SettingsControlTile(palette: palette, minHeight: 54) {
                                Toggle(AppLocalization.text("settings.balance.allowEnvironmentCredentials"), isOn: envCredentialsBinding)
                                    .font(.caption)
                            }
                        }
                    }
                }

                Divider()

                SettingsFieldGroup(
                    title: AppLocalization.text("settings.opencodeGo.credentials.title"),
                    palette: palette,
                    spacing: 12
                ) {
                    TextField(AppLocalization.text("settings.opencodeGo.credentials.workspaceID"), text: appPreferencesModel.opencodeGoWorkspaceIDBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .controlSize(.small)

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 8) {
                            authCookieField
                            saveGoCookieButton
                            testGoConnectionButton
                            if isTestingGoConnection {
                                smallInlineProgressIndicator
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            authCookieField

                            HStack(spacing: 8) {
                                saveGoCookieButton
                                testGoConnectionButton
                                if isTestingGoConnection {
                                    smallInlineProgressIndicator
                                }
                            }
                        }
                    }

                    if goCookieSaved {
                        Text(AppLocalization.text("settings.opencodeGo.credentials.saved"))
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }

                    Text(AppLocalization.text("settings.opencodeGo.credentials.hint"))
                        .font(.caption2)
                        .foregroundStyle(palette.subtitle)

                    browserImportButton

                    if isImportingFromBrowser {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(AppLocalization.text("settings.balance.searchingBrowser"))
                                .font(.caption2)
                                .foregroundStyle(palette.subtitle)
                        }
                    }

                    if let message = browserImportMessage {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(message.contains(AppLocalization.text("settings.opencodeGo.import.success"))
                                ? .green : .red)
                    }
                }
            }
        }
        .alert(AppLocalization.text("settings.balance.networkAlertTitle"), isPresented: $showBalanceNetworkAlert) {
            Button(AppLocalization.text("settings.action.cancel"), role: .cancel) {
                appPreferencesModel.balanceEnabledBinding.wrappedValue = false
            }
            Button(AppLocalization.text("settings.balance.confirmEnable")) {
                appPreferencesModel.balanceEnabledBinding.wrappedValue = true
                Task { await balanceManager.refresh() }
            }
        } message: {
            Text(AppLocalization.text("settings.balance.networkAlertMessage"))
        }
        .alert(goTestResultAlertTitle, isPresented: $showGoTestResultAlert) {
            Button(AppLocalization.text("settings.action.close"), role: .cancel) { }
        } message: {
            Text(goTestResultAlertMessage)
        }
        .alert(AppLocalization.text("settings.opencodeGo.import.confirmTitle"), isPresented: $showBrowserImportAlert) {
            Button(AppLocalization.text("settings.action.cancel"), role: .cancel) {}
            Button(AppLocalization.text("settings.action.continueImport")) { Task { await importFromBrowser() } }
        } message: {
            Text(AppLocalization.text("settings.opencodeGo.import.confirmMessage"))
        }
    }

    private func testGoConnection() {
        Task { @MainActor in
            isTestingGoConnection = true
            defer { isTestingGoConnection = false }

            if !goCookieInput.isEmpty {
                SecureCredentialStore.shared.saveAuthCookie(goCookieInput)
                goCookieInput = ""
                goCookieSaved = true
            }

            guard let apiKey = AuthTokenProvider.token(for: .opencodeGo), !apiKey.isEmpty else {
                goTestResultAlertTitle = AppLocalization.text("settings.opencodeGo.test.failed")
                goTestResultAlertMessage = AppLocalization.text("settings.opencodeGo.test.noApiKey")
                showGoTestResultAlert = true
                return
            }

            let credentials = SecureCredentialStore.shared.discoverCredentials(
                allowEnvironment: effectiveBalanceConfiguration.allowEnvironmentCredentials
            )
            guard credentials.workspaceID != nil, credentials.cookie != nil else {
                goTestResultAlertTitle = AppLocalization.text("settings.opencodeGo.test.failed")
                goTestResultAlertMessage = AppLocalization.text("settings.opencodeGo.test.noCookie")
                showGoTestResultAlert = true
                return
            }

            let checker = OpenCodeGoBalanceChecker(
                allowEnvironmentCredentials: effectiveBalanceConfiguration.allowEnvironmentCredentials
            )
            let snapshot = await balanceManager.testSnapshot(for: checker, authToken: apiKey)

            if snapshot.isAvailable {
                goTestResultAlertTitle = AppLocalization.text("settings.opencodeGo.test.success")
                goTestResultAlertMessage = AppLocalization.text("settings.opencodeGo.test.successMessage")
            } else {
                let reason = snapshot.errorMessage ?? AppLocalization.text("settings.opencodeGo.test.unknownError")
                goTestResultAlertTitle = AppLocalization.text("settings.opencodeGo.test.failed")
                goTestResultAlertMessage = reason
            }
            showGoTestResultAlert = true
        }
    }

    private func importFromBrowser() async {
        isImportingFromBrowser = true
        browserImportMessage = nil
        defer { isImportingFromBrowser = false }

        let result = BrowserCookieExtractor.extractCredentials()
        guard let cookie = result.cookie else {
            browserImportMessage = AppLocalization.text("settings.opencodeGo.import.noBrowser")
            return
        }

        if let browserID = result.workspaceID {
            SecureCredentialStore.shared.saveWorkspaceID(browserID)
            appPreferencesModel.updatePreferences { prefs in
                prefs.opencodeGoWorkspaceID = browserID
            }
        }

        SecureCredentialStore.shared.saveAuthCookie(cookie)

        if result.workspaceID != nil || SecureCredentialStore.shared.getWorkspaceID() != nil {
            browserImportMessage = AppLocalization.text("settings.opencodeGo.import.success")
        } else {
            browserImportMessage = AppLocalization.text("settings.opencodeGo.import.partial")
        }
    }

    private var modelSelectableProviders: [BalanceProviderKind] {
        BalanceProviderKind.allCases
    }

    private var effectiveBalanceConfiguration: BalanceConfiguration {
        appPreferencesModel.effectiveBalanceConfiguration
    }

    private func providerBinding(for provider: BalanceProviderKind) -> Binding<Bool> {
        Binding(
            get: {
                effectiveBalanceConfiguration.enabledBalanceProviders.contains(provider)
            },
            set: { enabled in
                appPreferencesModel.updateBalanceConfiguration { config in
                    if enabled {
                        if !config.enabledBalanceProviders.contains(provider) {
                            config.enabledBalanceProviders.append(provider)
                            config.enabledBalanceProviders.sort { $0.sortOrder < $1.sortOrder }
                        }
                    } else {
                        config.enabledBalanceProviders.removeAll { $0 == provider }
                    }
                }
            }
        )
    }

    private var envCredentialsBinding: Binding<Bool> {
        Binding(
            get: { effectiveBalanceConfiguration.allowEnvironmentCredentials },
            set: { allow in
                appPreferencesModel.updateBalanceConfiguration { config in
                    config.allowEnvironmentCredentials = allow
                }
            }
        )
    }

    private var balanceEnabledBinding: Binding<Bool> {
        Binding(
            get: { appPreferencesModel.preferences.balanceEnabled },
            set: { newValue in
                if newValue, !appPreferencesModel.preferences.balanceEnabled {
                    showBalanceNetworkAlert = true
                } else {
                    appPreferencesModel.balanceEnabledBinding.wrappedValue = newValue
                }
            }
        )
    }

    private var authCookieField: some View {
        SecureField(AppLocalization.text("settings.opencodeGo.credentials.authCookie"), text: $goCookieInput)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .controlSize(.small)
    }

    private var saveGoCookieButton: some View {
        Button(AppLocalization.text("settings.action.save")) {
            if !goCookieInput.isEmpty {
                SecureCredentialStore.shared.saveAuthCookie(goCookieInput)
                goCookieInput = ""
                goCookieSaved = true
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    private var testGoConnectionButton: some View {
        Button(AppLocalization.text("settings.action.testConnection")) {
            testGoConnection()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isTestingGoConnection)
    }

    private var smallInlineProgressIndicator: some View {
        ProgressView()
            .scaleEffect(0.7)
            .frame(width: 16, height: 16)
    }

    private var browserImportButton: some View {
        Button(AppLocalization.text("settings.opencodeGo.importFromBrowser")) {
            showBrowserImportAlert = true
        }
        .disabled(isImportingFromBrowser)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var skillsShowSourceBinding: Binding<Bool> {
        Binding(
            get: { appPreferencesModel.preferences.skillsPanel.showSourceColumn },
            set: { newValue in
                appPreferencesModel.updateSkillsPanel(showSource: newValue)
            }
        )
    }

    private var skillsShowStateBinding: Binding<Bool> {
        Binding(
            get: { appPreferencesModel.preferences.skillsPanel.showStateColumn },
            set: { newValue in
                appPreferencesModel.updateSkillsPanel(showState: newValue)
            }
        )
    }

    private var skillsShowTagsBinding: Binding<Bool> {
        Binding(
            get: { appPreferencesModel.preferences.skillsPanel.showTagsColumn },
            set: { newValue in
                appPreferencesModel.updateSkillsPanel(showTags: newValue)
            }
        )
    }

    private var skillsPreviewLengthBinding: Binding<Int> {
        Binding(
            get: { appPreferencesModel.preferences.skillsPanel.previewLength },
            set: { newValue in
                appPreferencesModel.updateSkillsPanel(previewLength: newValue)
            }
        )
    }

    private var codexSection: some View {
        TokenSectionCard(
            title: AppLocalization.text("settings.codex.sources.title"),
            subtitle: AppLocalization.text("settings.codex.sources.subtitle"),
            trailing: nil,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsControlGrid {
                    SettingsControlTile(palette: palette, minHeight: 54) {
                        Toggle(AppLocalization.text("settings.codex.autoRescan"), isOn: codexBinding(\.autoRescan))
                    }

                    SettingsControlTile(palette: palette, minHeight: 62) {
                        Stepper(value: codexBinding(\.snapshotRetentionCount), in: 1...20) {
                            Text(AppLocalization.format("settings.codex.snapshotRetention", codexModel.settings.snapshotRetentionCount))
                        }
                    }
                }

                SettingsActionWrap {
                    Button {
                        codexModel.addSourceRoot()
                    } label: {
                        Label(AppLocalization.text("settings.action.addSessionDirectory"), systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        codexModel.addSourceFile()
                    } label: {
                        Label(AppLocalization.text("settings.action.addSessionFile"), systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        codexModel.refresh()
                    } label: {
                        Label(AppLocalization.text("settings.action.refreshCodex"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(role: .destructive) {
                        codexModel.resetSettingsToDefaults()
                    } label: {
                        Label(AppLocalization.text("settings.action.restoreCodexDefaults"), systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var codexRootsSection: some View {
        TokenCollapsibleSectionCard(
            title: AppLocalization.text("settings.codex.roots.title"),
            subtitle: codexModel.sourceRootsDescription,
            isExpanded: $isCodexRootsExpanded,
            palette: palette
        ) {
            if codexModel.settings.sourceRoots.isEmpty {
                emptySettingsState(AppLocalization.text("settings.empty.codexRoots"))
            } else {
                let bounds = paginationBounds(
                    itemCount: codexModel.settings.sourceRoots.count,
                    pageIndex: codexRootsPageIndex,
                    pageSize: listPageSize
                )
                let visibleRoots = Array(codexModel.settings.sourceRoots[bounds.startIndex..<bounds.endIndex])

                VStack(spacing: 8) {
                    ForEach(Array(visibleRoots.enumerated()), id: \.offset) { offset, path in
                        let index = bounds.startIndex + offset
                        SettingsPathRow(
                            path: path,
                            palette: palette
                        ) {
                            codexModel.removeSourceRoot(at: IndexSet(integer: index))
                        }
                    }
                }

                if codexModel.settings.sourceRoots.count > listPageSize {
                    PaginationControls(
                        pageIndex: $codexRootsPageIndex,
                        itemCount: codexModel.settings.sourceRoots.count,
                        pageSize: listPageSize,
                        palette: palette,
                        title: AppLocalization.text("settings.pagination.codexRoots")
                    )
                }
            }
        }
    }

    private var codexManualSection: some View {
        TokenCollapsibleSectionCard(
            title: AppLocalization.text("settings.codex.manual.title"),
            subtitle: codexModel.manualSourcePathsDescription,
            isExpanded: $isCodexManualExpanded,
            palette: palette
        ) {
            if codexModel.settings.manualSourcePaths.isEmpty {
                emptySettingsState(AppLocalization.text("settings.empty.codexManual"))
            } else {
                let bounds = paginationBounds(
                    itemCount: codexModel.settings.manualSourcePaths.count,
                    pageIndex: codexManualPageIndex,
                    pageSize: listPageSize
                )
                let visiblePaths = Array(codexModel.settings.manualSourcePaths[bounds.startIndex..<bounds.endIndex])

                VStack(spacing: 8) {
                    ForEach(Array(visiblePaths.enumerated()), id: \.offset) { offset, path in
                        let index = bounds.startIndex + offset
                        SettingsPathRow(
                            path: path,
                            palette: palette
                        ) {
                            codexModel.removeSourcePath(at: IndexSet(integer: index))
                        }
                    }
                }

                if codexModel.settings.manualSourcePaths.count > listPageSize {
                    PaginationControls(
                        pageIndex: $codexManualPageIndex,
                        itemCount: codexModel.settings.manualSourcePaths.count,
                        pageSize: listPageSize,
                        palette: palette,
                        title: AppLocalization.text("settings.pagination.codexManual")
                    )
                }
            }
        }
    }

    private var skillsPanelSection: some View {
        TokenCollapsibleSectionCard(
            title: AppLocalization.text("settings.skills.title"),
            subtitle: AppLocalization.text("settings.skills.subtitle"),
            isExpanded: $isSkillsExpanded,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsControlGrid(minimumWidth: 240) {
                    SettingsControlTile(palette: palette, minHeight: 54) {
                        Toggle(AppLocalization.text("settings.skills.showSourceBadges"), isOn: skillsShowSourceBinding)
                    }

                    SettingsControlTile(palette: palette, minHeight: 54) {
                        Toggle(AppLocalization.text("settings.skills.showStateIndicators"), isOn: skillsShowStateBinding)
                    }

                    SettingsControlTile(palette: palette, minHeight: 54) {
                        Toggle(AppLocalization.text("settings.skills.showTagBadges"), isOn: skillsShowTagsBinding)
                    }
                }

                SettingsControlTile(palette: palette, minHeight: 72) {
                    SettingsInlineControlRow(
                        title: AppLocalization.text("settings.skills.previewLength"),
                        palette: palette
                    ) {
                        Picker("", selection: skillsPreviewLengthBinding) {
                            Text("200").tag(200)
                            Text("300").tag(300)
                            Text("500").tag(500)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 220)
                    }
                }
            }
        }
    }

    private var safetySection: some View {
        TokenCollapsibleSectionCard(
            title: AppLocalization.text("settings.security.title"),
            subtitle: AppLocalization.text("settings.security.subtitle"),
            isExpanded: $isSafetyExpanded,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalization.text("settings.security.body"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    openCodeModel.resetSettingsToDefaults()
                } label: {
                    Label(AppLocalization.text("settings.action.restoreDefaults"), systemImage: "arrow.counterclockwise")
                }
            }
        }
    }

    private func paginationBounds(itemCount: Int, pageIndex: Int, pageSize: Int) -> (startIndex: Int, endIndex: Int) {
        guard itemCount > 0 else {
            return (0, 0)
        }
        let pageCount = max((itemCount + pageSize - 1) / pageSize, 1)
        let clampedPage = min(max(pageIndex, 0), pageCount - 1)
        let startIndex = clampedPage * pageSize
        let endIndex = min(startIndex + pageSize, itemCount)
        return (startIndex, endIndex)
    }

    private func emptySettingsState(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<TokenCostSettings, Value>) -> Binding<Value> {
        Binding(
            get: { openCodeModel.settings[keyPath: keyPath] },
            set: { newValue in
                openCodeModel.updateSettings { settings in
                    settings[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func codexBinding<Value>(_ keyPath: WritableKeyPath<TokenCostSettings, Value>) -> Binding<Value> {
        Binding(
            get: { codexModel.settings[keyPath: keyPath] },
            set: { newValue in
                codexModel.updateSettings { settings in
                    settings[keyPath: keyPath] = newValue
                }
            }
        )
    }
}

private struct BillingProviderPlanCard: View {
    let provider: BillingProvider
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    let palette: TokenCostPalette

    private var resolvedPlan: ResolvedBillingPlan {
        appPreferencesModel.preferences.resolvedBillingPlan(for: provider)
    }

    private var isCustomSelected: Bool {
        appPreferencesModel.preferences.billingSelection(for: provider).mode == .customMonthlyUSD
    }

    private var isSubscribed: Bool {
        resolvedPlan.isSubscribed
    }

    private var hasSubscriptionPresets: Bool {
        !BillingPlanCatalog.subscriptionPresets(for: provider).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(provider.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.subtitle)

            Toggle(isOn: appPreferencesModel.subscribedBinding(for: provider)) {
                Text(AppLocalization.text("settings.billing.subscribed"))
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .disabled(!hasSubscriptionPresets)

            if isSubscribed && hasSubscriptionPresets {
                Picker(provider.displayName, selection: appPreferencesModel.billingPlanOptionBinding(for: provider)) {
                    ForEach(BillingPlanCatalog.subscriptionPresets(for: provider)) { preset in
                        Text("\(preset.name) · \(preset.displayPrice)").tag(preset.id)
                    }
                    Text(AppLocalization.text("settings.billing.customPlan")).tag(BillingPlanCatalog.customOptionID)
                }
                .pickerStyle(.menu)

                if isCustomSelected {
                    HStack(spacing: 8) {
                        Text(appPreferencesModel.preferences.displayCurrency.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.subtitle)

                        TextField(
                            AppLocalization.text("settings.billing.customCost"),
                            value: appPreferencesModel.customBillingCostBinding(for: provider),
                            format: .number.precision(.fractionLength(2))
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                    }
                }

                Text(resolvedPlan.priceDescription)
                    .font(.caption)
                    .foregroundStyle(palette.title)

                if let preset = resolvedPlan.preset {
                    Text(preset.usageNote)
                        .font(.caption2)
                        .foregroundStyle(palette.subtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(resolvedPlan.priceDescription)
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(palette.cardStroke, lineWidth: 1)
                )
        )
    }
}

private struct SettingsPathRow: View {
    let path: String
    let palette: TokenCostPalette
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(palette.accent)

            Text(path)
                .font(.caption)
                .foregroundStyle(palette.title)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.cardStroke.opacity(0.65), lineWidth: 1)
        )
    }
}

private struct CodexDiscoveryRow: View {
    let source: TokenCostSource
    let palette: TokenCostPalette

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(source.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.title)
                        .lineLimit(1)

                    Text(source.locationKind.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.subtitle)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(palette.trackBackground, in: Capsule())
                }

                Text(source.displayPath)
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let origin = source.originURL?.path, origin != source.displayPath {
                    Text(AppLocalization.format("settings.codex.discovery.origin", origin))
                        .font(.caption2)
                        .foregroundStyle(palette.subtitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text(source.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(palette.subtitle)
            }

            Spacer(minLength: 0)

            SourceStatusPill(source: source, palette: palette)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.cardStroke.opacity(0.65), lineWidth: 1)
        )
    }
}

private struct ThemeChoiceCard: View {
    let choice: TokenCostThemeChoice
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        let palette = TokenCostPalette(theme: choice)
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.backgroundWashTop,
                                palette.backgroundWashBottom
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 58)
                    .overlay(
                        HStack(spacing: 8) {
                            Circle().fill(palette.accent).frame(width: 10, height: 10)
                            Circle().fill(palette.accentSecondary).frame(width: 10, height: 10)
                            Spacer()
                        }
                        .padding(12)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(palette.accent)
                                .padding(10)
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(choice.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(choice.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isSelected ? palette.accent : palette.cardStroke, lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: palette.cardShadow, radius: 10, x: 0, y: 6)
            )
        }
        .buttonStyle(.plain)
    }
}
