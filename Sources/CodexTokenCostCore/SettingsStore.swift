import Foundation

public struct SettingsLoadResult {
    public var settings: TokenCostSettings
    public var didFallbackToDefaults: Bool
    public var errorMessage: String?

    public init(settings: TokenCostSettings, didFallbackToDefaults: Bool, errorMessage: String? = nil) {
        self.settings = settings
        self.didFallbackToDefaults = didFallbackToDefaults
        self.errorMessage = errorMessage
    }
}

public final class SettingsStore {
    private let fileStore: SafeFileStore
    private let settingsRelativePath: String
    private let defaultSettings: () -> TokenCostSettings

    public init(
        runtimeRoot: URL = TokenCostPaths.runtimeRoot,
        settingsRelativePath: String = "config/settings.json",
        defaultSettings: @escaping () -> TokenCostSettings = { TokenCostSettings() }
    ) {
        self.fileStore = SafeFileStore(root: runtimeRoot)
        self.settingsRelativePath = settingsRelativePath
        self.defaultSettings = defaultSettings
    }

    public func load() -> SettingsLoadResult {
        do {
            let settings = try fileStore.readCodable(TokenCostSettings.self, from: settingsRelativePath)
            return SettingsLoadResult(settings: settings, didFallbackToDefaults: false)
        } catch {
            return SettingsLoadResult(
                settings: defaultSettings(),
                didFallbackToDefaults: true,
                errorMessage: error.localizedDescription
            )
        }
    }

    public func save(_ settings: TokenCostSettings) throws {
        try SettingsBackupRotation.backupIfPresent(
            fileStore: fileStore,
            relativePath: settingsRelativePath,
            backupDirectory: "config/backups/settings"
        )
        try fileStore.writeCodable(settings, to: settingsRelativePath)
    }
}

enum SettingsBackupRotation {
    static func backupIfPresent(
        fileStore: SafeFileStore,
        relativePath: String,
        backupDirectory: String,
        keep: Int = 10
    ) throws {
        let currentURL = try fileStore.resolve(relativePath)
        guard FileManager.default.fileExists(atPath: currentURL.path) else { return }

        let directory = try fileStore.resolve(backupDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let baseName = URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent
        let backupURL = directory.appendingPathComponent("\(baseName)-\(timestamp()).json")
        try? FileManager.default.removeItem(at: backupURL)
        try FileManager.default.copyItem(at: currentURL, to: backupURL)
        rotate(in: directory, keep: keep)
    }

    private static func rotate(in directory: URL, keep: Int) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let sorted = urls.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return lhsDate > rhsDate
        }
        for url in sorted.dropFirst(max(keep, 0)) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }
}

public final class SnapshotStore {
    private let fileStore: SafeFileStore

    public init(runtimeRoot: URL = TokenCostPaths.runtimeRoot) {
        self.fileStore = SafeFileStore(root: runtimeRoot)
    }

    public func loadLatest(sourceID: String) -> DashboardPayload? {
        let key = sourceKey(sourceID)
        do {
            return try fileStore.readCodable(DashboardPayload.self, from: "latest/\(key).json")
        } catch {
            return nil
        }
    }

    public func saveLatest(_ payload: DashboardPayload, sourceID: String, retention: Int) throws {
        let key = sourceKey(sourceID)
        try fileStore.writeCodable(payload, to: "latest/\(key).json")
        try fileStore.writeCodable(payload, to: "snapshots/\(key)/\(timestamp()).json")
        try rotateSnapshots(sourceKey: key, retention: max(retention, 1))
    }

    private func rotateSnapshots(sourceKey: String, retention: Int) throws {
        let snapshotDirectory = try fileStore.resolve("snapshots/\(sourceKey)")
        guard FileManager.default.fileExists(atPath: snapshotDirectory.path) else {
            return
        }
        let urls = try FileManager.default.contentsOfDirectory(at: snapshotDirectory, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
        let sorted = urls.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return lhsDate > rhsDate
        }
        guard sorted.count > retention else {
            return
        }
        for url in sorted.dropFirst(retention) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func sourceKey(_ sourceID: String) -> String {
        TokenCostPaths.stableIdentifier(for: sourceID)
    }

    private func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        let raw = formatter.string(from: Date())
        return raw
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }
}
