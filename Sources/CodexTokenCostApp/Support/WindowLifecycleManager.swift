import AppKit

@MainActor
final class WindowLifecycleManager {

    private let setPolicy: @MainActor @Sendable (NSApplication.ActivationPolicy) -> Void
    private let getPolicy: @MainActor @Sendable () -> NSApplication.ActivationPolicy
    private let retryCount: Int
    private let retryDelay: UInt64

    private var mainWindowOpen = false
    private var settingsWindowOpen = false
    private var observationTokens: [ObservationTokenBox] = []

    init(
        setPolicy: @escaping @MainActor @Sendable (NSApplication.ActivationPolicy) -> Void,
        getPolicy: @escaping @MainActor @Sendable () -> NSApplication.ActivationPolicy,
        retryCount: Int = 3,
        retryDelay: UInt64 = 100_000_000
    ) {
        self.setPolicy = setPolicy
        self.getPolicy = getPolicy
        self.retryCount = retryCount
        self.retryDelay = retryDelay
    }

    deinit {
        for token in observationTokens {
            NotificationCenter.default.removeObserver(token.rawValue)
        }
    }

    func isMainWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == "main"
    }

    /// Returns `true` only for windows whose identifiers match the
    /// managed scene set: main, settings, pricing-doc, dev-doc.
    /// Transient MenuBarExtra panels and other unidentified windows
    /// are excluded so they cannot spuriously flip Dock policy.
    func isManagedWindow(_ window: NSWindow) -> Bool {
        guard let identifier = window.identifier?.rawValue else { return false }
        return identifier == "main" || isTrackedSupplementaryWindow(identifier: identifier)
    }

    func windowDidOpen(identifier: String) {
        if identifier == "main" {
            mainWindowOpen = true
        } else if isTrackedSupplementaryWindow(identifier: identifier) {
            settingsWindowOpen = true
        }
        if shouldShowDockIcon {
            showInDock()
        }
    }

    func windowWillClose(identifier: String) {
        if identifier == "main" {
            mainWindowOpen = false
        } else if isTrackedSupplementaryWindow(identifier: identifier) {
            settingsWindowOpen = false
        }
        if !shouldShowDockIcon {
            hideFromDock()
        }
    }

    var shouldShowDockIcon: Bool {
        mainWindowOpen || settingsWindowOpen
    }

    func showInDock() {
        applyPolicyWithRetry(.regular)
    }

    func hideFromDock() {
        applyPolicyWithRetry(.accessory)
    }

    func syncDockPolicy() {
        if hasVisibleUserWindow() {
            showInDock()
        } else {
            hideFromDock()
        }
    }

    func syncDockPolicyAfterWindowClose() {
        DispatchQueue.main.async { [weak self] in
            self?.syncDockPolicy()
        }
    }

    func startObservingWindows(
        onWillClose: @escaping @MainActor @Sendable (NSWindow) -> Void,
        onDidBecomeKey: @escaping @MainActor @Sendable (NSWindow) -> Void
    ) {
        stopObserving()
        observationTokens = [
            ObservationTokenBox(
            NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor in
                onWillClose(window)
            }
        }
        ),
            ObservationTokenBox(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: nil,
                    queue: .main
                ) { notification in
                    guard let window = notification.object as? NSWindow else { return }
                    Task { @MainActor in
                        onDidBecomeKey(window)
                    }
                }
            )
        ]
    }

    func startObservingWindowClose(
        onWillClose: @escaping @MainActor @Sendable (NSWindow) -> Void
    ) {
        startObservingWindows(onWillClose: onWillClose, onDidBecomeKey: { _ in })
    }

    func stopObserving() {
        for token in observationTokens {
            NotificationCenter.default.removeObserver(token.rawValue)
        }
        observationTokens = []
    }

    private func isTrackedSupplementaryWindow(identifier: String) -> Bool {
        identifier.contains("Settings")
            || identifier.contains("settings")
            || identifier.contains("pricing-doc")
            || identifier.contains("dev-doc")
    }

    private func hasVisibleUserWindow() -> Bool {
        NSApp.windows.contains { window in
            window.isVisible && !window.isMiniaturized && window.canBecomeKey
        }
    }

    private func applyPolicyWithRetry(_ target: NSApplication.ActivationPolicy) {
        setPolicy(target)
        verifyRetry(target: target, attemptsLeft: retryCount)
    }

    private func verifyRetry(target: NSApplication.ActivationPolicy, attemptsLeft: Int) {
        guard attemptsLeft > 0 else { return }
        if getPolicy() == target { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: retryDelay)
            self.setPolicy(target)
            self.verifyRetry(target: target, attemptsLeft: attemptsLeft - 1)
        }
    }
}

extension WindowLifecycleManager {
    static func withDefaultPolicies() -> WindowLifecycleManager {
        WindowLifecycleManager(
            setPolicy: { NSApp.setActivationPolicy($0) },
            getPolicy: { NSApp.activationPolicy() }
        )
    }
}

private final class ObservationTokenBox: @unchecked Sendable {
    let rawValue: Any

    init(_ rawValue: Any) {
        self.rawValue = rawValue
    }
}
