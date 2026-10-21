import Foundation

public enum RelaySectionBuilder {
    public static func build(
        requestedSections: [String],
        params: BalanceRelaySectionParams?,
        analytics: TokenCostDashboardAnalytics,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) throws -> [String: BalanceRelayEncodedSection] {
        var result: [String: BalanceRelayEncodedSection] = [:]
        for section in requestedSections {
            let data: Data
            switch section {
            case "overview":
                data = try encode(RelayOverviewSection(
                    totalTokens: analytics.overview.totalTokens,
                    totalActualTokens: analytics.overview.totalActualTokens,
                    totalCostUSD: analytics.overview.totalCost,
                    dailyAverageTokens: analytics.overview.dailyAverage,
                    monthlyEstimateTokens: analytics.overview.monthlyEstimate,
                    activeDays: analytics.overview.activeDays
                ))
            case "cache":
                data = try encode(RelayCacheSection(
                    cacheReadTokens: analytics.cache.cacheReadTokens,
                    cacheWriteTokens: analytics.cache.cacheWriteTokens,
                    hitRate: analytics.cache.cacheHitRate,
                    savedCostUSD: analytics.cache.cacheSavedCost,
                    estimatedCacheReadTokens: analytics.cache.estimatedCacheReadTokens,
                    hasEstimates: analytics.cache.hasEstimates
                ))
            case "cost":
                data = try encode(RelayCostSection(
                    // Synthetic rows (e.g. opencode-go-api) mirror another
                    // provider's usage for comparison. Exporting them would
                    // count the same tokens twice.
                    providers: analytics.providerRankRows.filter { !$0.isSynthetic }.map {
                        RelayProviderMetric(provider: $0.providerKey, tokens: $0.actualTokens, costUSD: $0.effectiveCost)
                    },
                    models: analytics.modelComparisonRows.map {
                        // An unpriced model must not look like a known $0 cost.
                        RelayModelMetric(model: $0.modelKey, provider: $0.provider, tokens: $0.actualTokens, costUSD: $0.allocatedCost > 0 ? $0.allocatedCost : nil)
                    }
                ))
            case "usage":
                data = try encode(RelayUsageSection(
                    providers: analytics.providerRankRows.filter { !$0.isSynthetic }.map {
                        RelayProviderMetric(provider: $0.providerKey, tokens: $0.actualTokens, costUSD: nil)
                    },
                    models: analytics.modelComparisonRows.map {
                        RelayModelMetric(model: $0.modelKey, provider: $0.provider, tokens: $0.actualTokens, costUSD: nil)
                    }
                ))
            case "modelDistribution":
                data = try encode(RelayModelDistributionSection(
                    models: analytics.modelSlices.map {
                        RelayDistributionItem(label: $0.label, tokens: $0.value, percentage: $0.percentage, isOther: $0.isOther)
                    },
                    providers: analytics.providerSlices.map {
                        RelayDistributionItem(label: $0.label, tokens: $0.value, percentage: $0.percentage, isOther: $0.isOther)
                    }
                ))
            case "trend":
                let days = params?.trend?.days ?? 30
                let points = windowedTrendPoints(analytics.trendPoints, days: days).map {
                    RelayTrendPoint(
                        date: $0.dateString,
                        actualTokens: $0.actualTokens,
                        cacheReadTokens: $0.cacheReadTokens,
                        cacheWriteTokens: $0.cacheWriteTokens,
                        estimatedCacheReadTokens: $0.estimatedCacheReadTokens
                    )
                }
                data = try encode(RelayTrendSection(timeZoneIdentifier: timeZoneIdentifier, days: days, points: points))
            case "heatmap":
                let weeks = params?.heatmap?.weeks ?? 52
                let days = windowedTrendPoints(analytics.trendPoints, days: weeks * 7).map {
                    RelayHeatmapDay(
                        date: $0.dateString,
                        tokens: $0.displayActualTokens + $0.cacheReadTokens + $0.cacheWriteTokens
                    )
                }
                data = try encode(RelayHeatmapSection(timeZoneIdentifier: timeZoneIdentifier, weeks: weeks, days: days))
            default:
                continue
            }
            if data.count > RelayCompression.maxSectionBytes { continue }
            let compressed = try RelayCompression.zlibCompress(data)
            result[section] = BalanceRelayEncodedSection(
                uncompressedBytes: data.count,
                data: compressed.base64EncodedString()
            )
        }
        return result
    }

    /// Selects the most recent `days` calendar days ending at the newest data
    /// point. Using `suffix(days)` would shrink the window whenever data has
    /// gaps (e.g. a week without usage), silently changing the reported range.
    private static func windowedTrendPoints(
        _ points: [TokenCostDashboardAnalytics.TrendPoint],
        days: Int
    ) -> [TokenCostDashboardAnalytics.TrendPoint] {
        guard days > 0, let last = points.last else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: last.date) else {
            return points
        }
        return points.filter { $0.date >= cutoff }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard try containsOnlyValidNumbers(data) else { throw RelaySectionBuildError.invalidNumber }
        return data
    }

    private static func containsOnlyValidNumbers(_ data: Data) throws -> Bool {
        let object = try JSONSerialization.jsonObject(with: data)
        func validate(_ value: Any) -> Bool {
            if let number = value as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() { return true }
                let double = number.doubleValue
                return double.isFinite && double >= 0
            }
            if let array = value as? [Any] { return array.allSatisfy(validate) }
            if let dictionary = value as? [String: Any] { return dictionary.values.allSatisfy(validate) }
            return true
        }
        return validate(object)
    }
}
