import Foundation

public struct DeveloperModePreferences: Codable, Equatable, Sendable {
    public var isEnabled: Bool = false
    public var localGovernanceEnabled: Bool = false
    public var aiAnalysisEnabled: Bool = false  // Phase 4 前始终 false

    public init(
        isEnabled: Bool = false,
        localGovernanceEnabled: Bool = false,
        aiAnalysisEnabled: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.localGovernanceEnabled = localGovernanceEnabled
        self.aiAnalysisEnabled = aiAnalysisEnabled
    }
}
