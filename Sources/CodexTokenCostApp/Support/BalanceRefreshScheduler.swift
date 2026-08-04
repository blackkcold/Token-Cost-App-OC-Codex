import AppKit
import Combine
import Foundation
import CodexTokenCostCore

@MainActor
final class BalanceRefreshScheduler: ObservableObject {
    private let balanceManager: BalanceManager
    private let preferencesModel: AppPreferencesModel
    private var refreshTask: Task<Void, Never>?
    private var terminationObserver: SchedulerObservationToken?

    init(balanceManager: BalanceManager, preferencesModel: AppPreferencesModel) {
        self.balanceManager = balanceManager
        self.preferencesModel = preferencesModel
        terminationObserver = SchedulerObservationToken(
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.stop()
                }
            }
        )
    }

    deinit {
        refreshTask?.cancel()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver.rawValue)
        }
    }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task.detached(priority: .medium) { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                } catch {
                    break
                }

                guard let self else { break }
                let balanceEnabled = await MainActor.run {
                    self.preferencesModel.preferences.balanceEnabled
                }
                let shouldRefresh = await MainActor.run {
                    self.balanceManager.shouldRefresh(
                        intervalSeconds: self.preferencesModel.preferences.balanceRefreshSeconds
                    )
                }
                guard Self.shouldAttemptRefresh(
                    balanceEnabled: balanceEnabled,
                    credentialBootstrapComplete: CredentialBootstrapService.shared.isCachePopulated,
                    intervalElapsed: shouldRefresh
                ) else { continue }
                await self.balanceManager.refresh()
            }
        }
    }

    nonisolated static func shouldAttemptRefresh(
        balanceEnabled: Bool,
        credentialBootstrapComplete: Bool,
        intervalElapsed: Bool
    ) -> Bool {
        balanceEnabled && credentialBootstrapComplete && intervalElapsed
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}

private final class SchedulerObservationToken: @unchecked Sendable {
    let rawValue: NSObjectProtocol

    init(_ rawValue: NSObjectProtocol) {
        self.rawValue = rawValue
    }
}
