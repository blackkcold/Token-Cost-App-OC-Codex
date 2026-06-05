import XCTest
import AppKit
@testable import CodexTokenCostApp

@MainActor
final class WindowLifecycleManagerTests: XCTestCase {

    // MARK: - Policy Tests

    func testShowInDockSetsRegularPolicy() {
        let state = SendableState(initialPolicy: .regular)
        let manager = WindowLifecycleManager(
            setPolicy: { state.setPolicy($0) },
            getPolicy: { state.currentPolicy },
            retryCount: 0
        )

        manager.showInDock()
        XCTAssertEqual(state.currentPolicy, .regular)
    }

    func testHideFromDockSetsAccessoryPolicy() {
        let state = SendableState(initialPolicy: .regular)
        let manager = WindowLifecycleManager(
            setPolicy: { state.setPolicy($0) },
            getPolicy: { state.currentPolicy },
            retryCount: 0
        )

        manager.hideFromDock()
        XCTAssertEqual(state.currentPolicy, .accessory)
    }

    // MARK: - Window Identification Tests

    func testIsMainWindowMatchesIdentifier() {
        let manager = WindowLifecycleManager.withDefaultPolicies()
        let window = NSWindow(
            contentRect: .zero,
            styleMask: .closable,
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("main")
        XCTAssertTrue(manager.isMainWindow(window))
    }

    func testIsMainWindowRejectsOtherIdentifiers() {
        let manager = WindowLifecycleManager.withDefaultPolicies()
        let window = NSWindow(
            contentRect: .zero,
            styleMask: .closable,
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("some_other_id")
        XCTAssertFalse(manager.isMainWindow(window))
    }

    func testIsMainWindowRejectsSettingsWindow() {
        let manager = WindowLifecycleManager.withDefaultPolicies()
        let window = NSWindow(
            contentRect: .zero,
            styleMask: .closable,
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("com_apple_swiftui_Settings")
        XCTAssertFalse(manager.isMainWindow(window))
    }

    // MARK: - Retry Tests

    func testRetriesWhenPolicyNotApplied() {
        let expectation = XCTestExpectation(description: "Retry should fire at least 2 times")
        let state = SendableState(initialPolicy: .regular)

        let manager = WindowLifecycleManager(
            setPolicy: { _ in
                state.increment()
                if state.count >= 2 {
                    state.setPolicy(.accessory)
                }
            },
            getPolicy: { state.currentPolicy },
            retryCount: 2,
            retryDelay: 10_000_000
        )

        manager.hideFromDock()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertGreaterThanOrEqual(state.count, 2)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Window State Tracking Tests

    func testShouldShowDockWhenMainWindowOpens() {
        let manager = WindowLifecycleManager(
            setPolicy: { _ in }, getPolicy: { .regular }, retryCount: 0
        )
        XCTAssertFalse(manager.shouldShowDockIcon)

        manager.windowDidOpen(identifier: "main")
        XCTAssertTrue(manager.shouldShowDockIcon)
    }

    func testShouldHideDockWhenAllWindowsClosed() {
        let manager = WindowLifecycleManager(
            setPolicy: { _ in }, getPolicy: { .regular }, retryCount: 0
        )
        manager.windowDidOpen(identifier: "main")
        XCTAssertTrue(manager.shouldShowDockIcon)

        manager.windowWillClose(identifier: "main")
        XCTAssertFalse(manager.shouldShowDockIcon)
    }

    func testShouldShowDockWhenSettingsOpen() {
        let manager = WindowLifecycleManager(
            setPolicy: { _ in }, getPolicy: { .regular }, retryCount: 0
        )
        XCTAssertFalse(manager.shouldShowDockIcon)

        manager.windowDidOpen(identifier: "com_apple_swiftui_Settings_window")
        XCTAssertTrue(manager.shouldShowDockIcon)
    }

    func testShouldNotHideDockWhenMainClosesButSettingsRemains() {
        let manager = WindowLifecycleManager(
            setPolicy: { _ in }, getPolicy: { .regular }, retryCount: 0
        )
        manager.windowDidOpen(identifier: "main")
        manager.windowDidOpen(identifier: "com_apple_swiftui_Settings_window")

        manager.windowWillClose(identifier: "main")
        XCTAssertTrue(manager.shouldShowDockIcon, "Settings still open")
    }

    // MARK: - Observer Management

    func testObserversAreAddedAndRemoved() {
        let manager = WindowLifecycleManager(
            setPolicy: { _ in }, getPolicy: { .regular }, retryCount: 0
        )
        let counter = SendableInteger()

        manager.startObservingWindowClose { _ in counter.increment() }

        let window = NSWindow(
            contentRect: .zero,
            styleMask: .closable,
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("main")

        NotificationCenter.default.post(
            name: NSWindow.willCloseNotification,
            object: window
        )
        let firstDelivery = XCTestExpectation(description: "Observer should receive first close")
        DispatchQueue.main.async {
            XCTAssertEqual(counter.value, 1)
            firstDelivery.fulfill()
        }
        wait(for: [firstDelivery], timeout: 1.0)

        manager.stopObserving()

        NotificationCenter.default.post(
            name: NSWindow.willCloseNotification,
            object: window
        )
        let secondDelivery = XCTestExpectation(description: "Removed observer should stay silent")
        DispatchQueue.main.async {
            XCTAssertEqual(counter.value, 1, "Observer should be removed")
            secondDelivery.fulfill()
        }
        wait(for: [secondDelivery], timeout: 1.0)
    }
}

private final class SendableState: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var count = 0
    private(set) var currentPolicy: NSApplication.ActivationPolicy

    init(initialPolicy: NSApplication.ActivationPolicy) {
        self.currentPolicy = initialPolicy
    }

    func increment() {
        lock.lock(); defer { lock.unlock() }
        count += 1
    }

    func setPolicy(_ policy: NSApplication.ActivationPolicy) {
        lock.lock(); defer { lock.unlock() }
        currentPolicy = policy
    }
}

private final class SendableInteger: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return _value
    }

    func increment() {
        lock.lock(); defer { lock.unlock() }
        _value += 1
    }
}
