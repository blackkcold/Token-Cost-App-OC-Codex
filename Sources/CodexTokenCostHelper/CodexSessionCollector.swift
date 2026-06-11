import Foundation
import CodexTokenCostCore

public enum CodexSessionCollectorError: LocalizedError {
    case invalidArgument(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArgument(let message):
            return message
        }
    }
}

public final class CodexSessionCollector {
    private let fileManager = FileManager.default
    private let sourceRoots: [URL]
    private let manualSourcePaths: [URL]
    private let profile: TokenCostSourceProfile
    private let maxDepth: Int
    private let maxCandidates: Int

    public init(
        sourceRoots: [URL] = [],
        manualSourcePaths: [URL] = [],
        profile: TokenCostSourceProfile = .codex,
        maxDepth: Int = 6,
        maxCandidates: Int = 256
    ) {
        self.sourceRoots = sourceRoots
        self.manualSourcePaths = manualSourcePaths
        self.profile = profile
        self.maxDepth = maxDepth
        self.maxCandidates = maxCandidates
    }

    public func loadPayload() throws -> CodexDashboardPayload {
        let files = discoverSessionFiles()
        let sessions = files.compactMap { parseSessionFile($0) }
        return buildPayload(from: sessions)
    }

    private func discoverSessionFiles() -> [URL] {
        var seen = Set<String>()
        var urls: [URL] = []

        for configuredPath in effectiveSourceRoots + effectiveManualSourcePaths {
            collectConfiguredPath(configuredPath, seen: &seen, into: &urls)
            if urls.count >= maxCandidates { break }
        }

        return urls.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.path < rhs.path
            }
            return lhsDate > rhsDate
        }
    }

    private func collectConfiguredPath(_ configuredPath: URL, seen: inout Set<String>, into urls: inout [URL]) {
        let canonical = TokenCostPathUtilities.canonicalURL(configuredPath)
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: canonical.path, isDirectory: &isDirectory) else {
            return
        }

        if isDirectory.boolValue {
            collectSessionFiles(in: canonical, seen: &seen, into: &urls)
            return
        }

        guard profile.matchesCandidateFile(canonical) else {
            return
        }

        appendIfNeeded(canonical, seen: &seen, into: &urls)
    }

    private func collectSessionFiles(in root: URL, seen: inout Set<String>, into urls: inout [URL]) {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }

        let rootComponents = root.standardizedFileURL.pathComponents.count

        for case let itemURL as URL in enumerator {
            if urls.count >= maxCandidates { break }

            let canonical = TokenCostPathUtilities.canonicalURL(itemURL)
            let relativeDepth = canonical.standardizedFileURL.pathComponents.count - rootComponents
            if relativeDepth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            guard TokenCostPathUtilities.isDescendant(canonical, of: root) else {
                continue
            }
            guard profile.matchesCandidateFile(canonical) else {
                continue
            }
            appendIfNeeded(canonical, seen: &seen, into: &urls)
        }
    }

    private func appendIfNeeded(_ url: URL, seen: inout Set<String>, into urls: inout [URL]) {
        let key = TokenCostPathUtilities.canonicalURL(url).path
        guard seen.insert(key).inserted else {
            return
        }
        urls.append(TokenCostPathUtilities.canonicalURL(url))
    }

    private func parseSessionFile(_ url: URL) -> CodexSessionSummary? {
        do {
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { fileHandle.closeFile() }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            var accumulator = SessionAccumulator()
            accumulator.updatedAt = modificationTimestamp(for: url) ?? ISO8601DateFormatter().string(from: Date())

            let data = fileHandle.readDataToEndOfFile()
            guard let contents = String(data: data, encoding: .utf8) else {
                return nil
            }

            for line in contents.split(whereSeparator: \.isNewline) {
                guard let lineData = line.data(using: .utf8) else { continue }

                if let event = try? decoder.decode(SessionLine.self, from: lineData) {
                    let rawLine = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
                    processTypedLine(event, rawLine: rawLine, accumulator: &accumulator, fallbackPath: url)
                } else if let rawObject = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                    processGenericLine(rawObject, accumulator: &accumulator, fallbackPath: url)
                }
            }

            guard accumulator.hasAnyData else {
                return nil
            }

            let sessionID = accumulator.sessionID.isEmpty ? TokenCostPaths.stableIdentifier(for: TokenCostPathUtilities.canonicalURL(url).path) : accumulator.sessionID
            let shortID = String(sessionID.prefix(8))
            let label = accumulator.agentNickname?.isEmpty == false
                ? "\(accumulator.agentNickname!) · \(shortID)"
                : shortID

            return CodexSessionSummary(
                sessionID: sessionID,
                label: label,
                agentNickname: accumulator.agentNickname,
                startedAt: accumulator.startedAt,
                updatedAt: accumulator.updatedAt,
                planType: accumulator.planType,
                tokenCountEvents: accumulator.tokenCountEvents,
                validTokenCountEvents: accumulator.validTokenCountEvents,
                usage: accumulator.usage,
                modelContextWindow: accumulator.modelContextWindow
            )
        } catch {
            FileHandle.standardError.write(Data("Skipping Codex session file \(url.path): \(error.localizedDescription)\n".utf8))
            return nil
        }
    }

    private func processTypedLine(
        _ event: SessionLine,
        rawLine: [String: Any]?,
        accumulator: inout SessionAccumulator,
        fallbackPath: URL
    ) {
        switch event.type {
        case "session_meta":
            if event.payload.id != nil || event.payload.agentNickname != nil || event.payload.timestamp != nil {
                accumulator.apply(sessionMeta: event.payload, fallbackPath: fallbackPath)
                let timestamp = event.payload.timestamp ?? event.timestamp
                accumulator.startedAt = accumulator.startedAt ?? timestamp
            } else if let rawPayload = rawLine.flatMap({ dictionaryValue($0["payload"]) }) {
                processGenericSessionMeta(rawPayload, accumulator: &accumulator, fallbackPath: fallbackPath)
            }

        case "event_msg":
            let rawPayload = rawLine.flatMap { dictionaryValue($0["payload"]) }
            let absoluteUsage = event.payload.info?.totalTokenUsage.map { codexTokenUsage(from: $0) }
                ?? rawPayload.flatMap { extractAbsoluteUsage(from: $0, depth: 0) }

            if event.payload.payloadType == "token_count" || absoluteUsage != nil {
                accumulator.recordTokenEvent(at: event.timestamp)
                if let usage = absoluteUsage {
                    accumulator.recordAbsoluteUsage(
                        usage,
                        planType: event.payload.rateLimits?.planType,
                        modelContextWindow: event.payload.info?.modelContextWindow,
                        timestamp: event.timestamp
                    )
                } else if accumulator.planType == nil {
                    accumulator.planType = event.payload.rateLimits?.planType
                }
            } else if accumulator.planType == nil {
                accumulator.planType = event.payload.rateLimits?.planType
            }

        default:
            if let rawPayload = rawLine.flatMap({ dictionaryValue($0["payload"]) ?? $0 }),
               let usage = extractAbsoluteUsage(from: rawPayload, depth: 0) {
                accumulator.recordTokenEvent(at: event.timestamp)
                accumulator.recordAbsoluteUsage(usage, planType: nil, modelContextWindow: nil, timestamp: event.timestamp)
            } else if let rawPayload = rawLine.flatMap({ dictionaryValue($0["payload"]) ?? $0 }) {
                processGenericSessionMeta(rawPayload, accumulator: &accumulator, fallbackPath: fallbackPath)
            }
        }
    }

    private func processGenericLine(
        _ rawLine: [String: Any],
        accumulator: inout SessionAccumulator,
        fallbackPath: URL
    ) {
        let type = stringValue(rawLine["type"]) ?? stringValue(rawLine["event"])
        let timestamp = stringValue(rawLine["timestamp"])
        let rawPayload = dictionaryValue(rawLine["payload"]) ?? rawLine

        if type == "session_meta" {
            processGenericSessionMeta(rawPayload, accumulator: &accumulator, fallbackPath: fallbackPath)
            if let timestamp, accumulator.startedAt == nil {
                accumulator.startedAt = timestamp
            }
            return
        }

        if let usage = extractAbsoluteUsage(from: rawPayload, depth: 0) {
            accumulator.recordTokenEvent(at: timestamp)
            accumulator.recordAbsoluteUsage(usage, planType: planType(from: rawPayload), modelContextWindow: modelContextWindow(from: rawPayload), timestamp: timestamp)
            return
        }

        if let rawPayloadType = stringValue(rawPayload["type"]), rawPayloadType == "token_count" {
            accumulator.recordTokenEvent(at: timestamp)
            if accumulator.planType == nil {
                accumulator.planType = planType(from: rawPayload)
            }
        }
    }

    private func processGenericSessionMeta(
        _ payload: [String: Any],
        accumulator: inout SessionAccumulator,
        fallbackPath: URL
    ) {
        let sessionID = stringValue(payload["id"])
        let nickname = stringValue(payload["agentNickname"])
        let timestamp = stringValue(payload["timestamp"])

        if sessionID != nil || nickname != nil || timestamp != nil {
            accumulator.apply(
                sessionID: sessionID,
                agentNickname: nickname,
                timestamp: timestamp,
                fallbackPath: fallbackPath
            )
        }
    }

    private func extractAbsoluteUsage(from object: Any?, depth: Int) -> CodexTokenUsage? {
        guard depth < 20, let dict = dictionaryValue(object) else {
            return nil
        }

        if let direct = directUsage(in: dict) {
            return direct
        }

        let nestedKeys = [
            "total_token_usage",
            "totalTokenUsage",
            "usage",
            "info",
            "token_usage",
            "tokenUsage",
            "codex_totals",
            "codexTotals",
            "payload",
            "data",
            "details",
            "summary",
            "result"
        ]

        for key in nestedKeys {
            if let usage = extractAbsoluteUsage(from: dict[key], depth: depth + 1) {
                return usage
            }
        }

        return nil
    }

    private func directUsage(in dict: [String: Any]) -> CodexTokenUsage? {
        let inputTokens = doubleValue(dict["input_tokens"])
            ?? doubleValue(dict["inputTokens"])
            ?? doubleValue(dict["codex_input_tokens"])
            ?? doubleValue(dict["codexInputTokens"])

        let cachedInputTokens = doubleValue(dict["cached_input_tokens"])
            ?? doubleValue(dict["cachedInputTokens"])

        let outputTokens = doubleValue(dict["output_tokens"])
            ?? doubleValue(dict["outputTokens"])
            ?? doubleValue(dict["codex_output_tokens"])
            ?? doubleValue(dict["codexOutputTokens"])

        let reasoningOutputTokens = doubleValue(dict["reasoning_output_tokens"])
            ?? doubleValue(dict["reasoningOutputTokens"])

        let totalTokens = doubleValue(dict["total_tokens"])
            ?? doubleValue(dict["totalTokens"])
            ?? doubleValue(dict["codex_total_tokens"])
            ?? doubleValue(dict["codexTotalTokens"])

        guard inputTokens != nil || cachedInputTokens != nil || outputTokens != nil || reasoningOutputTokens != nil || totalTokens != nil else {
            return nil
        }

        return CodexTokenUsage(
            inputTokens: inputTokens ?? 0,
            cachedInputTokens: cachedInputTokens ?? 0,
            outputTokens: outputTokens ?? 0,
            reasoningOutputTokens: reasoningOutputTokens ?? 0,
            totalTokens: totalTokens ?? 0
        )
    }

    private func planType(from object: Any?) -> String? {
        guard let dict = dictionaryValue(object) else {
            return nil
        }

        if let rateLimits = dictionaryValue(dict["rate_limits"] ?? dict["rateLimits"]) {
            return stringValue(rateLimits["plan_type"] ?? rateLimits["planType"])
        }

        return stringValue(dict["plan_type"] ?? dict["planType"])
    }

    private func modelContextWindow(from object: Any?) -> Int? {
        guard let dict = dictionaryValue(object) else {
            return nil
        }

        if let info = dictionaryValue(dict["info"]) {
            return intValue(info["model_context_window"] ?? info["modelContextWindow"])
        }

        return intValue(dict["model_context_window"] ?? dict["modelContextWindow"])
    }

    private func dictionaryValue(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private func codexTokenUsage(from usage: TokenUsage) -> CodexTokenUsage {
        CodexTokenUsage(
            inputTokens: usage.inputTokens ?? 0,
            cachedInputTokens: usage.cachedInputTokens ?? 0,
            outputTokens: usage.outputTokens ?? 0,
            reasoningOutputTokens: usage.reasoningOutputTokens ?? 0,
            totalTokens: usage.totalTokens ?? 0
        )
    }

    private func buildPayload(from sessions: [CodexSessionSummary]) -> CodexDashboardPayload {
        let sortedSessions = sessions.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        let summary = sortedSessions.reduce(into: CodexDashboardPayload.Summary(
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
            lastSessionUpdatedAt: nil,
            sourceRootLabel: sourceDescription(),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )) { result, session in
            result.sessionCount += 1
            result.tokenCountEvents += session.tokenCountEvents
            result.validTokenCountEvents += session.validTokenCountEvents
            result.totalInputTokens += session.usage.inputTokens
            result.totalCachedInputTokens += session.usage.cachedInputTokens
            result.totalOutputTokens += session.usage.outputTokens
            result.totalReasoningOutputTokens += session.usage.reasoningOutputTokens
            result.totalTokens += session.usage.totalTokens
            if let planType = session.planType, !planType.isEmpty {
                result.planTypeCounts[planType, default: 0] += 1
            }
            if let startedAt = session.startedAt {
                if let current = result.firstSessionStartedAt {
                    result.firstSessionStartedAt = min(current, startedAt)
                } else {
                    result.firstSessionStartedAt = startedAt
                }
            }
            if let current = result.lastSessionUpdatedAt {
                result.lastSessionUpdatedAt = max(current, session.updatedAt)
            } else {
                result.lastSessionUpdatedAt = session.updatedAt
            }
        }

        return CodexDashboardPayload(summary: summary, sessions: sortedSessions)
    }

    private func sourceDescription() -> String {
        let roots = effectiveSourceRoots.isEmpty
            ? [profile.sourceRootsLabel]
            : effectiveSourceRoots.map { TokenCostPathUtilities.canonicalURL($0).path }
        let manuals = effectiveManualSourcePaths.map { TokenCostPathUtilities.canonicalURL($0).path }
        let parts = roots + manuals
        return parts.joined(separator: " · ")
    }

    private var effectiveSourceRoots: [URL] {
        deduplicatedURLs(from: sourceRoots + profile.defaultSourceRoots.map { TokenCostPathUtilities.expandedURL(from: $0) })
    }

    private var effectiveManualSourcePaths: [URL] {
        deduplicatedURLs(from: manualSourcePaths + profile.defaultManualSourcePaths.map { TokenCostPathUtilities.expandedURL(from: $0) })
    }

    private func deduplicatedURLs(from urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var results: [URL] = []

        for url in urls {
            let canonical = TokenCostPathUtilities.canonicalURL(url)
            guard seen.insert(canonical.path).inserted else {
                continue
            }
            results.append(canonical)
        }

        return results
    }

    private func modificationTimestamp(for url: URL) -> String? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else {
            return nil
        }
        return ISO8601DateFormatter().string(from: date)
    }
}

private struct SessionLine: Decodable {
    var timestamp: String
    var type: String
    var payload: SessionLinePayload
}

private struct SessionLinePayload: Decodable {
    var payloadType: String?
    var info: TokenCountInfo?
    var rateLimits: TokenCountRateLimits?
    var id: String?
    var timestamp: String?
    var agentNickname: String?
    var originator: String?
    var modelProvider: String?

    private enum CodingKeys: String, CodingKey {
        case payloadType = "type"
        case info
        case rateLimits
        case id
        case timestamp
        case agentNickname
        case originator
        case modelProvider
    }
}

private struct TokenCountInfo: Decodable {
    var totalTokenUsage: TokenUsage?
    var lastTokenUsage: TokenUsage?
    var modelContextWindow: Int?
}

private struct TokenUsage: Decodable {
    var inputTokens: Double?
    var cachedInputTokens: Double?
    var outputTokens: Double?
    var reasoningOutputTokens: Double?
    var totalTokens: Double?
}

private struct TokenCountRateLimits: Decodable {
    var planType: String?
}

private struct SessionAccumulator {
    var sessionID: String = ""
    var agentNickname: String?
    var startedAt: String?
    var updatedAt: String = ""
    var planType: String?
    var tokenCountEvents: Int = 0
    var validTokenCountEvents: Int = 0
    var usage: CodexTokenUsage = .zero
    var modelContextWindow: Int?

    var hasAnyData: Bool {
        tokenCountEvents > 0
    }

    mutating func apply(sessionMeta: SessionLinePayload, fallbackPath: URL) {
        if let id = sessionMeta.id, !id.isEmpty {
            sessionID = id
        }
        if let nickname = sessionMeta.agentNickname, !nickname.isEmpty {
            agentNickname = nickname
        }
        if let timestamp = sessionMeta.timestamp, !timestamp.isEmpty {
            startedAt = timestamp
        }
        if sessionID.isEmpty {
            sessionID = TokenCostPaths.stableIdentifier(for: TokenCostPathUtilities.canonicalURL(fallbackPath).path)
        }
    }

    mutating func apply(
        sessionID: String?,
        agentNickname: String?,
        timestamp: String?,
        fallbackPath: URL
    ) {
        if let sessionID, !sessionID.isEmpty {
            self.sessionID = sessionID
        }
        if let agentNickname, !agentNickname.isEmpty {
            self.agentNickname = agentNickname
        }
        if let timestamp, !timestamp.isEmpty {
            startedAt = timestamp
        }
        if self.sessionID.isEmpty {
            self.sessionID = TokenCostPaths.stableIdentifier(for: TokenCostPathUtilities.canonicalURL(fallbackPath).path)
        }
    }

    mutating func recordTokenEvent(at timestamp: String?) {
        tokenCountEvents += 1
        if let timestamp, !timestamp.isEmpty {
            updatedAt = timestamp
        }
    }

    mutating func recordAbsoluteUsage(
        _ usage: CodexTokenUsage,
        planType: String?,
        modelContextWindow: Int?,
        timestamp: String?
    ) {
        validTokenCountEvents += 1
        self.usage = usage
        if let planType, !planType.isEmpty {
            self.planType = planType
        }
        if let modelContextWindow {
            self.modelContextWindow = modelContextWindow
        }
        if let timestamp, !timestamp.isEmpty {
            updatedAt = timestamp
        }
    }
}
