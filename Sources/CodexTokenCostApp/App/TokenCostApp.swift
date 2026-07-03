import AppKit
import Combine
import SwiftUI
import CodexTokenCostCore

@main
struct CodexTokenCostApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var appPreferencesModel: AppPreferencesModel
    @StateObject private var openCodeModel: TokenCostModel
    @StateObject private var codexModel: CodexSessionModel
    @StateObject private var balanceManager: BalanceManager
    @StateObject private var updateChecker: UpdateCheckerModel
    @StateObject private var skillsModel: OpenCodeSkillsModel

    init() {
        let preferencesModel = AppPreferencesModel()
        _appPreferencesModel = StateObject(wrappedValue: preferencesModel)
        _openCodeModel = StateObject(wrappedValue: TokenCostModel())
        _codexModel = StateObject(wrappedValue: CodexSessionModel())
        _balanceManager = StateObject(
            wrappedValue: BalanceManager(configuration: preferencesModel.effectiveBalanceConfiguration)
        )
        _updateChecker = StateObject(wrappedValue: UpdateCheckerModel())
        _skillsModel = StateObject(wrappedValue: OpenCodeSkillsModel())
    }

    var body: some Scene {
        WindowGroup(CodexAppPaths.appDisplayName, id: "main") {
            ContentView(
                openCodeModel: openCodeModel,
                codexModel: codexModel,
                appPreferencesModel: appPreferencesModel,
                balanceManager: balanceManager,
                updateChecker: updateChecker,
                skillsModel: skillsModel
            )
            .task {
                appPreferencesModel.migrateThemeFromSettingsIfNeeded(openCodeModel.settings.theme)
            }
            .onChange(of: appPreferencesModel.preferences.balanceConfig) { _, newConfig in
                balanceManager.updateConfiguration(newConfig ?? BalanceConfiguration())
            }
            .onChange(of: appPreferencesModel.preferences.developerMode) { _, _ in
                balanceManager.updateConfiguration(appPreferencesModel.effectiveBalanceConfiguration)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
                openWindow(id: "main")
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
                balanceManager: balanceManager
            )
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 960, height: 860)
        .environment(\.locale, appPreferencesModel.preferences.language.locale)

        MenuBarExtra(appPreferencesModel.preferences.language == .zhHans ? "代币费用" : "Token Cost", systemImage: "chart.bar.fill") {
            MenuBarView(
                openCodeModel: openCodeModel,
                codexModel: codexModel,
                appPreferencesModel: appPreferencesModel,
                balanceManager: balanceManager,
                palette: TokenCostPalette(theme: appPreferencesModel.preferences.theme)
            )
        }
        .menuBarExtraStyle(.window)
    }
}
