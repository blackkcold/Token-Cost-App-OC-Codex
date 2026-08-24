import AppKit
import SwiftUI
import CodexTokenCostCore

@main
struct CodexTokenCostApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appPreferencesModel: AppPreferencesModel
    @StateObject private var openCodeModel: TokenCostModel
    @StateObject private var codexModel: CodexSessionModel
    @StateObject private var balanceManager: BalanceManager
    @StateObject private var balanceRefreshScheduler: BalanceRefreshScheduler
    @StateObject private var relayCoordinator: BalanceRelayCoordinator
    @StateObject private var backupScheduler: BackupScheduler
    @StateObject private var updateChecker: UpdateCheckerModel
    @StateObject private var skillsModel: OpenCodeSkillsModel
    private let balanceFloatingPanelCoordinator: BalanceFloatingPanelCoordinator

    init() {
        let preferencesModel = AppPreferencesModel()
        _appPreferencesModel = StateObject(wrappedValue: preferencesModel)
        let openCodeModel = TokenCostModel()
        _openCodeModel = StateObject(wrappedValue: openCodeModel)
        _codexModel = StateObject(wrappedValue: CodexSessionModel())
        let balanceManager = BalanceManager(configuration: preferencesModel.effectiveBalanceConfiguration)
        let balanceFloatingPanelCoordinator = BalanceFloatingPanelCoordinator(
            balanceManager: balanceManager,
            appPreferencesModel: preferencesModel
        )
        self.balanceFloatingPanelCoordinator = balanceFloatingPanelCoordinator
        AppDelegate.balanceFloatingPanelCoordinator = balanceFloatingPanelCoordinator
        let scheduler = BalanceRefreshScheduler(balanceManager: balanceManager, preferencesModel: preferencesModel)
        scheduler.start()
        let relayAnalyticsProvider = RelayDashboardAnalyticsProvider(
            openCodeModel: openCodeModel,
            preferencesModel: preferencesModel
        )
        let relayCoordinator = BalanceRelayCoordinator(
            balanceManager: balanceManager,
            analyticsProvider: relayAnalyticsProvider
        )
        AppDelegate.relayCoordinator = relayCoordinator
        let backupScheduler = BackupScheduler(preferencesModel: preferencesModel)
        backupScheduler.start()
        _balanceManager = StateObject(wrappedValue: balanceManager)
        _balanceRefreshScheduler = StateObject(wrappedValue: scheduler)
        _relayCoordinator = StateObject(wrappedValue: relayCoordinator)
        _backupScheduler = StateObject(wrappedValue: backupScheduler)
        _updateChecker = StateObject(wrappedValue: UpdateCheckerModel())
        _skillsModel = StateObject(wrappedValue: OpenCodeSkillsModel())
    }

    var body: some Scene {
        Window(CodexAppPaths.appDisplayName, id: "main") {
            ContentView(
                openCodeModel: openCodeModel,
                codexModel: codexModel,
                appPreferencesModel: appPreferencesModel,
                balanceManager: balanceManager,
                updateChecker: updateChecker,
                skillsModel: skillsModel
            )
            .preferredColorScheme(appPreferencesModel.preferences.appearanceMode.preferredColorScheme)
            .environment(\.tokenCostUsesWorkshopStyle, appPreferencesModel.preferences.accentPalette == .workshop)
            .tokenWindowStyle(usesWorkshopStyle: appPreferencesModel.preferences.accentPalette == .workshop)
            .task {
                appPreferencesModel.migrateThemeFromSettingsIfNeeded(openCodeModel.settings.theme)
            }
            .onChange(of: appPreferencesModel.preferences.balanceConfig) { _, newConfig in
                balanceManager.updateConfiguration(newConfig ?? BalanceConfiguration())
            }
        }
        .defaultSize(width: 1260, height: 860)
        .environment(\.locale, appPreferencesModel.preferences.language.locale)
        .commands {
            CodexTokenCostCommands(
                openCodeModel: openCodeModel,
                codexModel: codexModel,
                appPreferencesModel: appPreferencesModel
            )
        }

        Window("Settings", id: "settings") {
            SettingsView(
                openCodeModel: openCodeModel,
                codexModel: codexModel,
                appPreferencesModel: appPreferencesModel,
                balanceManager: balanceManager,
                relayCoordinator: relayCoordinator,
                updateCheckerModel: updateChecker
            )
            .preferredColorScheme(appPreferencesModel.preferences.appearanceMode.preferredColorScheme)
            .environment(\.tokenCostUsesWorkshopStyle, appPreferencesModel.preferences.accentPalette == .workshop)
            .tokenWindowStyle(usesWorkshopStyle: appPreferencesModel.preferences.accentPalette == .workshop)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 960, height: 860)
        .environment(\.locale, appPreferencesModel.preferences.language.locale)

        Window(AppLocalization.text("settings.billing.pricingDoc"), id: "pricing-doc") {
            PricingDocView(palette: TokenCostPalette(accentPalette: appPreferencesModel.preferences.accentPalette))
                .preferredColorScheme(appPreferencesModel.preferences.appearanceMode.preferredColorScheme)
                .environment(\.tokenCostUsesWorkshopStyle, appPreferencesModel.preferences.accentPalette == .workshop)
                .tokenWindowStyle(usesWorkshopStyle: appPreferencesModel.preferences.accentPalette == .workshop)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 760)
        .environment(\.locale, appPreferencesModel.preferences.language.locale)

        Window(AppLocalization.text("developerMode.doc.title"), id: "dev-doc") {
            DeveloperModeDocView(palette: TokenCostPalette(accentPalette: appPreferencesModel.preferences.accentPalette))
                .preferredColorScheme(appPreferencesModel.preferences.appearanceMode.preferredColorScheme)
                .environment(\.tokenCostUsesWorkshopStyle, appPreferencesModel.preferences.accentPalette == .workshop)
                .tokenWindowStyle(usesWorkshopStyle: appPreferencesModel.preferences.accentPalette == .workshop)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 820, height: 680)
        .environment(\.locale, appPreferencesModel.preferences.language.locale)

        MenuBarExtra {
            MenuBarView(
                openCodeModel: openCodeModel,
                codexModel: codexModel,
                appPreferencesModel: appPreferencesModel,
                balanceManager: balanceManager,
                balanceFloatingPanelCoordinator: balanceFloatingPanelCoordinator,
                palette: TokenCostPalette(accentPalette: appPreferencesModel.preferences.accentPalette)
            )
            .preferredColorScheme(appPreferencesModel.preferences.appearanceMode.preferredColorScheme)
            .environment(\.tokenCostUsesWorkshopStyle, appPreferencesModel.preferences.accentPalette == .workshop)
        } label: {
            Image(systemName: appPreferencesModel.preferences.accentPalette == .workshop ? "chart.bar.fill" : "chart.bar.xaxis")
                .font(.system(
                    size: 12,
                    weight: appPreferencesModel.preferences.accentPalette == .workshop ? .black : .semibold
                ))
                .accessibilityLabel(Text(appPreferencesModel.preferences.language == .zhHans ? "代币费用" : "Token Cost"))
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: appPreferencesModel.balanceMenuBarExtraVisibleBinding) {
            BalanceMenuBarPopoverView(
                balanceManager: balanceManager,
                appPreferencesModel: appPreferencesModel,
                balanceFloatingPanelCoordinator: balanceFloatingPanelCoordinator,
                palette: TokenCostPalette(accentPalette: appPreferencesModel.preferences.accentPalette)
            )
            .preferredColorScheme(appPreferencesModel.preferences.appearanceMode.preferredColorScheme)
            .environment(\.tokenCostUsesWorkshopStyle, appPreferencesModel.preferences.accentPalette == .workshop)
        } label: {
            BalanceMenuBarExtraLabelView(
                selection: BalanceMenuBarExtraSupport.selection(
                    for: appPreferencesModel.sortBalanceSnapshots(balanceManager.snapshots),
                    displayMode: appPreferencesModel.preferences.balanceDisplayMode,
                    displayCurrency: appPreferencesModel.preferences.displayCurrency
                ),
                palette: TokenCostPalette(accentPalette: appPreferencesModel.preferences.accentPalette)
            )
        }
        .menuBarExtraStyle(.window)
    }
}
