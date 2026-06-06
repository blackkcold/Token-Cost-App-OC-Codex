import Foundation

/// Developer Mode Optimize v1: Metadata-only file system scanner.
/// HARD CONSTRAINT: Does NOT read any file content. Uses only file attributes (size, dates, count).
public struct DeveloperFinding: Identifiable, Sendable {
    public let id = UUID()
    public let category: FindingCategory
    public let title: String
    public let detail: String
    public let suggestion: String

    public enum FindingCategory: String, Sendable {
        case staleSnapshot = "staleSnapshot"
        case excessBackup = "excessBackup"
        case largeSessionDir = "largeSessionDir"
        case configFragmentation = "configFragmentation"
        case staleLatest = "staleLatest"
    }
}

public enum OptimizeScanner: Sendable {
    private static let maxFindingsPerCategory = 5
    private static let maxTotalFindings = 100

    /// Run all metadata checks. Returns findings sorted by category.
    /// Only accesses file attributes — never reads file content.
    public static func scan() -> [DeveloperFinding] {
        var findings: [DeveloperFinding] = []

        findings.append(contentsOf: checkStaleSnapshots())
        findings.append(contentsOf: checkExcessBackups())
        findings.append(contentsOf: checkLargeSessionDir())
        findings.append(contentsOf: checkConfigFragmentation())
        findings.append(contentsOf: checkStaleLatest())

        return Array(findings.prefix(maxTotalFindings))
    }

    // MARK: - Individual Checks

    /// Check 1: Stale snapshots (older than 30 days)
    private static func checkStaleSnapshots() -> [DeveloperFinding] {
        let snapshotsDir = TokenCostPaths.snapshotRoot
        guard let sources = try? FileManager.default.contentsOfDirectory(
            at: snapshotsDir, includingPropertiesForKeys: [.creationDateKey]
        ) else { return [] }

        let threshold = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        var findings: [DeveloperFinding] = []

        for source in sources {
            guard source.hasDirectoryPath else { continue }
            guard let snapshots = try? FileManager.default.contentsOfDirectory(
                at: source, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            let stale = snapshots.filter { url in
                guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return false }
                return date < threshold
            }

            if !stale.isEmpty {
                findings.append(DeveloperFinding(
                    category: .staleSnapshot,
                    title: AppLocalization.text("developerMode.optimize.staleSnapshot.title"),
                    detail: AppLocalization.format("developerMode.optimize.staleSnapshot.detail", source.lastPathComponent, stale.count),
                    suggestion: AppLocalization.text("developerMode.optimize.staleSnapshot.suggestion")
                ))
                if findings.count >= maxFindingsPerCategory { break }
            }
        }
        return findings
    }

    /// Check 2: Excess backups (>20 files or >10MB)
    private static func checkExcessBackups() -> [DeveloperFinding] {
        var findings: [DeveloperFinding] = []
        let backupDirs = [
            TokenCostPaths.runtimeRoot.appendingPathComponent("config/backups/app-preferences"),
            TokenCostPaths.runtimeRoot.appendingPathComponent("config/backups/settings")
        ]

        for dir in backupDirs {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]
            ) else { continue }

            let totalSize = files.compactMap { url -> Int? in
                try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            }.reduce(0, +)

            if files.count > 20 || totalSize > 10 * 1024 * 1024 {
                findings.append(DeveloperFinding(
                    category: .excessBackup,
                    title: AppLocalization.text("developerMode.optimize.excessBackup.title"),
                    detail: AppLocalization.format("developerMode.optimize.excessBackup.detail", dir.lastPathComponent, files.count, totalSize / (1024 * 1024)),
                    suggestion: AppLocalization.text("developerMode.optimize.excessBackup.suggestion")
                ))
            }
            if findings.count >= maxFindingsPerCategory { break }
        }
        return findings
    }

    /// Check 3: Large session directory (>500MB)
    private static func checkLargeSessionDir() -> [DeveloperFinding] {
        let sessionsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return [] }

        let totalSize = files.compactMap { url -> Int? in
            try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        }.reduce(0, +)

        if totalSize > 500 * 1024 * 1024 {
            return [DeveloperFinding(
                category: .largeSessionDir,
                title: AppLocalization.text("developerMode.optimize.largeSession.title"),
                detail: AppLocalization.format("developerMode.optimize.largeSession.detail", totalSize / (1024 * 1024)),
                suggestion: AppLocalization.text("developerMode.optimize.largeSession.suggestion")
            )]
        }
        return []
    }

    /// Check 4: Config fragmentation (>5 .bak files)
    private static func checkConfigFragmentation() -> [DeveloperFinding] {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: configDir, includingPropertiesForKeys: nil
        ) else { return [] }

        let bakCount = files.filter { $0.lastPathComponent.hasPrefix(".bak-") }.count
        if bakCount > 5 {
            return [DeveloperFinding(
                category: .configFragmentation,
                title: AppLocalization.text("developerMode.optimize.configFrag.title"),
                detail: AppLocalization.format("developerMode.optimize.configFrag.detail", bakCount),
                suggestion: AppLocalization.text("developerMode.optimize.configFrag.suggestion")
            )]
        }
        return []
    }

    /// Check 5: Stale latest snapshot (>7 days)
    private static func checkStaleLatest() -> [DeveloperFinding] {
        let latestDir = TokenCostPaths.latestPayloadRoot
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: latestDir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }

        let threshold = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let stale = files.filter { url in
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return false }
            return date < threshold
        }

        if !stale.isEmpty {
            return [DeveloperFinding(
                category: .staleLatest,
                title: AppLocalization.text("developerMode.optimize.staleLatest.title"),
                detail: AppLocalization.format("developerMode.optimize.staleLatest.detail", stale.count),
                suggestion: AppLocalization.text("developerMode.optimize.staleLatest.suggestion")
            )]
        }
        return []
    }
}
