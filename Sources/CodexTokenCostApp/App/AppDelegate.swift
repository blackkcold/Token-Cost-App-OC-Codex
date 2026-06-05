import AppKit
import Foundation

extension Notification.Name {
    static let openMainWindow = Notification.Name("CodexTokenCost.openMainWindow")
}

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private var lifecycleManager: WindowLifecycleManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        lifecycleManager = WindowLifecycleManager.withDefaultPolicies()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        lifecycleManager?.windowDidOpen(identifier: "main")
        lifecycleManager?.startObservingWindowClose { [weak lifecycleManager] window in
            MainActor.assumeIsolated {
                guard let manager = lifecycleManager else { return }
                if manager.isMainWindow(window) {
                    manager.windowWillClose(identifier: "main")
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        lifecycleManager?.hideFromDock()
        return false
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        lifecycleManager?.showInDock()
    }
}
