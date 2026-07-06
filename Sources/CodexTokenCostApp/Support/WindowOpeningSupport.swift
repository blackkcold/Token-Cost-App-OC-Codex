import AppKit
import SwiftUI

@MainActor
enum WindowOpeningSupport {
    static func showOrRevealMainWindow(openWindow: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }

    static func openSingletonWindow(id: String, openWindow: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }
}
