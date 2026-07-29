import AppKit
import Combine
import SwiftUI
import CodexTokenCostCore

@MainActor
final class BalanceFloatingPanelCoordinator: NSObject, NSWindowDelegate {
    private let balanceManager: BalanceManager
    private let appPreferencesModel: AppPreferencesModel

    private var panel: BalanceFloatingPanelWindow?
    private var hostingView: NSHostingView<BalanceFloatingPanelView>?
    private var cancellables: Set<AnyCancellable> = []
    private var didPerformInitialPresentation = false
    private var didSetInitialFrame = false
    private var isApplyingVisibilityChange = false
    private var isApplicationTerminating = false

    init(balanceManager: BalanceManager, appPreferencesModel: AppPreferencesModel) {
        self.balanceManager = balanceManager
        self.appPreferencesModel = appPreferencesModel
        super.init()
        observePreferenceChanges()
        observeApplicationTermination()
    }

    func requestInitialPresentation() {
        didPerformInitialPresentation = true
        syncVisibilityToPreference()
    }

    func markApplicationTerminating() {
        isApplicationTerminating = true
    }

    func toggleFromMenuBar() {
        appPreferencesModel.updatePreferences { preferences in
            preferences.balanceFloatingPanelEnabled.toggle()
        }
    }

    func show() {
        let panel = ensurePanel()
        syncPanelLevel()
        if !didSetInitialFrame {
            panel.center()
            didSetInitialFrame = true
        }
        updatePanelPresentation(animated: false)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func close() {
        guard let panel else { return }
        isApplyingVisibilityChange = true
        panel.orderOut(nil)
        appPreferencesModel.updatePreferences { preferences in
            preferences.balanceFloatingPanelEnabled = false
        }
        isApplyingVisibilityChange = false
    }

    func toggleVisibility() {
        toggleFromMenuBar()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isApplicationTerminating else { return true }
        guard appPreferencesModel.preferences.balanceFloatingPanelEnabled else {
            sender.orderOut(nil)
            return false
        }

        isApplyingVisibilityChange = true
        appPreferencesModel.updatePreferences { preferences in
            preferences.balanceFloatingPanelEnabled = false
        }
        isApplyingVisibilityChange = false
        sender.orderOut(nil)
        return false
    }

    private func observePreferenceChanges() {
        appPreferencesModel.$preferences
            .map(\.balanceFloatingPanelEnabled)
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                self?.handlePreferenceChange(isEnabled)
            }
            .store(in: &cancellables)

        appPreferencesModel.$preferences
            .map(\.balanceFloatingPanelDisplayMode)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updatePanelPresentation(animated: true)
            }
            .store(in: &cancellables)

        appPreferencesModel.$preferences
            .map(\.balanceFloatingPanelAlwaysOnTop)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.syncPanelLevel()
            }
            .store(in: &cancellables)

        balanceManager.$snapshots
            .map(\.count)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updatePanelPresentation(animated: true)
            }
            .store(in: &cancellables)
    }

    private func observeApplicationTermination() {
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.isApplicationTerminating = true
            }
            .store(in: &cancellables)
    }

    private func handlePreferenceChange(_ isEnabled: Bool) {
        guard didPerformInitialPresentation, !isApplyingVisibilityChange else { return }
        syncVisibility(isEnabled: isEnabled)
    }

    private func syncVisibilityToPreference() {
        syncVisibility(isEnabled: appPreferencesModel.preferences.balanceFloatingPanelEnabled)
    }

    private func syncVisibility(isEnabled: Bool) {
        isApplyingVisibilityChange = true
        defer { isApplyingVisibilityChange = false }

        if isEnabled {
            show()
        } else {
            hide()
        }
    }

    private func ensurePanel() -> BalanceFloatingPanelWindow {
        if let panel {
            return panel
        }

        let panel = BalanceFloatingPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [
                .borderless,
                .resizable,
                .fullSizeContentView,
                .nonactivatingPanel
            ],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.title = AppLocalization.text("balance.title")
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.minSize = BalanceFloatingPanelLayout.minimumPanelSize

        let rootView = BalanceFloatingPanelView(
            balanceManager: balanceManager,
            appPreferencesModel: appPreferencesModel,
            onRequestClose: { [weak self] in
                self?.close()
            }
        )

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.focusRingType = .none
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView
        return panel
    }

    private func syncPanelLevel() {
        guard let panel else { return }
        panel.level = appPreferencesModel.preferences.balanceFloatingPanelAlwaysOnTop ? .floating : .normal
    }

    private func updatePanelPresentation(animated: Bool) {
        guard let panel else { return }

        syncPanelLevel()

        let targetSize = BalanceFloatingPanelLayout.panelSize(
            for: appPreferencesModel.preferences.balanceFloatingPanelDisplayMode,
            providerCount: balanceManager.snapshots.count
        )

        panel.minSize = targetSize

        guard panel.frame.size != targetSize else { return }

        let currentFrame = panel.frame
        let resizedFrame = NSRect(
            x: currentFrame.minX,
            y: currentFrame.maxY - targetSize.height,
            width: targetSize.width,
            height: targetSize.height
        )

        panel.setFrame(resizedFrame, display: true, animate: animated && panel.isVisible)
    }
}

final class BalanceFloatingPanelWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
