import Foundation
import CodexTokenCostCore

struct GitHubRelease: Codable {
    let tagName: String
    let htmlUrl: String
    let name: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case name
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let size: Int
    let browserDownloadUrl: String

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case browserDownloadUrl = "browser_download_url"
    }
}

struct UpdateCheckCache: Codable {
    var lastCheckDate: Date
    var lastSeenVersion: String
}

enum UpdateError: LocalizedError {
    case downloadFailed
    case downloadVerificationFailed
    case unzipFailed
    case noReleaseAsset
    case releaseFetchFailed(statusCode: Int)
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return "Download failed"
        case .downloadVerificationFailed:
            return "Download verification failed — file size mismatch or empty"
        case .unzipFailed:
            return "Failed to extract downloaded archive"
        case .noReleaseAsset:
            return "No downloadable asset found in release"
        case .releaseFetchFailed(let code):
            return "GitHub API returned HTTP \(code)"
        case .rateLimited:
            return "GitHub API rate limit exceeded — try again later"
        }
    }
}

enum UpdateChecker {
    private static let repoOwner = "blackkcold"
    private static let repoName = "Token-Cost-App-OC-Codex"
    private static let checkInterval: TimeInterval = 86_400

    // MARK: - Version

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - Paths

    static var cacheURL: URL {
        CodexAppPaths.runtimeRoot
            .appendingPathComponent("config/update-check.json")
    }

    static var updatesDirectory: URL {
        CodexAppPaths.runtimeRoot
            .appendingPathComponent("updates", isDirectory: true)
    }

    // MARK: - Cache

    static func loadCache() -> UpdateCheckCache? {
        let store = SafeFileStore(root: CodexAppPaths.runtimeRoot)
        return try? store.readCodable(UpdateCheckCache.self, from: "config/update-check.json")
    }

    static func saveCache(_ cache: UpdateCheckCache) {
        let store = SafeFileStore(root: CodexAppPaths.runtimeRoot)
        do {
            try store.ensureDirectory("config")
            try store.writeCodable(cache, to: "config/update-check.json")
        } catch {
            #if DEBUG
            print("[UpdateChecker] Failed to save cache: \(error.localizedDescription)")
            #endif
        }
    }

    static func shouldCheckAgain(lastCheck: Date) -> Bool {
        Date().timeIntervalSince(lastCheck) >= checkInterval
    }

    // MARK: - Semver

    static func semverCompare(_ a: String, _ b: String) -> ComparisonResult {
        let cleanA = a.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        let cleanB = b.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        return cleanA.compare(cleanB, options: .numeric)
    }

    // MARK: - GitHub API

    static func checkLatestRelease() async throws -> GitHubRelease? {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            return nil
        }
    
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Token-Cost-App-OC-Codex/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
    
        let session = URLSession(configuration: .ephemeral)
        let (data, response) = try await session.data(for: request)
    
        guard let httpResponse = response as? HTTPURLResponse else {
            return nil
        }
    
        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            return try decoder.decode(GitHubRelease.self, from: data)
        case 403, 429:
            throw UpdateError.rateLimited
        default:
            throw UpdateError.releaseFetchFailed(statusCode: httpResponse.statusCode)
        }
    }

    static func isUpdateAvailable(latestVersion: String) -> Bool {
        semverCompare(latestVersion, currentVersion) == .orderedDescending
    }

    // MARK: - Download

    /// Downloads a release asset zip with progress callbacks on the calling actor.
    /// The `onProgress` closure receives values in [0, 1].
    static func downloadUpdate(
        from url: URL,
        onProgress: @Sendable (Double) -> Void
    ) async throws -> URL {
        let destinationURL = updatesDirectory
            .appendingPathComponent("latest.zip")

        try FileManager.default.createDirectory(at: updatesDirectory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destinationURL)

        let session = URLSession(configuration: .ephemeral)
        let (asyncBytes, response) = try await session.bytes(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UpdateError.downloadFailed
        }

        let expectedLength = max(0, httpResponse.expectedContentLength)
        var buffer = Data()
        buffer.reserveCapacity(max(Int(expectedLength), 1_048_576))
        var lastProgressReport = 0

        do {
            for try await byte in asyncBytes {
                buffer.append(byte)

                if expectedLength > 0, buffer.count - lastProgressReport >= 262_144 {
                    lastProgressReport = buffer.count
                    let progress = min(1.0, Double(buffer.count) / Double(expectedLength))
                    onProgress(progress)
                }
            }
        } catch {
            throw error
        }

        try buffer.write(to: destinationURL, options: .atomic)
        onProgress(1.0)

        // Verify: file exists and has non-zero size
        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw UpdateError.downloadVerificationFailed
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        guard fileSize > 0 else {
            throw UpdateError.downloadVerificationFailed
        }

        // Cross-check against Content-Length if available
        if expectedLength > 0, abs(fileSize - expectedLength) > 1_024 {
            throw UpdateError.downloadVerificationFailed
        }

        #if DEBUG
        print("[UpdateChecker] Download verified: \(fileSize) bytes")
        #endif

        // Unzip
        try unzipUpdate(at: destinationURL)

        return destinationURL
    }

    // MARK: - Unzip

    static func unzipUpdate(at zipURL: URL) throws {
        // Remove any previously extracted .app
        if let existingApp = downloadedAppURL() {
            try? FileManager.default.removeItem(at: existingApp)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, updatesDirectory.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            #if DEBUG
            print("[UpdateChecker] ditto unzip failed with status \(process.terminationStatus)")
            #endif
            throw UpdateError.unzipFailed
        }

        #if DEBUG
        print("[UpdateChecker] Unzip complete: \(updatesDirectory.path)")
        #endif

        guard let appURL = downloadedAppURL(), verifyCodeSign(at: appURL) else {
            throw UpdateError.downloadVerificationFailed
        }
    }

    private static func verifyCodeSign(at appURL: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--verbose=1", appURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Locate extracted app

    static func downloadedAppURL() -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: updatesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return contents.first { $0.pathExtension == "app" }
    }

    // MARK: - Helper: Find download asset

    static func findZipAsset(in release: GitHubRelease) -> GitHubAsset? {
        release.assets.first { asset in
            asset.name.hasPrefix("Token-Cost-App-OC-Codex-")
                && asset.name.contains("-macOS-")
                && asset.name.hasSuffix(".zip")
        } ?? release.assets.first { asset in
            asset.name.hasSuffix(".zip") && !asset.name.hasPrefix("Source")
        }
    }

    // MARK: - Install (原子替换 + 重启)

    /// 原子替换当前 app bundle，返回新 app 路径供重启使用。
    /// 先将旧 app rename 为 .old（同卷原子操作），再将新 app 移到原位。
    /// 若移动失败，从 .old 恢复旧 app。跨卷移动失败时抛错。
    static func replaceAppBundle(
        currentAppURL: URL,
        newAppURL: URL,
        backupName: String = "Token Cost App - OC Codex.old"
    ) throws -> URL {
        let parentDir = currentAppURL.deletingLastPathComponent()
        let backupURL = parentDir.appendingPathComponent(backupName)

        try? FileManager.default.removeItem(at: backupURL)
        try FileManager.default.moveItem(at: currentAppURL, to: backupURL)

        do {
            try FileManager.default.moveItem(at: newAppURL, to: currentAppURL)
        } catch {
            try? FileManager.default.moveItem(at: backupURL, to: currentAppURL)
            throw error
        }

        return currentAppURL
    }

    /// 清理上次替换留下的 .old 备份（下次启动时调用）。
    static func cleanupOldBackup(
        in parentDir: URL,
        backupName: String = "Token Cost App - OC Codex.old"
    ) {
        let oldURL = parentDir.appendingPathComponent(backupName)
        try? FileManager.default.removeItem(at: oldURL)
    }

    /// 启动 detached shell 进程：sleep 1 秒后 open 新 app，再由调用方 terminate。
    static func scheduleRelaunch(at appURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; open \"\(appURL.path)\""]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
    }
}
