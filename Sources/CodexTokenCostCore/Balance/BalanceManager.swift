import Foundation
import Combine
import OSLog

@MainActor
public final class BalanceManager: ObservableObject {
    @Published public var configuration: BalanceConfiguration {
        didSet { rebuildCheckers() }
    }
    @Published public private(set) var snapshots: [BalanceSnapshot] = []
    @Published public private(set) var lastRefreshTime: Date?
    @Published public private(set) var isRefreshing: Bool = false
    @Published public private(set) var goLastDiagnosis: BalanceProviderError?
    private var consecutiveFailures: Int = 0
    private var checkers: [BalanceChecker] = []

    public init(configuration: BalanceConfiguration = BalanceConfiguration()) {
        self.configuration = configuration
        rebuildCheckers()
    }

    /// Hot-update configuration at runtime (e.g. user toggles DeepSeek).
    public func updateConfiguration(_ new: BalanceConfiguration) {
        configuration = new
    }

    /// Maximum time the overall refresh may take before returning partial results.
    private static let refreshTimeout: UInt64 = 45_000_000_000  // 45s

    public func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        guard !checkers.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if !force, consecutiveFailures > 0, let lastRefreshTime {
            let backoff = backoffSeconds()
            if Date().timeIntervalSince(lastRefreshTime) < Double(backoff) {
                BalanceLog.general.debug("Backoff active: \(backoff, privacy: .public)s remaining")
                return
            }
        }

        BalanceLog.general.info("Balance refresh started for \(self.checkers.count, privacy: .public) providers (timeout: 45s)")

        let now = Date()
        let currentCheckers = checkers

        // Returns (collected snapshots, anySucceeded, timedOut).
        // Uses BalanceSnapshot? so the timeout sentinel can signal via nil.
        let (results, anySucceeded, timedOut): ([BalanceSnapshot], Bool, Bool) = await withTaskGroup(
            of: BalanceSnapshot?.self,
            returning: ([BalanceSnapshot], Bool, Bool).self
        ) { group in
            // Timeout sentinel: returns nil to signal the deadline.
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: Self.refreshTimeout)
                    return nil
                } catch is CancellationError {
                    // Not a genuine timeout — the group was cancelled externally.
                    return BalanceSnapshot.unavailable(.opencodeGo, reason: "Cancelled")
                } catch {
                    return nil
                }
            }

            for checker in currentCheckers {
                group.addTask {
                    guard let token = AuthTokenProvider.token(for: checker.providerKind) else {
                        return BalanceSnapshot.unavailable(
                            checker.providerKind,
                            reason: AppLocalization.text("balance.error.noAuthToken")
                        )
                    }
                    do {
                        return try await checker.fetch(authToken: token)
                    } catch {
                        return BalanceSnapshot.unavailable(checker.providerKind, reason: error.localizedDescription)
                    }
                }
            }

            var snapshots: [BalanceSnapshot] = []
            var succeeded = false
            var didTimeout = false
            for await result in group {
                if let snapshot = result {
                    if snapshot.isAvailable { succeeded = true }
                    // Progressive visual feedback: update @Published snapshots
                    // as each provider completes. The final sorted assignment at
                    // the end ensures a consistent complete view.
                    upsertSnapshot(snapshot, updateRefreshTime: false)
                    snapshots.append(snapshot)
                } else {
                    // Timeout sentinel fired (nil).
                    didTimeout = true
                    group.cancelAll()
                }
            }
            return (snapshots, succeeded, didTimeout)
        }

        // Post-processing: batch finalization with complete sorted results.
        // This overwrites the progressive streaming updates with the full list.
        snapshots = results.sorted { $0.provider.sortOrder < $1.provider.sortOrder }
        lastRefreshTime = now

        if timedOut {
            BalanceLog.general.notice("Balance refresh timed out after 45s, collected \(results.count, privacy: .public)/\(currentCheckers.count, privacy: .public) providers")
        }

        if !snapshots.isEmpty {
            snapshots = ConsumptionRateCalculator.compute(current: snapshots)
            ConsumptionRateCalculator.store(snapshots)
        }

        if let goSnapshot = snapshots.first(where: { $0.provider == .opencodeGo }),
           !goSnapshot.isAvailable,
           let errorMessage = goSnapshot.errorMessage {
            goLastDiagnosis = BalanceProviderError(
                provider: .opencodeGo,
                category: goSnapshot.errorRequiresReimport ? .auth : .unknown,
                publicMessage: errorMessage,
                recoveryHint: goSnapshot.errorRecoveryHint ?? "",
                requiresReimport: goSnapshot.errorRequiresReimport
            )
        } else if snapshots.contains(where: { $0.provider == .opencodeGo && $0.isAvailable }) {
            goLastDiagnosis = nil
        }

        let availableCount = snapshots.filter(\.isAvailable).count
        let unavailableCount = snapshots.count - availableCount
        BalanceLog.general.info("Balance refresh completed: \(availableCount, privacy: .public) available, \(unavailableCount, privacy: .public) unavailable")

        if anySucceeded {
            consecutiveFailures = 0
        } else {
            consecutiveFailures += 1
            BalanceLog.general.error("All providers failed, consecutive failures: \(self.consecutiveFailures, privacy: .public)")
        }
    }

    /// Test-only: fetch a snapshot for a single provider bypassing
    /// refresh backoff, concurrency guard, and global state.
    public func testSnapshot(for checker: BalanceChecker, authToken: String) async -> BalanceSnapshot {
        do {
            return try await checker.fetch(authToken: authToken)
        } catch {
            return BalanceSnapshot.unavailable(checker.providerKind, reason: error.localizedDescription)
        }
    }

    /// Upserts a single provider snapshot without touching refresh backoff state.
    public func upsertSnapshot(_ snapshot: BalanceSnapshot) {
        upsertSnapshot(snapshot, updateRefreshTime: true)
    }

    /// Upserts a single provider snapshot.
    /// When `updateRefreshTime` is false, `lastRefreshTime` is left untouched —
    /// used during streaming partial updates in `refresh()` to avoid polluting
    /// the backoff anchor before all providers have reported.
    public func upsertSnapshot(_ snapshot: BalanceSnapshot, updateRefreshTime: Bool) {
        snapshots.removeAll { $0.provider == snapshot.provider }
        snapshots.append(snapshot)
        snapshots.sort { $0.provider.sortOrder < $1.provider.sortOrder }
        if updateRefreshTime {
            lastRefreshTime = Date()
        }
    }

    public func shouldRefresh(intervalSeconds: Int) -> Bool {
        guard let lastRefreshTime else { return true }
        let elapsed = Date().timeIntervalSince(lastRefreshTime)
        return elapsed >= Double(intervalSeconds)
    }

    public func clearDiagnosis() {
        goLastDiagnosis = nil
    }

    var activeProviderKinds: [BalanceProviderKind] {
        checkers
            .map(\.providerKind)
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func backoffSeconds() -> UInt64 {
        let seconds = min(60 * pow(2.0, Double(consecutiveFailures)), 30 * 60)
        return UInt64(seconds)
    }

    private func rebuildCheckers() {
        let enabled = Set(configuration.enabledBalanceProviders)
        checkers = enabled.compactMap { kind -> BalanceChecker? in
            switch kind {
            case .opencodeGo:
                return OpenCodeGoBalanceChecker(
                    allowEnvironmentCredentials: configuration.allowEnvironmentCredentials
                )
            case .codex: return CodexBalanceChecker()
            case .opencodeZen: return OpenCodeZenBalanceChecker()
            case .deepseek: return DeepSeekBalanceChecker()
            case .ollama: return OllamaBalanceChecker()
            }
        }
        // Remove snapshots for disabled providers.
        snapshots = snapshots.filter { enabled.contains($0.provider) }
    }
}
