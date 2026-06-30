import Foundation

public enum TokenCostDetailSortField: String, CaseIterable, Identifiable, Codable, Sendable {
    case date
    case model
    case provider
    case input
    case output
    case cacheRead
    case cacheWrite
    case total
    case cost

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .date: return AppLocalization.text("sort.detail.date")
        case .model: return AppLocalization.text("sort.detail.model")
        case .provider: return AppLocalization.text("sort.detail.provider")
        case .input: return AppLocalization.text("sort.detail.input")
        case .output: return AppLocalization.text("sort.detail.output")
        case .cacheRead: return AppLocalization.text("sort.detail.cacheRead")
        case .cacheWrite: return AppLocalization.text("sort.detail.cacheWrite")
        case .total: return AppLocalization.text("sort.detail.total")
        case .cost: return AppLocalization.text("sort.detail.cost")
        }
    }
}

public enum TokenCostSortDirection: String, CaseIterable, Identifiable, Codable, Sendable {
    case descending
    case ascending

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .descending: return AppLocalization.text("sort.direction.descending")
        case .ascending: return AppLocalization.text("sort.direction.ascending")
        }
    }

    public var systemImage: String {
        switch self {
        case .descending: return "arrow.down"
        case .ascending: return "arrow.up"
        }
    }
}

public struct TokenCostDashboardAnalytics: Sendable {
    public struct Overview: Sendable {
        public var totalTokens: Double
        public var totalActualTokens: Double
        public var totalCost: Double
        public var dailyAverage: Double
        public var monthlyEstimate: Double
        public var averagePerRequest: Double
        public var totalMessages: Int
        public var activeDays: Int
        public var dateRangeStart: String?
        public var dateRangeEnd: String?
        public var updatedAt: String
    }

    public struct CacheSummary: Sendable {
        public var cacheReadTokens: Double
        public var cacheWriteTokens: Double
        public var totalCacheTokens: Double
        public var cacheHitRate: Double
        public var cacheSavedCost: Double
    }

    public struct ProviderCacheRow: Identifiable, Sendable {
        public var id: String { key }

        public var key: String
        public var displayName: String
        public var usageTokens: Double
        public var actualTokens: Double
        public var cacheReadTokens: Double
        public var cacheWriteTokens: Double
        public var cacheWriteLabel: String
        public var cacheRate: Double
        public var colorKey: String
    }

    public struct ProviderRankRow: Identifiable, Sendable {
        public var id: String
        public var providerKey: String
        public var displayName: String
        public var actualTokens: Double
        public var cacheReadTokens: Double
        public var cacheWriteTokens: Double
        public var messages: Int
        public var rawCost: Double
        public var effectiveCost: Double?
        public var tokensPerDollar: Double
        public var modelCount: Int
        public var isSubscription: Bool
        public var isSynthetic: Bool
        public var hasPricing: Bool
        public var colorKey: String
    }

    public struct ModelComparisonRow: Identifiable, Sendable {
        public var id: String { modelKey }

        public var modelKey: String
        public var displayName: String
        public var provider: String
        public var actualTokens: Double
        public var allocatedCost: Double
        public var tokensPerDollar: Double
        public var colorKey: String
    }

    public struct DistributionSlice: Identifiable, Sendable {
        public var id: String { "\(colorKey)|\(label)" }

        public var label: String
        public var value: Double
        public var percentage: Double
        public var colorKey: String
        public var isOther: Bool
    }

    public struct TrendPoint: Identifiable, Sendable {
        public var id: String { dateString }
        public var date: Date
        public var dateString: String
        public var actualTokens: Double
        public var cacheReadTokens: Double
        public var cacheWriteTokens: Double
    }

    public struct StackedSeries: Identifiable, Sendable {
        public var id: String { colorKey }
        public var label: String
        public var values: [Double]
        public var total: Double
        public var colorKey: String
        public var isOther: Bool
    }

    public let overview: Overview
    public let cache: CacheSummary
    public let providerCacheRows: [ProviderCacheRow]
    public let providerRankRows: [ProviderRankRow]
    public let modelComparisonRows: [ModelComparisonRow]
    public let modelSlices: [DistributionSlice]
    public let providerSlices: [DistributionSlice]
    public let trendPoints: [TrendPoint]
    public let stackedSeries: [StackedSeries]

    private let rawRows: [DashboardPayload.RawRow]

    public init(
        payload: DashboardPayload,
        showZeroUsageXiaomiProvider: Bool = false,
        billingOverridesByProviderKey: [String: Double] = [:]
    ) {
        self.rawRows = payload.rawData

        var providerAccumulators: [String: ProviderAccumulator] = [:]
        var modelAccumulators: [String: ModelAccumulator] = [:]
        var dailyActual: [String: Double] = [:]
        var dailyCacheRead: [String: Double] = [:]
        var dailyCacheWrite: [String: Double] = [:]
        var dailyModelTotals: [String: [String: Double]] = [:]
        var dateKeys: Set<String> = []
        var totalTokensFromRows: Double = 0
        var totalActualTokens: Double = 0
        var totalMessages: Int = 0

        for row in payload.rawData {
            let providerKey = Self.normalizeProviderKey(row.provider)
            let providerDisplayName = Self.displayProviderName(row.provider)
            let modelKey = TokenCostPricingCatalog.normalizeModelName(row.model)
            let actualTokens = row.input + row.output + row.reasoning

            dateKeys.insert(row.date)
            totalTokensFromRows += row.total
            totalActualTokens += actualTokens
            totalMessages += row.msgCount

            dailyActual[row.date, default: 0] += actualTokens
            dailyCacheRead[row.date, default: 0] += row.cacheRead
            dailyCacheWrite[row.date, default: 0] += row.cacheWrite

            var dayModelTotals = dailyModelTotals[row.date, default: [:]]
            dayModelTotals[modelKey, default: 0] += row.total
            dailyModelTotals[row.date] = dayModelTotals

            if providerAccumulators[providerKey] == nil {
                providerAccumulators[providerKey] = ProviderAccumulator(displayName: providerDisplayName)
            }

            providerAccumulators[providerKey]?.input += row.input
            providerAccumulators[providerKey]?.output += row.output
            providerAccumulators[providerKey]?.cacheRead += row.cacheRead
            providerAccumulators[providerKey]?.cacheWrite += row.cacheWrite
            providerAccumulators[providerKey]?.cacheWriteMissingCount += row.cacheWriteMissingCount
            providerAccumulators[providerKey]?.cacheWriteReportedCount += row.cacheWriteReportedCount
            providerAccumulators[providerKey]?.total += row.total
            providerAccumulators[providerKey]?.actualTokens += actualTokens
            providerAccumulators[providerKey]?.rawCost += row.cost
            providerAccumulators[providerKey]?.messages += row.msgCount
            providerAccumulators[providerKey]?.models.insert(modelKey)
            providerAccumulators[providerKey]?.rows.append(row)

            let apiCost = TokenCostPricingCatalog.apiCost(
                model: row.model,
                input: row.input,
                output: row.output,
                reasoning: row.reasoning,
                cacheRead: row.cacheRead,
                cacheWrite: row.cacheWrite
            )
            if apiCost > 0 {
                providerAccumulators[providerKey]?.syntheticApiCost += apiCost
            }

            if modelAccumulators[modelKey] == nil {
                modelAccumulators[modelKey] = ModelAccumulator(displayName: modelKey)
            }

            modelAccumulators[modelKey]?.total += row.total
            modelAccumulators[modelKey]?.actualTokens += actualTokens
            modelAccumulators[modelKey]?.cacheRead += row.cacheRead
            modelAccumulators[modelKey]?.cacheWrite += row.cacheWrite
            modelAccumulators[modelKey]?.messages += row.msgCount
            if modelAccumulators[modelKey]?.primaryProvider == nil {
                modelAccumulators[modelKey]?.primaryProvider = providerDisplayName
            }
        }

        let filteredProviderAccumulators = Self.filteredProviderAccumulators(
            from: providerAccumulators,
            showZeroUsageXiaomiProvider: showZeroUsageXiaomiProvider
        )
        let filteredModelAccumulators = Self.filteredModelAccumulators(from: modelAccumulators)
        let sortedDateKeys = dateKeys.sorted()
        let providerEffectiveCosts = Self.providerEffectiveCosts(
            from: providerAccumulators,
            billingOverridesByProviderKey: billingOverridesByProviderKey
        )
        let totalCost = providerEffectiveCosts.values.reduce(0, +)
        let activeDays = sortedDateKeys.count
        let dailyAverage = activeDays > 0 ? totalActualTokens / Double(activeDays) : 0
        let monthlyEstimate = dailyAverage * 30
        let averagePerRequest = totalMessages > 0 ? totalActualTokens / Double(totalMessages) : 0
        let cacheReadTokens = dailyCacheRead.values.reduce(0, +)
        let cacheWriteTokens = dailyCacheWrite.values.reduce(0, +)
        let totalCacheTokens = cacheReadTokens + cacheWriteTokens
        let averageActualCostPerToken = totalActualTokens > 0 ? totalCost / totalActualTokens : 0
        let cacheSavedCost = cacheReadTokens * averageActualCostPerToken
        let cacheHitRate = (totalActualTokens + cacheReadTokens) > 0 ? cacheReadTokens / (totalActualTokens + cacheReadTokens) : 0

        self.overview = Overview(
            totalTokens: totalTokensFromRows,
            totalActualTokens: totalActualTokens,
            totalCost: totalCost,
            dailyAverage: dailyAverage,
            monthlyEstimate: monthlyEstimate,
            averagePerRequest: averagePerRequest,
            totalMessages: totalMessages,
            activeDays: activeDays,
            dateRangeStart: sortedDateKeys.first,
            dateRangeEnd: sortedDateKeys.last,
            updatedAt: payload.summary.updatedAt
        )

        self.cache = CacheSummary(
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            totalCacheTokens: totalCacheTokens,
            cacheHitRate: cacheHitRate,
            cacheSavedCost: cacheSavedCost
        )

        self.providerCacheRows = filteredProviderAccumulators
            .map { key, accumulator in
                let usageTokens = accumulator.actualTokens + accumulator.cacheRead + accumulator.cacheWrite
                let totalCache = accumulator.actualTokens + accumulator.cacheRead
                let cacheRate = totalCache > 0 ? accumulator.cacheRead / totalCache : 0
                return ProviderCacheRow(
                    key: key,
                    displayName: accumulator.displayName,
                    usageTokens: usageTokens,
                    actualTokens: accumulator.actualTokens,
                    cacheReadTokens: accumulator.cacheRead,
                    cacheWriteTokens: accumulator.cacheWrite,
                    cacheWriteLabel: Self.cacheWriteLabel(
                        writeTokens: accumulator.cacheWrite,
                        missingCount: accumulator.cacheWriteMissingCount,
                        reportedCount: accumulator.cacheWriteReportedCount
                    ),
                    cacheRate: cacheRate,
                    colorKey: key
                )
            }
            .sorted { lhs, rhs in
                if lhs.usageTokens == rhs.usageTokens {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
                return lhs.usageTokens > rhs.usageTokens
            }

        self.providerRankRows = Self.buildProviderRankRows(
            from: filteredProviderAccumulators,
            effectiveCosts: providerEffectiveCosts
        )
        self.modelComparisonRows = Self.buildModelComparisonRows(
            from: filteredModelAccumulators,
            providerAccumulators: filteredProviderAccumulators,
            providerEffectiveCosts: providerEffectiveCosts
        )
        self.modelSlices = Self.buildDistributionSlices(
            valuesByKey: filteredModelAccumulators.mapValues { $0.total },
            topLimit: 7,
            otherLabel: AppLocalization.text("common.other"),
            otherColorKey: "other-models"
        )
        self.providerSlices = Self.buildDistributionSlices(
            valuesByKey: filteredProviderAccumulators.mapValues { $0.total },
            topLimit: 7,
            otherLabel: AppLocalization.text("common.other"),
            otherColorKey: "other-providers"
        )
        self.trendPoints = Self.buildTrendPoints(
            sortedDateKeys: sortedDateKeys,
            dailyActual: dailyActual,
            dailyCacheRead: dailyCacheRead,
            dailyCacheWrite: dailyCacheWrite
        )
        self.stackedSeries = Self.buildStackedSeries(
            sortedDateKeys: sortedDateKeys,
            dailyModelTotals: dailyModelTotals,
            modelAccumulators: filteredModelAccumulators
        )
    }

    public func sortedDetailRows(
        sortField: TokenCostDetailSortField,
        direction: TokenCostSortDirection
    ) -> [DashboardPayload.RawRow] {
        let rows = rawRows.sorted { lhs, rhs in
            compare(lhs, rhs, field: sortField)
        }

        guard direction == .ascending else {
            return Array(rows.reversed())
        }
        return rows
    }

    /// Returns per-provider raw cost and synthetic API cost directly from payload rows,
    /// without billing overrides or legacy fallback subscription interference.
    public static func providerUsageCosts(payload: DashboardPayload) -> [String: (raw: Double, synthetic: Double)] {
        var result: [String: (raw: Double, synthetic: Double)] = [:]
        for row in payload.rawData {
            let key = Self.normalizeProviderKey(row.provider)
            var entry = result[key] ?? (0, 0)
            entry.raw += row.cost
            entry.synthetic += TokenCostPricingCatalog.apiCost(
                model: row.model,
                input: row.input,
                output: row.output,
                reasoning: row.reasoning,
                cacheRead: row.cacheRead,
                cacheWrite: row.cacheWrite
            )
            result[key] = entry
        }
        return result
    }

    private func compare(_ lhs: DashboardPayload.RawRow, _ rhs: DashboardPayload.RawRow, field: TokenCostDetailSortField) -> Bool {
        switch field {
        case .date:
            return compareString(lhs.date, rhs.date)
        case .model:
            return compareString(lhs.model, rhs.model)
        case .provider:
            return compareString(lhs.provider, rhs.provider)
        case .input:
            return compareNumeric(lhs.input, rhs.input)
        case .output:
            return compareNumeric(lhs.output, rhs.output)
        case .cacheRead:
            return compareNumeric(lhs.cacheRead, rhs.cacheRead)
        case .cacheWrite:
            return compareNumeric(lhs.cacheWrite, rhs.cacheWrite)
        case .total:
            return compareNumeric(lhs.total, rhs.total)
        case .cost:
            return compareNumeric(lhs.cost, rhs.cost)
        }
    }

    private func compareString(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private func compareNumeric(_ lhs: Double, _ rhs: Double) -> Bool {
        lhs < rhs
    }

    private static func providerEffectiveCosts(
        from providerAccumulators: [String: ProviderAccumulator],
        billingOverridesByProviderKey: [String: Double]
    ) -> [String: Double] {
        var effectiveCosts: [String: Double] = [:]
        let normalizedOverrides = billingOverridesByProviderKey.reduce(into: [String: Double]()) { partialResult, item in
            let key = item.key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if item.value.isFinite, item.value > 0 {
                partialResult[key] = item.value
            }
        }

        for (providerKey, accumulator) in providerAccumulators {
            if let overrideCost = normalizedOverrides[providerKey], overrideCost > 0 {
                effectiveCosts[providerKey] = overrideCost
                continue
            }

            if let subscriptionCost = TokenCostPricingCatalog.subscriptionMonthlyCost(for: providerKey), subscriptionCost > 0 {
                effectiveCosts[providerKey] = subscriptionCost
            } else if accumulator.syntheticApiCost > 0 {
                effectiveCosts[providerKey] = accumulator.syntheticApiCost
            } else if accumulator.rawCost > 0 {
                effectiveCosts[providerKey] = accumulator.rawCost
            } else {
                effectiveCosts[providerKey] = 0
            }
        }

        return effectiveCosts
    }

    private static func buildProviderRankRows(
        from providerAccumulators: [String: ProviderAccumulator],
        effectiveCosts: [String: Double]
    ) -> [ProviderRankRow] {
        var rows: [ProviderRankRow] = []

        for (providerKey, accumulator) in providerAccumulators {
            let usageTokens = accumulator.actualTokens + accumulator.cacheRead + accumulator.cacheWrite
            guard usageTokens > 0 || shouldIncludeZeroUsageXiaomiProvider(providerKey) else {
                continue
            }

            let effectiveCost = effectiveCosts[providerKey] ?? 0
            let hasPricing = effectiveCost > 0
            let displayName = providerKey == "opencode-go" ? AppLocalization.text("provider.openCodeGo.subscription") : accumulator.displayName

            rows.append(
                ProviderRankRow(
                    id: providerKey,
                    providerKey: providerKey,
                    displayName: displayName,
                    actualTokens: accumulator.actualTokens,
                    cacheReadTokens: accumulator.cacheRead,
                    cacheWriteTokens: accumulator.cacheWrite,
                    messages: accumulator.messages,
                    rawCost: accumulator.rawCost,
                    effectiveCost: hasPricing ? effectiveCost : nil,
                    tokensPerDollar: hasPricing ? accumulator.actualTokens / effectiveCost : 0,
                    modelCount: accumulator.models.count,
                    isSubscription: TokenCostPricingCatalog.subscriptionMonthlyCost(for: providerKey) != nil,
                    isSynthetic: false,
                    hasPricing: hasPricing,
                    colorKey: providerKey
                )
            )

            if providerKey == "opencode-go" {
                let apiCost = accumulator.syntheticApiCost
                rows.append(
                    ProviderRankRow(
                        id: "\(providerKey)-api",
                        providerKey: "opencode-go-api",
                        displayName: AppLocalization.text("provider.openCodeGo.api"),
                        actualTokens: accumulator.actualTokens,
                        cacheReadTokens: accumulator.cacheRead,
                        cacheWriteTokens: accumulator.cacheWrite,
                        messages: accumulator.messages,
                        rawCost: accumulator.rawCost,
                        effectiveCost: apiCost > 0 ? apiCost : nil,
                        tokensPerDollar: apiCost > 0 ? accumulator.actualTokens / apiCost : 0,
                        modelCount: accumulator.models.count,
                        isSubscription: false,
                        isSynthetic: true,
                        hasPricing: apiCost > 0,
                        colorKey: "opencode-go-api"
                    )
                )
            }
        }

        return rows.sorted { lhs, rhs in
            if lhs.tokensPerDollar == rhs.tokensPerDollar {
                if lhs.hasPricing != rhs.hasPricing {
                    return lhs.hasPricing && !rhs.hasPricing
                }
                if lhs.actualTokens == rhs.actualTokens {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
                return lhs.actualTokens > rhs.actualTokens
            }
            return lhs.tokensPerDollar > rhs.tokensPerDollar
        }
    }

    private static func buildModelComparisonRows(
        from modelAccumulators: [String: ModelAccumulator],
        providerAccumulators: [String: ProviderAccumulator],
        providerEffectiveCosts: [String: Double]
    ) -> [ModelComparisonRow] {
        var modelRows: [String: ModelAccumulator] = modelAccumulators

        for row in providerAccumulators.values.flatMap({ $0.rows }) {
            let modelKey = TokenCostPricingCatalog.normalizeModelName(row.model)

            let apiModelCost = TokenCostPricingCatalog.apiCost(
                model: row.model,
                input: row.input,
                output: row.output,
                reasoning: row.reasoning,
                cacheRead: row.cacheRead,
                cacheWrite: row.cacheWrite
            )

            if modelRows[modelKey] == nil {
                modelRows[modelKey] = ModelAccumulator(displayName: modelKey)
            }
            modelRows[modelKey]?.allocatedCost += apiModelCost
        }

        return modelRows
            .filter { $0.value.total > 0 }
            .map { key, accumulator in
                let ratio = accumulator.allocatedCost > 0 ? accumulator.actualTokens / accumulator.allocatedCost : 0
                return ModelComparisonRow(
                    modelKey: key,
                    displayName: accumulator.displayName,
                    provider: accumulator.primaryProvider ?? AppLocalization.text("common.unspecified"),
                    actualTokens: accumulator.actualTokens,
                    allocatedCost: accumulator.allocatedCost,
                    tokensPerDollar: ratio,
                    colorKey: key
                )
            }
            .sorted { lhs, rhs in
                if lhs.tokensPerDollar == rhs.tokensPerDollar {
                    if lhs.actualTokens == rhs.actualTokens {
                        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                    }
                    return lhs.actualTokens > rhs.actualTokens
                }
                return lhs.tokensPerDollar > rhs.tokensPerDollar
            }
    }

    private static func buildDistributionSlices(
        valuesByKey: [String: Double],
        topLimit: Int,
        otherLabel: String,
        otherColorKey: String
    ) -> [DistributionSlice] {
        let sorted = valuesByKey
            .map { ($0.key, $0.value) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending
                }
                return lhs.1 > rhs.1
            }

        let total = sorted.reduce(0) { $0 + $1.1 }
        guard total > 0 else {
            return []
        }

        let topEntries = Array(sorted.prefix(topLimit))
        let remaining = sorted.dropFirst(topLimit).reduce(0) { $0 + $1.1 }

        var slices: [DistributionSlice] = topEntries.enumerated().map { index, entry in
            DistributionSlice(
                label: displayName(for: entry.0),
                value: entry.1,
                percentage: entry.1 / total,
                colorKey: entry.0,
                isOther: false
            )
        }

        if remaining > 0 {
            slices.append(
                DistributionSlice(
                    label: otherLabel,
                    value: remaining,
                    percentage: remaining / total,
                    colorKey: otherColorKey,
                    isOther: true
                )
            )
        }

        return slices
    }

    private static func buildTrendPoints(
        sortedDateKeys: [String],
        dailyActual: [String: Double],
        dailyCacheRead: [String: Double],
        dailyCacheWrite: [String: Double]
    ) -> [TrendPoint] {
        sortedDateKeys.compactMap { key in
            guard let date = Self.chartDateFormatter.date(from: key) else {
                return nil
            }
            return TrendPoint(
                date: date,
                dateString: key,
                actualTokens: dailyActual[key] ?? 0,
                cacheReadTokens: dailyCacheRead[key] ?? 0,
                cacheWriteTokens: dailyCacheWrite[key] ?? 0
            )
        }
    }

    private static func buildStackedSeries(
        sortedDateKeys: [String],
        dailyModelTotals: [String: [String: Double]],
        modelAccumulators: [String: ModelAccumulator]
    ) -> [StackedSeries] {
        let topModelKeys = Array(
            modelAccumulators
                .map { ($0.key, $0.value.total) }
                .sorted { lhs, rhs in
                    if lhs.1 == rhs.1 {
                        return lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending
                    }
                    return lhs.1 > rhs.1
                }
                .prefix(8)
                .map { $0.0 }
        )

        let topModelSet = Set(topModelKeys)
        let topSeries: [StackedSeries] = topModelKeys.map { modelKey in
            let values = sortedDateKeys.map { date in
                dailyModelTotals[date]?[modelKey] ?? 0
            }
            return StackedSeries(
                label: modelKey,
                values: values,
                total: values.reduce(0, +),
                colorKey: modelKey,
                isOther: false
            )
        }

        let otherValues = sortedDateKeys.map { date in
            guard let models = dailyModelTotals[date] else { return 0.0 }
            return models.reduce(0.0) { partialResult, element in
                topModelSet.contains(element.key) ? partialResult : partialResult + element.value
            }
        }

        var series = topSeries
        if otherValues.contains(where: { $0 > 0 }) {
            series.append(
                StackedSeries(
                    label: AppLocalization.text("common.other"),
                    values: otherValues,
                    total: otherValues.reduce(0, +),
                    colorKey: "other-models",
                    isOther: true
                )
            )
        }

        return series
    }

    private static func cacheWriteLabel(writeTokens: Double, missingCount: Int, reportedCount: Int) -> String {
        if reportedCount == 0 && missingCount > 0 {
            return AppLocalization.text("dashboard.cacheWrite.missingReport")
        }
        if writeTokens > 0 {
            return String(format: "%.0f", writeTokens)
        }
        if missingCount > 0 {
            return AppLocalization.text("dashboard.cacheWrite.partialMissing")
        }
        return "0"
    }

    private static func normalizeProviderKey(_ provider: String) -> String {
        let trimmed = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed.lowercased()
    }

    private static func displayProviderName(_ provider: String) -> String {
        let trimmed = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    private static func displayName(for key: String) -> String {
        switch key.lowercased() {
        case "opencode-go":
            return AppLocalization.text("provider.openCodeGo.subscription")
        case "opencode-go-api":
            return AppLocalization.text("provider.openCodeGo.api")
        default:
            return key
        }
    }

    private static func filteredProviderAccumulators(
        from providerAccumulators: [String: ProviderAccumulator],
        showZeroUsageXiaomiProvider: Bool
    ) -> [String: ProviderAccumulator] {
        providerAccumulators.filter { key, accumulator in
            let usageTokens = accumulator.actualTokens + accumulator.cacheRead + accumulator.cacheWrite
            guard usageTokens > 0 else {
                return showZeroUsageXiaomiProvider && shouldIncludeZeroUsageXiaomiProvider(key)
            }
            return true
        }
    }

    private static func filteredModelAccumulators(from modelAccumulators: [String: ModelAccumulator]) -> [String: ModelAccumulator] {
        modelAccumulators.filter { $0.value.total > 0 }
    }

    private static func shouldIncludeZeroUsageXiaomiProvider(_ providerKey: String) -> Bool {
        providerKey.localizedCaseInsensitiveContains("xiaomi")
    }

    private static let chartDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private struct ProviderAccumulator {
        var displayName: String
        var input: Double = 0
        var output: Double = 0
        var cacheRead: Double = 0
        var cacheWrite: Double = 0
        var cacheWriteMissingCount: Int = 0
        var cacheWriteReportedCount: Int = 0
        var total: Double = 0
        var actualTokens: Double = 0
        var rawCost: Double = 0
        var messages: Int = 0
        var models: Set<String> = []
        var rows: [DashboardPayload.RawRow] = []
        var syntheticApiCost: Double = 0
    }

    private struct ModelAccumulator {
        var displayName: String
        var total: Double = 0
        var actualTokens: Double = 0
        var cacheRead: Double = 0
        var cacheWrite: Double = 0
        var messages: Int = 0
        var allocatedCost: Double = 0
        var primaryProvider: String?
    }
}

private enum TokenCostPricingCatalog {
    /// Legacy fallback subscription costs — used ONLY when billingOverridesByProviderKey
    /// does not provide a value for a given provider key. User billing plan selections
    /// (via AppPreferences.billingOverridesByProviderKey()) always take precedence.
    static let legacyFallbackMonthlyCosts: [String: Double] = [
        "minimax-cn-coding-plan": TokenCostCurrencyService.convert(98, from: .cny, to: .usd),
        "xiaomi-token-plan-cn": TokenCostCurrencyService.convert(34.9, from: .cny, to: .usd),
        "openai": 20.00
    ]

    private static let modelAliases: [String: String] = [
        "minimax-m2.7-highspeed": "minimax-m2.7",
        "deepseek-chat": "deepseek-v4-flash",
        "deepseek-reasoner": "deepseek-v4-pro"
    ]

    private static let zenPricing: [String: [String: Double]] = [
        "minimax-m2.7": ["input": 0.30, "output": 1.20, "cacheRead": 0.06, "cacheWrite": 0.375],
        "minimax-m2.5": ["input": 0.30, "output": 1.20, "cacheRead": 0.06, "cacheWrite": 0.375],
        "glm-5.1": ["input": 1.40, "output": 4.40, "cacheRead": 0.26],
        "glm-5": ["input": 1.00, "output": 3.20, "cacheRead": 0.20],
        "kimi-k2.5": ["input": 0.60, "output": 3.00, "cacheRead": 0.10],
        "kimi-k2.6": ["input": 0.95, "output": 4.00, "cacheRead": 0.16],
        "qwen3.6-plus": ["input": 0.50, "output": 3.00, "cacheRead": 0.05, "cacheWrite": 0.625],
        "qwen3.5-plus": ["input": 0.20, "output": 1.20, "cacheRead": 0.02, "cacheWrite": 0.25],
        "claude-opus-4.7": ["input": 5.00, "output": 25.00, "cacheRead": 0.50, "cacheWrite": 6.25],
        "claude-sonnet-4.6": ["input": 3.00, "output": 15.00, "cacheRead": 0.30, "cacheWrite": 3.75],
        "claude-haiku-4.5": ["input": 1.00, "output": 5.00, "cacheRead": 0.10, "cacheWrite": 1.25],
        "gemini-3.1-pro": ["input": 2.00, "output": 12.00, "cacheRead": 0.20],
        "gemini-3-flash": ["input": 0.50, "output": 3.00, "cacheRead": 0.05],
        "gpt-5.5": ["input": 5.00, "output": 30.00, "cacheRead": 0.50],
        "gpt-5.4": ["input": 2.50, "output": 15.00, "cacheRead": 0.25],
        "gpt-5.4-mini": ["input": 0.75, "output": 4.50, "cacheRead": 0.075],
        "gpt-5.4-nano": ["input": 0.20, "output": 1.25, "cacheRead": 0.02],
        "gpt-5": ["input": 1.07, "output": 8.50, "cacheRead": 0.107],
        "gpt-5.4-pro": ["input": 30.00, "output": 180.00, "cacheRead": 30.00],
        "deepseek-v4-pro": ["input": 0.435, "output": 0.87, "cacheRead": 0.003625],  // 官方当前定价（2026/06）
        "deepseek-v4-flash": ["input": 0.14, "output": 0.28, "cacheRead": 0.0028],
        "big-pickle": ["input": 0, "output": 0, "cacheRead": 0],
        "mimo-v2-omni": ["input": 0.30, "output": 1.20, "cacheRead": 0.06, "cacheWrite": 0.375],
        "mimo-v2-pro": ["input": 0.30, "output": 1.20, "cacheRead": 0.06, "cacheWrite": 0.375],
        "mimo-v2.5": ["input": 0.30, "output": 1.20, "cacheRead": 0.06, "cacheWrite": 0.375],
        "mimo-v2.5-pro": ["input": 0.30, "output": 1.20, "cacheRead": 0.06, "cacheWrite": 0.375]
    ]

    static func normalizeModelName(_ model: String) -> String {
        guard !model.isEmpty else {
            return ""
        }
        var normalized = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        normalized = normalized
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        if let slashIndex = normalized.lastIndex(of: "/") {
            normalized = String(normalized[normalized.index(after: slashIndex)...])
        }

        return modelAliases[normalized] ?? normalized
    }

    static func subscriptionMonthlyCost(for provider: String) -> Double? {
        let key = provider.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cost = legacyFallbackMonthlyCosts[key], cost > 0 else {
            return nil
        }
        return cost
    }

    static func effectiveCost(for provider: String, rawCost: Double) -> Double? {
        if let subscription = subscriptionMonthlyCost(for: provider), subscription > 0 {
            return subscription
        }
        return rawCost > 0 ? rawCost : nil
    }

    static func apiCost(model: String, input: Double, output: Double, reasoning: Double, cacheRead: Double, cacheWrite: Double) -> Double {
        let key = normalizeModelName(model)
        guard let pricing = zenPricing[key] else {
            return 0
        }
        let inputCost = (input / 1_000_000) * (pricing["input"] ?? 0)
        let outputCost = (output / 1_000_000) * (pricing["output"] ?? 0)
        let reasoningCost = (reasoning / 1_000_000) * (pricing["reasoning"] ?? pricing["output"] ?? 0)
        let cacheReadCost = (cacheRead / 1_000_000) * (pricing["cacheRead"] ?? 0)
        let cacheWriteCost = (cacheWrite / 1_000_000) * (pricing["cacheWrite"] ?? 0)
        return inputCost + outputCost + reasoningCost + cacheReadCost + cacheWriteCost
    }
}
