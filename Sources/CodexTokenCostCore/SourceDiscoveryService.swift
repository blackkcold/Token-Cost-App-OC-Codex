import Foundation

public final class SourceDiscoveryService {
    private let fileManager = FileManager.default
    private let probe = TokenDatabaseClient()

    public init() {}

    public func discover(settings: TokenCostSettings, profile overrideProfile: TokenCostSourceProfile? = nil) -> [TokenCostSource] {
        let profile = overrideProfile ?? settings.profile
        var seenIDs = Set<String>()
        var sources: [TokenCostSource] = []

        for path in settings.effectiveManualSourcePaths {
            discoverConfiguredPath(
                path,
                profile: profile,
                preferredLocationKind: .file,
                maxDepth: settings.maxScanDepth,
                maxCandidates: settings.maxScanCandidates,
                seenIDs: &seenIDs,
                into: &sources
            )
        }

        for path in settings.effectiveSourceRoots {
            discoverConfiguredPath(
                path,
                profile: profile,
                preferredLocationKind: .directory,
                maxDepth: settings.maxScanDepth,
                maxCandidates: settings.maxScanCandidates,
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

    private func discoverConfiguredPath(
        _ path: String,
        profile: TokenCostSourceProfile,
        preferredLocationKind: TokenCostSourceLocationKind,
        maxDepth: Int,
        maxCandidates: Int,
        seenIDs: inout Set<String>,
        into sources: inout [TokenCostSource]
    ) {
        let locationURL = TokenCostPathUtilities.expandedURL(from: path)
        let canonicalLocationURL = TokenCostPathUtilities.canonicalURL(locationURL)

        guard isValidScanRoot(canonicalLocationURL) else {
            return
        }

        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: canonicalLocationURL.path, isDirectory: &isDirectory) else {
            return
        }

        if isDirectory.boolValue {
            scanDirectory(
                canonicalLocationURL,
                profile: profile,
                locationURL: canonicalLocationURL,
                preferredLocationKind: .directory,
                maxDepth: maxDepth,
                maxCandidates: maxCandidates,
                seenIDs: &seenIDs,
                into: &sources
            )
            return
        }

        if let source = makeSource(
            from: canonicalLocationURL,
            profile: profile,
            locationKind: .file,
            locationURL: canonicalLocationURL
        ) {
            append(source, seenIDs: &seenIDs, into: &sources)
        }
    }

    private func scanDirectory(
        _ root: URL,
        profile: TokenCostSourceProfile,
        locationURL: URL,
        preferredLocationKind: TokenCostSourceLocationKind,
        maxDepth: Int,
        maxCandidates: Int,
        seenIDs: inout Set<String>,
        into sources: inout [TokenCostSource]
    ) {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }

        var discovered = 0
        for case let itemURL as URL in enumerator {
            let canonicalItemURL = TokenCostPathUtilities.canonicalURL(itemURL)
            guard TokenCostPathUtilities.isDescendant(canonicalItemURL, of: root) else {
                continue
            }

            let relativeDepth = canonicalItemURL.pathComponents.count - root.pathComponents.count
            if relativeDepth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            if discovered >= maxCandidates {
                break
            }

            guard profile.matchesCandidateFile(canonicalItemURL) else {
                continue
            }

            discovered += 1
            if let source = makeSource(
                from: canonicalItemURL,
                profile: profile,
                locationKind: preferredLocationKind,
                locationURL: locationURL
            ) {
                append(source, seenIDs: &seenIDs, into: &sources)
            }
        }
    }

    private func makeSource(
        from url: URL,
        profile: TokenCostSourceProfile,
        locationKind: TokenCostSourceLocationKind,
        locationURL: URL?
    ) -> TokenCostSource? {
        let normalized = TokenCostPathUtilities.canonicalURL(url)
        let identifier = TokenCostPaths.stableIdentifier(for: normalized.path)
        let status = probe.probe(at: normalized)
        let modificationDate = modificationDate(for: normalized)

        let messageKind: TokenCostSourceStatusMessageKind
        switch status {
        case .available:
            messageKind = .available
        case .missing:
            messageKind = .missingPath
        case .locked:
            messageKind = .lockedFile
        case .unsupported:
            messageKind = .unsupportedSchema
        case .unknown:
            messageKind = .unknown
        }

        return TokenCostSource(
            id: identifier,
            name: displayName(for: normalized),
            sourceFamily: profile.family,
            locationKind: locationKind,
            sourceURL: normalized,
            locationURL: locationURL,
            status: status,
            statusMessageKind: messageKind,
            lastModified: modificationDate,
            isReadOnly: true
        )
    }

    private func append(_ source: TokenCostSource, seenIDs: inout Set<String>, into sources: inout [TokenCostSource]) {
        guard seenIDs.insert(source.id).inserted else {
            return
        }
        sources.append(source)
    }

    private func displayName(for url: URL) -> String {
        let fileName = url.deletingPathExtension().lastPathComponent
        if fileName.isEmpty {
            return url.lastPathComponent
        }
        return fileName
    }

    private func modificationDate(for url: URL) -> String? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else {
            return nil
        }
        return ISO8601DateFormatter().string(from: date)
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

    private static let forbiddenScanRoots: Set<String> = ["/", "/System", "/Users", "/Applications", "/Library", "/private", "/.Trash"]

    private func isValidScanRoot(_ url: URL) -> Bool {
        let path = url.path
        guard !Self.forbiddenScanRoots.contains(path) else { return false }
        return true
    }
}
