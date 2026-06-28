import Foundation
import Combine

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

    public func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true

        if !force, consecutiveFailures > 0, let lastRefreshTime {
            let backoff = backoffSeconds()
            if Date().timeIntervalSince(lastRefreshTime) < Double(backoff) {
                isRefreshing = false
                return
            }
        }

        let now = Date()
        let currentCheckers = checkers

        let (results, anySucceeded): ([BalanceSnapshot], Bool) = await withTaskGroup(
            of: BalanceSnapshot.self,
            returning: ([BalanceSnapshot], Bool).self
        ) { group in
            for checker in currentCheckers {
                group.addTask {
                    guard let token = AuthTokenProvider.token(for: checker.providerKind) else {
                        return BalanceSnapshot.unavailable(checker.providerKind, reason: "未找到认证信息")
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
            for await snapshot in group {
                if snapshot.isAvailable { succeeded = true }
                snapshots.append(snapshot)
            }
            return (snapshots, succeeded)
        }

        snapshots = results.sorted { $0.provider.sortOrder < $1.provider.sortOrder }
        lastRefreshTime = now

        // Compute rates against prior history first, then store this refresh as the next sample.
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

        if anySucceeded {
            consecutiveFailures = 0
        } else {
            consecutiveFailures += 1
        }

        isRefreshing = false
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
            }
        }
        // Remove snapshots for disabled providers.
        snapshots = snapshots.filter { enabled.contains($0.provider) }
    }
}
