import SwiftUI
import CodexTokenCostCore

struct SettingsView: View {
    @ObservedObject var openCodeModel: TokenCostModel
    @ObservedObject var codexModel: CodexSessionModel
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    @ObservedObject var balanceManager: BalanceManager
    @Environment(\.dismiss) private var dismiss

    @State private var isPricingDocPresented = false
    @State private var isDeveloperDocPresented = false
    @State private var selectedSection: SettingsSection = .overview

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

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case overview
        case preferences
        case billing
        case balance
        case opencode
        case codex
        case skills
        case security
        case developer

        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            palette.pageBackground
                .ignoresSafeArea()

            NavigationSplitView {
                settingsSidebar
            } detail: {
                settingsDetail
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 720)
        .sheet(isPresented: $isPricingDocPresented) {
            PricingDocView(palette: palette)
        }
        .sheet(isPresented: $isDeveloperDocPresented) {
            DeveloperModeDocView(palette: palette)
        }
    }

    private var settingsSidebar: some View {
        List(selection: $selectedSection) {
            ForEach(SettingsSection.allCases) { section in
                SettingsSidebarRow(
                    title: title(for: section),
                    subtitle: subtitle(for: section),
                    iconName: iconName(for: section),
                    badge: badge(for: section),
                    badgeTint: badgeTint(for: section),
                    palette: palette
                )
                .tag(section)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(AppLocalization.text("settings.title"))
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
    }

    private var settingsDetail: some View {
        ScrollView {
            Group {
                if #available(macOS 26, *) {
                    GlassEffectContainer(spacing: 18) {
                        settingsDetailStack
                    }
                } else {
                    settingsDetailStack
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    private var settingsDetailStack: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !warningMessages.isEmpty {
                settingsWarningBanner
            }

            selectedSectionContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsWarningBanner: some View {
        SettingsSurfaceCard(
            title: AppLocalization.text("settings.warning.title"),
            subtitle: AppLocalization.text("settings.warning.subtitle"),
            role: .warning,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(warningMessages.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .frame(width: 110, alignment: .leading)

                        Text(item.message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedSection {
        case .overview:
            overviewSection
        case .preferences:
            preferencesSection
        case .billing:
            billingSection
        case .balance:
            balanceSection
        case .opencode:
            openCodeSection
        case .codex:
            codexSettingsSection
        case .skills:
            skillsSection
        case .security:
            securitySection
        case .developer:
            developerSection
        }
    }

    private var overviewSection: some View {
        SettingsSurfaceCard(
            title: AppLocalization.text("overview.settings.title"),
            subtitle: AppLocalization.text("overview.settings.subtitle"),
            trailing: AnyView(
                Button {
                    openCodeModel.rescanSources()
                    codexModel.refresh()
                    Task { await balanceManager.refresh() }
                } label: {
                    Label(AppLocalization.text("tab.action.refreshAll"), systemImage: "arrow.clockwise")
                }
                .settingsGlassButtonStyle(prominent: true)
                .controlSize(.small)
            ),
            palette: palette
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top)],
                alignment: .leading,
                spacing: 12
            ) {
                SettingsSummaryCard(
                    title: AppLocalization.text("settings.appPreferences.title"),
                    value: "\(appPreferencesModel.preferences.theme.displayName) · \(appPreferencesModel.preferences.language.displayName) · \(appPreferencesModel.preferences.displayCurrency.displayName)",
                    subtitle: AppLocalization.text("settings.appPreferences.subtitle"),
                    systemImage: "slider.horizontal.3",
                    tint: palette.accent,
                    palette: palette
                )

                SettingsSummaryCard(
                    title: AppLocalization.text("settings.opencode.title"),
                    value: "\(openCodeModel.settings.scanRoots.count + openCodeModel.settings.manualDatabasePaths.count)",
                    subtitle: "\(openCodeModel.settings.scanRoots.count) roots · \(openCodeModel.settings.manualDatabasePaths.count) files",
                    systemImage: "externaldrive",
                    tint: palette.accentSecondary,
                    palette: palette
                )

                SettingsSummaryCard(
                    title: AppLocalization.text("settings.codex.title"),
                    value: "\(codexModel.settings.sourceRoots.count + codexModel.settings.manualSourcePaths.count)",
                    subtitle: "\(codexModel.settings.sourceRoots.count) roots · \(codexModel.settings.manualSourcePaths.count) files",
                    systemImage: "terminal",
                    tint: .green,
                    palette: palette
                )

                SettingsSummaryCard(
                    title: AppLocalization.text("settings.balance.title"),
                    value: appPreferencesModel.preferences.balanceEnabled ? AppLocalization.text("common.ready") : AppLocalization.text("common.unavailable"),
                    subtitle: "\(effectiveBalanceConfiguration.enabledBalanceProviders.count) providers · \(appPreferencesModel.preferences.balanceRefreshMinutes) min refresh",
                    systemImage: "chart.bar.xaxis",
                    tint: appPreferencesModel.preferences.balanceEnabled ? .green : .orange,
                    palette: palette
                )

                SettingsSummaryCard(
                    title: AppLocalization.text("settings.developerMode.title"),
                    value: appPreferencesModel.preferences.developerMode.isEnabled ? AppLocalization.text("common.ready") : AppLocalization.text("common.unavailable"),
                    subtitle: AppLocalization.text("settings.developerMode.subtitle"),
                    systemImage: "wrench.and.screwdriver",
                    tint: appPreferencesModel.preferences.developerMode.isEnabled ? palette.accent : palette.subtitle,
                    palette: palette
                )
            }
        }
    }

    private func title(for section: SettingsSection) -> String {
        switch section {
        case .overview:
            return AppLocalization.text("overview.settings.title")
        case .preferences:
            return AppLocalization.text("settings.appPreferences.title")
        case .billing:
            return AppLocalization.text("settings.billing.title")
        case .balance:
            return AppLocalization.text("settings.balance.title")
        case .opencode:
            return AppLocalization.text("settings.opencode.title")
        case .codex:
            return AppLocalization.text("settings.codex.title")
        case .skills:
            return AppLocalization.text("settings.skills.title")
        case .security:
            return AppLocalization.text("settings.security.title")
        case .developer:
            return AppLocalization.text("settings.developerMode.title")
        }
    }

    private func subtitle(for section: SettingsSection) -> String {
        switch section {
        case .overview:
            return AppLocalization.text("overview.settings.subtitle")
        case .preferences:
            return AppLocalization.text("settings.appPreferences.subtitle")
        case .billing:
            return AppLocalization.text("settings.billing.subtitle")
        case .balance:
            return AppLocalization.text("settings.balance.subtitle")
        case .opencode:
            return AppLocalization.text("settings.opencode.subtitle")
        case .codex:
            return AppLocalization.text("settings.codex.subtitle")
        case .skills:
            return AppLocalization.text("settings.skills.subtitle")
        case .security:
            return AppLocalization.text("settings.security.subtitle")
        case .developer:
            return AppLocalization.text("settings.developerMode.subtitle")
        }
    }

    private func iconName(for section: SettingsSection) -> String {
        switch section {
        case .overview:
            return "square.grid.2x2"
        case .preferences:
            return "slider.horizontal.3"
        case .billing:
            return "creditcard"
        case .balance:
            return "chart.bar.xaxis"
        case .opencode:
            return "externaldrive"
        case .codex:
            return "terminal"
        case .skills:
            return "gearshape.2"
        case .security:
            return "lock.shield"
        case .developer:
            return "wrench.and.screwdriver"
        }
    }

    private func badge(for section: SettingsSection) -> String? {
        switch section {
        case .overview:
            return warningMessages.isEmpty ? nil : "\(warningMessages.count)"
        case .preferences:
            return appPreferencesModel.preferences.theme.displayName
        case .billing:
            return "\(billingProviderCount)"
        case .balance:
            return appPreferencesModel.preferences.balanceEnabled ? AppLocalization.text("common.ready") : AppLocalization.text("common.unavailable")
        case .opencode:
            return "\(openCodeModel.settings.scanRoots.count + openCodeModel.settings.manualDatabasePaths.count)"
        case .codex:
            return "\(codexModel.settings.sourceRoots.count + codexModel.settings.manualSourcePaths.count)"
        case .skills:
            return "\(appPreferencesModel.preferences.skillsPanel.previewLength)"
        case .security:
            return nil
        case .developer:
            return appPreferencesModel.preferences.developerMode.isEnabled ? AppLocalization.text("common.ready") : AppLocalization.text("common.unavailable")
        }
    }

    private func badgeTint(for section: SettingsSection) -> Color {
        switch section {
        case .overview:
            return warningMessages.isEmpty ? palette.accent : .orange
        case .preferences:
            return palette.accent
        case .billing:
            return palette.accentSecondary
        case .balance:
            return appPreferencesModel.preferences.balanceEnabled ? .green : .orange
        case .opencode:
            return palette.accent
        case .codex:
            return palette.accentSecondary
        case .skills:
            return palette.accent
        case .security:
            return .red
        case .developer:
            return appPreferencesModel.preferences.developerMode.isEnabled ? palette.accent : palette.subtitle
        }
    }

    private var billingProviderCount: Int {
        BillingProvider.allCases.filter {
            !BillingPlanCatalog.subscriptionPresets(for: $0).isEmpty
        }.count
    }

    // MARK: - Sections

    private var preferencesSection: some View {
        SettingsSurfaceCard(
            title: AppLocalization.text("settings.appPreferences.title"),
            subtitle: AppLocalization.text("settings.appPreferences.subtitle"),
            role: .primary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 18) {
                SettingsControlGrid(minimumWidth: 250) {
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

                SettingsFieldGroup(
                    title: AppLocalization.text("settings.theme.title"),
                    palette: palette,
                    spacing: 10
                ) {
                    Text(AppLocalization.text("settings.theme.subtitle"))
                        .font(.caption)
                        .foregroundStyle(palette.subtitle)
                        .fixedSize(horizontal: false, vertical: true)

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
    }

    private var billingSection: some View {
        SettingsSurfaceCard(
            title: AppLocalization.text("settings.billing.title"),
            subtitle: AppLocalization.text("settings.billing.subtitle"),
            trailing: AnyView(
                Button {
                    isPricingDocPresented = true
                } label: {
                    Label(AppLocalization.text("settings.billing.pricingDoc"), systemImage: "doc.text")
                }
                .settingsGlassButtonStyle()
                .controlSize(.small)
            ),
            role: .secondary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)], spacing: 12) {
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
                    .fixedSize(horizontal: false, vertical: true)

                Text(AppLocalization.text("settings.billing.apiOnlyProviders"))
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSurfaceCard(
                title: AppLocalization.text("settings.balance.title"),
                subtitle: AppLocalization.text("settings.balance.subtitle"),
                trailing: AnyView(
                    Button {
                        Task { await balanceManager.refresh() }
                    } label: {
                        Label(AppLocalization.text("settings.balance.refreshNow"), systemImage: "arrow.clockwise")
                    }
                    .settingsGlassButtonStyle()
                    .controlSize(.small)
                ),
                role: .primary,
                palette: palette
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsControlGrid {
                        SettingsControlTile(palette: palette, minHeight: 54) {
                            Toggle(AppLocalization.text("settings.balance.enable"), isOn: balanceEnabledBinding)
                        }

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
                                    .settingsGlassButtonStyle()
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

                    if appPreferencesModel.preferences.balanceEnabled {
                        Text(AppLocalization.text("settings.balance.networkNotice"))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if appPreferencesModel.preferences.balanceEnabled {
                SettingsSurfaceCard(
                    title: AppLocalization.text("settings.balance.providerToggles"),
                    subtitle: AppLocalization.text("settings.balance.allowEnvironmentCredentials"),
                    role: .secondary,
                    palette: palette
                ) {
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

            SettingsSurfaceCard(
                title: AppLocalization.text("settings.opencodeGo.credentials.title"),
                subtitle: AppLocalization.text("settings.opencodeGo.credentials.hint"),
                role: .secondary,
                palette: palette
            ) {
                SettingsFieldGroup(palette: palette, spacing: 12) {
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
    }

    private var openCodeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSurfaceCard(
                title: AppLocalization.text("settings.source.title"),
                subtitle: AppLocalization.text("settings.source.subtitle"),
                role: .primary,
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
                        .settingsGlassButtonStyle()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            openCodeModel.addDatabaseFile()
                        } label: {
                            Label(AppLocalization.text("settings.action.addDatabaseFile"), systemImage: "doc.badge.plus")
                        }
                        .settingsGlassButtonStyle()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            openCodeModel.rescanSources()
                        } label: {
                            Label(AppLocalization.text("settings.action.rescan"), systemImage: "arrow.clockwise")
                        }
                        .settingsGlassButtonStyle()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            SettingsSurfaceCard(
                title: AppLocalization.text("settings.opencode.title"),
                subtitle: AppLocalization.text("settings.opencode.subtitle"),
                role: .secondary,
                palette: palette
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    pagedPathListSection(
                        title: AppLocalization.text("settings.scanRoots.title"),
                        subtitle: AppLocalization.text("settings.scanRoots.subtitle"),
                        paths: openCodeModel.settings.scanRoots,
                        pageIndex: $scanRootsPageIndex,
                        emptyMessage: AppLocalization.text("settings.empty.scanRoots"),
                        paginationTitle: AppLocalization.text("settings.pagination.installRoots"),
                        systemImage: "folder"
                    ) { index in
                        openCodeModel.removeScanRoot(at: IndexSet(integer: index))
                    }

                    Divider()

                    pagedPathListSection(
                        title: AppLocalization.text("settings.manualDatabase.title"),
                        subtitle: AppLocalization.text("settings.manualDatabase.subtitle"),
                        paths: openCodeModel.settings.manualDatabasePaths,
                        pageIndex: $manualDatabasePageIndex,
                        emptyMessage: AppLocalization.text("settings.empty.manualDatabase"),
                        paginationTitle: AppLocalization.text("settings.pagination.manualDatabase"),
                        systemImage: "doc"
                    ) { index in
                        openCodeModel.removeDatabasePath(at: IndexSet(integer: index))
                    }
                }
            }
        }
    }

    private var codexSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSurfaceCard(
                title: AppLocalization.text("settings.codex.sources.title"),
                subtitle: AppLocalization.text("settings.codex.sources.subtitle"),
                role: .primary,
                palette: palette
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(AppLocalization.text("settings.codex.body"))
                        .font(.callout)
                        .foregroundStyle(palette.subtitle)
                        .fixedSize(horizontal: false, vertical: true)

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
                        .settingsGlassButtonStyle()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            codexModel.addSourceFile()
                        } label: {
                            Label(AppLocalization.text("settings.action.addSessionFile"), systemImage: "doc.badge.plus")
                        }
                        .settingsGlassButtonStyle()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            codexModel.refresh()
                        } label: {
                            Label(AppLocalization.text("settings.action.refreshCodex"), systemImage: "arrow.clockwise")
                        }
                        .settingsGlassButtonStyle()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button(role: .destructive) {
                            codexModel.resetSettingsToDefaults()
                        } label: {
                            Label(AppLocalization.text("settings.action.restoreCodexDefaults"), systemImage: "arrow.counterclockwise")
                        }
                        .settingsGlassButtonStyle(prominent: true)
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            SettingsSurfaceCard(
                title: AppLocalization.text("settings.codex.discovery.title"),
                subtitle: codexModel.shouldPromptForSourceConfirmation ? AppLocalization.text("settings.codex.discovery.prompt") : AppLocalization.text("settings.codex.discovery.ready"),
                role: .secondary,
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

                    Divider()

                    pagedPathListSection(
                        title: AppLocalization.text("settings.codex.roots.title"),
                        subtitle: codexModel.sourceRootsDescription,
                        paths: codexModel.settings.sourceRoots,
                        pageIndex: $codexRootsPageIndex,
                        emptyMessage: AppLocalization.text("settings.empty.codexRoots"),
                        paginationTitle: AppLocalization.text("settings.pagination.codexRoots"),
                        systemImage: "folder"
                    ) { index in
                        codexModel.removeSourceRoot(at: IndexSet(integer: index))
                    }

                    Divider()

                    pagedPathListSection(
                        title: AppLocalization.text("settings.codex.manual.title"),
                        subtitle: codexModel.manualSourcePathsDescription,
                        paths: codexModel.settings.manualSourcePaths,
                        pageIndex: $codexManualPageIndex,
                        emptyMessage: AppLocalization.text("settings.empty.codexManual"),
                        paginationTitle: AppLocalization.text("settings.pagination.codexManual"),
                        systemImage: "doc"
                    ) { index in
                        codexModel.removeSourcePath(at: IndexSet(integer: index))
                    }

                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            dismiss()
                        } label: {
                            Label(AppLocalization.text("settings.action.close"), systemImage: "xmark")
                        }
                        .settingsGlassButtonStyle()
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var skillsSection: some View {
        SettingsSurfaceCard(
            title: AppLocalization.text("settings.skills.title"),
            subtitle: AppLocalization.text("settings.skills.subtitle"),
            role: .secondary,
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

    private var securitySection: some View {
        SettingsSurfaceCard(
            title: AppLocalization.text("settings.security.title"),
            subtitle: AppLocalization.text("settings.security.subtitle"),
            role: .warning,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalization.text("settings.security.body"))
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer(minLength: 0)

                    Button(role: .destructive) {
                        openCodeModel.resetSettingsToDefaults()
                    } label: {
                        Label(AppLocalization.text("settings.action.restoreDefaults"), systemImage: "arrow.counterclockwise")
                    }
                    .settingsGlassButtonStyle(prominent: true)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Developer Section

    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSurfaceCard(
                title: AppLocalization.text("settings.developerMode.title"),
                subtitle: AppLocalization.text("settings.developerMode.subtitle"),
                trailing: AnyView(
                    Button {
                        isDeveloperDocPresented = true
                    } label: {
                        Image(systemName: "doc.text")
                    }
                    .settingsGlassButtonStyle()
                    .controlSize(.small)
                    .help(AppLocalization.text("developerMode.doc.title"))
                ),
                role: .primary,
                palette: palette
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsControlGrid(minimumWidth: 240) {
                        SettingsControlTile(palette: palette, minHeight: 54) {
                            Toggle(AppLocalization.text("settings.developerMode.enableToggle"), isOn: appPreferencesModel.developerModeIsEnabledBinding)
                        }
                    }

                    if appPreferencesModel.preferences.developerMode.isEnabled {
                        Divider()

                        SettingsControlGrid(minimumWidth: 240) {
                            SettingsControlTile(palette: palette, minHeight: 54) {
                                Toggle(AppLocalization.text("settings.developerMode.taskClassification"), isOn: developerBinding(\.taskClassificationEnabled))
                            }

                            SettingsControlTile(palette: palette, minHeight: 54) {
                                Toggle(AppLocalization.text("settings.developerMode.optimize"), isOn: developerBinding(\.optimizeEnabled))
                            }

                            SettingsControlTile(palette: palette, minHeight: 54) {
                                Toggle(AppLocalization.text("settings.developerMode.localGovernance"), isOn: developerBinding(\.localGovernanceEnabled))
                            }

                            SettingsControlTile(palette: palette, minHeight: 54) {
                                Toggle(AppLocalization.text("settings.developerMode.multiCurrency"), isOn: developerBinding(\.multiCurrencyEnabled))
                            }

                            SettingsControlTile(palette: palette, minHeight: 54) {
                                Toggle(AppLocalization.text("settings.developerMode.modelCompare"), isOn: developerBinding(\.modelCompareEnabled))
                            }

                            SettingsControlTile(palette: palette, minHeight: 54) {
                                Toggle(AppLocalization.text("settings.developerMode.aiAnalysisDisabled"), isOn: developerBinding(\.aiAnalysisEnabled))
                                    .disabled(true)
                            }
                        }

                        Text(AppLocalization.text("developerMode.aiAnalysis.disabled"))
                            .font(.caption2)
                            .foregroundStyle(palette.subtitle)
                    }
                }
            }

            if appPreferencesModel.preferences.developerMode.isEnabled
                && appPreferencesModel.preferences.developerMode.localGovernanceEnabled {
                governancePanel
            }

            if appPreferencesModel.preferences.developerMode.isEnabled {
                SettingsActionWrap(minimumWidth: 170, spacing: 10) {
                    Button {
                        appPreferencesModel.updatePreferences { prefs in
                            prefs.developerMode.localGovernanceEnabled = true
                            prefs.developerMode.optimizeEnabled = true
                        }
                    } label: {
                        Label(AppLocalization.text("developerMode.optimize.scan"), systemImage: "magnifyingglass")
                    }
                    .settingsGlassButtonStyle()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(role: .destructive) {
                        appPreferencesModel.updatePreferences { prefs in
                            prefs.developerMode = DeveloperModePreferences()
                        }
                    } label: {
                        Label(AppLocalization.text("settings.action.resetDeveloperMode"), systemImage: "arrow.counterclockwise")
                    }
                    .settingsGlassButtonStyle()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var governancePanel: some View {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode")
        let skillsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode/skills")
        let sessionsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")

        let configCount = directoryItemCount(at: configDir)
        let skillsCount = directoryItemCount(at: skillsDir)
        let sessionsCount = directoryItemCount(at: sessionsDir)

        let configStatus = DeveloperFileAccessPolicy.isAccessible(configDir.path)
        let skillsStatus = DeveloperFileAccessPolicy.isAccessible(skillsDir.path)
        let sessionsStatus = DeveloperFileAccessPolicy.isAccessible(sessionsDir.path)

        return SettingsSurfaceCard(
            title: AppLocalization.text("settings.developerMode.governance.title"),
            subtitle: AppLocalization.text("settings.developerMode.governance.subtitle"),
            role: .secondary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200), spacing: 12, alignment: .top)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    governanceDirectoryCard(
                        title: AppLocalization.text("settings.developerMode.governance.configDir"),
                        path: configDir.path,
                        itemCount: configCount,
                        isAccessible: configStatus,
                        systemImage: "gearshape.2"
                    )

                    governanceDirectoryCard(
                        title: AppLocalization.text("settings.developerMode.governance.skillsDir"),
                        path: skillsDir.path,
                        itemCount: skillsCount,
                        isAccessible: skillsStatus,
                        systemImage: "sparkles"
                    )

                    governanceDirectoryCard(
                        title: AppLocalization.text("settings.developerMode.governance.sessionDir"),
                        path: sessionsDir.path,
                        itemCount: sessionsCount,
                        isAccessible: sessionsStatus,
                        systemImage: "terminal"
                    )
                }

                if appPreferencesModel.preferences.developerMode.optimizeEnabled {
                    let findings = OptimizeScanner.scan()
                    if !findings.isEmpty {
                        Divider()

                        SettingsFieldGroup(
                            title: AppLocalization.text("developerMode.optimize.findings"),
                            palette: palette,
                            spacing: 8
                        ) {
                            ForEach(Array(findings.prefix(10))) { finding in
                                optimizeFindingRow(finding)
                            }
                        }
                    }
                }
            }
        }
    }

    private func governanceDirectoryCard(
        title: String,
        path: String,
        itemCount: Int,
        isAccessible: Bool,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(isAccessible ? palette.accent : .orange)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.title)

                Spacer(minLength: 0)

                Circle()
                    .fill(isAccessible ? .green : .orange)
                    .frame(width: 8, height: 8)
            }

            Text(path)
                .font(.caption2)
                .foregroundStyle(palette.subtitle)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 12) {
                Label(
                    AppLocalization.format("developerMode.governance.fileSummary", itemCount),
                    systemImage: "doc"
                )
                .font(.caption2)
                .foregroundStyle(palette.subtitle)

                Label(
                    isAccessible ? AppLocalization.text("common.ready") : AppLocalization.text("common.unavailable"),
                    systemImage: isAccessible ? "checkmark.shield" : "xmark.shield"
                )
                .font(.caption2)
                .foregroundStyle(isAccessible ? .green : .orange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsInsetSurface(
            in: RoundedRectangle(cornerRadius: 12, style: .continuous),
            palette: palette
        )
    }

    private func optimizeFindingRow(_ finding: DeveloperFinding) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)

                Text(finding.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.title)
            }

            Text(finding.detail)
                .font(.caption2)
                .foregroundStyle(palette.subtitle)
                .fixedSize(horizontal: false, vertical: true)

            Text(finding.suggestion)
                .font(.caption2)
                .foregroundStyle(palette.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsInsetSurface(
            in: RoundedRectangle(cornerRadius: 10, style: .continuous),
            palette: palette,
            stroke: .orange.opacity(0.22)
        )
    }

    private func directoryItemCount(at url: URL) -> Int {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return 0
        }
        return contents.count
    }

    // MARK: - Helpers

    private func pagedPathListSection(
        title: String,
        subtitle: String,
        paths: [String],
        pageIndex: Binding<Int>,
        emptyMessage: String,
        paginationTitle: String,
        systemImage: String,
        onDelete: @escaping (Int) -> Void
    ) -> some View {
        SettingsFieldGroup(title: title, palette: palette, spacing: 8) {
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(palette.subtitle)
                .fixedSize(horizontal: false, vertical: true)

            if paths.isEmpty {
                emptySettingsState(emptyMessage)
            } else {
                let bounds = paginationBounds(
                    itemCount: paths.count,
                    pageIndex: pageIndex.wrappedValue,
                    pageSize: listPageSize
                )
                let visiblePaths = Array(paths[bounds.startIndex..<bounds.endIndex])

                VStack(spacing: 8) {
                    ForEach(Array(visiblePaths.enumerated()), id: \.offset) { offset, path in
                        let index = bounds.startIndex + offset
                        SettingsPathRow(
                            path: path,
                            systemImage: systemImage,
                            palette: palette
                        ) {
                            onDelete(index)
                        }
                    }
                }

                if paths.count > listPageSize {
                    PaginationControls(
                        pageIndex: pageIndex,
                        itemCount: paths.count,
                        pageSize: listPageSize,
                        palette: palette,
                        title: paginationTitle
                    )
                }
            }
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
        .settingsGlassButtonStyle(prominent: true)
        .controlSize(.small)
    }

    private var testGoConnectionButton: some View {
        Button(AppLocalization.text("settings.action.testConnection")) {
            testGoConnection()
        }
        .settingsGlassButtonStyle()
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
        .settingsGlassButtonStyle()
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

    // MARK: - Bindings

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

    private func developerBinding(_ keyPath: WritableKeyPath<DeveloperModePreferences, Bool>) -> Binding<Bool> {
        appPreferencesModel.developerModeToggleBinding(for: keyPath)
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
}

// MARK: - Private Subviews

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

    private var formattedPrice: String {
        guard resolvedPlan.isSubscribed else {
            return resolvedPlan.priceDescription
        }
        guard let monthlyUSD = resolvedPlan.monthlyUSD, monthlyUSD > 0 else {
            return resolvedPlan.priceDescription
        }
        let dc = appPreferencesModel.preferences.displayCurrency
        return TokenCostFormatters.currency(monthlyUSD, displayCurrency: dc) + AppLocalization.text("unit.perMonth")
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

                Text(formattedPrice)
                    .font(.caption)
                    .foregroundStyle(palette.title)

                if let preset = resolvedPlan.preset {
                    Text(preset.usageNote)
                        .font(.caption2)
                        .foregroundStyle(palette.subtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(formattedPrice)
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
    var systemImage: String = "folder"
    let palette: TokenCostPalette
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
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
        .settingsInsetSurface(
            in: RoundedRectangle(cornerRadius: 14, style: .continuous),
            palette: palette
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
        .settingsInsetSurface(
            in: RoundedRectangle(cornerRadius: 14, style: .continuous),
            palette: palette
        )
        .shadow(color: palette.cardShadow, radius: 8, x: 0, y: 4)
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
            .settingsInsetSurface(
                in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                palette: palette,
                stroke: isSelected ? palette.accent : palette.cardStroke,
                lineWidth: isSelected ? 1.6 : 0.9
            )
            .shadow(color: palette.cardShadow, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsSidebarRow: View {
    let title: String
    let subtitle: String
    let iconName: String
    let badge: String?
    let badgeTint: Color
    let palette: TokenCostPalette

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 32, height: 32)
                .settingsInsetSurface(
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous),
                    palette: palette
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.title)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(palette.subtitle)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(badgeTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(badgeTint.opacity(0.12), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(badgeTint.opacity(0.22), lineWidth: 0.8)
                    )
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
