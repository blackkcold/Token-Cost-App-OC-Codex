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
    private static let readChunkSize = 1024 * 1024
    private static let maxLineSize = 32 * 1024 * 1024

    private let fileManager = FileManager.default
    private let sourceRoots: [URL]
    private let manualSourcePaths: [URL]
    private let profile: TokenCostSourceProfile
    private let maxDepth: Int
    private let maxCandidates: Int

    private static nonisolated(unsafe) let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

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

            var buffer = Data()
            var lineNumber = 0

            var accumulator = SessionAccumulator()
            accumulator.updatedAt = modificationTimestamp(for: url) ?? Self.iso8601Formatter.string(from: Date())

            while true {
                let chunk = fileHandle.readData(ofLength: Self.readChunkSize)
                if chunk.isEmpty { break }
                buffer.append(chunk)

                while let nlRange = findNewline(in: buffer) {
                    let lineData = buffer.subdata(in: 0..<nlRange.lowerBound)
                    buffer.removeSubrange(0..<nlRange.upperBound)
                    lineNumber += 1

                    guard lineData.count <= Self.maxLineSize else {
                        fputs("Warning: Skipping over-size line \(lineNumber) in \(url.lastPathComponent) (\(lineData.count) bytes)\n", stderr)
                        continue
                    }

                    guard !lineData.isEmpty else { continue }

                    if let rawObject = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                        processLine(rawObject, accumulator: &accumulator, fallbackPath: url)
                    }
                }
            }

            if !buffer.isEmpty {
                lineNumber += 1
                if buffer.count <= Self.maxLineSize {
                    if let rawObject = try? JSONSerialization.jsonObject(with: buffer) as? [String: Any] {
                        processLine(rawObject, accumulator: &accumulator, fallbackPath: url)
                    }
                } else {
                    fputs("Warning: Skipping over-size final line \(lineNumber) in \(url.lastPathComponent) (\(buffer.count) bytes)\n", stderr)
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
                modelContextWindow: accumulator.modelContextWindow,
                modelBreakdown: accumulator.modelBreakdown
            )
        } catch {
            FileHandle.standardError.write(Data("Skipping Codex session file \(url.path): \(error.localizedDescription)\n".utf8))
            return nil
        }
    }

    private func findNewline(in data: Data) -> Range<Int>? {
        for i in 0..<data.count {
            if data[i] == 0x0A {
                let start = i > 0 && data[i - 1] == 0x0D ? i - 1 : i
                return start..<(i + 1)
            }
        }
        return nil
    }

    private func processLine(
        _ rawLine: [String: Any],
        accumulator: inout SessionAccumulator,
        fallbackPath: URL
    ) {
        let type = stringValue(rawLine["type"]) ?? stringValue(rawLine["event"])
        let timestamp = stringValue(rawLine["timestamp"])
        let rawPayload = dictionaryValue(rawLine["payload"]) ?? rawLine

        switch type {
        case "turn_context":
            let model = stringValue(rawPayload["model"])
            if let model, !model.isEmpty, model != accumulator.currentModel {
                accumulator.currentModel = model
            }

        case "session_meta":
            let sessionID = stringValue(rawPayload["id"])
            let nickname = stringValue(rawPayload["agentNickname"])
            let ts = stringValue(rawPayload["timestamp"])
            let provider = stringValue(rawPayload["modelProvider"])

            if sessionID != nil || nickname != nil || ts != nil {
                accumulator.apply(
                    sessionID: sessionID,
                    agentNickname: nickname,
                    timestamp: ts,
                    fallbackPath: fallbackPath
                )
                if let provider, !provider.isEmpty {
                    accumulator.modelProvider = provider
                }
                accumulator.startedAt = accumulator.startedAt ?? (ts ?? timestamp)
            } else {
                processGenericSessionMeta(rawPayload, accumulator: &accumulator, fallbackPath: fallbackPath)
            }

        case "event_msg":
            let absoluteUsage = extractAbsoluteUsage(from: rawPayload, depth: 0)
            let payloadType = stringValue(rawPayload["type"])
            let isTokenCount = payloadType == "token_count"

            if isTokenCount || absoluteUsage != nil {
                accumulator.recordTokenEvent(at: timestamp)
            }

            if let usage = absoluteUsage {
                accumulator.recordAbsoluteUsage(
                    usage,
                    planType: planType(from: rawPayload),
                    modelContextWindow: modelContextWindow(from: rawPayload),
                    timestamp: timestamp
                )
                if let lastUsage = extractLastTokenUsage(from: rawPayload) {
                    if lastUsage.totalTokens > 0 {
                        accumulator.recordModelUsage(from: lastUsage)
                    }
                }
            } else if isTokenCount, accumulator.planType == nil, let pt = planType(from: rawPayload) {
                accumulator.planType = pt
            } else if accumulator.planType == nil, let pt = planType(from: rawPayload) {
                accumulator.planType = pt
            }

        default:
            if let usage = extractAbsoluteUsage(from: rawPayload, depth: 0) {
                accumulator.recordTokenEvent(at: timestamp)
                accumulator.recordAbsoluteUsage(
                    usage,
                    planType: planType(from: rawPayload),
                    modelContextWindow: modelContextWindow(from: rawPayload),
                    timestamp: timestamp
                )
                if let lastUsage = extractLastTokenUsage(from: rawPayload) {
                    if lastUsage.totalTokens > 0 {
                        accumulator.recordModelUsage(from: lastUsage)
                    }
                }
            } else {
                let payloadType = stringValue(rawPayload["type"])
                if payloadType == "token_count" {
                    accumulator.recordTokenEvent(at: timestamp)
                    if accumulator.planType == nil {
                        accumulator.planType = planType(from: rawPayload)
                    }
                } else {
                    processGenericSessionMeta(rawPayload, accumulator: &accumulator, fallbackPath: fallbackPath)
                }
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
        let provider = stringValue(payload["modelProvider"])

        if sessionID != nil || nickname != nil || timestamp != nil {
            accumulator.apply(
                sessionID: sessionID,
                agentNickname: nickname,
                timestamp: timestamp,
                fallbackPath: fallbackPath
            )
            if let provider, !provider.isEmpty {
                accumulator.modelProvider = provider
            }
        }
    }

    private func extractLastTokenUsage(from object: Any?) -> CodexTokenUsage? {
        guard let dict = dictionaryValue(object),
              let lastUsage = dictionaryValue(dict["last_token_usage"] ?? dict["lastTokenUsage"]) else {
            return nil
        }
        return CodexTokenUsage(
            inputTokens: doubleValue(lastUsage["input_tokens"] ?? lastUsage["inputTokens"]) ?? 0,
            cachedInputTokens: doubleValue(lastUsage["cached_input_tokens"] ?? lastUsage["cachedInputTokens"]) ?? 0,
            outputTokens: doubleValue(lastUsage["output_tokens"] ?? lastUsage["outputTokens"]) ?? 0,
            reasoningOutputTokens: doubleValue(lastUsage["reasoning_output_tokens"] ?? lastUsage["reasoningOutputTokens"]) ?? 0,
            totalTokens: doubleValue(lastUsage["total_tokens"] ?? lastUsage["totalTokens"]) ?? 0
        )
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

    private func buildPayload(from sessions: [CodexSessionSummary]) -> CodexDashboardPayload {
        let sortedSessions = sessions.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        var modelDict: [String: CodexModelUsage] = [:]
        for session in sortedSessions {
            for modelUsage in session.modelBreakdown {
                if let existing = modelDict[modelUsage.model] {
                    modelDict[modelUsage.model] = CodexModelUsage(
                        model: modelUsage.model,
                        provider: modelUsage.provider ?? existing.provider,
                        inputTokens: existing.inputTokens + modelUsage.inputTokens,
                        cachedInputTokens: existing.cachedInputTokens + modelUsage.cachedInputTokens,
                        outputTokens: existing.outputTokens + modelUsage.outputTokens,
                        reasoningOutputTokens: existing.reasoningOutputTokens + modelUsage.reasoningOutputTokens,
                        totalTokens: existing.totalTokens + modelUsage.totalTokens,
                        turnCount: existing.turnCount + modelUsage.turnCount
                    )
                } else {
                    modelDict[modelUsage.model] = modelUsage
                }
            }
        }
        let mergedModelBreakdown = modelDict.values.sorted { $0.totalTokens > $1.totalTokens }

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
            modelBreakdown: mergedModelBreakdown,
            lastSessionUpdatedAt: nil,
            sourceRootLabel: sourceDescription(),
            updatedAt: Self.iso8601Formatter.string(from: Date())
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
        return Self.iso8601Formatter.string(from: date)
    }
}

private struct ModelUsageAccumulator {
    var inputTokens: Double = 0
    var cachedInputTokens: Double = 0
    var outputTokens: Double = 0
    var reasoningOutputTokens: Double = 0
    var totalTokens: Double = 0
    var turnCount: Int = 0
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
    var currentModel: String?
    var modelProvider: String?
    var modelUsages: [String: ModelUsageAccumulator] = [:]

    var hasAnyData: Bool {
        tokenCountEvents > 0
    }

    var modelBreakdown: [CodexModelUsage] {
        modelUsages.map { model, acc in
            CodexModelUsage(
                model: model,
                provider: modelProvider,
                inputTokens: acc.inputTokens,
                cachedInputTokens: acc.cachedInputTokens,
                outputTokens: acc.outputTokens,
                reasoningOutputTokens: acc.reasoningOutputTokens,
                totalTokens: acc.totalTokens,
                turnCount: acc.turnCount
            )
        }.sorted { $0.totalTokens > $1.totalTokens }
    }

    mutating func recordModelUsage(from usage: CodexTokenUsage) {
        guard let model = currentModel else { return }
        var acc = modelUsages[model] ?? ModelUsageAccumulator()
        acc.inputTokens += usage.inputTokens
        acc.cachedInputTokens += usage.cachedInputTokens
        acc.outputTokens += usage.outputTokens
        acc.reasoningOutputTokens += usage.reasoningOutputTokens
        acc.totalTokens += usage.totalTokens
        acc.turnCount += 1
        modelUsages[model] = acc
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
