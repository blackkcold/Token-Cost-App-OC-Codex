import Foundation

public enum OpenCodeSkillSourceKind: String, Codable, Sendable {
    case opencodePlural
    case opencodeSingular
    case claude
    case agents
    case configSkillsPath
    case customConfigDir
    case builtin
}

public struct OpenCodeSkillRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let canonicalPath: String
    public let displayPath: String
    public let sourceKind: OpenCodeSkillSourceKind
    public let manifest: OpenCodeSkillManifest
    public var duplicatePaths: [String]
    public let isSymlink: Bool
    public let targetCanonicalPath: String?

    public init(
        name: String,
        canonicalPath: String,
        displayPath: String,
        sourceKind: OpenCodeSkillSourceKind,
        manifest: OpenCodeSkillManifest,
        duplicatePaths: [String] = [],
        isSymlink: Bool = false,
        targetCanonicalPath: String? = nil
    ) {
        self.id = canonicalPath
        self.name = name
        self.canonicalPath = canonicalPath
        self.displayPath = displayPath
        self.sourceKind = sourceKind
        self.manifest = manifest
        self.duplicatePaths = duplicatePaths
        self.isSymlink = isSymlink
        self.targetCanonicalPath = targetCanonicalPath
    }
}

public enum OpenCodeSkillsScopeCoverage: String, Codable, Sendable {
    case scanned
    case excludedDueToError
    case notApplicable
}

public struct OpenCodeSkillsDiscoverResult {
    public let records: [OpenCodeSkillRecord]
    public let builtinSkills: [OpenCodeSkillRecord]
    public let warnings: [String]
    public let scannedPaths: [String: OpenCodeSkillsScopeCoverage]
    public let excludedPaths: [String]
    public let scanTimestamp: Date
    public let directoryErrors: [String: String]

    public init(
        records: [OpenCodeSkillRecord],
        builtinSkills: [OpenCodeSkillRecord] = [],
        warnings: [String] = [],
        scannedPaths: [String: OpenCodeSkillsScopeCoverage] = [:],
        excludedPaths: [String] = [],
        directoryErrors: [String: String] = [:]
    ) {
        self.records = records
        self.builtinSkills = builtinSkills
        self.warnings = warnings
        self.scannedPaths = scannedPaths
        self.excludedPaths = excludedPaths
        self.scanTimestamp = Date()
        self.directoryErrors = directoryErrors
    }
}

public enum OpenCodeSkillDiscovery {

    private static let homeDir = FileManager.default.homeDirectoryForCurrentUser

    private static let standardSourceRoots: [(OpenCodeSkillSourceKind, String)] = [
        (.opencodePlural, "~/.config/opencode/skills"),
        (.opencodeSingular, "~/.config/opencode/skill"),
        (.claude, "~/.claude/skills"),
        (.agents, "~/.agents/skills"),
    ]

    private static let allowedRootPaths: Set<String> = {
        let expanded: [String] = [
            "~/.config/opencode",
            "~/.claude",
            "~/.agents",
        ].map { TokenCostPathUtilities.canonicalPathString(from: $0) }
        return Set(expanded)
    }()

    // MARK: - Public API

    public static func discoverStandardSkills() -> OpenCodeSkillsDiscoverResult {
        var allRecords: [OpenCodeSkillRecord] = []
        var allWarnings: [String] = []
        var scannedPaths: [String: OpenCodeSkillsScopeCoverage] = [:]
        var excludedPaths: [String] = []
        var directoryErrors: [String: String] = [:]
        var seenCanonicalPaths: [String: Int] = [:]

        for (kind, rawPath) in standardSourceRoots {
            let expanded = TokenCostPathUtilities.expandedURL(from: rawPath)
            let canonical = TokenCostPathUtilities.canonicalURL(expanded)

            if !FileManager.default.fileExists(atPath: canonical.path) {
                scannedPaths[canonical.path] = .notApplicable
                continue
            }

            let result = scanDirectory(
                at: canonical,
                sourceKind: kind,
                isStandardRoot: true
            )

            scannedPaths[canonical.path] = result.coverage
            if let err = result.error {
                directoryErrors[canonical.path] = err
                allWarnings.append("Skipped directory: \(canonical.path) — \(err)")
                continue
            }

            for var record in result.records {
                let canonicalFile = TokenCostPathUtilities.canonicalURL(
                    URL(fileURLWithPath: record.canonicalPath)
                ).path

                if let existingIdx = seenCanonicalPaths[canonicalFile] {
                    var existing = allRecords[existingIdx]
                    if !existing.duplicatePaths.contains(record.displayPath) {
                        existing.duplicatePaths.append(record.displayPath)
                    }
                    allRecords[existingIdx] = existing
                    allWarnings.append("Duplicate skill '\(record.name)': \(record.displayPath) (same as \(existing.displayPath))")
                } else {
                    seenCanonicalPaths[canonicalFile] = allRecords.count
                    allRecords.append(record)
                }
            }
            for p in result.excluded {
                excludedPaths.append(p)
            }
            allWarnings.append(contentsOf: result.warnings)
        }

        let builtinSkills = discoverBuiltinSkills()

        return OpenCodeSkillsDiscoverResult(
            records: allRecords,
            builtinSkills: builtinSkills,
            warnings: allWarnings,
            scannedPaths: scannedPaths,
            excludedPaths: excludedPaths,
            directoryErrors: directoryErrors
        )
    }

    public static func discoverFromCustomPaths(_ paths: [String]) -> OpenCodeSkillsDiscoverResult {
        var allRecords: [OpenCodeSkillRecord] = []
        var allWarnings: [String] = []
        var scannedPaths: [String: OpenCodeSkillsScopeCoverage] = [:]
        var excludedPaths: [String] = []
        var directoryErrors: [String: String] = [:]

        for rawPath in paths {
            let expanded = TokenCostPathUtilities.expandedURL(from: rawPath)
            let canonical = TokenCostPathUtilities.canonicalURL(expanded)

            if !FileManager.default.fileExists(atPath: canonical.path) {
                scannedPaths[canonical.path] = .notApplicable
                allWarnings.append("Custom skill path not found: \(canonical.path)")
                continue
            }

            let result = scanDirectory(
                at: canonical,
                sourceKind: .configSkillsPath,
                isStandardRoot: false
            )

            scannedPaths[canonical.path] = result.coverage
            if let err = result.error {
                directoryErrors[canonical.path] = err
                allWarnings.append("Skipped custom directory: \(canonical.path) — \(err)")
                continue
            }

            for record in result.records {
                allRecords.append(record)
            }
            for p in result.excluded {
                excludedPaths.append(p)
            }
            allWarnings.append(contentsOf: result.warnings)
        }

        return OpenCodeSkillsDiscoverResult(
            records: allRecords,
            warnings: allWarnings,
            scannedPaths: scannedPaths,
            excludedPaths: excludedPaths,
            directoryErrors: directoryErrors
        )
    }

    public static func discoverFromCustomConfigDir(_ configDir: String) -> OpenCodeSkillsDiscoverResult {
        let expanded = TokenCostPathUtilities.expandedURL(from: configDir)
        let canonical = TokenCostPathUtilities.canonicalURL(expanded)

        var allRecords: [OpenCodeSkillRecord] = []
        var allWarnings: [String] = []
        var scannedPaths: [String: OpenCodeSkillsScopeCoverage] = [:]
        var excludedPaths: [String] = []
        var directoryErrors: [String: String] = [:]

        for sub in ["skills", "skill"] {
            let subDir = canonical.appendingPathComponent(sub)
            guard FileManager.default.fileExists(atPath: subDir.path) else {
                scannedPaths[subDir.path] = .notApplicable
                continue
            }

            let result = scanDirectory(
                at: subDir,
                sourceKind: .customConfigDir,
                isStandardRoot: false
            )
            scannedPaths[subDir.path] = result.coverage
            if let err = result.error {
                directoryErrors[subDir.path] = err
                allWarnings.append("Skipped custom config subdirectory: \(subDir.path) — \(err)")
                continue
            }
            allRecords.append(contentsOf: result.records)
            excludedPaths.append(contentsOf: result.excluded)
            allWarnings.append(contentsOf: result.warnings)
        }

        return OpenCodeSkillsDiscoverResult(
            records: allRecords,
            warnings: allWarnings,
            scannedPaths: scannedPaths,
            excludedPaths: excludedPaths,
            directoryErrors: directoryErrors
        )
    }

    // MARK: - Directory Scanning

    private struct DirectoryScanResult {
        let records: [OpenCodeSkillRecord]
        let warnings: [String]
        let excluded: [String]
        let coverage: OpenCodeSkillsScopeCoverage
        let error: String?
    }

    private static func scanDirectory(
        at url: URL,
        sourceKind: OpenCodeSkillSourceKind,
        isStandardRoot: Bool
    ) -> DirectoryScanResult {
        let fm = FileManager.default
        var records: [OpenCodeSkillRecord] = []
        var warnings: [String] = []
        var excluded: [String] = []

        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return DirectoryScanResult(
                records: [], warnings: [],
                excluded: [url.path],
                coverage: .excludedDueToError,
                error: "Cannot read directory: \(url.path)"
            )
        }

        let sortedContents = contents.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        for item in sortedContents {
            let skillMD = item.appendingPathComponent("SKILL.md")

            guard fm.fileExists(atPath: item.path), skillMD.path == skillMD.path else {
                continue
            }

            guard fm.fileExists(atPath: skillMD.path) else { continue }

            let canonicalItem = TokenCostPathUtilities.canonicalURL(item)
            let canonicalSkillMD = TokenCostPathUtilities.canonicalURL(skillMD)

            let isSymlink: Bool
            var targetCanonicalPath: String?
            do {
                let resourceValues = try item.resourceValues(forKeys: [.isSymbolicLinkKey])
                isSymlink = resourceValues.isSymbolicLink ?? false
                if isSymlink {
                    let resolved = try? fm.destinationOfSymbolicLink(atPath: item.path)
                    if let target = resolved {
                        let fullTarget: String
                        if target.hasPrefix("/") {
                            fullTarget = target
                        } else {
                            fullTarget = item.deletingLastPathComponent().appendingPathComponent(target).path
                        }
                        targetCanonicalPath = TokenCostPathUtilities.canonicalURL(
                            URL(fileURLWithPath: fullTarget)
                        ).path
                    }
                }
            } catch {
                isSymlink = false
                targetCanonicalPath = nil
            }

            if isSymlink, isStandardRoot, let target = targetCanonicalPath {
                if !isWithinAllowedRoots(target) {
                    warnings.append("Symlink outside allowed roots: \(item.path) -> \(target)")
                    excluded.append(item.path)
                    continue
                }
            }

            guard let content = try? String(contentsOf: skillMD, encoding: .utf8) else {
                warnings.append("Unreadable or non-UTF-8: \(skillMD.path)")
                excluded.append(skillMD.path)
                continue
            }

            let parentDirName = item.lastPathComponent
            let manifest = OpenCodeSkillManifestParser.parse(
                skillMDContent: content,
                sourcePath: canonicalSkillMD.path,
                parentDirectoryName: parentDirName
            )

            let displayName = manifest.name ?? parentDirName
            records.append(OpenCodeSkillRecord(
                name: displayName,
                canonicalPath: canonicalSkillMD.path,
                displayPath: item.path,
                sourceKind: sourceKind,
                manifest: manifest,
                isSymlink: isSymlink,
                targetCanonicalPath: targetCanonicalPath
            ))
        }

        return DirectoryScanResult(
            records: records,
            warnings: warnings,
            excluded: excluded,
            coverage: .scanned,
            error: nil
        )
    }

    // MARK: - Built-in Skills

    private static func discoverBuiltinSkills() -> [OpenCodeSkillRecord] {
        let builtinManifest = OpenCodeSkillManifest(
            name: "customize-opencode",
            description: "Use ONLY when the user is editing or creating opencode's own configuration",
            license: nil,
            compatibility: "opencode",
            metadata: nil,
            unknownFieldKeys: [],
            state: .valid,
            issues: [],
            sourcePath: "builtin://customize-opencode"
        )
        let record = OpenCodeSkillRecord(
            name: "customize-opencode",
            canonicalPath: "builtin://customize-opencode",
            displayPath: "builtin://customize-opencode",
            sourceKind: .builtin,
            manifest: builtinManifest
        )
        return [record]
    }

    // MARK: - Helpers

    private static func isWithinAllowedRoots(_ canonicalPath: String) -> Bool {
        for root in allowedRootPaths {
            if canonicalPath.hasPrefix(root + "/") || canonicalPath == root {
                return true
            }
        }
        return false
    }
}
