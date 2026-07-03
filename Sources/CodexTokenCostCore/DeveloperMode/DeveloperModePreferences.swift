import Foundation

public struct DeveloperModePreferences: Codable, Equatable, Sendable {
    public var isEnabled: Bool = false
    public var localGovernanceEnabled: Bool = false
    public var aiAnalysisEnabled: Bool = false  // Phase 4 前始终 false
    public var ollamaUsageTrackingEnabled: Bool = false

    public init(
        isEnabled: Bool = false,
        localGovernanceEnabled: Bool = false,
        aiAnalysisEnabled: Bool = false,
        ollamaUsageTrackingEnabled: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.localGovernanceEnabled = localGovernanceEnabled
        self.aiAnalysisEnabled = aiAnalysisEnabled
        self.ollamaUsageTrackingEnabled = ollamaUsageTrackingEnabled
    }

    // MARK: - Custom Codable (backward compat: missing new field → false)

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case localGovernanceEnabled
        case aiAnalysisEnabled
        case ollamaUsageTrackingEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        self.localGovernanceEnabled = try container.decodeIfPresent(Bool.self, forKey: .localGovernanceEnabled) ?? false
        self.aiAnalysisEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiAnalysisEnabled) ?? false
        self.ollamaUsageTrackingEnabled = try container.decodeIfPresent(Bool.self, forKey: .ollamaUsageTrackingEnabled) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(localGovernanceEnabled, forKey: .localGovernanceEnabled)
        try container.encode(aiAnalysisEnabled, forKey: .aiAnalysisEnabled)
        try container.encode(ollamaUsageTrackingEnabled, forKey: .ollamaUsageTrackingEnabled)
    }
}