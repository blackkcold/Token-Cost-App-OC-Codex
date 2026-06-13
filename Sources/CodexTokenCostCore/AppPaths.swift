import Foundation

public enum TokenCostPaths {
    public static let appDisplayName = "Token Cost App - OC Codex"
    public static let bundleIdentifier = "com.yanghaoran.CodexTokenCost"
    public static let mainExecutableName = "CodexTokenCostApp"
    public static let helperExecutableName = "CodexTokenCostHelper"

    public static var applicationSupportRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    public static var bundleURL: URL {
        Bundle.main.bundleURL
    }

    public static var distDirectory: URL {
        bundleURL.deletingLastPathComponent()
    }

    public static var runtimeRoot: URL {
        applicationSupportRoot
    }

    public static var configURL: URL {
        runtimeRoot.appendingPathComponent("config/settings.json")
    }

    public static var latestPayloadRoot: URL {
        runtimeRoot.appendingPathComponent("latest", isDirectory: true)
    }

    public static var snapshotRoot: URL {
        runtimeRoot.appendingPathComponent("snapshots", isDirectory: true)
    }

    public static var logRoot: URL {
        runtimeRoot.appendingPathComponent("logs", isDirectory: true)
    }

    public static var helperBinaryURL: URL {
        bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent(helperExecutableName)
    }

    public static func ensureRuntimeDirectories() throws {
        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: latestPayloadRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapshotRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    public static func stableIdentifier(for string: String) -> String {
        string.utf8.map { String(format: "%02x", $0) }.joined()
    }

    public static func displayName(for sourceURL: URL) -> String {
        let fileName = sourceURL.deletingPathExtension().lastPathComponent
        if fileName.isEmpty {
            return sourceURL.lastPathComponent
        }
        return fileName
    }
}
