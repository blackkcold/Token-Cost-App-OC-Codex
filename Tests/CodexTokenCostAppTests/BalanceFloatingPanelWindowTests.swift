import XCTest
import AppKit
import CodexTokenCostCore
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

    func testAlwaysOnTopPreferenceUpdatesPanelLevelImmediately() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("balance_floating_panel_level_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appPreferences = AppPreferencesModel(runtimeRoot: tempDir)
        let coordinator = BalanceFloatingPanelCoordinator(
            balanceManager: BalanceManager(),
            appPreferencesModel: appPreferences
        )
        coordinator.show()
        defer { coordinator.hide() }

        guard let panel = coordinator.panel else {
            return XCTFail("Coordinator must have created a panel")
        }

        XCTAssertTrue(appPreferences.preferences.balanceFloatingPanelAlwaysOnTop)
        XCTAssertEqual(panel.level, .floating)

        appPreferences.balanceFloatingPanelAlwaysOnTopBinding.wrappedValue = false
        waitForLevel(.normal, of: panel)

        appPreferences.balanceFloatingPanelAlwaysOnTopBinding.wrappedValue = true
        waitForLevel(.floating, of: panel)
    }

    private func waitForLevel(_ expected: NSWindow.Level, of panel: NSWindow, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while panel.level != expected && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        XCTAssertEqual(panel.level, expected, "Expected panel level \(expected.rawValue) after toggling")
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
