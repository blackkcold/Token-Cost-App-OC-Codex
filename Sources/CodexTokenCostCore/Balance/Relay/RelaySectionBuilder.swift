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
                    providers: analytics.providerRankRows.map {
                        RelayProviderMetric(provider: $0.providerKey, tokens: $0.actualTokens, costUSD: $0.effectiveCost)
                    },
                    models: analytics.modelComparisonRows.map {
                        RelayModelMetric(model: $0.modelKey, provider: $0.provider, tokens: $0.actualTokens, costUSD: $0.allocatedCost)
                    }
                ))
            case "usage":
                data = try encode(RelayUsageSection(
                    providers: analytics.providerRankRows.map {
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
                let points = analytics.trendPoints.suffix(days).map {
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
                let days = analytics.trendPoints.suffix(weeks * 7).map {
                    RelayHeatmapDay(
                        date: $0.dateString,
                        tokens: $0.actualTokens + $0.cacheReadTokens + $0.cacheWriteTokens + $0.estimatedCacheReadTokens
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
