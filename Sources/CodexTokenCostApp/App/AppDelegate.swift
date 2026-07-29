import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var balanceFloatingPanelCoordinator: BalanceFloatingPanelCoordinator?

    private var lifecycleManager: WindowLifecycleManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let parentDir = Bundle.main.bundleURL.deletingLastPathComponent()
        UpdateChecker.cleanupOldBackup(in: parentDir)

        lifecycleManager = WindowLifecycleManager.withDefaultPolicies()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        lifecycleManager?.windowDidOpen(identifier: "main")
        DispatchQueue.main.async {
            AppDelegate.balanceFloatingPanelCoordinator?.requestInitialPresentation()
        }
        lifecycleManager?.startObservingWindows(
            onWillClose: { [weak lifecycleManager] window in
            guard let manager = lifecycleManager else { return }
            guard manager.isManagedWindow(window) else { return }
            if manager.isMainWindow(window) {
                manager.windowWillClose(identifier: "main")
            } else if let identifier = window.identifier?.rawValue {
                manager.windowWillClose(identifier: identifier)
            }
            manager.syncDockPolicyAfterWindowClose()
        }, onDidBecomeKey: { [weak lifecycleManager] window in
            guard let manager = lifecycleManager else { return }
            guard manager.isManagedWindow(window) else { return }
            guard let identifier = window.identifier?.rawValue else { return }
            manager.windowDidOpen(identifier: identifier)
        })
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        lifecycleManager?.hideFromDock()
        return false
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        lifecycleManager?.syncDockPolicy()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.balanceFloatingPanelCoordinator?.markApplicationTerminating()
    }
}
