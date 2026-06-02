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
        request.timeoutInterval = 15

        let session = URLSession(configuration: .ephemeral)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        let decoder = JSONDecoder()
        return try decoder.decode(GitHubRelease.self, from: data)
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
        release.assets.first { $0.name.hasSuffix(".zip") }
    }
}
