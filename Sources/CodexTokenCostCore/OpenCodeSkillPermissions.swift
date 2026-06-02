import Foundation

// MARK: - Permission Action

public enum OpenCodePermissionAction: String, Codable, Sendable {
    case allow
    case ask
    case deny
    case implicitDefault
}

// MARK: - Skill Rule

public struct OpenCodeSkillRule: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let pattern: String
    public let action: OpenCodePermissionAction
    public let source: String
    public let order: Int
    public let isLegacy: Bool

    public init(pattern: String, action: OpenCodePermissionAction, source: String, order: Int, isLegacy: Bool = false) {
        self.id = UUID().uuidString
        self.pattern = pattern
        self.action = action
        self.source = source
        self.order = order
        self.isLegacy = isLegacy
    }
}

// MARK: - Agent Types

public enum OpenCodeAgentKind: String, Codable, CaseIterable, Sendable {
    case build
    case plan
    case general
    case explore
    case scout
    case compaction
    case title
    case summary
}

public struct OpenCodeAgentSkillAvailability: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let agent: OpenCodeAgentKind
    public let skillToolAvailable: Bool
    public let baselineAction: OpenCodePermissionAction
    public let overridden: Bool
    public let nativeAllow: Bool
    public let note: String?

    public init(
        agent: OpenCodeAgentKind,
        skillToolAvailable: Bool,
        baselineAction: OpenCodePermissionAction,
        overridden: Bool = false,
        nativeAllow: Bool = true,
        note: String? = nil
    ) {
        self.id = agent.rawValue
        self.agent = agent
        self.skillToolAvailable = skillToolAvailable
        self.baselineAction = baselineAction
        self.overridden = overridden
        self.nativeAllow = nativeAllow
        self.note = note
    }
}

// MARK: - Baseline State

public struct OpenCodeSkillBaselineState: Codable, Hashable, Sendable {
    public let skillName: String
    public let resolvedAction: OpenCodePermissionAction
    public let matchedRule: OpenCodeSkillRule?
    public let ruleChain: [OpenCodeSkillRule]
    public let explainMessage: String

    public init(
        skillName: String,
        resolvedAction: OpenCodePermissionAction,
        matchedRule: OpenCodeSkillRule? = nil,
        ruleChain: [OpenCodeSkillRule] = [],
        explainMessage: String = ""
    ) {
        self.skillName = skillName
        self.resolvedAction = resolvedAction
        self.matchedRule = matchedRule
        self.ruleChain = ruleChain
        self.explainMessage = explainMessage
    }
}

// MARK: - Permission Resolver

public enum OpenCodeSkillPermissionResolver {

    public static func resolveSkillPermission(
        skillName: String,
        permissionConfig: Any?,
        toolsConfig: Any? = nil
    ) -> OpenCodeSkillBaselineState {
        var ruleChain: [OpenCodeSkillRule] = []
        var orderCounter = 0

        let configDict = permissionConfig as? [String: Any]

        if let scalarAction = permissionConfig as? String,
           let action = parseAction(scalarAction) {
            let rule = OpenCodeSkillRule(
                pattern: "*",
                action: action,
                source: "global",
                order: orderCounter
            )
            ruleChain.append(rule)
            orderCounter += 1

            return OpenCodeSkillBaselineState(
                skillName: skillName,
                resolvedAction: action,
                matchedRule: rule,
                ruleChain: ruleChain,
                explainMessage: "Global scalar permission: \(scalarAction) applies to all permissions"
            )
        }

        if let dict = configDict {
            let topLevelKeys = orderedKeys(from: dict)

            for key in topLevelKeys {
                let value = dict[key]

                if key == "skill" {
                    if let scalarValue = value as? String, let action = parseAction(scalarValue) {
                        let rule = OpenCodeSkillRule(
                            pattern: "*",
                            action: action,
                            source: "global",
                            order: orderCounter
                        )
                        ruleChain.append(rule)
                        orderCounter += 1

                        return OpenCodeSkillBaselineState(
                            skillName: skillName,
                            resolvedAction: action,
                            matchedRule: rule,
                            ruleChain: ruleChain,
                            explainMessage: "Global permission.skill = \(scalarValue)"
                        )
                    }

                    if let nestedDict = value as? [String: Any] {
                        let nestedKeys = orderedKeys(from: nestedDict)
                        var matchedAction: OpenCodePermissionAction?

                        for nestedKey in nestedKeys {
                            if let actionStr = nestedDict[nestedKey] as? String,
                               let action = parseAction(actionStr) {
                                let rule = OpenCodeSkillRule(
                                    pattern: nestedKey,
                                    action: action,
                                    source: "global",
                                    order: orderCounter
                                )
                                ruleChain.append(rule)
                                orderCounter += 1

                                if matchWildcard(pattern: nestedKey, against: skillName) {
                                    matchedAction = action
                                }
                            }
                        }

                        if let action = matchedAction {
                            let matchedRule = ruleChain.last(where: { $0.action == action && matchWildcard(pattern: $0.pattern, against: skillName) })
                            return OpenCodeSkillBaselineState(
                                skillName: skillName,
                                resolvedAction: action,
                                matchedRule: matchedRule,
                                ruleChain: ruleChain,
                                explainMessage: "Permission.skill object rule matched: \(skillName) → \(action.rawValue)"
                            )
                        }
                    }
                }

                if matchWildcard(pattern: key, against: "skill") {
                    if let scalarValue = value as? String, let action = parseAction(scalarValue) {
                        let rule = OpenCodeSkillRule(
                            pattern: key,
                            action: action,
                            source: "global",
                            order: orderCounter
                        )
                        ruleChain.append(rule)
                        orderCounter += 1

                        return OpenCodeSkillBaselineState(
                            skillName: skillName,
                            resolvedAction: action,
                            matchedRule: rule,
                            ruleChain: ruleChain,
                            explainMessage: "Top-level permission '\(key)' = \(scalarValue) applies to skill"
                        )
                    }
                }
            }
        }

        if let tools = toolsConfig as? [String: Any] {
            if let skillTool = tools["skill"] as? Bool, !skillTool {
                let rule = OpenCodeSkillRule(
                    pattern: "*",
                    action: .deny,
                    source: "legacy-tools",
                    order: orderCounter,
                    isLegacy: true
                )
                ruleChain.append(rule)
                return OpenCodeSkillBaselineState(
                    skillName: skillName,
                    resolvedAction: .deny,
                    matchedRule: rule,
                    ruleChain: ruleChain,
                    explainMessage: "Legacy tools.skill=false disables skill tool"
                )
            }
            if let wildcard = tools["*"] as? Bool, !wildcard {
                let rule = OpenCodeSkillRule(
                    pattern: "*",
                    action: .deny,
                    source: "legacy-tools",
                    order: orderCounter,
                    isLegacy: true
                )
                ruleChain.append(rule)
                return OpenCodeSkillBaselineState(
                    skillName: skillName,
                    resolvedAction: .deny,
                    matchedRule: rule,
                    ruleChain: ruleChain,
                    explainMessage: "Legacy tools.*=false disables all tools including skill"
                )
            }
        }

        return OpenCodeSkillBaselineState(
            skillName: skillName,
            resolvedAction: .implicitDefault,
            ruleChain: ruleChain,
            explainMessage: "No matching rule — implicit default allow"
        )
    }

    public static func buildAgentMatrix(
        permissionConfig: Any?,
        agentOverrides: [OpenCodeAgentKind: [String: Any]] = [:],
        legacyTools: [String: Any] = [:]
    ) -> [OpenCodeAgentSkillAvailability] {
        var results: [OpenCodeAgentSkillAvailability] = []

        for agent in OpenCodeAgentKind.allCases {
            let nativeAllow = nativeSkillAllow(agent)
            var skillToolAvailable = nativeAllow
            let overridden = agentOverrides[agent] != nil
            var note: String?

            let agentTools = legacyTools[agent.rawValue] as? [String: Any]
            if let skillTool = agentTools?["skill"] as? Bool, !skillTool {
                skillToolAvailable = false
                note = "legacy tools.skill=false overrides"
            }
            if let wildcard = agentTools?["*"] as? Bool, !wildcard {
                skillToolAvailable = false
                note = "legacy tools.*=false overrides"
            }

            if let agentPerm = agentOverrides[agent]?["permission"] as? [String: Any] {
                if let skill = agentPerm["skill"] as? String, skill == "deny" {
                    skillToolAvailable = false
                    note = "agent permission.skill=deny"
                }
                if let wildcard = agentPerm["*"] as? String, wildcard == "deny" {
                    skillToolAvailable = false
                    note = "agent permission.*=deny"
                }
            }

            let baselineAction: OpenCodePermissionAction = skillToolAvailable ? .allow : .deny

            results.append(OpenCodeAgentSkillAvailability(
                agent: agent,
                skillToolAvailable: skillToolAvailable,
                baselineAction: baselineAction,
                overridden: overridden,
                nativeAllow: nativeAllow,
                note: note
            ))
        }

        return results
    }

    public static func matchWildcard(pattern: String, against skillName: String) -> Bool {
        let regexPattern = "^" + NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".") + "$"
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: []) else {
            return pattern == skillName
        }
        let range = NSRange(location: 0, length: skillName.utf16.count)
        return regex.firstMatch(in: skillName, options: [], range: range) != nil
    }

    // MARK: - Helpers

    private static func parseAction(_ raw: String) -> OpenCodePermissionAction? {
        switch raw.lowercased() {
        case "allow": return .allow
        case "ask": return .ask
        case "deny": return .deny
        default: return nil
        }
    }

    private static func nativeSkillAllow(_ agent: OpenCodeAgentKind) -> Bool {
        switch agent {
        case .build, .plan, .general:
            return true
        case .explore, .scout, .compaction, .title, .summary:
            return false
        }
    }

    private static func orderedKeys(from dict: [String: Any]) -> [String] {
        Array(dict.keys)
    }
}
