import AppKit
import XCTest
@testable import CodexTokenCostApp

@MainActor
final class WindowThemeStyleTests: XCTestCase {
    func testWorkshopStyleAppliesCustomWindowChrome() {
        let window = makeWindow()
        let probe = TokenWindowStyleProbeView()
        window.contentView = probe

        probe.usesWorkshopStyle = true
        probe.applyWindowStyleIfPossible()

        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertEqual(window.toolbarStyle, .unifiedCompact)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertEqual(window.backgroundColor, .textBackgroundColor)
    }

    func testDefaultStyleRestoresSystemWindowChrome() {
        let window = makeWindow()
        let probe = TokenWindowStyleProbeView()
        window.contentView = probe
        probe.usesWorkshopStyle = true
        probe.applyWindowStyleIfPossible()

        probe.usesWorkshopStyle = false
        probe.applyWindowStyleIfPossible()

        XCTAssertFalse(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, .visible)
        XCTAssertEqual(window.toolbarStyle, .automatic)
        XCTAssertEqual(window.titlebarSeparatorStyle, .automatic)
        XCTAssertEqual(window.backgroundColor, .windowBackgroundColor)
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
    }
}
