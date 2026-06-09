import Foundation

public enum BackupInterval: String, Codable, CaseIterable, Identifiable, Sendable {
    case hourly
    case daily
    case weekly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .hourly: return AppLocalization.text("settings.backup.interval.hourly")
        case .daily: return AppLocalization.text("settings.backup.interval.daily")
        case .weekly: return AppLocalization.text("settings.backup.interval.weekly")
        }
    }

    public var timeInterval: TimeInterval {
        switch self {
        case .hourly: return 3600
        case .daily: return 86400
        case .weekly: return 604800
        }
    }
}

// MARK: - BackupFileType

public enum BackupFileType: String, Codable, Sendable, Hashable {
    case flat       // 扁平文件备份（单个配置文件）
    case layered    // 分层目录备份（backup-YYYY-MM-DD_HHMM/）
}

// MARK: - BakFileSortOrder

public enum BakFileSortOrder: String, CaseIterable, Identifiable, Sendable {
    case newestFirst
    case oldestFirst

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .newestFirst: return AppLocalization.text("settings.backup.sortNewest")
        case .oldestFirst: return AppLocalization.text("settings.backup.sortOldest")
        }
    }
}

// MARK: - BackupLayer

public enum BackupLayer: String, CaseIterable, Identifiable, Sendable {
    case globalEntry
    case globalMemory
    case commandsSnapshot
    case configSnapshot
    case skillsSnapshot
    case scripts
    case launchd

    public var id: String { rawValue }

    public var directoryName: String {
        switch self {
        case .globalEntry: return "global-entry"
        case .globalMemory: return "global-memory"
        case .commandsSnapshot: return "commands-snapshot"
        case .configSnapshot: return "config-snapshot"
        case .skillsSnapshot: return "skills-snapshot"
        case .scripts: return "scripts"
        case .launchd: return "launchd"
        }
    }

    public var displayName: String {
        switch self {
        case .globalEntry: return AppLocalization.text("settings.backup.layer.globalEntry")
        case .globalMemory: return AppLocalization.text("settings.backup.layer.globalMemory")
        case .commandsSnapshot: return AppLocalization.text("settings.backup.layer.commandsSnapshot")
        case .configSnapshot: return AppLocalization.text("settings.backup.layer.configSnapshot")
        case .skillsSnapshot: return AppLocalization.text("settings.backup.layer.skillsSnapshot")
        case .scripts: return AppLocalization.text("settings.backup.layer.scripts")
        case .launchd: return AppLocalization.text("settings.backup.layer.launchd")
        }
    }

    public var iconName: String {
        switch self {
        case .globalEntry: return "doc.text"
        case .globalMemory: return "brain"
        case .commandsSnapshot: return "terminal"
        case .configSnapshot: return "gearshape"
        case .skillsSnapshot: return "gearshape.2"
        case .scripts: return "scroll"
        case .launchd: return "clock.arrow"
        }
    }
}

// MARK: - ConfigFileGroup

public struct ConfigFileGroup: Identifiable, Sendable {
    public let id: String
    public let groupName: String
    public let files: [ConfigFileStatus]
    public let isDeprecated: Bool

    public init(id: String, groupName: String, files: [ConfigFileStatus], isDeprecated: Bool) {
        self.id = id
        self.groupName = groupName
        self.files = files
        self.isDeprecated = isDeprecated
    }

    public var allFilesExist: Bool {
        files.allSatisfy { $0.sourceExists }
    }

    public var anyBackedUp: Bool {
        files.contains { $0.hasBackup }
    }

    public var lastBackupDate: Date? {
        files.compactMap { $0.lastBackupDate }.max()
    }
}

// MARK: - ConfigFileStatus

public struct ConfigFileStatus: Identifiable, Sendable {
    public let id: String
    public let fileName: String
    public let sourcePath: String
    public let sourceExists: Bool
    public let hasBackup: Bool
    public let lastBackupDate: Date?
    public let backupRecordPath: String?

    public init(fileName: String, sourcePath: String, sourceExists: Bool, hasBackup: Bool, lastBackupDate: Date?, backupRecordPath: String?) {
        self.id = fileName
        self.fileName = fileName
        self.sourcePath = sourcePath
        self.sourceExists = sourceExists
        self.hasBackup = hasBackup
        self.lastBackupDate = lastBackupDate
        self.backupRecordPath = backupRecordPath
    }
}

// MARK: - BackupLayerResult

public struct BackupLayerResult: Identifiable, Sendable {
    public let id: String
    public let layer: BackupLayer
    public let fileCount: Int
    public let totalBytes: Int64
    public let error: String?

    public init(layer: BackupLayer, fileCount: Int, totalBytes: Int64, error: String?) {
        self.id = layer.rawValue
        self.layer = layer
        self.fileCount = fileCount
        self.totalBytes = totalBytes
        self.error = error
    }

    public var isSuccessful: Bool { error == nil }
    public var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

// MARK: - FullBackupResult

public struct FullBackupResult: Sendable {
    public let timestampDir: String
    public let layers: [BackupLayerResult]
    public let totalFiles: Int
    public let totalBytes: Int64

    public init(timestampDir: String, layers: [BackupLayerResult]) {
        self.timestampDir = timestampDir
        self.layers = layers
        self.totalFiles = layers.reduce(0) { $0 + $1.fileCount }
        self.totalBytes = layers.reduce(0) { $0 + $1.totalBytes }
    }

    public var allSuccessful: Bool {
        layers.allSatisfy { $0.isSuccessful }
    }

    public var totalSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

// MARK: - BackupPreferences

public struct BackupPreferences: Codable, Equatable, Sendable {
    /// 外部备份目录路径（绝对路径字符串）
    public var backupDirectory: String
    /// 是否启用自动备份
    public var autoBackupEnabled: Bool
    /// 自动备份间隔
    public var autoBackupInterval: BackupInterval
    /// 是否启用自动清理
    public var autoCleanEnabled: Bool
    /// 自动清理时保留最近 N 份备份
    public var autoCleanKeepCount: Int
    /// 最近一次备份时间
    public var lastBackupDate: Date?
    /// 最近一次清理时间
    public var lastCleanDate: Date?
    /// 是否显示已弃用文件（oh-my-opencode）
    public var showDeprecatedFiles: Bool
    /// 分层备份轮转保留份数
    public var maxBackupCount: Int
    /// 分层备份启用的内容层（默认全部启用）
    public var enabledLayers: Set<BackupLayer>

    public init(
        backupDirectory: String = defaultBackupDirectory(),
        autoBackupEnabled: Bool = false,
        autoBackupInterval: BackupInterval = .daily,
        autoCleanEnabled: Bool = false,
        autoCleanKeepCount: Int = 10,
        lastBackupDate: Date? = nil,
        lastCleanDate: Date? = nil,
        showDeprecatedFiles: Bool = false,
        maxBackupCount: Int = 4,
        enabledLayers: Set<BackupLayer> = Set(BackupLayer.allCases)
    ) {
        self.backupDirectory = backupDirectory
        self.autoBackupEnabled = autoBackupEnabled
        self.autoBackupInterval = autoBackupInterval
        self.autoCleanEnabled = autoCleanEnabled
        self.autoCleanKeepCount = max(1, min(autoCleanKeepCount, 100))
        self.lastBackupDate = lastBackupDate
        self.lastCleanDate = lastCleanDate
        self.showDeprecatedFiles = showDeprecatedFiles
        self.maxBackupCount = max(1, min(maxBackupCount, 50))
        self.enabledLayers = enabledLayers
    }

    private enum CodingKeys: String, CodingKey {
        case backupDirectory = "backup_directory"
        case autoBackupEnabled = "auto_backup_enabled"
        case autoBackupInterval = "auto_backup_interval"
        case autoCleanEnabled = "auto_clean_enabled"
        case autoCleanKeepCount = "auto_clean_keep_count"
        case lastBackupDate = "last_backup_date"
        case lastCleanDate = "last_clean_date"
        case showDeprecatedFiles = "show_deprecated_files"
        case maxBackupCount = "max_backup_count"
        case enabledLayers = "enabled_layers"
    }

    private enum DecodingKeys: String, CodingKey {
        case backupDirectory = "backupDirectory"
        case autoBackupEnabled = "autoBackupEnabled"
        case autoBackupInterval = "autoBackupInterval"
        case autoCleanEnabled = "autoCleanEnabled"
        case autoCleanKeepCount = "autoCleanKeepCount"
        case lastBackupDate = "lastBackupDate"
        case lastCleanDate = "lastCleanDate"
        case showDeprecatedFiles = "showDeprecatedFiles"
        case maxBackupCount = "maxBackupCount"
        case enabledLayers = "enabledLayers"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DecodingKeys.self)
        let legacyContainer = try? decoder.container(keyedBy: CodingKeys.self)

        self.backupDirectory = try container.decodeIfPresent(String.self, forKey: .backupDirectory)
            ?? legacyContainer?.decodeIfPresent(String.self, forKey: .backupDirectory)
            ?? BackupPreferences.defaultBackupDirectory()
        self.autoBackupEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoBackupEnabled)
            ?? legacyContainer?.decodeIfPresent(Bool.self, forKey: .autoBackupEnabled)
            ?? false
        self.autoBackupInterval = try container.decodeIfPresent(BackupInterval.self, forKey: .autoBackupInterval)
            ?? legacyContainer?.decodeIfPresent(BackupInterval.self, forKey: .autoBackupInterval)
            ?? .daily
        self.autoCleanEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoCleanEnabled)
            ?? legacyContainer?.decodeIfPresent(Bool.self, forKey: .autoCleanEnabled)
            ?? false
        self.autoCleanKeepCount = try container.decodeIfPresent(Int.self, forKey: .autoCleanKeepCount)
            ?? legacyContainer?.decodeIfPresent(Int.self, forKey: .autoCleanKeepCount)
            ?? 10
        self.lastBackupDate = try container.decodeIfPresent(Date.self, forKey: .lastBackupDate)
            ?? legacyContainer?.decodeIfPresent(Date.self, forKey: .lastBackupDate)
        self.lastCleanDate = try container.decodeIfPresent(Date.self, forKey: .lastCleanDate)
            ?? legacyContainer?.decodeIfPresent(Date.self, forKey: .lastCleanDate)
        self.showDeprecatedFiles = try container.decodeIfPresent(Bool.self, forKey: .showDeprecatedFiles)
            ?? legacyContainer?.decodeIfPresent(Bool.self, forKey: .showDeprecatedFiles)
            ?? false
        self.maxBackupCount = try container.decodeIfPresent(Int.self, forKey: .maxBackupCount)
            ?? legacyContainer?.decodeIfPresent(Int.self, forKey: .maxBackupCount)
            ?? 4
        let layerRawValues = try container.decodeIfPresent([String].self, forKey: .enabledLayers)
            ?? legacyContainer?.decodeIfPresent([String].self, forKey: .enabledLayers)
        self.enabledLayers = layerRawValues.flatMap { Set($0.compactMap { BackupLayer(rawValue: $0) }) }
            ?? Set(BackupLayer.allCases)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(backupDirectory, forKey: .backupDirectory)
        try container.encode(autoBackupEnabled, forKey: .autoBackupEnabled)
        try container.encode(autoBackupInterval, forKey: .autoBackupInterval)
        try container.encode(autoCleanEnabled, forKey: .autoCleanEnabled)
        try container.encode(autoCleanKeepCount, forKey: .autoCleanKeepCount)
        try container.encodeIfPresent(lastBackupDate, forKey: .lastBackupDate)
        try container.encodeIfPresent(lastCleanDate, forKey: .lastCleanDate)
        try container.encode(showDeprecatedFiles, forKey: .showDeprecatedFiles)
        try container.encode(maxBackupCount, forKey: .maxBackupCount)
        try container.encode(Array(enabledLayers.map { $0.rawValue }), forKey: .enabledLayers)
    }

    /// 默认备份目录（与 backup-memory.sh 的 BACKUP_ROOT 一致）
    public static func defaultBackupDirectory() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Documents/Opencode project/记忆备份", isDirectory: true).path
    }
}

// MARK: - 备份文件记录

public struct BackupFileRecord: Identifiable, Hashable, Sendable {
    public let id: String
    public let fileName: String
    public let sourceFileName: String
    public let path: String
    public let byteCount: Int64
    public let createdAt: Date?
    public let backupType: BackupFileType
    public var idValue: String { id }

    public init(fileName: String, sourceFileName: String, path: String, byteCount: Int64, createdAt: Date?, backupType: BackupFileType = .flat) {
        self.id = path
        self.fileName = fileName
        self.sourceFileName = sourceFileName
        self.path = path
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.backupType = backupType
    }
}

// MARK: - .bak 文件信息

public struct BakFileInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let fileName: String
    public let path: String
    public let byteCount: Int64
    public let modifiedAt: Date?
    public let creationDate: Date?

    public init(fileName: String, path: String, byteCount: Int64, modifiedAt: Date?, creationDate: Date? = nil) {
        self.id = path
        self.fileName = fileName
        self.path = path
        self.byteCount = byteCount
        self.modifiedAt = modifiedAt
        self.creationDate = creationDate
    }

    public var displayDate: Date? { creationDate ?? modifiedAt }

    public var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

// MARK: - 备份完备性报告

public struct BackupCompletenessReport: Sendable {
    /// 预期应备份的文件清单
    public let expectedFiles: [String]
    /// 已备份的文件名
    public let backedUpFiles: [String]
    /// 缺失的文件名
    public let missingFiles: [String]
    /// 覆盖率 0.0~1.0
    public let coverage: Double
    /// 按组报告（仅 config 文件）
    public let groupReports: [String: Bool]

    public init(expectedFiles: [String], backedUpFiles: [String], groupReports: [String: Bool] = [:]) {
        self.expectedFiles = expectedFiles
        self.backedUpFiles = backedUpFiles
        let backedSet = Set(backedUpFiles.map { $0.lowercased() })
        self.missingFiles = expectedFiles.filter { !backedSet.contains($0.lowercased()) }
        self.coverage = expectedFiles.isEmpty ? 1.0 : Double(expectedFiles.count - missingFiles.count) / Double(expectedFiles.count)
        self.groupReports = groupReports
    }

    public var coveragePercent: String {
        String(format: "%.0f%%", coverage * 100)
    }

    public var isComplete: Bool {
        missingFiles.isEmpty
    }
}

// MARK: - 备份概览

public struct BackupOverview: Sendable {
    public let fileCount: Int
    public let totalByteCount: Int64
    public let lastBackupDate: Date?
    public let directoryPath: String
    /// 分层备份（backup-* 目录）数量
    public let layeredBackupCount: Int
    /// 扁平配置文件备份数量
    public let flatFileCount: Int

    public init(
        fileCount: Int,
        totalByteCount: Int64,
        lastBackupDate: Date?,
        directoryPath: String,
        layeredBackupCount: Int = 0,
        flatFileCount: Int = 0
    ) {
        self.fileCount = fileCount
        self.totalByteCount = totalByteCount
        self.lastBackupDate = lastBackupDate
        self.directoryPath = directoryPath
        self.layeredBackupCount = layeredBackupCount
        self.flatFileCount = flatFileCount
    }

    public var totalSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalByteCount, countStyle: .file)
    }
}
