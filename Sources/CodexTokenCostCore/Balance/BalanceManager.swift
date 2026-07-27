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

        // Sentinel + counter: cancel group when all providers done (no 45s wait)
        // or on timeout. nil = sentinel/cancelled, never a fake snapshot.
        let providerCount = currentCheckers.count
        let (results, anySucceeded, timedOut): ([BalanceSnapshot], Bool, Bool) = await withTaskGroup(
            of: BalanceSnapshot?.self,
            returning: ([BalanceSnapshot], Bool, Bool).self
        ) { group in
            group.addTask {
                try? await Task.sleep(nanoseconds: Self.refreshTimeout)
                return nil
            }

            for checker in currentCheckers {
                group.addTask {
                    let token = await Task.detached {
                        AuthTokenProvider.token(for: checker.providerKind)
                    }.value
                    guard let token = token else {
                        return BalanceSnapshot.unavailable(
                            checker.providerKind,
                            reason: AppLocalization.text("balance.error.noAuthToken")
                        )
                    }
                    do {
                        return try await checker.fetch(authToken: token)
                    } catch is CancellationError {
                        return nil
                    } catch {
                        return BalanceSnapshot.unavailable(checker.providerKind, reason: error.localizedDescription)
                    }
                }
            }

            var snapshots: [BalanceSnapshot] = []
            var succeeded = false
            var didTimeout = false
            var nilCount = 0
            for await result in group {
                if let snapshot = result {
                    if snapshot.isAvailable { succeeded = true }
                    upsertSnapshot(snapshot, updateRefreshTime: false)
                    snapshots.append(snapshot)
                } else {
                    nilCount += 1
                    if nilCount == 1 {
                        didTimeout = true
                        group.cancelAll()
                    }
                }
                if snapshots.count >= providerCount {
                    group.cancelAll()
                }
            }
            return (snapshots, succeeded, didTimeout)
        }

        let sorted = results.sorted { $0.provider.sortOrder < $1.provider.sortOrder }
        let computed = ConsumptionRateCalculator.compute(current: sorted)
        ConsumptionRateCalculator.store(computed)
        snapshots = computed
        lastRefreshTime = now

        if timedOut {
            BalanceLog.general.notice("Balance refresh timed out after 45s, collected \(results.count, privacy: .public)/\(currentCheckers.count, privacy: .public) providers")
        }

        if let goSnapshot = computed.first(where: { $0.provider == .opencodeGo }),
           !goSnapshot.isAvailable,
           let errorMessage = goSnapshot.errorMessage {
            goLastDiagnosis = BalanceProviderError(
                provider: .opencodeGo,
                category: goSnapshot.errorRequiresReimport ? .auth : .unknown,
                publicMessage: errorMessage,
                recoveryHint: goSnapshot.errorRecoveryHint ?? "",
                requiresReimport: goSnapshot.errorRequiresReimport
            )
        } else if computed.contains(where: { $0.provider == .opencodeGo && $0.isAvailable }) {
            goLastDiagnosis = nil
        }

        let availableCount = computed.filter(\.isAvailable).count
        let unavailableCount = computed.count - availableCount
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
        if !enabled.contains(.opencodeGo) {
            goLastDiagnosis = nil
        }
    }
}
