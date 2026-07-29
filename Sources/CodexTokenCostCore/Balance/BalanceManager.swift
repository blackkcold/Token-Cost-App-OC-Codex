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

    /// Set by refresh(): true when the timeout sentinel fired.
    var lastRefreshDidTimeout: Bool = false

    public init(configuration: BalanceConfiguration = BalanceConfiguration()) {
        self.configuration = configuration
        rebuildCheckers()
    }

    /// Test-only: inject mock checkers with optional reduced timeout.
    init(checkers: [BalanceChecker], configuration: BalanceConfiguration = BalanceConfiguration(), timeoutNanos: UInt64? = nil) {
        self.configuration = configuration
        self.checkers = checkers
        self._testTimeoutNanos = timeoutNanos
    }

    private var _testTimeoutNanos: UInt64?

    private var effectiveTimeoutNanos: UInt64 {
        _testTimeoutNanos ?? Self.refreshTimeout
    }

    /// Hot-update configuration at runtime (e.g. user toggles DeepSeek).
    public func updateConfiguration(_ new: BalanceConfiguration) {
        configuration = new
    }

    /// Maximum time the overall refresh may take before returning partial results.
    private static let refreshTimeout: UInt64 = 45_000_000_000  // 45s

    /// Distinct outcomes for each provider task: timeout, cancellation, and success/failure
    /// are represented independently so the for-await loop never conflates them.
    private enum ProviderOutcome: Sendable {
        case snapshot(BalanceSnapshot)
        case cancelled
        case timeout
    }

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
        let providerCount = currentCheckers.count
        let timeoutNanos = effectiveTimeoutNanos

        let (rawSnapshots, anySucceeded, timedOut): ([BalanceSnapshot], Bool, Bool) = await withTaskGroup(
            of: ProviderOutcome.self,
            returning: ([BalanceSnapshot], Bool, Bool).self
        ) { group in
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanos)
                    return ProviderOutcome.timeout
                } catch {
                    return ProviderOutcome.cancelled
                }
            }

            for checker in currentCheckers {
                group.addTask {
                    let token = await Task.detached {
                        AuthTokenProvider.token(for: checker.providerKind)
                    }.value
                    guard let token = token else {
                        return .snapshot(BalanceSnapshot.unavailable(
                            checker.providerKind,
                            reason: AppLocalization.text("balance.error.noAuthToken")
                        ))
                    }
                    do {
                        return .snapshot(try await checker.fetch(authToken: token))
                    } catch is CancellationError {
                        return .cancelled
                    } catch {
                        return .snapshot(BalanceSnapshot.unavailable(
                            checker.providerKind,
                            reason: error.localizedDescription
                        ))
                    }
                }
            }

            var snapshots: [BalanceSnapshot] = []
            var succeeded = false
            var didTimeout = false
            var completed = 0
            for await outcome in group {
                switch outcome {
                case .snapshot(let snapshot):
                    if snapshot.isAvailable { succeeded = true }
                    snapshots.append(snapshot)
                    completed += 1
                case .cancelled:
                    completed += 1
                case .timeout:
                    didTimeout = true
                    group.cancelAll()
                }
                if completed >= providerCount {
                    group.cancelAll()
                }
            }
            return (snapshots, succeeded, didTimeout)
        }

        let (amountEnriched, computed, _): ([BalanceSnapshot], [BalanceSnapshot], Set<BalanceProviderKind>) = await Task.detached {
            let sorted = rawSnapshots.sorted { $0.provider.sortOrder < $1.provider.sortOrder }
            let kindSet = Set(currentCheckers.map(\.providerKind))
            let c = ConsumptionRateCalculator.compute(current: sorted)
            ConsumptionRateCalculator.store(c, activeProviderKinds: kindSet)
            let ae = AmountConsumptionRateCalculator.compute(current: c)
            AmountConsumptionRateCalculator.store(ae, activeProviderKinds: kindSet)
            return (ae, c, kindSet)
        }.value

        lastRefreshDidTimeout = timedOut

        snapshots = amountEnriched
        lastRefreshTime = now

        if timedOut {
            BalanceLog.general.notice("Balance refresh timed out after 45s, collected \(rawSnapshots.count, privacy: .public)/\(providerCount, privacy: .public) providers")
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
    /// useful when injecting snapshots without affecting backoff.
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
