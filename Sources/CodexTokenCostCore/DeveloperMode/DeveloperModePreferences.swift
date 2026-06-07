import Foundation

public struct DeveloperModePreferences: Codable, Equatable, Sendable {
    public var isEnabled: Bool = false
    public var taskClassificationEnabled: Bool = false
    public var optimizeEnabled: Bool = false
    public var localGovernanceEnabled: Bool = false
    public var multiCurrencyEnabled: Bool = false
    public var modelCompareEnabled: Bool = false
    public var aiAnalysisEnabled: Bool = false  // Phase 4 前始终 false

    public init(
        isEnabled: Bool = false,
        taskClassificationEnabled: Bool = false,
        optimizeEnabled: Bool = false,
        localGovernanceEnabled: Bool = false,
        multiCurrencyEnabled: Bool = false,
        modelCompareEnabled: Bool = false,
        aiAnalysisEnabled: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.taskClassificationEnabled = taskClassificationEnabled
        self.optimizeEnabled = optimizeEnabled
        self.localGovernanceEnabled = localGovernanceEnabled
        self.multiCurrencyEnabled = multiCurrencyEnabled
        self.modelCompareEnabled = modelCompareEnabled
        self.aiAnalysisEnabled = aiAnalysisEnabled
    }
}
