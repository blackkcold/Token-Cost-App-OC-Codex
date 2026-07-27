import AppKit
import SwiftUI

@MainActor
enum WindowOpeningSupport {
    static func openWindow(id: String, openWindow: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }
}
