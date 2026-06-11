import Foundation
import CryptoKit
import CodexTokenCostCore

public final class CodexSnapshotStore {
    private let fileStore: SafeFileStore

    public init(runtimeRoot: URL = CodexAppPaths.runtimeRoot) {
        self.fileStore = SafeFileStore(root: runtimeRoot)
    }

    public func loadLatest(settings: TokenCostSettings) -> CodexDashboardPayload? {
        do {
            return try fileStore.readCodable(CodexDashboardPayload.self, from: latestRelativePath(for: settings))
        } catch {
            return nil
        }
    }

    public func saveLatest(_ payload: CodexDashboardPayload, settings: TokenCostSettings, retention: Int = 4) throws {
        let relativePath = latestRelativePath(for: settings)
        try fileStore.writeCodable(payload, to: relativePath)
        try fileStore.writeCodable(payload, to: snapshotsRelativePath(for: settings, timestamp: timestamp()))
        try rotateSnapshots(snapshotDirectory: snapshotsDirectory(for: settings), retention: max(retention, 1))
    }

    public func loadLatest() -> CodexDashboardPayload? {
        loadLatest(settings: .codexDefaults())
    }

    public func saveLatest(_ payload: CodexDashboardPayload, retention: Int = 4) throws {
        try saveLatest(payload, settings: .codexDefaults(), retention: retention)
    }

    private func rotateSnapshots(snapshotDirectory: URL, retention: Int) throws {
        guard FileManager.default.fileExists(atPath: snapshotDirectory.path) else {
            return
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: snapshotDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
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

    private func latestRelativePath(for settings: TokenCostSettings) -> String {
        "latest/codex/\(snapshotKey(for: settings)).json"
    }

    private func snapshotsRelativePath(for settings: TokenCostSettings, timestamp: String) -> String {
        "snapshots/codex/\(snapshotKey(for: settings))/\(timestamp).json"
    }

    private func snapshotsDirectory(for settings: TokenCostSettings) -> URL {
        fileStore.root.appendingPathComponent("snapshots/codex/\(snapshotKey(for: settings))", isDirectory: true)
    }

    private func snapshotKey(for settings: TokenCostSettings) -> String {
        let seed = [settings.sourceFamily.rawValue]
            + settings.effectiveSourceRoots.map { TokenCostPathUtilities.canonicalPathString(from: $0) }
            + settings.effectiveManualSourcePaths.map { TokenCostPathUtilities.canonicalPathString(from: $0) }
        let data = Data(seed.joined(separator: "|").utf8)
        let hash = SHA256.hash(data: data)
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        let raw = formatter.string(from: Date())
        return raw
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }
}
