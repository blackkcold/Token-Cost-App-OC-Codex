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
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    // 10s polling allows rapid response to balanceEnabled /
                    // balanceRefreshSeconds config changes without waiting for
                    // the full configured interval. shouldRefresh() guard
                    // prevents unnecessary refresh calls — most polls are no-ops.
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                } catch {
                    break
                }

                guard let self else { break }
                guard self.preferencesModel.preferences.balanceEnabled else { continue }
                guard self.balanceManager.shouldRefresh(
                    intervalSeconds: self.preferencesModel.preferences.balanceRefreshSeconds
                ) else { continue }
                await self.balanceManager.refresh()
            }
        }
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
