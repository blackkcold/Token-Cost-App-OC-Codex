import Foundation
import CryptoKit
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
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case browserDownloadUrl = "browser_download_url"
        case digest
    }
}

struct UpdateCheckCache: Codable {
    var lastCheckDate: Date
    var lastSeenVersion: String
}

struct UpdateManifest: Codable, Equatable {
    let version: String
    let bundleIdentifier: String
    let architecture: String
    let assetName: String
    let assetSize: Int64
    let sha256: String
    let signature: String

    var canonicalData: Data {
        Data(
            "\(version)\n\(bundleIdentifier)\n\(architecture)\n\(assetName)\n\(assetSize)\n\(sha256.lowercased())\n".utf8
        )
    }
}

struct VerifiedUpdate: Equatable {
    let manifest: UpdateManifest
    let assetURL: URL
}

enum UpdateError: LocalizedError {
    case downloadFailed
    case downloadVerificationFailed
    case unzipFailed
    case noReleaseAsset
    case releaseFetchFailed(statusCode: Int)
    case rateLimited
    case manifestMissing
    case manifestInvalid
    case updateTooLarge

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
        case .manifestMissing:
            return "This release does not provide a signed update manifest"
        case .manifestInvalid:
            return "The update manifest signature or metadata is invalid"
        case .updateTooLarge:
            return "The update exceeds the allowed download size"
        }
    }
}

enum UpdateChecker {
    private static let repoOwner = "blackkcold"
    private static let repoName = "Token-Cost-App-OC-Codex"
    private static let checkInterval: TimeInterval = 86_400
    private static let maximumManifestBytes = 64 * 1024
    private static let maximumUpdateBytes: Int64 = 512 * 1024 * 1024
    private static let downloadWriteChunkBytes = 64 * 1024

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

    static var stagingDirectory: URL {
        updatesDirectory.appendingPathComponent("staging", isDirectory: true)
    }

    static var bundledManifestPublicKey: Data? {
        guard let encoded = Bundle.main.object(forInfoDictionaryKey: "UpdateManifestPublicKey") as? String,
              !encoded.isEmpty else {
            return nil
        }
        return Data(base64Encoded: encoded)
    }

    static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
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

    // MARK: - Signed manifest

    static func prepareVerifiedUpdate(
        from release: GitHubRelease,
        publicKey: Data? = bundledManifestPublicKey,
        session: URLSession = URLSession(configuration: .ephemeral)
    ) async throws -> VerifiedUpdate {
        guard let manifestAsset = findManifestAsset(in: release),
              let manifestURL = URL(string: manifestAsset.browserDownloadUrl) else {
            throw UpdateError.manifestMissing
        }

        var request = URLRequest(url: manifestURL)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              data.count <= maximumManifestBytes else {
            throw UpdateError.manifestInvalid
        }

        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
        guard let publicKey,
              verify(manifest: manifest, publicKey: publicKey),
              manifest.version == release.tagName,
              manifest.bundleIdentifier == "com.yanghaoran.CodexTokenCost",
              manifest.architecture == currentArchitecture,
              manifest.assetSize > 0,
              manifest.assetSize <= maximumUpdateBytes,
              let asset = release.assets.first(where: { $0.name == manifest.assetName }),
              Int64(asset.size) == manifest.assetSize,
              let assetURL = URL(string: asset.browserDownloadUrl) else {
            throw UpdateError.manifestInvalid
        }

        return VerifiedUpdate(manifest: manifest, assetURL: assetURL)
    }

    static func verify(manifest: UpdateManifest, publicKey: Data) -> Bool {
        guard let signature = Data(base64Encoded: manifest.signature),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else {
            return false
        }
        return key.isValidSignature(signature, for: manifest.canonicalData)
    }

    // MARK: - Download

    /// Downloads a release asset zip with progress callbacks on the calling actor.
    /// The `onProgress` closure receives values in [0, 1].
    static func downloadUpdate(
        _ verifiedUpdate: VerifiedUpdate,
        onProgress: @Sendable (Double) -> Void
    ) async throws -> URL {
        let expectedLength = verifiedUpdate.manifest.assetSize
        let expectedSHA256 = verifiedUpdate.manifest.sha256.lowercased()
        return try await performDownload(
            assetURL: verifiedUpdate.assetURL,
            expectedLength: expectedLength,
            expectedSHA256: expectedSHA256,
            onProgress: onProgress
        )
    }

    /// Fallback download path used when a release ships a zip but no signed
    /// `update-manifest.json` (the release pipeline skips the manifest when
    /// signing keys are absent). Integrity is still enforced via the GitHub
    /// API-provided `sha256:` digest and the asset size, followed by unzip and
    /// code-sign verification. This keeps auto-update working for unsigned
    /// releases without weakening the verified-manifest path.
    static func downloadDirect(
        from release: GitHubRelease,
        onProgress: @Sendable (Double) -> Void
    ) async throws -> URL {
        guard let asset = findZipAsset(in: release),
              let assetURL = URL(string: asset.browserDownloadUrl) else {
            throw UpdateError.noReleaseAsset
        }

        let expectedLength = Int64(asset.size)
        let expectedSHA256: String? = {
            guard let digest = asset.digest else { return nil }
            // GitHub returns "sha256:<hex>"; strip the prefix if present.
            let trimmed = digest.lowercased()
            let prefix = "sha256:"
            if trimmed.hasPrefix(prefix) {
                return String(trimmed.dropFirst(prefix.count))
            }
            return trimmed
        }()

        return try await performDownload(
            assetURL: assetURL,
            expectedLength: expectedLength,
            expectedSHA256: expectedSHA256,
            onProgress: onProgress
        )
    }

    private static func performDownload(
        assetURL: URL,
        expectedLength: Int64,
        expectedSHA256: String?,
        onProgress: @Sendable (Double) -> Void
    ) async throws -> URL {
        let destinationURL = stagingDirectory.appendingPathComponent("latest.zip")
        try resetStagingDirectory()
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: destinationURL)
        var shouldKeepStaging = false
        defer {
            try? output.close()
            if !shouldKeepStaging {
                try? FileManager.default.removeItem(at: stagingDirectory)
            }
        }

        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: assetURL)
        request.timeoutInterval = 60
        let (asyncBytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UpdateError.downloadFailed
        }

        if httpResponse.expectedContentLength > 0,
           httpResponse.expectedContentLength != expectedLength {
            throw UpdateError.downloadVerificationFailed
        }

        var buffer = Data()
        buffer.reserveCapacity(downloadWriteChunkBytes)
        var receivedBytes: Int64 = 0
        var hasher = SHA256()

        for try await byte in asyncBytes {
            buffer.append(byte)
            receivedBytes += 1
            guard receivedBytes <= expectedLength,
                  receivedBytes <= maximumUpdateBytes else {
                throw UpdateError.updateTooLarge
            }
            if buffer.count >= downloadWriteChunkBytes {
                hasher.update(data: buffer)
                try output.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                onProgress(min(1, Double(receivedBytes) / Double(expectedLength)))
            }
        }
        if !buffer.isEmpty {
            hasher.update(data: buffer)
            try output.write(contentsOf: buffer)
        }
        try output.synchronize()
        onProgress(1.0)

        let digest = Data(hasher.finalize()).map { String(format: "%02x", $0) }.joined()
        guard receivedBytes == expectedLength else {
            throw UpdateError.downloadVerificationFailed
        }
        if let expectedSHA256, digest != expectedSHA256 {
            throw UpdateError.downloadVerificationFailed
        }

        #if DEBUG
        print("[UpdateChecker] Download verified: \(receivedBytes) bytes")
        #endif

        try unzipUpdate(at: destinationURL)
        shouldKeepStaging = true
        return destinationURL
    }

    // MARK: - Unzip

    static func unzipUpdate(at zipURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, stagingDirectory.path]
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
        process.arguments = ["--verify", "--deep", "--strict", "--verbose=1", appURL.path]
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
            at: stagingDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let apps = contents.filter { $0.pathExtension == "app" }
        guard apps.count == 1,
              TokenCostPathUtilities.isDescendant(apps[0], of: stagingDirectory) else {
            return nil
        }
        return apps[0]
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

    static func findManifestAsset(in release: GitHubRelease) -> GitHubAsset? {
        release.assets.first { $0.name.hasSuffix(".update-manifest.json") }
    }

    static func resetStagingDirectory() throws {
        if FileManager.default.fileExists(atPath: stagingDirectory.path) {
            try FileManager.default.removeItem(at: stagingDirectory)
        }
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
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

    /// 启动独立 open 进程，再由调用方 terminate。
    static func scheduleRelaunch(at appURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", appURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
    }
}
