import Foundation

enum ConsumptionRateCalculator {
    private static let historyKey = "balance_history"
    private static let maxSamplesPerWindow = 200
    private static let minSampleInterval: TimeInterval = 600 // 10 minutes

    // MARK: - Storage model

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

    // MARK: - Load / save

    private static func loadHistory() -> History {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let history = try? JSONDecoder().decode(History.self, from: data) else {
            return History()
        }
        return history
    }

    private static func saveHistory(_ history: History) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    // MARK: - Store samples

    static func store(_ snapshots: [BalanceSnapshot]) {
        var history = loadHistory()

        for snapshot in snapshots where snapshot.isAvailable {
            guard let windows = snapshot.quotaWindows, !windows.isEmpty else { continue }
            let provider = snapshot.provider
            let sampleTime = snapshot.fetchedAt
            for window in windows {
                guard let usedRatio = window.usedRatio, let resetAt = window.resetAt else { continue }
                let key = storageKey(provider: provider, windowLabel: window.label)

                var samples = history.samplesByKey[key] ?? []

                // Detect window reset before debouncing so a reset never leaves stale history behind.
                if let lastSample = samples.last, lastSample.resetAt != resetAt {
                    samples.removeAll()
                }

                // Debounce: skip if last sample is too recent
                if let lastSample = samples.last,
                   sampleTime.timeIntervalSince(lastSample.timestamp) < minSampleInterval {
                    continue
                }

                let sample = WindowSample(timestamp: sampleTime, usedRatio: usedRatio, resetAt: resetAt)
                samples.append(sample)

                // Cap sample count
                if samples.count > maxSamplesPerWindow {
                    samples = Array(samples.suffix(maxSamplesPerWindow))
                }

                history.samplesByKey[key] = samples
            }
        }

        saveHistory(history)
    }

    // MARK: - Compute rates

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

    // MARK: - Linear regression

    private static func computeRate(
        for window: BalanceQuotaWindow,
        samples: [WindowSample],
        now: Date
    ) -> ConsumptionRate? {
        guard let usedRatio = window.usedRatio,
              let resetAt = window.resetAt else { return nil }

        // Filter samples from the same window cycle (same resetAt), older than the current snapshot.
        let windowSamples = samples.filter { $0.resetAt == resetAt && $0.timestamp < now }

        // Build (time, percentage-point) pairs — use percentage points to match ConsumptionRate docs/UI.
        var pairs: [(x: Double, y: Double)] = windowSamples.map {
            ($0.timestamp.timeIntervalSince1970, $0.usedRatio * 100)
        }
        // Add current point
        pairs.append((now.timeIntervalSince1970, usedRatio * 100))

        guard pairs.count >= 2 else {
            // Fallback: simple window-internal rate
            guard let windowSec = window.windowSeconds, windowSec > 0 else { return nil }
            let windowStart = resetAt.addingTimeInterval(-Double(windowSec))
            let elapsed = now.timeIntervalSince(windowStart)
            guard elapsed > 0 else { return nil }
            let elapsedHours = elapsed / 3600
            let elapsedDays = elapsed / 86400
            guard elapsedHours > 0 else { return nil }
            return ConsumptionRate(
                perHour: (usedRatio * 100) / elapsedHours,
                perDay: (usedRatio * 100) / max(elapsedDays, 0.01),
                confidence: min(1.0 / 5.0, 0.2)
            )
        }

        let baseX = pairs.first?.x ?? 0
        pairs = pairs.map { (x: $0.x - baseX, y: $0.y) }

        // Simple linear regression: y = slope * x + intercept
        let n = Double(pairs.count)
        let sumX = pairs.reduce(0) { $0 + $1.x }
        let sumY = pairs.reduce(0) { $0 + $1.y }
        let sumXY = pairs.reduce(0) { $0 + $1.x * $1.y }
        let sumX2 = pairs.reduce(0) { $0 + $1.x * $1.x }

        let denominator = n * sumX2 - sumX * sumX
        guard denominator != 0 else { return nil }

        let slopePerSecond = (n * sumXY - sumX * sumY) / denominator

        let perHour = max(0, slopePerSecond * 3600)
        let perDay = max(0, slopePerSecond * 86400)
        let confidence = min(Double(pairs.count) / 5.0, 1.0)

        return ConsumptionRate(perHour: perHour, perDay: perDay, confidence: confidence)
    }

    static func resetHistoryForTesting() {
        UserDefaults.standard.removeObject(forKey: historyKey)
    }
}
