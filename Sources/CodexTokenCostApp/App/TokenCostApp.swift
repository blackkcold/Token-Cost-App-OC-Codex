import AppKit
import SwiftUI
import CodexTokenCostCore

    @main
struct CodexTokenCostApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appPreferencesModel = AppPreferencesModel()
    @StateObject private var openCodeModel = TokenCostModel()
    @StateObject private var codexModel = CodexSessionModel()
    @StateObject private var balanceManager = BalanceManager()
    @StateObject private var updateChecker = UpdateCheckerModel()
    @StateObject private var skillsModel = OpenCodeSkillsModel()

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

        Settings {
            SettingsView(
                openCodeModel: openCodeModel,
                codexModel: codexModel,
                appPreferencesModel: appPreferencesModel,
                balanceManager: balanceManager
            )
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 860)
        .environment(\.locale, appPreferencesModel.preferences.language.locale)

        MenuBarExtra(appPreferencesModel.preferences.language == .zhHans ? "Token Cost" : "Token Cost", systemImage: "chart.bar.fill") {
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
