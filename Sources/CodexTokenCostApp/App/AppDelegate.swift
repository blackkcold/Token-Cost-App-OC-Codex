import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var lifecycleManager: WindowLifecycleManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        lifecycleManager = WindowLifecycleManager.withDefaultPolicies()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        lifecycleManager?.windowDidOpen(identifier: "main")
        lifecycleManager?.startObservingWindows(
            onWillClose: { [weak lifecycleManager] window in
            guard let manager = lifecycleManager else { return }
            if manager.isMainWindow(window) {
                manager.windowWillClose(identifier: "main")
            } else if let identifier = window.identifier?.rawValue {
                manager.windowWillClose(identifier: identifier)
            }
            manager.syncDockPolicyAfterWindowClose()
        }, onDidBecomeKey: { [weak lifecycleManager] window in
            guard let identifier = window.identifier?.rawValue else { return }
            lifecycleManager?.windowDidOpen(identifier: identifier)
        })
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        lifecycleManager?.hideFromDock()
        return false
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        lifecycleManager?.syncDockPolicy()
    }
}
