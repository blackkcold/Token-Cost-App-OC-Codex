import CryptoKit
import XCTest
@testable import CodexTokenCostApp

final class UpdateManifestTests: XCTestCase {
    func testValidManifestSignaturePasses() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let unsigned = makeManifest(signature: "")
        let signature = try privateKey.signature(for: unsigned.canonicalData)
        let manifest = makeManifest(signature: signature.base64EncodedString())

        XCTAssertTrue(
            UpdateChecker.verify(
                manifest: manifest,
                publicKey: privateKey.publicKey.rawRepresentation
            )
        )
    }

    func testTamperedManifestSignatureFails() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let unsigned = makeManifest(signature: "")
        let signature = try privateKey.signature(for: unsigned.canonicalData)
        let tampered = UpdateManifest(
            version: unsigned.version,
            bundleIdentifier: unsigned.bundleIdentifier,
            architecture: unsigned.architecture,
            assetName: unsigned.assetName,
            assetSize: unsigned.assetSize + 1,
            sha256: unsigned.sha256,
            signature: signature.base64EncodedString()
        )

        XCTAssertFalse(
            UpdateChecker.verify(
                manifest: tampered,
                publicKey: privateKey.publicKey.rawRepresentation
            )
        )
    }

    func testManifestAssetLookupRequiresManifestSuffix() {
        let release = GitHubRelease(
            tagName: "v1.2.3",
            htmlUrl: "https://example.com/release",
            name: "v1.2.3",
            assets: [
                GitHubAsset(name: "app.zip", size: 10, browserDownloadUrl: "https://example.com/app.zip", digest: nil),
                GitHubAsset(
                    name: "app.update-manifest.json",
                    size: 100,
                    browserDownloadUrl: "https://example.com/app.update-manifest.json",
                    digest: nil
                )
            ]
        )

        XCTAssertEqual(UpdateChecker.findManifestAsset(in: release)?.name, "app.update-manifest.json")
    }

    func testDownloadedAppRequiresExactlyOneStagedApp() throws {
        try UpdateChecker.resetStagingDirectory()
        defer { try? FileManager.default.removeItem(at: UpdateChecker.stagingDirectory) }

        let first = UpdateChecker.stagingDirectory.appendingPathComponent("First.app", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        XCTAssertEqual(UpdateChecker.downloadedAppURL(), first)

        let second = UpdateChecker.stagingDirectory.appendingPathComponent("Second.app", isDirectory: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        XCTAssertNil(UpdateChecker.downloadedAppURL())
    }

    private func makeManifest(signature: String) -> UpdateManifest {
        UpdateManifest(
            version: "v1.2.3",
            bundleIdentifier: "com.yanghaoran.CodexTokenCost",
            architecture: UpdateChecker.currentArchitecture,
            assetName: "Token-Cost-App-OC-Codex-v1.2.3-macOS-arm64.zip",
            assetSize: 42,
            sha256: String(repeating: "a", count: 64),
            signature: signature
        )
    }
}
