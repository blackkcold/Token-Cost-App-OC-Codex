import Foundation

public struct CodexModelUsage: Codable, Hashable, Sendable {
    public var model: String
    public var provider: String?
    public var inputTokens: Double
    public var cachedInputTokens: Double
    public var outputTokens: Double
    public var reasoningOutputTokens: Double
    public var totalTokens: Double
    public var turnCount: Int

    public init(
        model: String,
        provider: String?,
        inputTokens: Double,
        cachedInputTokens: Double,
        outputTokens: Double,
        reasoningOutputTokens: Double,
        totalTokens: Double,
        turnCount: Int
    ) {
        self.model = model
        self.provider = provider
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
        self.turnCount = turnCount
    }

    public var actualInputTokens: Double {
        max(inputTokens - cachedInputTokens, 0)
    }

    public var actualTokens: Double {
        actualInputTokens + outputTokens + reasoningOutputTokens
    }
}

public struct CodexTokenUsage: Codable, Hashable, Sendable {
    public var inputTokens: Double
    public var cachedInputTokens: Double
    public var outputTokens: Double
    public var reasoningOutputTokens: Double
    public var totalTokens: Double

    public init(
        inputTokens: Double,
        cachedInputTokens: Double,
        outputTokens: Double,
        reasoningOutputTokens: Double,
        totalTokens: Double
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }

    public static let zero = CodexTokenUsage(
        inputTokens: 0,
        cachedInputTokens: 0,
        outputTokens: 0,
        reasoningOutputTokens: 0,
        totalTokens: 0
    )

    public var actualInputTokens: Double {
        max(inputTokens - cachedInputTokens, 0)
    }

    public var actualTokens: Double {
        actualInputTokens + outputTokens + reasoningOutputTokens
    }
}

public struct CodexSessionSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { sessionId }

    public var sessionId: String
    public var sessionID: String { sessionId }
    public var label: String
    public var agentNickname: String?
    public var startedAt: String?
    public var updatedAt: String
    public var planType: String?
    public var tokenCountEvents: Int
    public var validTokenCountEvents: Int
    public var usage: CodexTokenUsage
    public var modelContextWindow: Int?
    public var modelBreakdown: [CodexModelUsage]

    public init(
        sessionID: String,
        label: String,
        agentNickname: String?,
        startedAt: String?,
        updatedAt: String,
        planType: String?,
        tokenCountEvents: Int,
        validTokenCountEvents: Int,
        usage: CodexTokenUsage,
        modelContextWindow: Int?,
        modelBreakdown: [CodexModelUsage] = []
    ) {
        self.sessionId = sessionID
        self.label = label
        self.agentNickname = agentNickname
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.planType = planType
        self.tokenCountEvents = tokenCountEvents
        self.validTokenCountEvents = validTokenCountEvents
        self.usage = usage
        self.modelContextWindow = modelContextWindow
        self.modelBreakdown = modelBreakdown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionId = try container.decode(String.self, forKey: .sessionId)
        self.label = try container.decode(String.self, forKey: .label)
        self.agentNickname = try container.decodeIfPresent(String.self, forKey: .agentNickname)
        self.startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        self.updatedAt = try container.decode(String.self, forKey: .updatedAt)
        self.planType = try container.decodeIfPresent(String.self, forKey: .planType)
        self.tokenCountEvents = try container.decode(Int.self, forKey: .tokenCountEvents)
        self.validTokenCountEvents = try container.decode(Int.self, forKey: .validTokenCountEvents)
        self.usage = try container.decode(CodexTokenUsage.self, forKey: .usage)
        self.modelContextWindow = try container.decodeIfPresent(Int.self, forKey: .modelContextWindow)
        self.modelBreakdown = try container.decodeIfPresent([CodexModelUsage].self, forKey: .modelBreakdown) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId
        case label
        case agentNickname
        case startedAt
        case updatedAt
        case planType
        case tokenCountEvents
        case validTokenCountEvents
        case usage
        case modelContextWindow
        case modelBreakdown
    }

    public var actualTokens: Double {
        usage.actualTokens
    }
}

public struct CodexDashboardPayload: Codable, Hashable, Sendable {
    public struct Summary: Codable, Hashable, Sendable {
        public var sessionCount: Int
        public var tokenCountEvents: Int
        public var validTokenCountEvents: Int
        public var totalInputTokens: Double
        public var totalCachedInputTokens: Double
        public var totalOutputTokens: Double
        public var totalReasoningOutputTokens: Double
        public var totalTokens: Double
        public var planTypeCounts: [String: Int]
        public var firstSessionStartedAt: String?
        public var modelBreakdown: [CodexModelUsage]
        public var lastSessionUpdatedAt: String?
        public var sourceRootLabel: String
        public var updatedAt: String

        public init(
            sessionCount: Int,
            tokenCountEvents: Int,
            validTokenCountEvents: Int,
            totalInputTokens: Double,
            totalCachedInputTokens: Double,
            totalOutputTokens: Double,
            totalReasoningOutputTokens: Double,
            totalTokens: Double,
            planTypeCounts: [String: Int],
            firstSessionStartedAt: String?,
            modelBreakdown: [CodexModelUsage] = [],
            lastSessionUpdatedAt: String?,
            sourceRootLabel: String,
            updatedAt: String
        ) {
            self.sessionCount = sessionCount
            self.tokenCountEvents = tokenCountEvents
            self.validTokenCountEvents = validTokenCountEvents
            self.totalInputTokens = totalInputTokens
            self.totalCachedInputTokens = totalCachedInputTokens
            self.totalOutputTokens = totalOutputTokens
            self.totalReasoningOutputTokens = totalReasoningOutputTokens
            self.totalTokens = totalTokens
            self.planTypeCounts = planTypeCounts
            self.firstSessionStartedAt = firstSessionStartedAt
            self.modelBreakdown = modelBreakdown
            self.lastSessionUpdatedAt = lastSessionUpdatedAt
            self.sourceRootLabel = sourceRootLabel
            self.updatedAt = updatedAt
        }

        public var totalActualInputTokens: Double {
            max(totalInputTokens - totalCachedInputTokens, 0)
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.sessionCount = try container.decode(Int.self, forKey: .sessionCount)
            self.tokenCountEvents = try container.decode(Int.self, forKey: .tokenCountEvents)
            self.validTokenCountEvents = try container.decode(Int.self, forKey: .validTokenCountEvents)
            self.totalInputTokens = try container.decode(Double.self, forKey: .totalInputTokens)
            self.totalCachedInputTokens = try container.decode(Double.self, forKey: .totalCachedInputTokens)
            self.totalOutputTokens = try container.decode(Double.self, forKey: .totalOutputTokens)
            self.totalReasoningOutputTokens = try container.decode(Double.self, forKey: .totalReasoningOutputTokens)
            self.totalTokens = try container.decode(Double.self, forKey: .totalTokens)
            self.planTypeCounts = try container.decode([String: Int].self, forKey: .planTypeCounts)
            self.firstSessionStartedAt = try container.decodeIfPresent(String.self, forKey: .firstSessionStartedAt)
            self.modelBreakdown = try container.decodeIfPresent([CodexModelUsage].self, forKey: .modelBreakdown) ?? []
            self.lastSessionUpdatedAt = try container.decodeIfPresent(String.self, forKey: .lastSessionUpdatedAt)
            self.sourceRootLabel = try container.decode(String.self, forKey: .sourceRootLabel)
            self.updatedAt = try container.decode(String.self, forKey: .updatedAt)
        }

        private enum CodingKeys: String, CodingKey {
            case sessionCount
            case tokenCountEvents
            case validTokenCountEvents
            case totalInputTokens
            case totalCachedInputTokens
            case totalOutputTokens
            case totalReasoningOutputTokens
            case totalTokens
            case planTypeCounts
            case firstSessionStartedAt
            case modelBreakdown
            case lastSessionUpdatedAt
            case sourceRootLabel
            case updatedAt
        }

        public var totalActualTokens: Double {
            totalActualInputTokens + totalOutputTokens + totalReasoningOutputTokens
        }
    }

    public var summary: Summary
    public var sessions: [CodexSessionSummary]

    public init(summary: Summary, sessions: [CodexSessionSummary]) {
        self.summary = summary
        self.sessions = sessions
    }

    public static func empty() -> CodexDashboardPayload {
        CodexDashboardPayload(
            summary: Summary(
                sessionCount: 0,
                tokenCountEvents: 0,
                validTokenCountEvents: 0,
                totalInputTokens: 0,
                totalCachedInputTokens: 0,
                totalOutputTokens: 0,
                totalReasoningOutputTokens: 0,
                totalTokens: 0,
                planTypeCounts: [:],
                firstSessionStartedAt: nil,
                modelBreakdown: [],
                lastSessionUpdatedAt: nil,
                sourceRootLabel: TokenCostSourceProfile.codex.sourceRootsLabel,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            ),
            sessions: []
        )
    }
}
