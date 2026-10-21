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

/// Public access points for Ollama Cloud cache-read estimation utilities.
public enum OllamaCloudCacheEstimation {
    public struct Context: Sendable {
        public enum Source: Sendable { case runtime, snapshot }
        public struct Reference: Sendable {
            public let rate: Double
            public let source: Source
            public let sampleCount: Int
            public let grossTokens: Double
        }
        private var references: [String: Reference] = [:]
        /// Honesty gate (D8). Keys are "\(normalizedModel)|\(date)" for every
        /// ollama-cloud reporting bucket that already carries a real
        /// cacheRead > 0. Provider-scoped on purpose: a non-Ollama provider
        /// reporting cache for the same model and date proves nothing about
        /// whether Ollama Cloud itself was reporting cache that day.
        private var ollamaReportedCacheKeys: Set<String> = []

        /// Rows are aggregated reporting-period buckets, not individual requests.
        public init(rows: [DashboardPayload.RawRow] = []) {
            for model in ["deepseek-v4-flash", "deepseek-v4-pro"] {
                var count = 0
                var gross = 0.0
                var cache = 0.0
                var overflow = false
                for row in rows {
                    guard row.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "ollama-cloud",
                          normalizedModelName(row.model) == model,
                          row.input.isFinite, row.cacheRead.isFinite,
                          row.input >= 100, row.cacheRead >= 0 else { continue }
                    let denominator = row.input + row.cacheRead
                    guard denominator.isFinite, denominator > 0 else { continue }
                    let rate = row.cacheRead / denominator
                    guard rate > 0.01, rate < 0.99 else { continue }
                    count += 1
                    gross += denominator
                    cache += row.cacheRead
                    if !gross.isFinite || !cache.isFinite { overflow = true; break }
                }
                let rate = gross > 0 ? cache / gross : 0
                let valid = !overflow && count >= 3 && gross >= 1_000 && rate.isFinite && rate > 0 && rate < 1
                references[model] = Reference(
                    rate: valid ? rate : cacheReadRate(for: model),
                    source: valid ? .runtime : .snapshot,
                    sampleCount: count,
                    grossTokens: overflow ? 0 : gross
                )
            }

            for row in rows {
                guard row.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ollama-cloud",
                      row.cacheRead > 0 else { continue }
                ollamaReportedCacheKeys.insert(Self.gateKey(model: row.model, date: row.date))
            }
        }

        private static func gateKey(model: String, date: String) -> String {
            "\(normalizedModelName(model))|\(date)"
        }

        /// D8 honesty gate: a cacheRead == 0 bucket is only treated as
        /// "unreported" when Ollama Cloud reported no cache at all for this
        /// normalized model on this date. Once any bucket on that (model, date)
        /// carries real cache, the remaining cacheRead == 0 buckets are
        /// genuine no-cache requests and must not be estimated.
        public func allowsEstimate(model: String, date: String) -> Bool {
            !ollamaReportedCacheKeys.contains(Self.gateKey(model: model, date: date))
        }

        public func reference(for model: String) -> Reference? {
            references[normalizedModelName(model)]
        }
    }

    public static func cacheReadRate(for model: String) -> Double {
        TokenCostPricingCatalog.ollamaCacheReadRate(for: normalizedModelName(model))
    }
    public static func normalizedModelName(_ model: String) -> String {
        TokenCostPricingCatalog.normalizeModelName(model)
    }

    /// Legacy miss-input multiplier, retained for source compatibility only.
    /// Ollama gross input estimation uses cacheReadRate, never this multiplier.
    public static func cacheReadMultiplier(for model: String) -> Double {
        TokenCostPricingCatalog.ollamaCacheReadEstimationMultiplier(for: model)
    }

    /// Pure eligibility predicate — no value computation. Single entry point for
    /// every estimation call site (dashboard loop, effectiveCacheRead, views,
    /// task classification). Provider key is normalized (trim + lowercase) the
    /// same way as TokenCostDashboardAnalytics.normalizeProviderKey, so
    /// "Ollama-Cloud" / " ollama-cloud " variants are all covered.
    public static func isEligibleOllamaEstimate(provider: String, model: String, cacheRead: Double, input: Double) -> Bool {
        let providerKey = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard providerKey == "ollama-cloud",
              cacheRead == 0,
              input > 0,
              input.isFinite else {
            return false
        }
        let normalized = TokenCostPricingCatalog.normalizeModelName(model)
        return normalized == "deepseek-v4-flash" || normalized == "deepseek-v4-pro"
    }

    /// Injects estimation for ollama-cloud when cacheRead == 0; returns real cacheRead otherwise.
    public static func effectiveCacheRead(provider: String, model: String, cacheRead: Double, input: Double, context: Context = Context(), date: String? = nil) -> Double {
        guard isEligibleOllamaEstimate(provider: provider, model: model, cacheRead: cacheRead, input: input) else {
            return cacheRead
        }
        if let date, !context.allowsEstimate(model: model, date: date) {
            return cacheRead
        }
        // Context accepts only non-Ollama raw observations; estimates never feed back.
        let rate = context.reference(for: model)?.rate ?? 0
        guard rate.isFinite, rate > 0, rate < 1 else { return cacheRead }
        let estimated = input * rate
        let remainder = input - estimated
        return (estimated.isFinite && estimated > 0 && remainder.isFinite && remainder > 0) ? estimated : cacheRead
    }

    /// Single split entry point for the Ollama gross-input deduction, so the
    /// dashboard loop, provider cache rows, trend points and task classification
    /// can never disagree about how much was deducted. Only genuine
    /// unreported-cache rows produce a non-zero `estimatedCacheRead`; every other
    /// row passes through with raw values and a deduction of 0.
    public struct Split: Sendable {
        public let estimatedCacheRead: Double
        public let displayInput: Double
        public let displayActual: Double
        public let displayUsage: Double
    }

    public static func split(
        provider: String,
        model: String,
        input: Double,
        output: Double,
        reasoning: Double,
        cacheRead: Double,
        cacheWrite: Double,
        date: String?,
        context: Context
    ) -> Split {
        let actual = input + output + reasoning
        let passthrough = Split(
            estimatedCacheRead: 0,
            displayInput: input,
            displayActual: actual,
            displayUsage: actual + cacheRead + cacheWrite
        )
        let eligible = isEligibleOllamaEstimate(
            provider: provider,
            model: model,
            cacheRead: cacheRead,
            input: input
        ) && (date.map { context.allowsEstimate(model: model, date: $0) } ?? true)
        guard eligible else { return passthrough }

        let estimated = effectiveCacheRead(
            provider: provider,
            model: model,
            cacheRead: cacheRead,
            input: input,
            context: context,
            date: date
        )
        guard estimated.isFinite, estimated > 0, estimated < input else { return passthrough }

        return Split(
            estimatedCacheRead: estimated,
            displayInput: input - estimated,
            displayActual: actual - estimated,
            displayUsage: actual + cacheRead + cacheWrite
        )
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
        public var totalEstimatedCacheReadTokens: Double

        /// Display-only net figure. `totalActualTokens` keeps its original
        /// reported/gross definition; this subtracts the Ollama gross-input
        /// deduction so "how much did I really burn" is answerable without
        /// redefining the compatibility metric that billing and cross-page
        /// summaries depend on.
        public var netActualTokens: Double { totalActualTokens - totalEstimatedCacheReadTokens }
        public var hasEstimatedCacheRead: Bool { totalEstimatedCacheReadTokens > 0 }
    }

    public struct CacheSummary: Sendable {
        public var cacheReadTokens: Double
        public var cacheWriteTokens: Double
        public var totalCacheTokens: Double
        public var cacheHitRate: Double
        public var cacheSavedCost: Double
        public var estimatedCacheReadTokens: Double
        public var hasEstimates: Bool
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
        public var inputTokens: Double
        public var estimatedCacheReadTokens: Double
        public var hasEstimates: Bool

        public var displayInputTokens: Double { inputTokens - estimatedCacheReadTokens }
        public var displayActualTokens: Double { actualTokens - estimatedCacheReadTokens }
        public var displayedUsageTokens: Double { usageTokens }
    }

    public struct ProviderRankRow: Identifiable, Sendable {
        public var id: String
        public var providerKey: String
        public var displayName: String
        public var actualTokens: Double
        public var netActualTokens: Double
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

    public enum ModelPricingStatus: String, Sendable {
        /// Price read verbatim from the catalog for this exact model id.
        case exact
        /// Price borrowed from a related key (build tag stripped, base model, prefix).
        case inherited
        /// Known free (catalog price is zero, or the id says free and no price exists).
        case free
        /// No price anywhere. Kept visible on purpose instead of being hidden or shown as $0.
        case unknown
    }

    public struct ModelComparisonRow: Identifiable, Sendable {
        public var id: String { "\(providerKey)|\(modelKey)" }

        public var modelKey: String
        public var displayName: String
        public var providerKey: String
        public var provider: String
        public var actualTokens: Double
        public var netActualTokens: Double
        public var allocatedCost: Double
        public var tokensPerDollar: Double
        public var colorKey: String
        public var pricingStatus: ModelPricingStatus
        /// The catalog key the price came from, when it differs from `modelKey`.
        public var priceReference: String?
        /// How many raw model ids (build tags, editions) were merged into this row.
        public var variantCount: Int
        /// Merged variants that carry no price at all.
        public var unpricedVariantCount: Int
        public var hasPrice: Bool
        public var isFree: Bool
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
        public var estimatedCacheReadTokens: Double

        public var displayActualTokens: Double { actualTokens - estimatedCacheReadTokens }
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
    public let cacheEstimationContext: OllamaCloudCacheEstimation.Context
    /// Provenance of the price directory used for model ranking.
    public let pricingMetadata: ModelPricingCatalog.Metadata

    private let rawRows: [DashboardPayload.RawRow]
    private let pricing: ModelPricingCatalog

    /// Canonical (variant-merged) key for a raw model id, using the same catalog
    /// that priced the dashboard. Charts must call this instead of grouping by
    /// the raw id, or `:1017`-style variants split into separate series.
    public func canonicalModelKey(provider: String, model: String) -> String {
        pricing.canonicalKey(provider: provider, model: model)
    }

    /// Rows whose merged family has no price at all, kept visible on purpose.
    public var unpricedModelCount: Int {
        modelComparisonRows.filter { !$0.hasPrice }.count
    }

    public init(
        payload: DashboardPayload,
        showZeroUsageXiaomiProvider: Bool = false,
        billingOverridesByProviderKey: [String: Double] = [:],
        pricing: ModelPricingCatalog = .bundledSnapshot
    ) {
        self.rawRows = payload.rawData
        self.pricingMetadata = pricing.metadata
        self.pricing = pricing
        let estimationContext = OllamaCloudCacheEstimation.Context(rows: payload.rawData)
        self.cacheEstimationContext = estimationContext


        var providerAccumulators: [String: ProviderAccumulator] = [:]
        var modelAccumulators: [String: ModelAccumulator] = [:]
        var modelComparisonAccumulators: [String: ModelAccumulator] = [:]
        var dailyActual: [String: Double] = [:]
        var dailyCacheRead: [String: Double] = [:]
        var dailyCacheWrite: [String: Double] = [:]
        var dailyEstimatedCacheRead: [String: Double] = [:]
        var dailyModelTotals: [String: [String: Double]] = [:]
        var dateKeys: Set<String> = []
        var totalTokensFromRows: Double = 0
        var totalActualTokens: Double = 0
        var totalInputTokens: Double = 0
        var totalMessages: Int = 0
        var totalCacheSavedCost: Double = 0

        for row in payload.rawData {
            let providerKey = Self.normalizeProviderKey(row.provider)
            let providerDisplayName = Self.displayProviderName(row.provider)
            // Grouping and pricing both come from the auto-discovered catalog:
            // build/edition variants merge onto one family, and the price is
            // scoped to the provider that produced the row.
            let resolution = pricing.resolve(provider: row.provider, model: row.model)
            let modelKey = resolution.canonicalKey
            let actualTokens = row.input + row.output + row.reasoning

            dateKeys.insert(row.date)
            totalTokensFromRows += row.total
            totalActualTokens += actualTokens
            totalInputTokens += row.input
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

            let rowCacheSavedCost = Self.cacheSavedCost(
                price: resolution.price,
                cacheRead: row.cacheRead
            )
            if rowCacheSavedCost.isFinite, rowCacheSavedCost > 0 {
                totalCacheSavedCost += rowCacheSavedCost
            }

            let split = OllamaCloudCacheEstimation.split(
                provider: row.provider,
                model: row.model,
                input: row.input,
                output: row.output,
                reasoning: row.reasoning,
                cacheRead: row.cacheRead,
                cacheWrite: row.cacheWrite,
                date: row.date,
                context: estimationContext
            )
            if split.estimatedCacheRead.isFinite, split.estimatedCacheRead > 0 {
                providerAccumulators[providerKey]?.estimatedCacheRead += split.estimatedCacheRead
                dailyEstimatedCacheRead[row.date, default: 0] += split.estimatedCacheRead
            }
            providerAccumulators[providerKey]?.netActualTokens += split.displayActual

            let apiCost = TokenCostPricingCatalog.apiCost(
                provider: row.provider,
                model: row.model,
                input: split.displayInput,
                output: row.output,
                reasoning: row.reasoning,
                cacheRead: row.cacheRead + split.estimatedCacheRead,
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

            let comparisonKey = "\(providerKey)|\(modelKey)"
            if modelComparisonAccumulators[comparisonKey] == nil {
                modelComparisonAccumulators[comparisonKey] = ModelAccumulator(
                    displayName: modelKey,
                    providerKey: providerKey,
                    primaryProvider: providerDisplayName
                )
            }
            let modelCost = resolution.price?.cost(
                input: split.displayInput,
                output: row.output,
                reasoning: row.reasoning,
                cacheRead: row.cacheRead + split.estimatedCacheRead,
                cacheWrite: row.cacheWrite
            ) ?? 0
            if modelCost.isFinite, modelCost > 0 {
                modelComparisonAccumulators[comparisonKey]?.allocatedCost += modelCost
            }
            modelComparisonAccumulators[comparisonKey]?.variants.insert(resolution.rawKey)
            if let price = resolution.price, !price.isFree {
                modelComparisonAccumulators[comparisonKey]?.pricedVariants.insert(resolution.rawKey)
            } else if resolution.isFree {
                modelComparisonAccumulators[comparisonKey]?.freeVariants.insert(resolution.rawKey)
            } else {
                modelComparisonAccumulators[comparisonKey]?.unknownVariants.insert(resolution.rawKey)
            }
            if resolution.isInherited, let matched = resolution.matchedKey {
                modelComparisonAccumulators[comparisonKey]?.inheritedKeys.insert(matched)
            }
            modelComparisonAccumulators[comparisonKey]?.total += row.total
            modelComparisonAccumulators[comparisonKey]?.actualTokens += actualTokens
            modelComparisonAccumulators[comparisonKey]?.netActualTokens += split.displayActual
            modelComparisonAccumulators[comparisonKey]?.cacheRead += row.cacheRead + split.estimatedCacheRead
            modelComparisonAccumulators[comparisonKey]?.cacheWrite += row.cacheWrite
            modelComparisonAccumulators[comparisonKey]?.messages += row.msgCount
        }

        let filteredProviderAccumulators = Self.filteredProviderAccumulators(
            from: providerAccumulators,
            showZeroUsageXiaomiProvider: showZeroUsageXiaomiProvider
        )
        let filteredModelAccumulators = Self.filteredModelAccumulators(from: modelAccumulators)
        let filteredModelComparisonAccumulators = Self.filteredModelAccumulators(from: modelComparisonAccumulators)
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
        let totalEstimatedCacheRead = dailyEstimatedCacheRead.values.reduce(0, +)
        let displayedCacheRead = cacheReadTokens + totalEstimatedCacheRead
        let totalCacheTokens = displayedCacheRead + cacheWriteTokens
        // Subtract the hidden cache split before adding displayed cache back.
        let cacheDenominator = totalInputTokens + cacheReadTokens
        let cacheHitRate = cacheDenominator > 0 ? displayedCacheRead / cacheDenominator : 0

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
            updatedAt: payload.summary.updatedAt,
            totalEstimatedCacheReadTokens: totalEstimatedCacheRead
        )

        self.cache = CacheSummary(
            cacheReadTokens: displayedCacheRead,
            cacheWriteTokens: cacheWriteTokens,
            totalCacheTokens: totalCacheTokens,
            cacheHitRate: cacheHitRate,
            cacheSavedCost: totalCacheSavedCost,
            estimatedCacheReadTokens: totalEstimatedCacheRead,
            hasEstimates: totalEstimatedCacheRead > 0
        )

        self.providerCacheRows = filteredProviderAccumulators
            .map { key, accumulator in
                let usageTokens = accumulator.actualTokens + accumulator.cacheRead + accumulator.cacheWrite
                let displayedCacheRead = accumulator.cacheRead + accumulator.estimatedCacheRead
                let cacheRate: Double
                if key == "ollama-cloud", accumulator.estimatedCacheRead > 0 {
                    let denom = accumulator.input + accumulator.cacheRead
                    cacheRate = denom > 0 ? displayedCacheRead / denom : 0
                } else {
                    let denom = accumulator.input + accumulator.cacheRead
                    cacheRate = denom > 0 ? accumulator.cacheRead / denom : 0
                }
                return ProviderCacheRow(
                    key: key,
                    displayName: accumulator.displayName,
                    usageTokens: usageTokens,
                    actualTokens: accumulator.actualTokens,
                    cacheReadTokens: displayedCacheRead,
                    cacheWriteTokens: accumulator.cacheWrite,
                    cacheWriteLabel: Self.cacheWriteLabel(
                        writeTokens: accumulator.cacheWrite,
                        missingCount: accumulator.cacheWriteMissingCount,
                        reportedCount: accumulator.cacheWriteReportedCount
                    ),
                    cacheRate: cacheRate,
                    colorKey: key,
                    inputTokens: accumulator.input,
                    estimatedCacheReadTokens: accumulator.estimatedCacheRead,
                    hasEstimates: accumulator.estimatedCacheRead > 0
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
            from: filteredModelComparisonAccumulators
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
            dailyCacheWrite: dailyCacheWrite,
            dailyEstimatedCacheRead: dailyEstimatedCacheRead
        )
        self.stackedSeries = Self.buildStackedSeries(
            sortedDateKeys: sortedDateKeys,
            dailyModelTotals: dailyModelTotals,
            modelAccumulators: filteredModelAccumulators
        )
    }

    /// Per-row deduction for the detail table, reusing the analytics-owned
    /// context so a row's displayed figure matches the aggregate figures above
    /// it. Returns `nil` when the row carries no deduction.
    public func displayDeduction(for row: DashboardPayload.RawRow) -> OllamaCloudCacheEstimation.Split? {
        guard row.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ollama-cloud",
              row.cacheRead == 0 else { return nil }
        let split = OllamaCloudCacheEstimation.split(
            provider: row.provider,
            model: row.model,
            input: row.input,
            output: row.output,
            reasoning: row.reasoning,
            cacheRead: row.cacheRead,
            cacheWrite: row.cacheWrite,
            date: row.date,
            context: cacheEstimationContext
        )
        return split.estimatedCacheRead > 0 ? split : nil
    }

    public func sortedDetailRows(
        sortField: TokenCostDetailSortField,
        direction: TokenCostSortDirection
    ) -> [DashboardPayload.RawRow] {        let rows = rawRows.sorted { lhs, rhs in
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
        let estimationContext = OllamaCloudCacheEstimation.Context(rows: payload.rawData)
        for row in payload.rawData {
            let key = Self.normalizeProviderKey(row.provider)
            var entry = result[key] ?? (0, 0)
            entry.raw += row.cost
            let split = OllamaCloudCacheEstimation.split(
                provider: row.provider,
                model: row.model,
                input: row.input,
                output: row.output,
                reasoning: row.reasoning,
                cacheRead: row.cacheRead,
                cacheWrite: row.cacheWrite,
                date: row.date,
                context: estimationContext
            )
            entry.synthetic += TokenCostPricingCatalog.apiCost(
                provider: row.provider,
                model: row.model,
                input: split.displayInput,
                output: row.output,
                reasoning: row.reasoning,
                cacheRead: row.cacheRead + split.estimatedCacheRead,
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
                    netActualTokens: accumulator.netActualTokens,
                    cacheReadTokens: accumulator.cacheRead + accumulator.estimatedCacheRead,
                    cacheWriteTokens: accumulator.cacheWrite,
                    messages: accumulator.messages,
                    rawCost: accumulator.rawCost,
                    effectiveCost: hasPricing ? effectiveCost : nil,
                    tokensPerDollar: hasPricing ? accumulator.netActualTokens / effectiveCost : 0,
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
                        netActualTokens: accumulator.netActualTokens,
                        cacheReadTokens: accumulator.cacheRead + accumulator.estimatedCacheRead,
                        cacheWriteTokens: accumulator.cacheWrite,
                        messages: accumulator.messages,
                        rawCost: accumulator.rawCost,
                        effectiveCost: apiCost > 0 ? apiCost : nil,
                        tokensPerDollar: apiCost > 0 ? accumulator.netActualTokens / apiCost : 0,
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
                if lhs.netActualTokens == rhs.netActualTokens {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
                return lhs.netActualTokens > rhs.netActualTokens
            }
            return lhs.tokensPerDollar > rhs.tokensPerDollar
        }
    }

    private static func buildModelComparisonRows(
        from modelAccumulators: [String: ModelAccumulator]
    ) -> [ModelComparisonRow] {
        modelAccumulators
            .filter { $0.value.total > 0 }
            .map { key, accumulator in
                let isFree = accumulator.pricedVariants.isEmpty
                    && !accumulator.freeVariants.isEmpty
                    && accumulator.unknownVariants.isEmpty
                let hasPrice = !accumulator.pricedVariants.isEmpty || isFree
                let status: ModelPricingStatus
                if isFree {
                    status = .free
                } else if hasPrice {
                    status = accumulator.inheritedKeys.isEmpty ? .exact : .inherited
                } else {
                    status = .unknown
                }
                let ratio: Double
                if hasPrice, accumulator.allocatedCost > 0 {
                    ratio = accumulator.netActualTokens / accumulator.allocatedCost
                } else {
                    ratio = 0
                }
                return ModelComparisonRow(
                    modelKey: accumulator.displayName,
                    displayName: accumulator.displayName,
                    providerKey: accumulator.providerKey ?? "unknown",
                    provider: accumulator.primaryProvider ?? AppLocalization.text("common.unspecified"),
                    actualTokens: accumulator.actualTokens,
                    netActualTokens: accumulator.netActualTokens,
                    allocatedCost: accumulator.allocatedCost,
                    tokensPerDollar: ratio,
                    colorKey: "\(accumulator.providerKey ?? "unknown")|\(accumulator.displayName)",
                    pricingStatus: status,
                    priceReference: accumulator.inheritedKeys.sorted().first,
                    variantCount: max(accumulator.variants.count, 1),
                    unpricedVariantCount: accumulator.unknownVariants.count,
                    hasPrice: hasPrice,
                    isFree: isFree
                )
            }
            .sorted { lhs, rhs in
                let lhsBucket = pricingSortBucket(lhs)
                let rhsBucket = pricingSortBucket(rhs)
                if lhsBucket != rhsBucket {
                    return lhsBucket < rhsBucket
                }
                switch lhsBucket {
                case 0: // free models are the best value; order them by volume
                    if lhs.netActualTokens != rhs.netActualTokens {
                        return lhs.netActualTokens > rhs.netActualTokens
                    }
                case 1: // priced: tokens per dollar, descending
                    if lhs.tokensPerDollar != rhs.tokensPerDollar {
                        return lhs.tokensPerDollar > rhs.tokensPerDollar
                    }
                default: // unpriced stay visible, ordered by volume
                    if lhs.netActualTokens != rhs.netActualTokens {
                        return lhs.netActualTokens > rhs.netActualTokens
                    }
                }
                if lhs.displayName == rhs.displayName {
                    return lhs.provider.localizedCaseInsensitiveCompare(rhs.provider) == .orderedAscending
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    /// 0 = free, 1 = priced, 2 = unpriced. Unpriced rows are never dropped: they
    /// sort last but still appear in the list and in the relay payload.
    private static func pricingSortBucket(_ row: ModelComparisonRow) -> Int {
        if row.isFree { return 0 }
        return row.hasPrice ? 1 : 2
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
        dailyCacheWrite: [String: Double],
        dailyEstimatedCacheRead: [String: Double]
    ) -> [TrendPoint] {
        sortedDateKeys.compactMap { key in
            guard let date = Self.chartDateFormatter.date(from: key) else {
                return nil
            }
            let estimated = dailyEstimatedCacheRead[key] ?? 0
            let realCacheRead = dailyCacheRead[key] ?? 0
            return TrendPoint(
                date: date,
                dateString: key,
                actualTokens: dailyActual[key] ?? 0,
                cacheReadTokens: realCacheRead + estimated,
                cacheWriteTokens: dailyCacheWrite[key] ?? 0,
                estimatedCacheReadTokens: estimated
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

    /// Cache-read savings at the resolved price. Zero when the model is unpriced
    /// or the cached rate is not cheaper than fresh input.
    private static func cacheSavedCost(price: ModelPrice?, cacheRead: Double) -> Double {
        guard let price,
              price.input > price.cacheRead,
              cacheRead.isFinite, cacheRead > 0 else {
            return 0
        }
        return cacheRead * (price.input - price.cacheRead) / 1_000_000
    }

    private static func shouldIncludeZeroUsageXiaomiProvider(_ providerKey: String) -> Bool {
        providerKey.localizedCaseInsensitiveContains("xiaomi")
    }

    private static let chartDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private struct ProviderAccumulator {
        var displayName: String
        var input: Double = 0
        var output: Double = 0
        var cacheRead: Double = 0
        var cacheWrite: Double = 0
        var estimatedCacheRead: Double = 0
        var cacheWriteMissingCount: Int = 0
        var cacheWriteReportedCount: Int = 0
        var total: Double = 0
        var actualTokens: Double = 0
        var netActualTokens: Double = 0
        var rawCost: Double = 0
        var messages: Int = 0
        var models: Set<String> = []
        var rows: [DashboardPayload.RawRow] = []
        var syntheticApiCost: Double = 0
    }

    private struct ModelAccumulator {
        var displayName: String
        var providerKey: String?
        var total: Double = 0
        var actualTokens: Double = 0
        var netActualTokens: Double = 0
        var cacheRead: Double = 0
        var cacheWrite: Double = 0
        var messages: Int = 0
        var allocatedCost: Double = 0
        var primaryProvider: String?
        var variants: Set<String> = []
        var pricedVariants: Set<String> = []
        var freeVariants: Set<String> = []
        var unknownVariants: Set<String> = []
        var inheritedKeys: Set<String> = []
    }
}

enum TokenCostPricingCatalog {
    /// Legacy fallback subscription costs — used ONLY when billingOverridesByProviderKey
    /// does not provide a value for a given provider key. User billing plan selections
    /// (via AppPreferences.billingOverridesByProviderKey()) always take precedence.
    // MARK: — Ollama Cloud DeepSeek V4 cache-read estimation
    //
    // ⚠️ Snapshot data from 2026-07 observation period. These rates are
    // compile-time constants and will silently drift from reality as Ollama
    // Cloud's cache infrastructure evolves. Re-snapshot quarterly or when
    // Ollama Cloud reports significant infra changes. See
    // docs/Token统计口径定义.md §4.2 for update procedure.

    /// Fallback snapshot rates, observed Jul 2026.
    /// rate = snapshot cacheRead / snapshot gross input (denominator includes cache).
    /// Used to estimate missing cache reads when provider reports input>0 but cacheRead==0.
    private static let ollamaDeepSeekCacheReadSnapshotRates: [String: Double] = [
        "deepseek-v4-flash": 553_686_784.0 / 600_792_157.0,
        "deepseek-v4-pro": 1_476_491_904.0 / 1_550_614_127.0
    ]

    static func ollamaCacheReadRate(for model: String) -> Double {
        guard let rate = ollamaDeepSeekCacheReadSnapshotRates[model],
              rate.isFinite, rate > 0, rate < 1 else { return 0 }
        return rate
    }

    /// Returns the estimated cache-read multiplier for an Ollama Cloud DeepSeek model.
    /// multiplier = rate / (1 − rate) = snapshot_cacheRead / snapshot_input.
    /// Returns 0 when rate is not finite, not in (0,1), or model unknown.
    /// — Only valid for normalized model names "deepseek-v4-flash" & "deepseek-v4-pro".
    static func ollamaCacheReadEstimationMultiplier(for model: String) -> Double {
        guard let rate = ollamaDeepSeekCacheReadSnapshotRates[model],
              rate.isFinite, rate > 0, rate < 1 else {
            return 0
        }
        return rate / (1 - rate)
    }

    /// Returns the estimated cost saved by serving `cacheRead` tokens from cache
    /// instead of computing them as input tokens, using the model's marginal price difference.
    /// Formula: cacheRead × (inputPrice − cacheReadPrice) / 1 000 000.
    /// Returns 0 when either price is missing or inputPrice ≤ cacheReadPrice.
    static func cacheSavedCost(provider: String, model: String, cacheRead: Double) -> Double {
        let key = normalizeModelName(model)
        guard let pricing = pricing(for: provider, modelKey: key),
              let inputPrice = pricing["input"],
              let cacheReadPrice = pricing["cacheRead"],
              inputPrice > cacheReadPrice,
              cacheRead.isFinite, cacheRead > 0 else {
            return 0
        }
        return cacheRead * (inputPrice - cacheReadPrice) / 1_000_000
    }

    // MARK: — Legacy subscription costs

    static let legacyFallbackMonthlyCosts: [String: Double] = [
        "minimax-cn-coding-plan": TokenCostCurrencyService.convert(98, from: .cny, to: .usd),
        "xiaomi-token-plan-cn": TokenCostCurrencyService.convert(34.9, from: .cny, to: .usd),
        "openai": 20.00
    ]

    static let modelAliases: [String: String] = [
        "minimax-m2.7-highspeed": "minimax-m2.7",
        "deepseek-chat": "deepseek-v4-flash",
        "deepseek-reasoner": "deepseek-v4-pro"
    ]

    /// Base model keys used for automatic variant categorization, sorted by length (longest first).
    /// A model variant (e.g. "deepseek-v4-flash-0731-cloud") that starts with one of these keys is
    /// collapsed to the base key so it is grouped and priced as that model instead of falling into
    /// the "other" bucket.
    private static var knownBaseModelKeys: [String] {
        var keys = Set(zenPricing.keys)
        for alias in modelAliases.values {
            keys.insert(alias)
        }
        return keys.sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs < rhs
            }
            return lhs.count > rhs.count
        }
    }

    /// Best-prefix match against known base model keys. Returns the longest known base key that is a
    /// strict prefix of `normalized`, or nil when no known key prefixes it or the string is itself a
    /// known base key (exact known models are never reduced to a shorter key).
    private static func categorizableBaseModelKey(for normalized: String) -> String? {
        guard !knownBaseModelKeys.contains(normalized) else {
            return nil
        }
        for baseKey in knownBaseModelKeys where normalized.count > baseKey.count && normalized.hasPrefix(baseKey) {
            return baseKey
        }
        return nil
    }

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
        "deepseek-v4-pro": ["input": 0.435, "output": 0.87, "cacheRead": 0.003625],  // OpenCode Zen snapshot
        "deepseek-v4-flash": ["input": 0.14, "output": 0.28, "cacheRead": 0.0028],
        "big-pickle": ["input": 0, "output": 0, "cacheRead": 0],
        "mimo-v2-omni": ["input": 0.30, "output": 1.20, "cacheRead": 0.06, "cacheWrite": 0.375],
        "mimo-v2-pro": ["input": 0.30, "output": 1.20, "cacheRead": 0.06, "cacheWrite": 0.375],
        "mimo-v2.5": ["input": 0.30, "output": 1.20, "cacheRead": 0.06, "cacheWrite": 0.375],
        "mimo-v2.5-pro": ["input": 0.30, "output": 1.20, "cacheRead": 0.06, "cacheWrite": 0.375]
    ]

    /// Historical static approximation retained for direct DeepSeek rows.
    /// The source data is aggregated by day, so it cannot reproduce time-of-day
    /// peak/off-peak billing. Do not present this table as real-time official pricing.
    private static let deepSeekLegacyPricing: [String: [String: Double]] = [
        "deepseek-v4-pro": ["input": 0.435, "output": 0.87, "cacheRead": 0.003625],
        "deepseek-v4-flash": ["input": 0.14, "output": 0.28, "cacheRead": 0.0028]
    ]

    /// Provider-scoped view of the legacy snapshot, used as the bundled fallback
    /// for `ModelPricingCatalog` so existing figures stay reproducible offline.
    static var bundledProviderTables: [String: [String: ModelPrice]] {
        var tables: [String: [String: ModelPrice]] = [:]
        for provider in ["opencode", "opencode-go", "ollama-cloud"] {
            tables[provider] = zenPricing.mapValues(ModelPrice.init(legacy:))
        }
        for provider in ["deepseek", "deepseek-api-cn"] {
            tables[provider] = deepSeekLegacyPricing.mapValues(ModelPrice.init(legacy:))
        }
        return tables
    }

    private static func pricing(for provider: String, modelKey: String) -> [String: Double]? {
        let providerKey = provider.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch providerKey {
        case "deepseek", "deepseek-api-cn":
            return deepSeekLegacyPricing[modelKey]
        case "opencode", "opencode-go", "ollama-cloud":
            return zenPricing[modelKey]
        default:
            return nil
        }
    }

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

        if let alias = modelAliases[normalized] {
            return alias
        }

        if let baseKey = categorizableBaseModelKey(for: normalized) {
            return baseKey
        }

        return normalized
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

    static func apiCost(provider: String, model: String, input: Double, output: Double, reasoning: Double, cacheRead: Double, cacheWrite: Double) -> Double {
        let key = normalizeModelName(model)
        guard let pricing = pricing(for: provider, modelKey: key) else {
            return 0
        }
        func validTokens(_ value: Double) -> Double {
            value.isFinite && value > 0 ? value : 0
        }
        let inputCost = (validTokens(input) / 1_000_000) * (pricing["input"] ?? 0)
        let outputCost = (validTokens(output) / 1_000_000) * (pricing["output"] ?? 0)
        let reasoningCost = (validTokens(reasoning) / 1_000_000) * (pricing["reasoning"] ?? pricing["output"] ?? 0)
        let cacheReadCost = (validTokens(cacheRead) / 1_000_000) * (pricing["cacheRead"] ?? 0)
        let cacheWriteCost = (validTokens(cacheWrite) / 1_000_000) * (pricing["cacheWrite"] ?? 0)
        return inputCost + outputCost + reasoningCost + cacheReadCost + cacheWriteCost
    }
}
