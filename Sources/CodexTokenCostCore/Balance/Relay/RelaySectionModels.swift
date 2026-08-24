import Foundation

public protocol RelayAnalyticsProviding: Sendable {
    func currentAnalytics() async -> TokenCostDashboardAnalytics?
}

public struct RelayOverviewSection: Codable, Equatable, Sendable {
    public let totalTokens: Double
    public let totalActualTokens: Double
    public let totalCostUSD: Double
    public let dailyAverageTokens: Double
    public let monthlyEstimateTokens: Double
    public let activeDays: Int
}

public struct RelayCacheSection: Codable, Equatable, Sendable {
    public let cacheReadTokens: Double
    public let cacheWriteTokens: Double
    public let hitRate: Double
    public let savedCostUSD: Double
    public let estimatedCacheReadTokens: Double
    public let hasEstimates: Bool
}

public struct RelayProviderMetric: Codable, Equatable, Sendable {
    public let provider: String
    public let tokens: Double
    public let costUSD: Double?
}

public struct RelayModelMetric: Codable, Equatable, Sendable {
    public let model: String
    public let provider: String
    public let tokens: Double
    public let costUSD: Double?
}

public struct RelayCostSection: Codable, Equatable, Sendable {
    public let providers: [RelayProviderMetric]
    public let models: [RelayModelMetric]
}

public struct RelayUsageSection: Codable, Equatable, Sendable {
    public let providers: [RelayProviderMetric]
    public let models: [RelayModelMetric]
}

public struct RelayDistributionItem: Codable, Equatable, Sendable {
    public let label: String
    public let tokens: Double
    public let percentage: Double
    public let isOther: Bool
}

public struct RelayModelDistributionSection: Codable, Equatable, Sendable {
    public let models: [RelayDistributionItem]
    public let providers: [RelayDistributionItem]
}

public struct RelayTrendPoint: Codable, Equatable, Sendable {
    public let date: String
    public let actualTokens: Double
    public let cacheReadTokens: Double
    public let cacheWriteTokens: Double
    public let estimatedCacheReadTokens: Double
}

public struct RelayTrendSection: Codable, Equatable, Sendable {
    public let timeZoneIdentifier: String
    public let days: Int
    public let points: [RelayTrendPoint]
}

public struct RelayHeatmapDay: Codable, Equatable, Sendable {
    public let date: String
    public let tokens: Double
}

public struct RelayHeatmapSection: Codable, Equatable, Sendable {
    public let timeZoneIdentifier: String
    public let weeks: Int
    public let days: [RelayHeatmapDay]
}

public enum RelaySectionBuildError: Error, Equatable {
    case invalidNumber
    case sectionTooLarge
}
