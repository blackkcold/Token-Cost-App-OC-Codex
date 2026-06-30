import Foundation

/// Performs Codex-specific source discovery off the MainActor.
///
/// ``discover(settings:)`` matches the same semantics as the old inline
/// ``CodexSessionModel.buildDiscoverySources`` — missing directories/files
/// produce ``.missing`` entries, manual files are probed for readability and
/// JSONL validity, and results are sorted by status rank then name.
///
/// This type is ``Sendable`` because it carries no mutable state; every call
/// creates its own local ``FileManager`` instance.
public final class CodexSessionDiscoveryService: Sendable {
    public init() {}

    public func discover(settings: TokenCostSettings) -> [TokenCostSource] {
        let profile = settings.profile
        var seenIDs = Set<String>()
        var sources: [TokenCostSource] = []

        for root in settings.effectiveSourceRoots {
            appendDirectorySources(
                for: root,
                profile: profile,
                maxDepth: settings.maxScanDepth,
                maxCandidates: settings.maxScanCandidates,
                seenIDs: &seenIDs,
                into: &sources
            )
        }

        for path in settings.effectiveManualSourcePaths {
            appendManualSource(
                for: path,
                profile: profile,
                seenIDs: &seenIDs,
                into: &sources
            )
        }

        return sources.sorted { lhs, rhs in
            if lhs.status == rhs.status {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return statusRank(lhs.status) < statusRank(rhs.status)
        }
    }

    // MARK: - Private helpers

    private func appendDirectorySources(
        for path: String,
        profile: TokenCostSourceProfile,
        maxDepth: Int,
        maxCandidates: Int,
        seenIDs: inout Set<String>,
        into sources: inout [TokenCostSource]
    ) {
        let fm = FileManager.default
        let normalized = TokenCostPathUtilities.canonicalURL(from: path)
        var isDirectory: ObjCBool = false
        let exists = fm.fileExists(atPath: normalized.path, isDirectory: &isDirectory)

        guard exists else {
            appendIfNeeded(
                makeCodexSource(
                    sourceURL: normalized,
                    locationURL: normalized,
                    locationKind: .directory,
                    profile: profile,
                    status: .missing,
                    statusMessageKind: .missingDefaultLocation,
                    isDefault: true
                ),
                seenIDs: &seenIDs,
                into: &sources
            )
            return
        }

        if isDirectory.boolValue {
            let discoveredFiles = discoverSessionFiles(
                in: normalized,
                profile: profile,
                maxDepth: maxDepth,
                maxCandidates: maxCandidates
            )

            if discoveredFiles.isEmpty {
                appendIfNeeded(
                    makeCodexSource(
                        sourceURL: normalized,
                        locationURL: normalized,
                        locationKind: .directory,
                        profile: profile,
                        status: .missing,
                        statusMessageKind: .missingDirectoryFiles,
                        isDefault: true
                    ),
                    seenIDs: &seenIDs,
                    into: &sources
                )
                return
            }

            for fileURL in discoveredFiles {
                let fStatus = fileStatus(for: fileURL, profile: profile)
                appendIfNeeded(
                    makeCodexSource(
                        sourceURL: fileURL,
                        locationURL: normalized,
                        locationKind: .file,
                        profile: profile,
                        status: fStatus,
                        statusMessageKind: fileStatusMessageKind(for: fileURL, profile: profile, status: fStatus),
                        isDefault: false
                    ),
                    seenIDs: &seenIDs,
                    into: &sources
                )
            }
            return
        }

        appendManualSource(
            for: normalized.path,
            profile: profile,
            seenIDs: &seenIDs,
            into: &sources
        )
    }

    private func appendManualSource(
        for path: String,
        profile: TokenCostSourceProfile,
        seenIDs: inout Set<String>,
        into sources: inout [TokenCostSource]
    ) {
        let fm = FileManager.default
        let normalized = TokenCostPathUtilities.canonicalURL(from: path)
        var isDirectory: ObjCBool = false
        let exists = fm.fileExists(atPath: normalized.path, isDirectory: &isDirectory)

        if exists == false {
            appendIfNeeded(
                makeCodexSource(
                    sourceURL: normalized,
                    locationURL: normalized,
                    locationKind: .file,
                    profile: profile,
                    status: .missing,
                    statusMessageKind: .missingPath,
                    isDefault: false
                ),
                seenIDs: &seenIDs,
                into: &sources
            )
            return
        }

        if isDirectory.boolValue {
            let discoveredFiles = discoverSessionFiles(
                in: normalized,
                profile: profile,
                maxDepth: profile.maxScanDepth,
                maxCandidates: profile.maxScanCandidates
            )

            if discoveredFiles.isEmpty {
                appendIfNeeded(
                    makeCodexSource(
                        sourceURL: normalized,
                        locationURL: normalized,
                        locationKind: .directory,
                        profile: profile,
                        status: .missing,
                        statusMessageKind: .missingDirectoryFiles,
                        isDefault: false
                    ),
                    seenIDs: &seenIDs,
                    into: &sources
                )
                return
            }

            for fileURL in discoveredFiles {
                let fStatus = fileStatus(for: fileURL, profile: profile)
                appendIfNeeded(
                    makeCodexSource(
                        sourceURL: fileURL,
                        locationURL: normalized,
                        locationKind: .file,
                        profile: profile,
                        status: fStatus,
                        statusMessageKind: fileStatusMessageKind(for: fileURL, profile: profile, status: fStatus),
                        isDefault: false
                    ),
                    seenIDs: &seenIDs,
                    into: &sources
                )
            }
            return
        }

        let fStatus = fileStatus(for: normalized, profile: profile)
        appendIfNeeded(
            makeCodexSource(
                sourceURL: normalized,
                locationURL: normalized,
                locationKind: .file,
                profile: profile,
                status: fStatus,
                statusMessageKind: fileStatusMessageKind(for: normalized, profile: profile, status: fStatus),
                isDefault: false
            ),
            seenIDs: &seenIDs,
            into: &sources
        )
    }

    private func discoverSessionFiles(
        in root: URL,
        profile: TokenCostSourceProfile,
        maxDepth: Int,
        maxCandidates: Int
    ) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [URL] = []
        for case let itemURL as URL in enumerator {
            let canonical = TokenCostPathUtilities.canonicalURL(itemURL)
            guard TokenCostPathUtilities.isDescendant(canonical, of: root) else {
                continue
            }
            let relativeDepth = canonical.pathComponents.count - root.pathComponents.count
            if relativeDepth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            guard profile.matchesCandidateFile(canonical) else {
                continue
            }

            results.append(canonical)
            if results.count >= maxCandidates {
                break
            }
        }
        return results.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.path < rhs.path
            }
            return lhsDate > rhsDate
        }
    }

    private func makeCodexSource(
        sourceURL: URL,
        locationURL: URL?,
        locationKind: TokenCostSourceLocationKind,
        profile: TokenCostSourceProfile,
        status: TokenCostSourceStatus,
        statusMessageKind: TokenCostSourceStatusMessageKind,
        isDefault: Bool
    ) -> TokenCostSource {
        let normalized = TokenCostPathUtilities.canonicalURL(sourceURL)
        return TokenCostSource(
            id: TokenCostPaths.stableIdentifier(for: normalized.path),
            name: displayName(for: normalized, kind: locationKind, isDefault: isDefault),
            sourceFamily: profile.family,
            locationKind: locationKind,
            sourceURL: normalized,
            locationURL: locationURL.map(TokenCostPathUtilities.canonicalURL),
            status: status,
            statusMessageKind: statusMessageKind,
            lastModified: modificationDate(for: normalized),
            isReadOnly: true
        )
    }

    private func fileStatus(for url: URL, profile: TokenCostSourceProfile) -> TokenCostSourceStatus {
        let fm = FileManager.default
        guard profile.matchesCandidateFile(url) else {
            return .unsupported
        }
        guard fm.isReadableFile(atPath: url.path) else {
            return .locked
        }
        if profile.family == .codex {
            if !probeIsValidCodexJSONL(at: url) {
                return .unsupported
            }
        }
        return .available
    }

    /// Probe whether a Codex JSONL file contains at least one valid JSON dictionary line.
    ///
    /// Uses chunked reading with collector-parity semantics:
    /// - Reads in 1 MB chunks, finds line boundaries, skips blank lines.
    /// - Tolerates invalid or oversize lines (>32 MB) by continuing to the next.
    /// - Returns `true` as soon as any line parses as `[String: Any]`.
    /// - Returns `false` only after scanning the entire file without finding one.
    internal func probeIsValidCodexJSONL(
        at url: URL,
        readChunkSize: Int = 1024 * 1024,
        maxLineSize: Int = 32 * 1024 * 1024
    ) -> Bool {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? fileHandle.close() }

        var buffer = Data()
        var skippingOversizeLine = false
        let chunkSize = max(readChunkSize, 1)
        let lineSizeLimit = max(maxLineSize, 1)

        while true {
            guard let chunk = try? fileHandle.read(upToCount: chunkSize), !chunk.isEmpty else {
                break
            }
            buffer.append(chunk)

            while let nlRange = findNewline(in: buffer) {
                if skippingOversizeLine {
                    buffer.removeSubrange(0..<nlRange.upperBound)
                    skippingOversizeLine = false
                    continue
                }

                let lineData = buffer.subdata(in: 0..<nlRange.lowerBound)
                let lineBytes = lineData.count
                buffer.removeSubrange(0..<nlRange.upperBound)

                guard lineBytes <= lineSizeLimit else { continue }
                guard !isBlankJSONLLine(lineData) else { continue }

                if isJSONDictionary(lineData) {
                    return true
                }
            }

            if buffer.count > lineSizeLimit {
                buffer.removeAll(keepingCapacity: true)
                skippingOversizeLine = true
            }
        }

        if !skippingOversizeLine && !buffer.isEmpty {
            let lineBytes = buffer.count
            if lineBytes <= lineSizeLimit {
                if isJSONDictionary(buffer) {
                    return true
                }
            }
        }

        return false
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

    private func isBlankJSONLLine(_ data: Data) -> Bool {
        data.allSatisfy { byte in
            byte == 0x20 || byte == 0x09
        }
    }

    private func isJSONDictionary(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
    }

    internal func fileStatusMessageKind(for url: URL, profile: TokenCostSourceProfile, status: TokenCostSourceStatus) -> TokenCostSourceStatusMessageKind {
        guard profile.matchesCandidateFile(url) else {
            return .fileFormatMismatch
        }
        if FileManager.default.isReadableFile(atPath: url.path) {
            if status == .unsupported {
                return .unsupportedSchema
            }
            return .fileReadable
        }
        return .fileUnreadable
    }

    private func displayName(for url: URL, kind: TokenCostSourceLocationKind, isDefault: Bool) -> String {
        if isDefault {
            return url.lastPathComponent.isEmpty ? "" : url.lastPathComponent
        }
        switch kind {
        case .directory:
            return url.lastPathComponent.isEmpty ? url.lastPathComponent : url.lastPathComponent
        case .file:
            let fileName = url.deletingPathExtension().lastPathComponent
            return fileName.isEmpty ? url.lastPathComponent : fileName
        }
    }

    private func modificationDate(for url: URL) -> String? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else {
            return nil
        }
        return ISO8601DateFormatter().string(from: date)
    }

    private func appendIfNeeded(
        _ source: TokenCostSource,
        seenIDs: inout Set<String>,
        into sources: inout [TokenCostSource]
    ) {
        guard seenIDs.insert(source.id).inserted else {
            return
        }
        sources.append(source)
    }

    private func statusRank(_ status: TokenCostSourceStatus) -> Int {
        switch status {
        case .available: return 0
        case .locked: return 1
        case .unsupported: return 2
        case .missing: return 3
        case .unknown: return 4
        }
    }
}
