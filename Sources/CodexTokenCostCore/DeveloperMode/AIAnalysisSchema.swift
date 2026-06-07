import Foundation

/// Schema for AI analysis findings. Feature is disabled in v1 — this defines the data contract only.
public struct AIFinding: Codable, Identifiable, Sendable {
    public let id: String
    public let category: Category
    public let severity: Severity
    public let title: String
    public let detail: String
    public let suggestion: String
    public let confidence: Double
    public let metadata: [String: String]
    
    public enum Category: String, Codable, Sendable {
        case tokenEfficiency = "token_efficiency"
        case costOptimization = "cost_optimization"
        case usagePattern = "usage_pattern"
        case providerComparison = "provider_comparison"
    }
    
    public enum Severity: String, Codable, Sendable {
        case info = "info"
        case warning = "warning"
        case critical = "critical"
    }
    
    public init(
        id: String = UUID().uuidString,
        category: Category,
        severity: Severity,
        title: String,
        detail: String,
        suggestion: String,
        confidence: Double,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.category = category
        self.severity = severity
        self.title = title
        self.detail = detail
        self.suggestion = suggestion
        self.confidence = confidence
        self.metadata = metadata
    }
}

/// Defines what data would be sent to an AI endpoint (if enabled).
/// Currently a no-op — the feature is disabled in v1.
public struct AIFindingRequest: Codable, Sendable {
    public let findings: [AIFinding]
    public let anonymizedContext: [String: String]
    public let consentToken: String
    
    public init(findings: [AIFinding], anonymizedContext: [String: String], consentToken: String) {
        self.findings = findings
        self.anonymizedContext = anonymizedContext
        self.consentToken = consentToken
    }
}

/// Placeholder for future endpoint configuration.
/// Currently returns nil — feature is disabled in v1.
public enum AIAnalysisEndpoint: Sendable {
    /// Returns nil in v1. Will return actual endpoint URL when feature is enabled.
    public static var url: URL? { nil }
    
    /// Allowed domains for future AI analysis requests.
    /// Only these domains will be permitted when the feature is enabled.
    public static let allowedDomains: [String] = []
    
    /// Maximum findings per request.
    public static let maxFindingsPerRequest: Int = 100
    
    /// Required consent level.
    public static let requiredConsentLevel: ConsentLevel = .explicitOptIn
    
    public enum ConsentLevel: String, Sendable {
        case implicit = "implicit"
        case explicitOptIn = "explicit_opt_in"
    }
}
