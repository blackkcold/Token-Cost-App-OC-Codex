import Foundation
import OSLog

enum AmountConsumptionRateCalculator {
    private static let historyKey = "com.token-cost-app.balance-amount-history"
    private static let maxSamplesPerKey = 200
    private static let minSampleInterval: TimeInterval = 600
    private static let minEffectiveSpanSeconds: TimeInterval = 300
    private static let maxTotalKeys = 500

    private struct History: Codable {
        var samplesByKey: [String: [AmountSample]] = [:]
    }

    struct AmountSample: Codable {
        let timestamp: Date
        let amount: Double
    }

    private static func storageKey(provider: BalanceProviderKind, entry: BalanceValueEntry) -> String {
        let raw = (entry.currencyCode ?? entry.label)
        let norm = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return "\(provider.rawValue)|\(norm)"
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
            BalanceLog.amountCalculator.fault("Failed to encode amount history: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func store(_ snapshots: [BalanceSnapshot], activeProviderKinds: Set<BalanceProviderKind>? = nil) {
        var history = loadHistory()

        for snapshot in snapshots where snapshot.isAvailable {
            guard let entries = snapshot.valueEntries, !entries.isEmpty else { continue }
            let provider = snapshot.provider
            let sampleTime = snapshot.fetchedAt

            for entry in entries {
                let key = storageKey(provider: provider, entry: entry)
                var samples = history.samplesByKey[key] ?? []

                if let lastSample = samples.last {
                    if entry.amount > lastSample.amount {
                        BalanceLog.amountCalculator.notice("Replenishment detected for \(key, privacy: .public), reset \(samples.count, privacy: .public) samples")
                        samples.removeAll()
                    } else if sampleTime.timeIntervalSince(lastSample.timestamp) < minSampleInterval {
                        continue
                    }
                }

                let sample = AmountSample(timestamp: sampleTime, amount: entry.amount)
                samples.append(sample)

                if samples.count > maxSamplesPerKey {
                    samples = Array(samples.suffix(maxSamplesPerKey))
                }

                history.samplesByKey[key] = samples
            }
        }

        pruneStaleKeys(in: &history, activeProviderKinds: activeProviderKinds)
        pruneGlobalKeyCount(in: &history)
        saveHistory(history)
        BalanceLog.amountCalculator.debug("Stored amount samples for \(history.samplesByKey.count, privacy: .public) keys")
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
            BalanceLog.amountCalculator.notice("Pruned \(dropped, privacy: .public) stale amount-history keys (total capped at \(maxTotalKeys, privacy: .public))")
        }
    }

    static func compute(current snapshots: [BalanceSnapshot]) -> [BalanceSnapshot] {
        let history = loadHistory()

        return snapshots.map { snapshot in
            guard snapshot.isAvailable,
                  let entries = snapshot.valueEntries, !entries.isEmpty else {
                return snapshot
            }

            let updatedEntries: [BalanceValueEntry] = entries.map { entry in
                let key = storageKey(provider: snapshot.provider, entry: entry)
                let samples = history.samplesByKey[key] ?? []
                let rate = computeRate(for: entry, samples: samples, now: snapshot.fetchedAt)

                return BalanceValueEntry(
                    label: entry.label,
                    currencyCode: entry.currencyCode,
                    amount: entry.amount,
                    grantedAmount: entry.grantedAmount,
                    toppedUpAmount: entry.toppedUpAmount,
                    amountConsumptionRate: rate
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
                quotaWindows: snapshot.quotaWindows,
                valueEntries: updatedEntries
            )
        }
    }

    private static func computeRate(
        for entry: BalanceValueEntry,
        samples: [AmountSample],
        now: Date
    ) -> BalanceAmountConsumptionRate? {
        let priorSamples = samples.filter { $0.timestamp < now }

        if let lastSample = priorSamples.last,
           entry.amount > lastSample.amount {
            BalanceLog.amountCalculator.notice("Replenishment detected during compute: current=\(entry.amount, privacy: .public) > last=\(lastSample.amount, privacy: .public)")
            return nil
        }

        guard !priorSamples.isEmpty else { return nil }

        var pairs: [(x: Double, y: Double)] = priorSamples.map {
            ($0.timestamp.timeIntervalSince1970, $0.amount)
        }
        pairs.append((now.timeIntervalSince1970, entry.amount))

        guard pairs.count >= 2 else { return nil }

        guard let firstX = pairs.first?.x, let lastX = pairs.last?.x,
              lastX - firstX >= minEffectiveSpanSeconds else {
            return nil
        }

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

        let rawPerHour: Double
        if slopePerSecond < 0 {
            rawPerHour = -slopePerSecond * 3600
        } else {
            rawPerHour = 0
        }

        let perDay = rawPerHour * 24
        let confidence = min(Double(pairs.count) / 5.0, 1.0)

        BalanceLog.amountCalculator.debug("Amount regression: \(pairs.count, privacy: .public) points, slope/s=\(slopePerSecond, privacy: .public), perHour=\(rawPerHour, privacy: .public)")

        return BalanceAmountConsumptionRate(
            perHour: rawPerHour,
            perDay: perDay,
            confidence: confidence
        )
    }

    static func resetHistoryForTesting() {
        UserDefaults.standard.removeObject(forKey: historyKey)
    }
}
