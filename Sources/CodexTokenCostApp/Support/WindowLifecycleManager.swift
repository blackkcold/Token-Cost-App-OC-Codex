import AppKit

final class WindowLifecycleManager: @unchecked Sendable {

    private let setPolicy: @Sendable (NSApplication.ActivationPolicy) -> Void
    private let getPolicy: @Sendable () -> NSApplication.ActivationPolicy
    private let retryCount: Int
    private let retryDelay: UInt64

    private var mainWindowOpen = false
    private var settingsWindowOpen = false
    private var observationToken: Any?

    init(
        setPolicy: @escaping @Sendable (NSApplication.ActivationPolicy) -> Void,
        getPolicy: @escaping @Sendable () -> NSApplication.ActivationPolicy,
        retryCount: Int = 3,
        retryDelay: UInt64 = 100_000_000
    ) {
        self.setPolicy = setPolicy
        self.getPolicy = getPolicy
        self.retryCount = retryCount
        self.retryDelay = retryDelay
    }

    deinit {
        stopObserving()
    }

    @MainActor
    func isMainWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == "main"
    }

    func windowDidOpen(identifier: String) {
        if identifier == "main" {
            mainWindowOpen = true
        } else if isSettingsWindow(identifier: identifier) {
            settingsWindowOpen = true
        }
        if shouldShowDockIcon {
            showInDock()
        }
    }

    func windowWillClose(identifier: String) {
        if identifier == "main" {
            mainWindowOpen = false
        } else if isSettingsWindow(identifier: identifier) {
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

    func startObservingWindowClose(
        onWillClose: @escaping @Sendable (NSWindow) -> Void
    ) {
        stopObserving()
        observationToken = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            onWillClose(window)
        }
    }

    func stopObserving() {
        if let token = observationToken {
            NotificationCenter.default.removeObserver(token)
            observationToken = nil
        }
    }

    private func isSettingsWindow(identifier: String) -> Bool {
        identifier.contains("Settings") || identifier.contains("settings")
    }

    private func applyPolicyWithRetry(_ target: NSApplication.ActivationPolicy) {
        setPolicy(target)
        verifyRetry(target: target, attemptsLeft: retryCount)
    }

    private func verifyRetry(target: NSApplication.ActivationPolicy, attemptsLeft: Int) {
        guard attemptsLeft > 0 else { return }
        if getPolicy() == target { return }
        let nsDelay = Double(retryDelay) / 1_000_000_000
        DispatchQueue.main.asyncAfter(deadline: .now() + nsDelay) { [weak self] in
            guard let self else { return }
            self.setPolicy(target)
            self.verifyRetry(target: target, attemptsLeft: attemptsLeft - 1)
        }
    }
}

extension WindowLifecycleManager {
    @MainActor
    static func withDefaultPolicies() -> WindowLifecycleManager {
        WindowLifecycleManager(
            setPolicy: { NSApp.setActivationPolicy($0) },
            getPolicy: { NSApp.activationPolicy() }
        )
    }
}
