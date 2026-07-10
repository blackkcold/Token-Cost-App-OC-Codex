import SwiftUI
import CodexTokenCostCore

struct SettingsView: View {
    @ObservedObject var openCodeModel: TokenCostModel
    @ObservedObject var codexModel: CodexSessionModel
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    @ObservedObject var balanceManager: BalanceManager
    @ObservedObject var updateCheckerModel: UpdateCheckerModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSection: SettingsSection = .overview

    @State private var scanRootsPageIndex = 0
    @State private var manualDatabasePageIndex = 0
    @State private var codexDiscoveryPageIndex = 0
    @State private var codexRootsPageIndex = 0
    @State private var codexManualPageIndex = 0
    @State private var showBalanceNetworkAlert = false
    @State private var goWorkspaceIDInput: String = ""
    @State private var goCookieInput: String = ""
    @State private var goCookieSaved: Bool = false
    @State private var isTestingGoConnection = false
    @State private var isTestingOllamaConnection = false
    @State private var testConnectionAlert: TestConnectionAlert?
    @State private var goConnectionTestTask: Task<Void, Never>?
    @State private var ollamaConnectionTestTask: Task<Void, Never>?
    @State private var showBrowserImportAlert = false
    @State private var browserImportMessage: String?
    @State private var isImportingFromBrowser = false
    @State private var showOllamaBrowserImportAlert = false
    @State private var ollamaBrowserImportMessage: String?
    @State private var isImportingOllamaFromBrowser = false
    @State private var ollamaCookieInput: String = ""
    @State private var ollamaCookieSaved: Bool = false

    private let listPageSize = 10

    private var palette: TokenCostPalette {
        TokenCostPalette(theme: appPreferencesModel.preferences.theme)
    }

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case overview
        case preferences
        case opencode
        case codex
        case skills
        case billing
        case balance
        case backup
        case security
        case developer

        var id: String { rawValue }
    }

    private struct TestConnectionAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String

        static func go(title: String, message: String) -> TestConnectionAlert {
            TestConnectionAlert(title: title, message: message)
        }

        static func ollama(title: String, message: String) -> TestConnectionAlert {
            TestConnectionAlert(title: title, message: message)
        }
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
        .frame(minWidth: 780, minHeight: 600)
        .onAppear {
            let snapshot = appPreferencesModel.localCredentialSnapshot()
            goWorkspaceIDInput = snapshot.workspaceID ?? appPreferencesModel.preferences.opencodeGoWorkspaceID ?? ""
            goCookieInput = snapshot.goCookie ?? ""
            goCookieSaved = !(snapshot.goCookie?.isEmpty ?? true)
            ollamaCookieInput = snapshot.ollamaCookie ?? ""
            ollamaCookieSaved = !(snapshot.ollamaCookie?.isEmpty ?? true)

            if snapshot.workspaceID != nil || snapshot.goCookie != nil {
                let cachedWorkspaceID = snapshot.workspaceID?.isEmpty == false ? snapshot.workspaceID : nil
                let cachedGoCookie = snapshot.goCookie?.isEmpty == false ? snapshot.goCookie : nil
                CredentialBootstrapService.shared.updateCachedGoCookie(
                    cachedGoCookie,
                    workspaceID: cachedWorkspaceID
                )
            }
            if let ollamaCookie = snapshot.ollamaCookie {
                CredentialBootstrapService.shared.updateCachedOllamaCookie(ollamaCookie.isEmpty ? nil : ollamaCookie)
            }
        }
        .onChange(of: isTestingGoConnection) { _, newValue in
            guard newValue else { return }
            goConnectionTestTask?.cancel()
            goConnectionTestTask = Task {
                let allowEnv = appPreferencesModel.preferences.balanceConfig?.allowEnvironmentCredentials ?? false
                let checker = OpenCodeGoBalanceChecker(allowEnvironmentCredentials: allowEnv)
                guard let apiKey = AuthTokenProvider.token(for: .opencodeGo) else {
                    guard !Task.isCancelled else { return }
                    testConnectionAlert = .go(
                        title: AppLocalization.text("settings.opencodeGo.test.failed"),
                        message: AppLocalization.text("settings.opencodeGo.test.noApiKey")
                    )
                    isTestingGoConnection = false
                    return
                }
                let snapshot = await balanceManager.testSnapshot(for: checker, authToken: apiKey)
                guard !Task.isCancelled else { return }
                if snapshot.isAvailable {
                    testConnectionAlert = .go(
                        title: AppLocalization.text("settings.opencodeGo.test.success"),
                        message: AppLocalization.text("settings.opencodeGo.test.successMessage")
                    )
                } else {
                    testConnectionAlert = .go(
                        title: AppLocalization.text("settings.opencodeGo.test.failed"),
                        message: snapshot.errorMessage ?? AppLocalization.text("settings.opencodeGo.test.unknownError")
                    )
                }
                isTestingGoConnection = false
            }
        }
        .onChange(of: isTestingOllamaConnection) { _, newValue in
            guard newValue else { return }
            ollamaConnectionTestTask?.cancel()
            ollamaConnectionTestTask = Task {
                let checker = OllamaBalanceChecker()
                guard let cookie = AuthTokenProvider.token(for: .ollama) else {
                    guard !Task.isCancelled else { return }
                    testConnectionAlert = .ollama(
                        title: AppLocalization.text("settings.ollama.test.failed"),
                        message: AppLocalization.text("settings.ollama.test.noCookie")
                    )
                    isTestingOllamaConnection = false
                    return
                }

                let snapshot = await balanceManager.testSnapshot(for: checker, authToken: cookie)
                guard !Task.isCancelled else { return }
                balanceManager.upsertSnapshot(snapshot)

                if snapshot.isAvailable {
                    testConnectionAlert = .ollama(
                        title: AppLocalization.text("settings.ollama.test.success"),
                        message: AppLocalization.text("settings.ollama.test.successMessage")
                    )
                } else {
                    testConnectionAlert = .ollama(
                        title: AppLocalization.text("settings.ollama.test.failed"),
                        message: snapshot.errorMessage ?? AppLocalization.text("settings.ollama.test.unknownError")
                    )
                }
                isTestingOllamaConnection = false
            }
        }
        .alert(item: $testConnectionAlert) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .cancel(Text(AppLocalization.text("settings.action.close")))
            )
        }
        .confirmationDialog(
            AppLocalization.text("settings.opencodeGo.import.confirmTitle"),
            isPresented: $showBrowserImportAlert,
            titleVisibility: .visible
        ) {
            Button(AppLocalization.text("settings.action.continueImport")) {
                showBrowserImportAlert = false
                isImportingFromBrowser = true
                Task.detached(priority: .userInitiated) {
                    let result = BrowserCookieExtractor.extractCredentials()
                    await MainActor.run {
                        let browserWorkspaceID = result.workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let browserCookie = result.cookie?.trimmingCharacters(in: .whitespacesAndNewlines)
                        if browserWorkspaceID?.isEmpty == false || browserCookie?.isEmpty == false {
                            let current = appPreferencesModel.localCredentialSnapshot()
                            let currentWorkspaceDraft = goWorkspaceIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            let currentCookieDraft = goCookieInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            let resolvedWorkspaceID = browserWorkspaceID?.isEmpty == false
                                ? browserWorkspaceID
                                : (!currentWorkspaceDraft.isEmpty ? currentWorkspaceDraft : current.workspaceID)
                            let resolvedCookie = browserCookie?.isEmpty == false
                                ? browserCookie
                                : (!currentCookieDraft.isEmpty ? currentCookieDraft : current.goCookie)
                            appPreferencesModel.saveLocalGoCredentials(
                                workspaceID: resolvedWorkspaceID,
                                cookie: resolvedCookie
                            )
                            let refreshed = appPreferencesModel.localCredentialSnapshot()
                            goWorkspaceIDInput = refreshed.workspaceID ?? ""
                            goCookieInput = refreshed.goCookie ?? ""
                            goCookieSaved = !(refreshed.goCookie?.isEmpty ?? true)
                            browserImportMessage = AppLocalization.text("settings.opencodeGo.import.success")
                        } else {
                            browserImportMessage = AppLocalization.text("settings.opencodeGo.import.noBrowser")
                        }
                        isImportingFromBrowser = false
                    }
                }
            }
            Button(AppLocalization.text("settings.action.cancel"), role: .cancel) {}
        } message: {
            Text(AppLocalization.text("settings.opencodeGo.import.confirmMessage"))
        }
        .confirmationDialog(
            AppLocalization.text("settings.ollama.import.title"),
            isPresented: $showOllamaBrowserImportAlert,
            titleVisibility: .visible
        ) {
            Button(AppLocalization.text("settings.action.continueImport")) {
                showOllamaBrowserImportAlert = false
                isImportingOllamaFromBrowser = true
                Task.detached(priority: .userInitiated) {
                    let cookie = BrowserCookieExtractor.extractOllamaCookie()
                    await MainActor.run {
                        if let cookie = cookie?.trimmingCharacters(in: .whitespacesAndNewlines), !cookie.isEmpty {
                            appPreferencesModel.saveLocalOllamaCookie(cookie)
                            let refreshed = appPreferencesModel.localCredentialSnapshot()
                            ollamaCookieInput = refreshed.ollamaCookie ?? ""
                            ollamaCookieSaved = !(refreshed.ollamaCookie?.isEmpty ?? true)
                            ollamaBrowserImportMessage = AppLocalization.text("settings.ollama.import.success")
                            isTestingOllamaConnection = true
                        } else {
                            ollamaBrowserImportMessage = AppLocalization.text("settings.ollama.import.noCookie")
                        }
                        isImportingOllamaFromBrowser = false
                    }
                }
            }
            Button(AppLocalization.text("settings.action.cancel"), role: .cancel) {}
        } message: {
            Text(AppLocalization.text("settings.ollama.import.message"))
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
            OverviewSectionView(
                openCodeModel: openCodeModel,
                codexModel: codexModel,
                appPreferencesModel: appPreferencesModel,
                balanceManager: balanceManager,
                palette: palette
            )
        case .preferences:
            PreferencesSectionView(
                appPreferencesModel: appPreferencesModel,
                palette: palette
            )
        case .billing:
            BillingSectionView(
                appPreferencesModel: appPreferencesModel,
                palette: palette
            )
        case .balance:
            BalanceSectionView(
                appPreferencesModel: appPreferencesModel,
                balanceManager: balanceManager,
                palette: palette,
                showBalanceNetworkAlert: $showBalanceNetworkAlert,
                goWorkspaceIDInput: $goWorkspaceIDInput,
                goCookieInput: $goCookieInput,
                goCookieSaved: $goCookieSaved,
                isTestingGoConnection: $isTestingGoConnection,
                isTestingOllamaConnection: $isTestingOllamaConnection,
                showBrowserImportAlert: $showBrowserImportAlert,
                browserImportMessage: $browserImportMessage,
                isImportingFromBrowser: $isImportingFromBrowser,
                showOllamaBrowserImportAlert: $showOllamaBrowserImportAlert,
                ollamaBrowserImportMessage: $ollamaBrowserImportMessage,
                isImportingOllamaFromBrowser: $isImportingOllamaFromBrowser,
                ollamaCookieInput: $ollamaCookieInput,
                ollamaCookieSaved: $ollamaCookieSaved
            )
        case .opencode:
            OpenCodeSectionView(
                openCodeModel: openCodeModel,
                palette: palette,
                listPageSize: listPageSize,
                scanRootsPageIndex: $scanRootsPageIndex,
                manualDatabasePageIndex: $manualDatabasePageIndex
            )
        case .codex:
            CodexSectionView(
                codexModel: codexModel,
                palette: palette,
                listPageSize: listPageSize,
                codexDiscoveryPageIndex: $codexDiscoveryPageIndex,
                codexRootsPageIndex: $codexRootsPageIndex,
                codexManualPageIndex: $codexManualPageIndex
            )
        case .skills:
            SkillsSectionView(
                appPreferencesModel: appPreferencesModel,
                palette: palette
            )
        case .security:
            SecuritySectionView(
                openCodeModel: openCodeModel,
                palette: palette
            )
        case .developer:
            DeveloperSectionView(
                appPreferencesModel: appPreferencesModel,
                updateCheckerModel: updateCheckerModel,
                palette: palette
            )
        case .backup:
            BackupSectionView(
                appPreferencesModel: appPreferencesModel,
                palette: palette
            )
        }
    }

    private func title(for section: SettingsSection) -> String {
        switch section {
        case .overview: return AppLocalization.text("overview.settings.title")
        case .preferences: return AppLocalization.text("settings.appPreferences.title")
        case .billing: return AppLocalization.text("settings.billing.title")
        case .balance: return AppLocalization.text("settings.balance.title")
        case .opencode: return AppLocalization.text("settings.opencode.title")
        case .codex: return AppLocalization.text("settings.codex.title")
        case .skills: return AppLocalization.text("settings.skills.title")
        case .security: return AppLocalization.text("settings.security.title")
        case .developer: return AppLocalization.text("settings.developerMode.title")
        case .backup: return AppLocalization.text("settings.backup.title")
        }
    }

    private func subtitle(for section: SettingsSection) -> String {
        switch section {
        case .overview: return AppLocalization.text("overview.settings.subtitle")
        case .preferences: return AppLocalization.text("settings.appPreferences.subtitle")
        case .billing: return AppLocalization.text("settings.billing.subtitle")
        case .balance: return AppLocalization.text("settings.balance.subtitle")
        case .opencode: return AppLocalization.text("settings.opencode.subtitle")
        case .codex: return AppLocalization.text("settings.codex.subtitle")
        case .skills: return AppLocalization.text("settings.skills.subtitle")
        case .security: return AppLocalization.text("settings.security.subtitle")
        case .developer: return AppLocalization.text("settings.developerMode.subtitle")
        case .backup: return AppLocalization.text("settings.backup.subtitle")
        }
    }

    private func iconName(for section: SettingsSection) -> String {
        switch section {
        case .overview: return "square.grid.2x2"
        case .preferences: return "slider.horizontal.3"
        case .billing: return "creditcard"
        case .balance: return "chart.bar.xaxis"
        case .opencode: return "externaldrive"
        case .codex: return "terminal"
        case .skills: return "gearshape.2"
        case .security: return "lock.shield"
        case .developer: return "wrench.and.screwdriver"
        case .backup: return "arrow.trianglehead.clockwise"
        }
    }

    private func badge(for section: SettingsSection) -> String? {
        switch section {
        case .overview: return warningMessages.isEmpty ? nil : "\(warningMessages.count)"
        case .preferences: return appPreferencesModel.preferences.theme.displayName
        case .billing: return "\(billingProviderCount)"
        case .balance: return appPreferencesModel.preferences.balanceEnabled ? AppLocalization.text("common.ready") : AppLocalization.text("common.unavailable")
        case .opencode: return "\(openCodeModel.settings.scanRoots.count + openCodeModel.settings.manualDatabasePaths.count)"
        case .codex: return "\(codexModel.settings.sourceRoots.count + codexModel.settings.manualSourcePaths.count)"
        case .skills: return "\(appPreferencesModel.preferences.skillsPanel.previewLength)"
        case .security: return nil
        case .developer: return appPreferencesModel.preferences.developerMode.isEnabled ? AppLocalization.text("common.ready") : AppLocalization.text("common.unavailable")
        case .backup: return appPreferencesModel.preferences.backup.autoBackupEnabled ? AppLocalization.text("common.ready") : AppLocalization.text("common.unavailable")
        }
    }

    private func badgeTint(for section: SettingsSection) -> Color {
        switch section {
        case .overview: return warningMessages.isEmpty ? palette.accent : .orange
        case .preferences: return palette.accent
        case .billing: return palette.accentSecondary
        case .balance: return appPreferencesModel.preferences.balanceEnabled ? .green : .orange
        case .opencode: return palette.accent
        case .codex: return palette.accentSecondary
        case .skills: return palette.accent
        case .security: return .red
        case .developer: return appPreferencesModel.preferences.developerMode.isEnabled ? palette.accent : palette.subtitle
        case .backup: return palette.accentSecondary
        }
    }

    private var billingProviderCount: Int {
        BillingProvider.allCases.filter {
            !BillingPlanCatalog.subscriptionPresets(for: $0).isEmpty
        }.count
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
