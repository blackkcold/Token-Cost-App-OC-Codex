import Foundation
import OSLog

enum ConsumptionRateCalculator {
    private static let historyKey = "com.token-cost-app.balance-history"
    private static let maxSamplesPerWindow = 200
    private static let minSampleInterval: TimeInterval = 600
    private static let minEffectiveSpanSeconds: TimeInterval = 300
    private static let maxPerHour = 200.0
    private static let maxTotalKeys = 500

    private struct History: Codable {
        var samplesByKey: [String: [WindowSample]] = [:]
    }

    struct WindowSample: Codable {
        let timestamp: Date
        let usedRatio: Double
        let resetAt: Date
    }

    private static func storageKey(provider: BalanceProviderKind, windowLabel: String) -> String {
        "\(provider.rawValue)|\(windowLabel)"
    }

    private static func loadHistory() -> History {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let history = try? JSONDecoder().decode(History.self, from: data) else {
            return History()
        }
        return history
    }

    private static func saveHistory(_ history: History) {
        do {
            let data = try JSONEncoder().encode(history)
            UserDefaults.standard.set(data, forKey: historyKey)
        } catch {
            BalanceLog.calculator.fault("Failed to encode history: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func store(_ snapshots: [BalanceSnapshot], activeProviderKinds: Set<BalanceProviderKind>? = nil) {
        var history = loadHistory()

        for snapshot in snapshots where snapshot.isAvailable {
            guard let windows = snapshot.quotaWindows, !windows.isEmpty else { continue }
            let provider = snapshot.provider
            let sampleTime = snapshot.fetchedAt
            for window in windows {
                guard let usedRatio = window.usedRatio, let resetAt = window.resetAt else { continue }
                let key = storageKey(provider: provider, windowLabel: window.label)

                var samples = history.samplesByKey[key] ?? []

                if let lastSample = samples.last, lastSample.resetAt != resetAt {
                    BalanceLog.calculator.notice("Window reset detected for \(key, privacy: .public), cleared \(samples.count, privacy: .public) samples")
                    samples.removeAll()
                }

                if let lastSample = samples.last,
                   sampleTime.timeIntervalSince(lastSample.timestamp) < minSampleInterval {
                    continue
                }

                let sample = WindowSample(timestamp: sampleTime, usedRatio: usedRatio, resetAt: resetAt)
                samples.append(sample)

                if samples.count > maxSamplesPerWindow {
                    samples = Array(samples.suffix(maxSamplesPerWindow))
                }

                history.samplesByKey[key] = samples
            }
        }

        pruneStaleKeys(in: &history, activeProviderKinds: activeProviderKinds)
        pruneGlobalKeyCount(in: &history)
        saveHistory(history)
        BalanceLog.calculator.debug("Stored samples for \(history.samplesByKey.count, privacy: .public) windows")
    }

    private static func pruneStaleKeys(in history: inout History, activeProviderKinds: Set<BalanceProviderKind>?) {
        guard let active = activeProviderKinds else { return }
        let activePrefixes = active.map { $0.rawValue + "|" }
        history.samplesByKey = history.samplesByKey.filter { key, _ in
            activePrefixes.contains { key.hasPrefix($0) }
        }
    }

    private static func pruneGlobalKeyCount(in history: inout History) {
        guard history.samplesByKey.count > maxTotalKeys else { return }
        let ranked = history.samplesByKey.map { key, samples in
            (key: key, newest: samples.last?.timestamp.timeIntervalSince1970 ?? 0)
        }.sorted { $0.newest > $1.newest }
        let keep = Set(ranked.prefix(maxTotalKeys).map(\.key))
        let dropped = history.samplesByKey.count - keep.count
        history.samplesByKey = history.samplesByKey.filter { keep.contains($0.key) }
        if dropped > 0 {
            BalanceLog.calculator.notice("Pruned \(dropped, privacy: .public) stale history keys (total capped at \(maxTotalKeys, privacy: .public))")
        }
    }

    static func compute(current snapshots: [BalanceSnapshot]) -> [BalanceSnapshot] {
        let history = loadHistory()

        return snapshots.map { snapshot in
            guard snapshot.isAvailable,
                  let windows = snapshot.quotaWindows, !windows.isEmpty else {
                return snapshot
            }

            let updatedWindows: [BalanceQuotaWindow] = windows.map { window in
                let key = storageKey(provider: snapshot.provider, windowLabel: window.label)
                let samples = history.samplesByKey[key] ?? []
                let rate = computeRate(for: window, samples: samples, now: snapshot.fetchedAt)
                if let rate {
                    BalanceLog.calculator.debug("Computed rate for \(key, privacy: .public): perHour=\(rate.perHour, privacy: .public), confidence=\(rate.confidence, privacy: .public)")
                }
                return BalanceQuotaWindow(
                    label: window.label,
                    usedRatio: window.usedRatio,
                    remainingRatio: window.remainingRatio,
                    resetAt: window.resetAt,
                    windowSeconds: window.windowSeconds,
                    consumptionRate: rate
                )
            }

            return BalanceSnapshot(
                provider: snapshot.provider,
                fetchedAt: snapshot.fetchedAt,
                isAvailable: snapshot.isAvailable,
                errorMessage: snapshot.errorMessage,
                errorRecoveryHint: snapshot.errorRecoveryHint,
                errorRequiresReimport: snapshot.errorRequiresReimport,
                remainingCredits: snapshot.remainingCredits,
                totalCredits: snapshot.totalCredits,
                usedCredits: snapshot.usedCredits,
                usagePercent: snapshot.usagePercent,
                planType: snapshot.planType,
                primaryWindowLabel: snapshot.primaryWindowLabel,
                primaryWindowUsagePercent: snapshot.primaryWindowUsagePercent,
                primaryWindowResetAt: snapshot.primaryWindowResetAt,
                secondaryWindowLabel: snapshot.secondaryWindowLabel,
                secondaryWindowUsagePercent: snapshot.secondaryWindowUsagePercent,
                secondaryWindowResetAt: snapshot.secondaryWindowResetAt,
                tertiaryWindowLabel: snapshot.tertiaryWindowLabel,
                tertiaryWindowUsagePercent: snapshot.tertiaryWindowUsagePercent,
                tertiaryWindowResetAt: snapshot.tertiaryWindowResetAt,
                totalCostUSD: snapshot.totalCostUSD,
                avgCostPerDayUSD: snapshot.avgCostPerDayUSD,
                quotaWindows: updatedWindows,
                valueEntries: snapshot.valueEntries
            )
        }
    }

    private static func computeRate(
        for window: BalanceQuotaWindow,
        samples: [WindowSample],
        now: Date
    ) -> ConsumptionRate? {
        guard let usedRatio = window.usedRatio,
              let resetAt = window.resetAt else { return nil }

        let windowSamples = samples.filter { $0.resetAt == resetAt && $0.timestamp < now }

        var pairs: [(x: Double, y: Double)] = windowSamples.map {
            ($0.timestamp.timeIntervalSince1970, $0.usedRatio * 100)
        }
        pairs.append((now.timeIntervalSince1970, usedRatio * 100))

        guard pairs.count >= 2 else {
            guard let windowSec = window.windowSeconds, windowSec > 0 else { return nil }
            let windowStart = resetAt.addingTimeInterval(-Double(windowSec))
            let elapsed = now.timeIntervalSince(windowStart)
            guard elapsed >= minEffectiveSpanSeconds else { return nil }
            let elapsedHours = elapsed / 3600
            guard elapsedHours > 0 else { return nil }
            let rawPerHour = (usedRatio * 100) / elapsedHours
            let perHour = min(rawPerHour, maxPerHour)
            let fallback = ConsumptionRate(
                perHour: perHour,
                perDay: perHour * 24,
                confidence: min(1.0 / 5.0, 0.2)
            )
            BalanceLog.calculator.notice("Fallback rate for window: perHour=\(fallback.perHour, privacy: .public) (single sample)")
            return fallback
        }

        guard let firstX = pairs.first?.x, let lastX = pairs.last?.x,
              lastX - firstX >= minEffectiveSpanSeconds else { return nil }

        let baseX = firstX
        pairs = pairs.map { (x: $0.x - baseX, y: $0.y) }

        let n = Double(pairs.count)
        let sumX = pairs.reduce(0) { $0 + $1.x }
        let sumY = pairs.reduce(0) { $0 + $1.y }
        let sumXY = pairs.reduce(0) { $0 + $1.x * $1.y }
        let sumX2 = pairs.reduce(0) { $0 + $1.x * $1.x }

        let denominator = n * sumX2 - sumX * sumX
        guard denominator != 0 else { return nil }

        let slopePerSecond = (n * sumXY - sumX * sumY) / denominator

        let rawPerHour = max(0, slopePerSecond * 3600)
        let perHour = min(rawPerHour, maxPerHour)
        let perDay = perHour * 24
        let confidence = min(Double(pairs.count) / 5.0, 1.0)

        BalanceLog.calculator.debug("Linear regression: \(pairs.count, privacy: .public) points, slope/s=\(slopePerSecond, privacy: .public)")

        return ConsumptionRate(perHour: perHour, perDay: perDay, confidence: confidence)
    }

    static func resetHistoryForTesting() {
        UserDefaults.standard.removeObject(forKey: historyKey)
    }
}
