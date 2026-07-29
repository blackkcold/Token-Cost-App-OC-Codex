import XCTest
import AppKit
@testable import CodexTokenCostApp

@MainActor
final class BalanceFloatingPanelWindowTests: XCTestCase {
    private var window: BalanceFloatingPanelWindow?

    override func tearDown() async throws {
        window?.orderOut(nil)
        window = nil
    }

    func testStyleMaskIncludesNonactivatingPanel() {
        let window = makeWindow()
        self.window = window
        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel),
                      "Panel styleMask must include .nonactivatingPanel")
    }

    func testCanBecomeKeyIsFalse() {
        let window = makeWindow()
        self.window = window
        XCTAssertFalse(window.canBecomeKey,
                       "Pointer-first panel must not become the key window")
    }

    func testCanBecomeMainIsFalse() {
        let window = makeWindow()
        self.window = window
        XCTAssertFalse(window.canBecomeMain,
                       "Pointer-first panel must not become the main window")
    }

    private func makeWindow() -> BalanceFloatingPanelWindow {
        BalanceFloatingPanelWindow(
            contentRect: NSRect(origin: .zero, size: BalanceFloatingPanelLayout.panelDefaultSize),
            styleMask: [.borderless, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
    }
}
