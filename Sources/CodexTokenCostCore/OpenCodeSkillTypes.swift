import Foundation

public typealias OpenCodeSkillManifestState = ValidationState

public enum OpenCodeSkillDiagnosticSeverity: String, Codable, Sendable {
    case info
    case warning
    case error
}

public struct OpenCodeDesktopSkillLockEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let source: String?
    public let sourceType: String?
    public let pluginName: String?
    public let updatedAt: Date?

    public init(name: String, source: String? = nil, sourceType: String? = nil, pluginName: String? = nil, updatedAt: Date? = nil) {
        self.name = name
        self.source = source
        self.sourceType = sourceType
        self.pluginName = pluginName
        self.updatedAt = updatedAt
    }
}

public struct OpenCodeDesktopSkillLockSignal: Codable, Sendable {
    public let detected: Bool
    public let parseError: String?
    public let version: Int?
    public let entries: [OpenCodeDesktopSkillLockEntry]

    public init(detected: Bool = false, parseError: String? = nil, version: Int? = nil, entries: [OpenCodeDesktopSkillLockEntry] = []) {
        self.detected = detected
        self.parseError = parseError
        self.version = version
        self.entries = entries
    }
}

public struct OpenCodeOhMyAgentOverride: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let disabled: Bool
    public let model: String?
    public let skillNames: [String]

    public init(name: String, disabled: Bool = false, model: String? = nil, skillNames: [String] = []) {
        self.name = name
        self.disabled = disabled
        self.model = model
        self.skillNames = skillNames
    }
}

public struct OpenCodeOhMyCategoryOverride: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct OpenCodeOhMyAgentSignal: Codable, Sendable {
    public let detected: Bool
    public let parseError: String?
    public let agentOverrides: [OpenCodeOhMyAgentOverride]
    public let categoryOverrides: [OpenCodeOhMyCategoryOverride]

    public init(detected: Bool = false, parseError: String? = nil, agentOverrides: [OpenCodeOhMyAgentOverride] = [], categoryOverrides: [OpenCodeOhMyCategoryOverride] = []) {
        self.detected = detected
        self.parseError = parseError
        self.agentOverrides = agentOverrides
        self.categoryOverrides = categoryOverrides
    }
}

public struct OpenCodeSkillDiagnosticEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let severity: OpenCodeSkillDiagnosticSeverity
    public let title: String
    public let message: String
    public let impact: String
    public let recommendation: String

    public init(id: String, severity: OpenCodeSkillDiagnosticSeverity, title: String, message: String, impact: String, recommendation: String) {
        self.id = id
        self.severity = severity
        self.title = title
        self.message = message
        self.impact = impact
        self.recommendation = recommendation
    }
}

public struct OpenCodeSkillBackupFileEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let fileName: String
    public let parseStatus: String
    public let modifiedAt: Date?
    public let targetName: String
    public let diffSummary: String
    public let changedKeySamples: [String]

    public init(id: String, fileName: String, parseStatus: String, modifiedAt: Date? = nil, targetName: String, diffSummary: String, changedKeySamples: [String] = []) {
        self.id = id
        self.fileName = fileName
        self.parseStatus = parseStatus
        self.modifiedAt = modifiedAt
        self.targetName = targetName
        self.diffSummary = diffSummary
        self.changedKeySamples = changedKeySamples
    }
}
