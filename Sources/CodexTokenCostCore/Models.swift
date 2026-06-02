import Foundation

public enum TokenCostSourceStatus: String, Codable, CaseIterable, Sendable {
    case available
    case missing
    case unsupported
    case locked
    case unknown
}

public enum TokenCostSourceKind: String, Codable, CaseIterable, Sendable {
    case automatic
    case manualFile
    case manualDirectory
}

public struct TokenCostSource: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var sourceFamily: TokenCostSourceFamily
    public var locationKind: TokenCostSourceLocationKind
    public var sourceURL: URL
    public var locationURL: URL?
    public var status: TokenCostSourceStatus
    public var statusMessageKind: TokenCostSourceStatusMessageKind
    public var lastModified: String?
    public var isReadOnly: Bool

    public var statusMessage: String {
        statusMessageKind.displayName
    }

    public var displayPath: String {
        sourceURL.path
    }

    public var isAvailable: Bool {
        status == .available
    }

    public var kind: TokenCostSourceKind {
        switch sourceFamily {
        case .opencode:
            if locationKind == .directory {
                return .automatic
            }
            return .manualFile
        case .codex:
            if locationKind == .directory {
                return .manualDirectory
            }
            return .manualFile
        }
    }

    public var databaseURL: URL {
        sourceURL
    }

    public var originURL: URL? {
        locationURL
    }

    public init(
        id: String,
        name: String,
        sourceFamily: TokenCostSourceFamily,
        locationKind: TokenCostSourceLocationKind,
        sourceURL: URL,
        locationURL: URL? = nil,
        status: TokenCostSourceStatus,
        statusMessageKind: TokenCostSourceStatusMessageKind,
        lastModified: String? = nil,
        isReadOnly: Bool
    ) {
        self.id = id
        self.name = name
        self.sourceFamily = sourceFamily
        self.locationKind = locationKind
        self.sourceURL = sourceURL
        self.locationURL = locationURL
        self.status = status
        self.statusMessageKind = statusMessageKind
        self.lastModified = lastModified
        self.isReadOnly = isReadOnly
    }
}

public enum TokenCostSourceStatusMessageKind: String, Codable, CaseIterable, Sendable {
    case available
    case missingDefaultLocation
    case missingDirectoryFiles
    case missingPath
    case unsupportedSchema
    case lockedFile
    case unknown
    case fileReadable
    case fileFormatMismatch
    case fileUnreadable
    case noReadableSource

    public var displayName: String {
        switch self {
        case .available:
            return AppLocalization.text("source.status.available")
        case .missingDefaultLocation:
            return AppLocalization.text("source.status.missingDefaultLocation")
        case .missingDirectoryFiles:
            return AppLocalization.text("source.status.missingDirectoryFiles")
        case .missingPath:
            return AppLocalization.text("source.status.missingPath")
        case .unsupportedSchema:
            return AppLocalization.text("source.status.unsupportedSchema")
        case .lockedFile:
            return AppLocalization.text("source.status.lockedFile")
        case .unknown:
            return AppLocalization.text("source.status.unknown")
        case .fileReadable:
            return AppLocalization.text("source.status.fileReadable")
        case .fileFormatMismatch:
            return AppLocalization.text("source.status.fileFormatMismatch")
        case .fileUnreadable:
            return AppLocalization.text("source.status.fileUnreadable")
        case .noReadableSource:
            return AppLocalization.text("source.status.noReadableSource")
        }
    }
}

public struct TokenCostSettings: Codable, Equatable, Sendable {
    public var sourceFamily: TokenCostSourceFamily
    public var sourceRoots: [String]
    public var manualSourcePaths: [String]
    public var selectedSourceID: String?
    public var autoRescan: Bool
    public var maxScanDepth: Int
    public var maxScanCandidates: Int
    public var snapshotRetentionCount: Int
    public var theme: TokenCostThemeChoice
    public var showZeroUsageXiaomiProvider: Bool

    public init(
        sourceFamily: TokenCostSourceFamily = .opencode,
        sourceRoots: [String]? = nil,
        manualSourcePaths: [String]? = nil,
        selectedSourceID: String? = nil,
        autoRescan: Bool = true,
        maxScanDepth: Int? = nil,
        maxScanCandidates: Int? = nil,
        snapshotRetentionCount: Int = 4,
        theme: TokenCostThemeChoice = .ocean,
        showZeroUsageXiaomiProvider: Bool = false
    ) {
        let profile = TokenCostSourceProfile.profile(for: sourceFamily)
        self.sourceFamily = sourceFamily
        self.sourceRoots = sourceRoots ?? profile.defaultSourceRoots
        self.manualSourcePaths = manualSourcePaths ?? profile.defaultManualSourcePaths
        self.selectedSourceID = selectedSourceID
        self.autoRescan = autoRescan
        self.maxScanDepth = maxScanDepth ?? profile.maxScanDepth
        self.maxScanCandidates = maxScanCandidates ?? profile.maxScanCandidates
        self.snapshotRetentionCount = snapshotRetentionCount
        self.theme = theme
        self.showZeroUsageXiaomiProvider = showZeroUsageXiaomiProvider
    }

    private enum CodingKeys: String, CodingKey {
        case sourceFamily
        case sourceRoots
        case manualSourcePaths
        case scanRoots
        case manualDatabasePaths
        case selectedSourceID = "selectedSourceId"
        case autoRescan
        case maxScanDepth
        case maxScanCandidates
        case snapshotRetentionCount
        case theme
        case showZeroUsageXiaomiProvider
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedFamily = try container.decodeIfPresent(TokenCostSourceFamily.self, forKey: .sourceFamily) ?? .opencode
        let profile = TokenCostSourceProfile.profile(for: decodedFamily)
        self.sourceFamily = decodedFamily
        let decodedSourceRoots = try container.decodeIfPresent([String].self, forKey: .sourceRoots)
        let legacySourceRoots = try container.decodeIfPresent([String].self, forKey: .scanRoots)
        self.sourceRoots = decodedSourceRoots ?? legacySourceRoots ?? profile.defaultSourceRoots

        let decodedManualSourcePaths = try container.decodeIfPresent([String].self, forKey: .manualSourcePaths)
        let legacyManualSourcePaths = try container.decodeIfPresent([String].self, forKey: .manualDatabasePaths)
        self.manualSourcePaths = decodedManualSourcePaths ?? legacyManualSourcePaths ?? profile.defaultManualSourcePaths
        self.selectedSourceID = try container.decodeIfPresent(String.self, forKey: .selectedSourceID)
        self.autoRescan = try container.decodeIfPresent(Bool.self, forKey: .autoRescan) ?? true
        self.maxScanDepth = try container.decodeIfPresent(Int.self, forKey: .maxScanDepth) ?? profile.maxScanDepth
        self.maxScanCandidates = try container.decodeIfPresent(Int.self, forKey: .maxScanCandidates) ?? profile.maxScanCandidates
        self.snapshotRetentionCount = try container.decodeIfPresent(Int.self, forKey: .snapshotRetentionCount) ?? 4
        self.theme = try container.decodeIfPresent(TokenCostThemeChoice.self, forKey: .theme) ?? .ocean
        self.showZeroUsageXiaomiProvider = try container.decodeIfPresent(Bool.self, forKey: .showZeroUsageXiaomiProvider) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceFamily, forKey: .sourceFamily)
        try container.encode(sourceRoots, forKey: .sourceRoots)
        try container.encode(sourceRoots, forKey: .scanRoots)
        try container.encode(manualSourcePaths, forKey: .manualSourcePaths)
        try container.encode(manualSourcePaths, forKey: .manualDatabasePaths)
        try container.encodeIfPresent(selectedSourceID, forKey: .selectedSourceID)
        try container.encode(autoRescan, forKey: .autoRescan)
        try container.encode(maxScanDepth, forKey: .maxScanDepth)
        try container.encode(maxScanCandidates, forKey: .maxScanCandidates)
        try container.encode(snapshotRetentionCount, forKey: .snapshotRetentionCount)
        try container.encode(theme, forKey: .theme)
        try container.encode(showZeroUsageXiaomiProvider, forKey: .showZeroUsageXiaomiProvider)
    }

    public var profile: TokenCostSourceProfile {
        TokenCostSourceProfile.profile(for: sourceFamily)
    }

    public var effectiveSourceRoots: [String] {
        Self.uniqueCanonicalPaths(from: sourceRoots + profile.defaultSourceRoots)
    }

    public var effectiveManualSourcePaths: [String] {
        Self.uniqueCanonicalPaths(from: manualSourcePaths + profile.defaultManualSourcePaths)
    }

    public var effectiveSourceLocations: [String] {
        effectiveSourceRoots + effectiveManualSourcePaths
    }

    public var scanRoots: [String] {
        get { sourceRoots }
        set { sourceRoots = newValue }
    }

    public var manualDatabasePaths: [String] {
        get { manualSourcePaths }
        set { manualSourcePaths = newValue }
    }

    public var sourceLocationsDescription: String {
        let roots = effectiveSourceRoots.isEmpty ? profile.sourceRootsLabel : effectiveSourceRoots.joined(separator: " · ")
        if effectiveManualSourcePaths.isEmpty {
            return roots
        }
        return roots + " · " + effectiveManualSourcePaths.joined(separator: " · ")
    }

    public static func opencodeDefaults() -> TokenCostSettings {
        TokenCostSettings(sourceFamily: .opencode)
    }

    public static func codexDefaults() -> TokenCostSettings {
        TokenCostSettings(sourceFamily: .codex)
    }

    private static func uniqueCanonicalPaths(from paths: [String]) -> [String] {
        var seen = Set<String>()
        var results: [String] = []

        for path in paths {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            let canonical = TokenCostPathUtilities.canonicalPathString(from: trimmed)
            guard seen.insert(canonical).inserted else {
                continue
            }
            results.append(canonical)
        }

        return results
    }
}

public struct UsageAggregateRow: Codable, Hashable, Sendable {
    public var date: String
    public var model: String
    public var provider: String
    public var input: Double
    public var output: Double
    public var reasoning: Double
    public var cacheRead: Double
    public var cacheWrite: Double
    public var cacheWriteMissingCount: Int
    public var cacheWriteReportedCount: Int
    public var total: Double
    public var cost: Double
    public var msgCount: Int
}

public struct DashboardPayload: Codable, Hashable, Sendable {
    public struct DateRange: Codable, Hashable, Sendable {
        public var start: String?
        public var end: String?
    }

    public struct Summary: Codable, Hashable, Sendable {
        public var totalTokens: Double
        public var totalActualTokens: Double
        public var totalCacheReadTokens: Double
        public var totalCacheWriteTokens: Double
        public var totalCacheTokens: Double
        public var totalCost: Double
        public var totalMessages: Int
        public var activeDays: Int
        public var dateRange: DateRange
        public var updatedAt: String
    }

    public struct ProviderTotals: Codable, Hashable, Sendable {
        public var input: Double
        public var output: Double
        public var cacheRead: Double
        public var cacheWrite: Double
        public var cacheWriteMissingCount: Int
        public var cacheWriteReportedCount: Int
        public var total: Double
        public var actualTokens: Double
        public var cost: Double
        public var messages: Int
    }

    public struct RawRow: Codable, Hashable, Identifiable, Sendable {
        public var id: String {
            "\(date)|\(model)|\(provider)"
        }

        public var date: String
        public var model: String
        public var provider: String
        public var input: Double
        public var output: Double
        public var reasoning: Double
        public var cacheRead: Double
        public var cacheWrite: Double
        public var cacheWriteMissingCount: Int
        public var cacheWriteReportedCount: Int
        public var total: Double
        public var cost: Double
        public var msgCount: Int
    }

    public var summary: Summary
    public var dailyTotals: [String: Double]
    public var modelTotals: [String: Double]
    public var providerCosts: [String: Double]
    public var providerTotals: [String: ProviderTotals]
    public var rawData: [RawRow]

    public var totalInputTokens: Double {
        rawData.reduce(0) { acc, row in acc + row.input }
    }

    /// OpenCode SQLite 中 `$.tokens.input` 已是非缓存值，不需要额外减去 cacheRead 或 cacheWrite。
    /// 该属性直接求和各行的 `input` 即可。
    public var totalActualInputTokens: Double {
        rawData.reduce(0) { acc, row in acc + row.input }
    }

    public static func empty() -> DashboardPayload {
        DashboardPayload(
            summary: Summary(
                totalTokens: 0,
                totalActualTokens: 0,
                totalCacheReadTokens: 0,
                totalCacheWriteTokens: 0,
                totalCacheTokens: 0,
                totalCost: 0,
                totalMessages: 0,
                activeDays: 0,
                dateRange: DateRange(start: nil, end: nil),
                updatedAt: ISO8601DateFormatter().string(from: Date())
            ),
            dailyTotals: [:],
            modelTotals: [:],
            providerCosts: [:],
            providerTotals: [:],
            rawData: []
        )
    }
}
