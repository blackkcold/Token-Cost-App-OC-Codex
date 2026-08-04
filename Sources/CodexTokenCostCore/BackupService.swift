import CryptoKit
import Foundation

public enum BackupServiceError: LocalizedError {
    case sourceFileNotFound(String)
    case backupDirectoryNotWritable(String)
    case backupWriteFailed(String)
    case directoryCreationFailed(String)
    case readError(String)
    case pathOutOfBounds(String)

    public var errorDescription: String? {
        switch self {
        case .sourceFileNotFound(let name):
            return "Source file not found: \(name)"
        case .backupDirectoryNotWritable(let path):
            return "Backup directory not writable: \(path)"
        case .backupWriteFailed(let detail):
            return "Backup write failed: \(detail)"
        case .directoryCreationFailed(let path):
            return "Failed to create directory: \(path)"
        case .readError(let detail):
            return "Read error: \(detail)"
        case .pathOutOfBounds(let detail):
            return "Path out of bounds: \(detail)"
        }
    }
}

public final class BackupService: @unchecked Sendable {
    private let fm = FileManager.default
    private let homeDir = FileManager.default.homeDirectoryForCurrentUser
    private let backupLock = NSLock()

    private var opencodeConfigDir: URL {
        homeDir.appendingPathComponent(".config/opencode", isDirectory: true)
    }

    private var opencodeMemoryDir: URL {
        opencodeConfigDir.appendingPathComponent("memory", isDirectory: true)
    }

    private var opencodeCommandsDir: URL {
        opencodeConfigDir.appendingPathComponent("commands", isDirectory: true)
    }

    private var opencodeSkillsDir: URL {
        opencodeConfigDir.appendingPathComponent("skills", isDirectory: true)
    }

    private var opencodeScriptsDir: URL {
        opencodeConfigDir.appendingPathComponent("scripts", isDirectory: true)
    }

    private var launchdPlistURL: URL {
        homeDir.appendingPathComponent("Library/LaunchAgents/com.opencode.memory-backup.plist")
    }

    public static let globalMemoryFiles: [String] = [
        "USER_CORE.md", "PREFS_INDEX.md", "FILE_OUTPUT_RULES.md",
        "RESEARCH_RULES.md", "WORKFLOW_PREFS.md", "SAFETY_RULES.md",
        "CAPACITY_RULES.md", "MEMORY_BACKUP.md", "USER_PROFILE.md"
    ]

    public static let scriptFiles: [String] = [
        "backup-memory.sh", "check-backup.sh", "rollback-memory.sh",
        "README-backup-v2.md"
    ]

    public static var allKnownConfigFiles: [String] {
        ["opencode.json", "opencode.jsonc",
         "oh-my-openagent.json", "oh-my-openagent.jsonc",
         "oh-my-opencode.json", "oh-my-opencode.jsonc",
         "AGENTS.md", "openpets.md"]
    }

    public static func configFileGroups(showDeprecated: Bool, backupRecords: [BackupFileRecord], latestLayeredDir: String? = nil) -> [ConfigFileGroup] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let configDir = home.appendingPathComponent(".config/opencode")

        func makeStatus(_ fileName: String) -> ConfigFileStatus {
            let sourceURL = configDir.appendingPathComponent(fileName)
            let sourceExists = fm.fileExists(atPath: sourceURL.path)
            // 1) 优先检查 flat 备份记录
            let flatRecord = backupRecords.first {
                $0.sourceFileName == fileName && $0.backupType == .flat
            }
            // 2) 其次检查最新 layered 备份目录（文件系统存在性为准，
            //    不依赖传入数组是否包含 layered 记录——verifyCompleteness 传的是 flat-only）
            var layeredExists = false
            var layeredRecord: BackupFileRecord?
            if let layeredDir = latestLayeredDir {
                let configSnapshotDir = URL(fileURLWithPath: layeredDir).appendingPathComponent("config-snapshot")
                let globalEntryDir = URL(fileURLWithPath: layeredDir).appendingPathComponent("global-entry")
                let layeredFile = configSnapshotDir.appendingPathComponent(fileName)
                let entryFile = globalEntryDir.appendingPathComponent(fileName)
                if fm.fileExists(atPath: layeredFile.path) || fm.fileExists(atPath: entryFile.path) {
                    layeredExists = true
                    layeredRecord = backupRecords.first { $0.backupType == .layered }
                }
            }
            let matchedRecord = flatRecord ?? layeredRecord
            return ConfigFileStatus(
                fileName: fileName,
                sourcePath: sourceURL.path,
                sourceExists: sourceExists,
                hasBackup: (flatRecord != nil) || layeredExists,
                lastBackupDate: matchedRecord?.createdAt,
                backupRecordPath: matchedRecord?.path
            )
        }

        var groups: [ConfigFileGroup] = [
            ConfigFileGroup(
                id: "opencode",
                groupName: AppLocalization.text("settings.backup.group.opencode"),
                files: [makeStatus("opencode.json"), makeStatus("opencode.jsonc")],
                isDeprecated: false
            ),
            ConfigFileGroup(
                id: "omo",
                groupName: AppLocalization.text("settings.backup.group.omo"),
                files: [makeStatus("oh-my-openagent.json"), makeStatus("oh-my-openagent.jsonc")],
                isDeprecated: false
            ),
            ConfigFileGroup(
                id: "agents",
                groupName: AppLocalization.text("settings.backup.group.agents"),
                files: [makeStatus("AGENTS.md"), makeStatus("openpets.md")],
                isDeprecated: false
            ),
        ]

        if showDeprecated {
            groups.append(ConfigFileGroup(
                id: "deprecated",
                groupName: AppLocalization.text("settings.backup.group.deprecated"),
                files: [makeStatus("oh-my-opencode.json"), makeStatus("oh-my-opencode.jsonc")],
                isDeprecated: true
            ))
        }

        return groups
    }

    public init() {}

    private func isWithinOpenCodeConfigDir(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(opencodeConfigDir.standardizedFileURL.path)
    }

    private func safeFileStore(for directory: String) throws -> SafeFileStore {
        let url = URL(fileURLWithPath: directory).standardizedFileURL.resolvingSymlinksInPath()
        return SafeFileStore(root: url)
    }

    private func ensureBackupDirectory(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        if !fm.fileExists(atPath: url.path) {
            do {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                throw BackupServiceError.directoryCreationFailed(path)
            }
        }
        guard fm.isWritableFile(atPath: url.path) else {
            throw BackupServiceError.backupDirectoryNotWritable(path)
        }
    }

    private func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        let raw = formatter.string(from: Date())
        return raw
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }

    private func backupTimestampDirName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return "backup-\(formatter.string(from: Date()))"
    }

    private func copyFileIfExists(from src: URL, to dst: URL) throws -> Bool {
        guard fm.fileExists(atPath: src.path) else { return false }
        if fm.fileExists(atPath: dst.path) {
            try? fm.removeItem(at: dst)
        }
        try fm.copyItem(at: src, to: dst)
        return true
    }

    private func countFiles(in dir: URL) -> Int {
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: []) else {
            return 0
        }
        var count = 0
        for url in contents {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                count += countFiles(in: url)
            } else {
                count += 1
            }
        }
        return count
    }

    private func directorySize(in dir: URL) -> Int64 {
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    // MARK: - 配置文件备份（单文件 + 批量）

    public func backupConfigFile(_ fileName: String, to backupDir: String) throws -> BackupFileRecord {
        let sourceURL = opencodeConfigDir.appendingPathComponent(fileName)
        guard fm.fileExists(atPath: sourceURL.path) else {
            throw BackupServiceError.sourceFileNotFound(fileName)
        }
        try ensureBackupDirectory(at: backupDir)

        let store = try safeFileStore(for: backupDir)
        let data = try Data(contentsOf: sourceURL)

        let baseName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: fileName).pathExtension
        let extSuffix = ext.isEmpty ? "" : ".\(ext)"
        let backupFileName = "\(baseName)-\(timestamp())\(extSuffix)"

        try store.writeData(data, to: backupFileName)
        let backupURL = try store.resolve(backupFileName)
        let byteCount = Int64(data.count)

        return BackupFileRecord(
            fileName: backupFileName, sourceFileName: fileName,
            path: backupURL.path, byteCount: byteCount,
            createdAt: Date(), backupType: .flat
        )
    }

    public func backupAllConfigs(to backupDir: String, showDeprecated: Bool = false) throws -> [BackupFileRecord] {
        try ensureBackupDirectory(at: backupDir)
        var records: [BackupFileRecord] = []

        let files = showDeprecated
            ? Self.allKnownConfigFiles
            : Self.allKnownConfigFiles.filter { !$0.contains("oh-my-opencode") }

        for fileName in files {
            let sourceURL = opencodeConfigDir.appendingPathComponent(fileName)
            guard fm.fileExists(atPath: sourceURL.path) else { continue }
            do {
                let record = try backupConfigFile(fileName, to: backupDir)
                records.append(record)
            } catch {
                continue
            }
        }
        return records
    }

    // MARK: - 完整分层备份（对标 backup-memory.sh）

    public func performFullLayeredBackup(to backupRoot: String, enabledLayers: Set<BackupLayer> = Set(BackupLayer.allCases)) throws -> FullBackupResult {
        return try backupLock.withLock {
            try _performFullLayeredBackup(to: backupRoot, enabledLayers: enabledLayers)
        }
    }

    private func _performFullLayeredBackup(to backupRoot: String, enabledLayers: Set<BackupLayer>) throws -> FullBackupResult {
        try ensureBackupDirectory(at: backupRoot)
        let tsDirName = backupTimestampDirName()
        let tsDir = URL(fileURLWithPath: backupRoot).appendingPathComponent(tsDirName)
        try fm.createDirectory(at: tsDir, withIntermediateDirectories: true)

        var layerResults: [BackupLayerResult] = []
        let layers = BackupLayer.allCases.filter { enabledLayers.contains($0) }

        for layer in layers {
            let result: BackupLayerResult
            do {
                switch layer {
                case .globalEntry: result = try backupGlobalEntryLayer(to: tsDir)
                case .globalMemory: result = try backupGlobalMemoryLayer(to: tsDir)
                case .commandsSnapshot: result = try backupCommandsSnapshotLayer(to: tsDir)
                case .configSnapshot: result = try backupConfigSnapshotLayer(to: tsDir)
                case .skillsSnapshot: result = try backupSkillsSnapshotLayer(to: tsDir)
                case .scripts: result = try backupScriptsLayer(to: tsDir)
                case .launchd: result = try backupLaunchdLayer(to: tsDir)
                }
            } catch {
                result = BackupLayerResult(layer: layer, fileCount: 0, totalBytes: 0, error: error.localizedDescription)
            }
            layerResults.append(result)
        }

        try writeBackupManifest(to: tsDir, timestampDir: tsDirName)
        try writeBackupChecksums(to: tsDir)

        return FullBackupResult(timestampDir: tsDir.path, layers: layerResults)
    }

    private func backupGlobalEntryLayer(to tsDir: URL) throws -> BackupLayerResult {
        let destDir = tsDir.appendingPathComponent("global-entry")
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let src = opencodeConfigDir.appendingPathComponent("AGENTS.md")
        let dst = destDir.appendingPathComponent("AGENTS.md")
        _ = try copyFileIfExists(from: src, to: dst)
        let size = directorySize(in: destDir)
        let count = countFiles(in: destDir)
        return BackupLayerResult(layer: .globalEntry, fileCount: count, totalBytes: size, error: nil)
    }

    private func backupGlobalMemoryLayer(to tsDir: URL) throws -> BackupLayerResult {
        let destDir = tsDir.appendingPathComponent("global-memory")
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        var fileCount = 0
        for file in Self.globalMemoryFiles {
            let src = opencodeMemoryDir.appendingPathComponent(file)
            let dst = destDir.appendingPathComponent(file)
            if try copyFileIfExists(from: src, to: dst) { fileCount += 1 }
        }
        let size = directorySize(in: destDir)
        return BackupLayerResult(layer: .globalMemory, fileCount: fileCount, totalBytes: size, error: nil)
    }

    private func backupCommandsSnapshotLayer(to tsDir: URL) throws -> BackupLayerResult {
        let destDir = tsDir.appendingPathComponent("commands-snapshot")
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        guard fm.fileExists(atPath: opencodeCommandsDir.path) else {
            return BackupLayerResult(layer: .commandsSnapshot, fileCount: 0, totalBytes: 0, error: nil)
        }
        var fileCount = 0
        if let files = try? fm.contentsOfDirectory(at: opencodeCommandsDir, includingPropertiesForKeys: nil) {
            for src in files where src.pathExtension == "md" {
                let dst = destDir.appendingPathComponent(src.lastPathComponent)
                if try copyFileIfExists(from: src, to: dst) { fileCount += 1 }
            }
        }
        let size = directorySize(in: destDir)
        return BackupLayerResult(layer: .commandsSnapshot, fileCount: fileCount, totalBytes: size, error: nil)
    }

    private func backupConfigSnapshotLayer(to tsDir: URL) throws -> BackupLayerResult {
        let destDir = tsDir.appendingPathComponent("config-snapshot")
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let configFiles = Self.allKnownConfigFiles
        var fileCount = 0
        for file in configFiles {
            let src = opencodeConfigDir.appendingPathComponent(file)
            let dst = destDir.appendingPathComponent(file)
            if try copyFileIfExists(from: src, to: dst) { fileCount += 1 }
        }
        let size = directorySize(in: destDir)
        return BackupLayerResult(layer: .configSnapshot, fileCount: fileCount, totalBytes: size, error: nil)
    }

    private func backupSkillsSnapshotLayer(to tsDir: URL) throws -> BackupLayerResult {
        let destDir = tsDir.appendingPathComponent("skills-snapshot")
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let skillsDest = destDir.appendingPathComponent("skills")
        guard fm.fileExists(atPath: opencodeSkillsDir.path) else {
            return BackupLayerResult(layer: .skillsSnapshot, fileCount: 0, totalBytes: 0, error: nil)
        }
        try fm.createDirectory(at: skillsDest, withIntermediateDirectories: true)

        if let files = try? fm.contentsOfDirectory(at: opencodeSkillsDir, includingPropertiesForKeys: nil) {
            for src in files {
                let name = src.lastPathComponent
                if name.hasPrefix(".") || name.hasSuffix(".backup") { continue }
                let dst = skillsDest.appendingPathComponent(name)
                if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
                try fm.copyItem(at: src, to: dst)
            }
        }
        let count = countFiles(in: destDir)
        let size = directorySize(in: destDir)
        return BackupLayerResult(layer: .skillsSnapshot, fileCount: count, totalBytes: size, error: nil)
    }

    private func backupScriptsLayer(to tsDir: URL) throws -> BackupLayerResult {
        let destDir = tsDir.appendingPathComponent("scripts")
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        var fileCount = 0
        for file in Self.scriptFiles {
            let src = opencodeScriptsDir.appendingPathComponent(file)
            let dst = destDir.appendingPathComponent(file)
            if try copyFileIfExists(from: src, to: dst) { fileCount += 1 }
        }
        let size = directorySize(in: destDir)
        return BackupLayerResult(layer: .scripts, fileCount: fileCount, totalBytes: size, error: nil)
    }

    private func backupLaunchdLayer(to tsDir: URL) throws -> BackupLayerResult {
        let destDir = tsDir.appendingPathComponent("launchd")
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let dst = destDir.appendingPathComponent("com.opencode.memory-backup.plist")
        _ = try copyFileIfExists(from: launchdPlistURL, to: dst)
        let size = directorySize(in: destDir)
        let count = countFiles(in: destDir)
        return BackupLayerResult(layer: .launchd, fileCount: count, totalBytes: size, error: nil)
    }

    private func writeBackupManifest(to tsDir: URL, timestampDir: String) throws {
        let manifestURL = tsDir.appendingPathComponent("MANIFEST.md")
        let content = """
        # Backup Manifest

        ## Metadata
        | Field | Value |
        |-------|-------|
        | Timestamp | \(timestampDir.replacingOccurrences(of: "backup-", with: "")) |
        | Directory | \(tsDir.path) |
        | Architecture | global-entry + global-memory + commands-snapshot + config-snapshot + skills-snapshot + scripts + launchd |

        ## Restore
        Config / skills snapshots are reference-only. Diff or cherry-pick, never overwrite directly.

        ## Layers
        | Layer | Description |
        |-------|-------------|
        | global-entry/ | AGENTS.md — single global entry point |
        | global-memory/ | USER_CORE.md, PREFS_INDEX.md, SAFETY_RULES.md, CAPACITY_RULES.md, etc. |
        | commands-snapshot/ | Live command wrappers |
        | config-snapshot/ | AGENTS.md, oh-my-openagent.json, opencode.json |
        | skills-snapshot/ | Skills snapshot for traceability |
        | scripts/ | Backup system scripts |
        | launchd/ | macOS scheduled task plist |

        Generated by Token Cost App on \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short)).
        """
        try content.write(to: manifestURL, atomically: true, encoding: .utf8)
    }

    private func writeBackupChecksums(to tsDir: URL) throws {
        let checksumURL = tsDir.appendingPathComponent("CHECKSUMS.txt")
        var lines: [String] = []
        if let enumerator = fm.enumerator(at: tsDir, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                guard fileURL.lastPathComponent != "CHECKSUMS.txt" else { continue }
                guard fileURL.lastPathComponent != "MANIFEST.md" else { continue }
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                let hash = data.sha256Hex
                let relative = fileURL.path.replacingOccurrences(of: tsDir.path + "/", with: "")
                lines.append("\(hash)  ./\(relative)")
            }
        }
        lines.sort()
        try lines.joined(separator: "\n").write(to: checksumURL, atomically: true, encoding: .utf8)
    }

    public func rotateFullBackups(in root: String, keep: Int) throws {
        let url = URL(fileURLWithPath: root)
        guard fm.fileExists(atPath: url.path),
              let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
        else { return }

        let backupDirs = contents.filter {
            $0.lastPathComponent.hasPrefix("backup-") && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted {
            ($0.lastPathComponent) > ($1.lastPathComponent)
        }

        guard backupDirs.count > keep else { return }
        for dir in backupDirs.dropFirst(keep) {
            try? fm.removeItem(at: dir)
        }
    }

    // MARK: - 备份列表（双模式：扁平文件 + 时间戳目录）

    public func listBackups(in backupDir: String) -> [BackupFileRecord] {
        let url = URL(fileURLWithPath: backupDir)
        guard fm.fileExists(atPath: url.path),
              let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .isDirectoryKey], options: [.skipsHiddenFiles])
        else { return [] }

        var records: [BackupFileRecord] = []

        for fileURL in contents {
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let name = fileURL.lastPathComponent

            if isDir && name.hasPrefix("backup-") {
                let size = directorySize(in: fileURL)
                let date = extractDateFromBackupDir(name)
                records.append(BackupFileRecord(
                    fileName: name, sourceFileName: name, path: fileURL.path,
                    byteCount: size, createdAt: date, backupType: .layered
                ))
            } else if !isDir {
                guard let vals = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey]),
                      vals.isRegularFile ?? false
                else { continue }
                let sourceName = inferSourceFileName(name)
                records.append(BackupFileRecord(
                    fileName: name, sourceFileName: sourceName, path: fileURL.path,
                    byteCount: Int64(vals.fileSize ?? 0), createdAt: vals.creationDate, backupType: .flat
                ))
            }
        }

        return records.sorted {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }
    }

    private func extractDateFromBackupDir(_ name: String) -> Date? {
        let ts = name.replacingOccurrences(of: "backup-", with: "")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return formatter.date(from: ts)
    }

    private func inferSourceFileName(_ backupName: String) -> String {
        for known in Self.allKnownConfigFiles {
            if backupName.hasPrefix(URL(fileURLWithPath: known).deletingPathExtension().lastPathComponent) {
                return known
            }
        }
        return backupName
    }

    // MARK: - 清理

    public func cleanOldBackups(in backupDir: String, keep: Int) throws -> [URL] {
        let url = URL(fileURLWithPath: backupDir)
        guard fm.fileExists(atPath: url.path),
              let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey], options: [.skipsHiddenFiles])
        else { return [] }

        let sorted = contents.sorted { a, b in
            let aDate = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let bDate = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return aDate > bDate
        }

        let flatFiles = sorted.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
        let backupDirs = sorted.filter { url in
            url.lastPathComponent.hasPrefix("backup-") && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        var removed: [URL] = []
        if flatFiles.count > keep {
            for file in flatFiles.dropFirst(keep) {
                try? fm.removeItem(at: file)
                removed.append(file)
            }
        }
        if backupDirs.count > keep {
            for dir in backupDirs.dropFirst(keep) {
                try? fm.removeItem(at: dir)
                removed.append(dir)
            }
        }
        return removed
    }

    // MARK: - .bak 文件管理

    public func listUnmanagedBakFiles(sortOrder: BakFileSortOrder = .newestFirst) -> [BakFileInfo] {
        guard let contents = try? fm.contentsOfDirectory(
            at: opencodeConfigDir, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .fileSizeKey], options: []
        ) else { return [] }

        let files = contents.compactMap { url -> BakFileInfo? in
            let name = url.lastPathComponent
            guard isBakFileName(name) else { return nil }
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .fileSizeKey])
            return BakFileInfo(
                fileName: name, path: url.path,
                byteCount: Int64(vals?.fileSize ?? 0),
                modifiedAt: vals?.contentModificationDate,
                creationDate: vals?.creationDate
            )
        }

        switch sortOrder {
        case .newestFirst:
            return files.sorted { ($0.displayDate ?? .distantPast) > ($1.displayDate ?? .distantPast) }
        case .oldestFirst:
            return files.sorted { ($0.displayDate ?? .distantPast) < ($1.displayDate ?? .distantPast) }
        }
    }

    private func isBakFileName(_ name: String) -> Bool {
        if name.hasSuffix(".original") { return true }
        let patterns = [".bak-", ".bak.", ".backup-", ".backup."]
        for p in patterns where name.contains(p) { return true }
        if name.hasSuffix(".bak") || name.hasSuffix(".backup") { return true }
        return false
    }

    public func trashUnmanagedBakFiles(_ files: [BakFileInfo]) throws {
        for file in files {
            let url = URL(fileURLWithPath: file.path)
            guard fm.fileExists(atPath: url.path), isWithinOpenCodeConfigDir(url) else { continue }
            var resultingItem: NSURL?
            try fm.trashItem(at: url, resultingItemURL: &resultingItem)
        }
    }

    // MARK: - 概览与完备性

    public func overview(in backupDir: String) -> BackupOverview {
        let records = listBackups(in: backupDir)
        let totalBytes = records.reduce(0) { $0 + $1.byteCount }
        let latestDate = records.first?.createdAt
        let layered = records.filter { $0.backupType == .layered }.count
        let flat = records.filter { $0.backupType == .flat }.count
        return BackupOverview(
            fileCount: records.count, totalByteCount: totalBytes,
            lastBackupDate: latestDate, directoryPath: backupDir,
            layeredBackupCount: layered, flatFileCount: flat
        )
    }

    public func verifyCompleteness(
        in backupDir: String,
        showDeprecated: Bool = false
    ) -> BackupCompletenessReport {
        let records = listBackups(in: backupDir)
        let flatRecords = records.filter { $0.backupType == .flat }
        var backedUpSourceNames = Set(flatRecords.map { $0.sourceFileName })

        let latestLayered = records.first { $0.backupType == .layered }
        let latestLayeredDir = latestLayered?.path

        if let layeredDir = latestLayeredDir {
            let configSnapshotDir = URL(fileURLWithPath: layeredDir).appendingPathComponent("config-snapshot")
            let globalEntryDir = URL(fileURLWithPath: layeredDir).appendingPathComponent("global-entry")
            for file in Self.allKnownConfigFiles {
                let layeredFile = configSnapshotDir.appendingPathComponent(file)
                let entryFile = globalEntryDir.appendingPathComponent(file)
                if fm.fileExists(atPath: layeredFile.path) || fm.fileExists(atPath: entryFile.path) {
                    backedUpSourceNames.insert(file)
                }
            }
        }

        let nonDeprecated = Self.allKnownConfigFiles.filter { !$0.contains("oh-my-opencode") }
        let existingFiles = nonDeprecated.filter { file in
            fm.fileExists(atPath: opencodeConfigDir.appendingPathComponent(file).path)
        }
        let groups = Self.configFileGroups(
            showDeprecated: showDeprecated,
            backupRecords: records,
            latestLayeredDir: latestLayeredDir
        )
        var groupReports: [String: Bool] = [:]
        for group in groups {
            groupReports[group.id] = group.anyBackedUp
        }

        return BackupCompletenessReport(
            expectedFiles: existingFiles,
            backedUpFiles: Array(backedUpSourceNames),
            groupReports: groupReports
        )
    }

    public func doesBakHaveExternalCopy(_ bakFile: BakFileInfo, backupDir: String) -> Bool {
        let records = listBackups(in: backupDir)
        let bakBaseName = bakFile.fileName
            .replacingOccurrences(of: ".bak", with: "")
            .replacingOccurrences(of: ".backup", with: "")
            .replacingOccurrences(of: ".original", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_."))

        return records.contains { record in
            let recordBase = URL(fileURLWithPath: record.sourceFileName).deletingPathExtension().lastPathComponent
            return bakBaseName.localizedCaseInsensitiveContains(recordBase)
                || recordBase.localizedCaseInsensitiveContains(bakBaseName)
        }
    }

    // MARK: - 备份内容层源状态

    public func layerSourceExists(_ layer: BackupLayer) -> Bool {
        switch layer {
        case .globalEntry:
            return fm.fileExists(atPath: opencodeConfigDir.appendingPathComponent("AGENTS.md").path)
        case .globalMemory:
            return fm.fileExists(atPath: opencodeMemoryDir.path)
        case .commandsSnapshot:
            return fm.fileExists(atPath: opencodeCommandsDir.path)
        case .configSnapshot:
            return Self.allKnownConfigFiles.contains {
                fm.fileExists(atPath: opencodeConfigDir.appendingPathComponent($0).path)
            }
        case .skillsSnapshot:
            return fm.fileExists(atPath: opencodeSkillsDir.path)
        case .scripts:
            return fm.fileExists(atPath: opencodeScriptsDir.path)
        case .launchd:
            return fm.fileExists(atPath: launchdPlistURL.path)
        }
    }

    // MARK: - launchd 定时任务管理

    public static let launchdLabel = "com.opencode.memory-backup"

    public var launchdPlistPath: String {
        launchdPlistURL.path
    }

    public func isLaunchdTaskLoaded() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.contains(Self.launchdLabel)
        } catch {
            return false
        }
    }

    public func writeLaunchdPlist(
        interval: BackupInterval,
        backupDirectory: String,
        keepCount: Int,
        enabledLayers: Set<BackupLayer>
    ) throws {
        let parentDir = launchdPlistURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parentDir.path) {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        var environment: [String: String] = [
            "OPENCODE_BACKUP_ROOT": backupDirectory,
            "MAX_BACKUPS": String(max(1, keepCount)),
        ]
        let layerValues = BackupLayer.allCases
            .filter { enabledLayers.contains($0) }
            .map { $0.rawValue }
        environment["OPENCODE_BACKUP_LAYERS"] = layerValues.joined(separator: ",")

        let scriptPath = opencodeScriptsDir.appendingPathComponent("backup-memory.sh").path

        let plist: [String: Any] = [
            "Label": Self.launchdLabel,
            "ProgramArguments": ["/bin/bash", scriptPath],
            "StartInterval": interval.timeInterval,
            "RunAtLoad": false,
            "StandardOutPath": opencodeConfigDir.appendingPathComponent("scripts/backup.log").path,
            "StandardErrorPath": opencodeConfigDir.appendingPathComponent("scripts/backup.log").path,
            "EnvironmentVariables": environment,
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: launchdPlistURL, options: .atomic)
    }

    public func setLaunchdTaskEnabled(_ enabled: Bool, config: LaunchdTaskConfiguration) throws {
        let plistExists = fm.fileExists(atPath: launchdPlistURL.path)
        if enabled {
            try writeLaunchdPlist(
                interval: config.interval,
                backupDirectory: config.backupDirectory,
                keepCount: config.keepCount,
                enabledLayers: config.enabledLayers
            )
            try runLaunchctl(["load", launchdPlistURL.path])
        } else {
            if plistExists {
                try runLaunchctl(["unload", launchdPlistURL.path])
            }
        }
    }

    private func runLaunchctl(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw BackupServiceError.backupWriteFailed("launchctl failed: \(error.localizedDescription)")
        }
    }

    // MARK: - .bak 与当前配置文件对比

    public func diffBakFile(_ bakFile: BakFileInfo) -> BakDiffResult {
        let targetName = inferTargetFileName(from: bakFile.fileName)
        let targetURL = opencodeConfigDir.appendingPathComponent(targetName)
        let targetExists = fm.fileExists(atPath: targetURL.path)

        guard targetExists,
              let bakData = try? Data(contentsOf: URL(fileURLWithPath: bakFile.path)),
              let targetData = try? Data(contentsOf: targetURL),
              let bakText = String(data: bakData, encoding: .utf8),
              let targetText = String(data: targetData, encoding: .utf8)
        else {
            return BakDiffResult(
                bakFileName: bakFile.fileName, targetFileName: targetName,
                targetExists: targetExists, addedCount: 0, removedCount: 0, lines: []
            )
        }

        let oldLines = bakText.components(separatedBy: .newlines)
        let newLines = targetText.components(separatedBy: .newlines)
        let diff = Self.computeLineDiff(oldLines, newLines)

        var added = 0
        var removed = 0
        var lines: [BakDiffLine] = []
        for (index, entry) in diff.enumerated() {
            switch entry {
            case .added(let text):
                added += 1
                lines.append(BakDiffLine(id: index, kind: .added, text: text))
            case .removed(let text):
                removed += 1
                lines.append(BakDiffLine(id: index, kind: .removed, text: text))
            case .context(let text):
                lines.append(BakDiffLine(id: index, kind: .context, text: text))
            }
        }

        return BakDiffResult(
            bakFileName: bakFile.fileName, targetFileName: targetName,
            targetExists: true, addedCount: added, removedCount: removed, lines: lines
        )
    }

    private func inferTargetFileName(from bakName: String) -> String {
        var base = bakName
        for suffix in [".original", ".backup", ".bak"] {
            if base.hasSuffix(suffix) {
                base = String(base.dropLast(suffix.count))
                break
            }
        }
        if let range = base.range(of: "-20") {
            base = String(base[..<range.lowerBound])
        }
        for known in Self.allKnownConfigFiles {
            if base == URL(fileURLWithPath: known).deletingPathExtension().lastPathComponent {
                return known
            }
        }
        return base
    }

    private enum DiffEntry {
        case added(String)
        case removed(String)
        case context(String)
    }

    private static func computeLineDiff(_ oldLines: [String], _ newLines: [String]) -> [DiffEntry] {
        let n = oldLines.count
        let m = newLines.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                if oldLines[i] == newLines[j] {
                    dp[i][j] = dp[i + 1][j + 1] + 1
                } else {
                    dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }

        var result: [DiffEntry] = []
        var i = 0
        var j = 0
        while i < n && j < m {
            if oldLines[i] == newLines[j] {
                result.append(.context(oldLines[i]))
                i += 1
                j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                result.append(.removed(oldLines[i]))
                i += 1
            } else {
                result.append(.added(newLines[j]))
                j += 1
            }
        }
        while i < n {
            result.append(.removed(oldLines[i]))
            i += 1
        }
        while j < m {
            result.append(.added(newLines[j]))
            j += 1
        }
        return result
    }
}

private extension Data {
    var sha256Hex: String {
        SHA256.hash(data: self).compactMap { String(format: "%02x", $0) }.joined()
    }
}
