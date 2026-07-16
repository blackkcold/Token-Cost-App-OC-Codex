import AppKit
import SwiftUI
import CodexTokenCostCore

struct CodexTokenCostCommands: Commands {
    @ObservedObject var openCodeModel: TokenCostModel
    @ObservedObject var codexModel: CodexSessionModel
    @ObservedObject var appPreferencesModel: AppPreferencesModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu(AppLocalization.text("menu.appTitle")) {
            Button(AppLocalization.text("menu.refreshAll")) {
                openCodeModel.rescanSources()
                codexModel.refresh()
            }
            .keyboardShortcut("r", modifiers: [.command])

            Divider()

            Button(AppLocalization.text("menu.openMainWindow")) {
                WindowOpeningSupport.openWindow(id: "main", openWindow: openWindow)
            }
            .keyboardShortcut("1", modifiers: [.command])
        }

        CommandGroup(replacing: .appSettings) {
            Button(AppLocalization.text("menu.openSettings")) {
                WindowOpeningSupport.openWindow(id: "settings", openWindow: openWindow)
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}
