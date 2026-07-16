import Foundation

/// Developer Mode v1: Heuristic-based task classification from aggregated session metadata.
/// Does NOT read any file content — operates purely on existing DashboardPayload.RawRow fields.
public enum TaskClassificationRule: String, Sendable, CaseIterable {
    case reasoning = "reasoning"
    case cacheHeavy = "cacheHeavy"
    case longOutput = "longOutput"
    case highFrequency = "highFrequency"
    case highCost = "highCost"
    case unclassified = "unclassified"
    
    public var displayName: String {
        switch self {
        case .reasoning: return AppLocalization.text("developerMode.classification.reasoning")
        case .cacheHeavy: return AppLocalization.text("developerMode.classification.cacheHeavy")
        case .longOutput: return AppLocalization.text("developerMode.classification.longOutput")
        case .highFrequency: return AppLocalization.text("developerMode.classification.highFrequency")
        case .highCost: return AppLocalization.text("developerMode.classification.highCost")
        case .unclassified: return AppLocalization.text("developerMode.classification.unclassified")
        }
    }
    
    public var confidence: Double {
        switch self {
        case .reasoning: return 0.8
        case .cacheHeavy: return 0.8
        case .longOutput: return 0.7
        case .highFrequency: return 0.6
        case .highCost: return 0.7
        case .unclassified: return 0.0
        }
    }
}

public struct TaskClassificationResult: Sendable {
    public let rule: TaskClassificationRule
    public let confidence: Double
    
    public init(rule: TaskClassificationRule, confidence: Double? = nil) {
        self.rule = rule
        self.confidence = confidence ?? rule.confidence
    }
}

public enum TaskClassificationEngine: Sendable {
    /// Classify a single RawRow using the 6-rule heuristic.
    /// Rules are evaluated in priority order; first match wins.
    public static func classify(_ row: DashboardPayload.RawRow) -> TaskClassificationResult {
        let actualTokens = row.input + row.output + row.reasoning
        
        // Rule 1: Reasoning-heavy — reasoning tokens > 20% of actual
        if actualTokens > 0, Double(row.reasoning) / actualTokens > 0.2 {
            return TaskClassificationResult(rule: .reasoning)
        }
        
        // Rule 2: Cache-heavy — cache tokens > 30% of total
        if row.total > 0 {
            let effectiveCacheRead = OllamaCloudCacheEstimation.effectiveCacheRead(
                provider: row.provider,
                model: row.model,
                cacheRead: Double(row.cacheRead),
                input: Double(row.input)
            )
            let cacheTotal = effectiveCacheRead + Double(row.cacheWrite)
            if cacheTotal / Double(row.total) > 0.3 {
                return TaskClassificationResult(rule: .cacheHeavy)
            }
        }
        
        // Rule 3: Long output — output > input * 2
        if row.input > 0, Double(row.output) > Double(row.input) * 2.0 {
            return TaskClassificationResult(rule: .longOutput)
        }
        
        // Rule 4: High frequency — msgCount > 20
        if row.msgCount > 20 {
            return TaskClassificationResult(rule: .highFrequency)
        }
        
        // Rule 5: High cost — cost > 5.0
        if row.cost > 5.0 {
            return TaskClassificationResult(rule: .highCost)
        }
        
        // Rule 6: Unclassified
        return TaskClassificationResult(rule: .unclassified)
    }
    
    /// Classify multiple rows and return a summary.
    public static func classify(rows: [DashboardPayload.RawRow]) -> [String: TaskClassificationResult] {
        var results: [String: TaskClassificationResult] = [:]
        for row in rows {
            let key = "\(row.date)_\(row.model)_\(row.provider)"
            results[key] = classify(row)
        }
        return results
    }
}
