import XCTest
import CryptoKit
@testable import CodexTokenCostCore

final class LocalEncryptedCredentialStoreTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("lest-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let root = tempRoot {
            try? FileManager.default.removeItem(at: root)
        }
        tempRoot = nil
        super.tearDown()
    }

    // MARK: - Init

    func testInitCreatesDirectoryAndKeyFile() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempRoot.path))

        _ = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)

        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempRoot.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        let keyURL = tempRoot.appendingPathComponent(".credential-key")
        XCTAssertTrue(FileManager.default.fileExists(atPath: keyURL.path))
        let keyData = try Data(contentsOf: keyURL)
        XCTAssertEqual(keyData.count, 32)
    }

    func testInitWithExistingDirectoryDoesNotOverwriteKey() throws {
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let keyURL = tempRoot.appendingPathComponent(".credential-key")
        let original = Data((0..<32).map { UInt8($0) })
        try original.write(to: keyURL, options: .atomic)

        _ = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)

        let stored = try Data(contentsOf: keyURL)
        XCTAssertEqual(stored, original)
    }

    // MARK: - Directory permissions

    func testDirectoryPermissionsAre0700() throws {
        _ = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)

        let attrs = try FileManager.default.attributesOfItem(atPath: tempRoot.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(perms, 0o700)
    }

    func testFilePermissionsAre0600() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)

        try store.writeCredentials(LocalCredentialPayload(workspaceID: "wrk"))

        let keyURL = tempRoot.appendingPathComponent(".credential-key")
        let dataURL = tempRoot.appendingPathComponent("credentials.enc")

        for url in [keyURL, dataURL] {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
            XCTAssertEqual(perms, 0o600, "\(url.lastPathComponent) should be 0600")
        }
    }

    // MARK: - Round-trip

    func testRoundTripAllFields() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        let payload = LocalCredentialPayload(
            workspaceID: "wrk_test123",
            goAuthCookie: "go-auth-token-abc",
            ollamaCookie: "ollama-session=xyz"
        )
        try store.writeCredentials(payload)

        let result = store.readCredentials()
        XCTAssertEqual(result, payload)
    }

    func testRoundTripPartialFields() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        let payload = LocalCredentialPayload(workspaceID: "only-id")
        try store.writeCredentials(payload)

        let result = store.readCredentials()
        XCTAssertEqual(result?.workspaceID, "only-id")
        XCTAssertNil(result?.goAuthCookie)
        XCTAssertNil(result?.ollamaCookie)
    }

    func testRoundTripNilFields() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        let payload = LocalCredentialPayload()
        try store.writeCredentials(payload)

        let result = store.readCredentials()
        XCTAssertNotNil(result)
        XCTAssertNil(result?.workspaceID)
        XCTAssertNil(result?.goAuthCookie)
        XCTAssertNil(result?.ollamaCookie)
    }

    func testRoundTripSpecialCharacters() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        let payload = LocalCredentialPayload(
            workspaceID: "wrk_äöü",
            goAuthCookie: "token=🔥+emoji",
            ollamaCookie: "session=hello world; path=/"
        )
        try store.writeCredentials(payload)

        let result = store.readCredentials()
        XCTAssertEqual(result, payload)
    }

    func testRoundTripLongValues() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        let longString = String(repeating: "ABCDEFGHIJ", count: 500)
        let payload = LocalCredentialPayload(
            workspaceID: longString,
            goAuthCookie: longString,
            ollamaCookie: longString
        )
        try store.writeCredentials(payload)

        let result = store.readCredentials()
        XCTAssertEqual(result, payload)
    }

    // MARK: - Overwrite

    func testOverwriteReplacesPreviousData() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)

        try store.writeCredentials(LocalCredentialPayload(workspaceID: "first"))
        XCTAssertEqual(store.readCredentials()?.workspaceID, "first")

        try store.writeCredentials(LocalCredentialPayload(workspaceID: "second"))
        XCTAssertEqual(store.readCredentials()?.workspaceID, "second")
    }

    func testOverwriteShrinksPayload() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)

        let full = LocalCredentialPayload(
            workspaceID: "wrk",
            goAuthCookie: "go",
            ollamaCookie: "ollama"
        )
        try store.writeCredentials(full)

        let partial = LocalCredentialPayload(workspaceID: "wrk")
        try store.writeCredentials(partial)

        let result = store.readCredentials()
        XCTAssertEqual(result?.workspaceID, "wrk")
        XCTAssertNil(result?.goAuthCookie)
        XCTAssertNil(result?.ollamaCookie)
    }

    // MARK: - Fresh nonce per write

    func testFreshNoncePerWriteProducesDifferentCiphertext() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        let payload = LocalCredentialPayload(workspaceID: "same")

        try store.writeCredentials(payload)
        let data1 = try Data(contentsOf: tempRoot.appendingPathComponent("credentials.enc"))

        try store.writeCredentials(payload)
        let data2 = try Data(contentsOf: tempRoot.appendingPathComponent("credentials.enc"))

        XCTAssertNotEqual(data1, data2, "identical payloads must produce different ciphertexts")
    }

    // MARK: - Envelope format

    func testEnvelopeContainsOnlyExpectedKeys() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        try store.writeCredentials(LocalCredentialPayload(workspaceID: "wrk"))

        let dataURL = tempRoot.appendingPathComponent("credentials.enc")
        let raw = try Data(contentsOf: dataURL)
        let json = try JSONSerialization.jsonObject(with: raw) as? [String: Any]
        XCTAssertNotNil(json)

        let keys = Set(json!.keys)
        XCTAssertEqual(keys, ["version", "nonce", "ciphertext", "tag"])
    }

    func testEnvelopeVersionIsOne() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        try store.writeCredentials(LocalCredentialPayload(workspaceID: "wrk"))

        let dataURL = tempRoot.appendingPathComponent("credentials.enc")
        let raw = try Data(contentsOf: dataURL)
        let json = try JSONSerialization.jsonObject(with: raw) as? [String: Any]
        XCTAssertEqual(json?["version"] as? Int, 1)
    }

    // MARK: - Missing / corrupted data → nil

    func testReadWhenNoDataFileReturnsNil() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        XCTAssertNil(store.readCredentials())
    }

    func testInitThrowsWhenKeyMissingButDataExists() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        try store.writeCredentials(LocalCredentialPayload(workspaceID: "unrecoverable"))

        let keyURL = tempRoot.appendingPathComponent(".credential-key")
        try FileManager.default.removeItem(at: keyURL)

        let dataURL = tempRoot.appendingPathComponent("credentials.enc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataURL.path))

        do {
            _ = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
            XCTFail("init must throw when data file exists but key is missing")
        } catch let error as LocalEncryptedCredentialStoreError {
            XCTAssertEqual(error, .keyMissingWithExistingData)
        }
    }

    func testWriteThrowsWhenKeyIsMissingAfterInit() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        try store.writeCredentials(LocalCredentialPayload(workspaceID: "before-key-loss"))

        let keyURL = tempRoot.appendingPathComponent(".credential-key")
        try FileManager.default.removeItem(at: keyURL)

        do {
            try store.writeCredentials(LocalCredentialPayload(workspaceID: "must-fail"))
            XCTFail("write must throw when key file has been deleted")
        } catch let error as LocalEncryptedCredentialStoreError {
            XCTAssertEqual(error, .keyUnavailable)
        }
    }

    func testReadAfterKeyLossDoesNotDeleteData() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        try store.writeCredentials(LocalCredentialPayload(workspaceID: "wrk"))

        let keyURL = tempRoot.appendingPathComponent(".credential-key")
        try FileManager.default.removeItem(at: keyURL)

        XCTAssertNil(store.readCredentials())
        let dataURL = tempRoot.appendingPathComponent("credentials.enc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataURL.path),
                       "data file must not be deleted on read failure after key loss")
    }

    func testReadWithMissingKeyFileReturnsNil() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        try store.writeCredentials(LocalCredentialPayload(workspaceID: "wrk"))

        let keyURL = tempRoot.appendingPathComponent(".credential-key")
        try FileManager.default.removeItem(at: keyURL)

        XCTAssertNil(store.readCredentials())
        let dataURL = tempRoot.appendingPathComponent("credentials.enc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataURL.path),
                       "data file must not be deleted on read failure")
    }

    func testReadWithWrongSizeKeyReturnsNil() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        try store.writeCredentials(LocalCredentialPayload(workspaceID: "wrk"))

        let keyURL = tempRoot.appendingPathComponent(".credential-key")
        try Data([0x01, 0x02, 0x03]).write(to: keyURL, options: .atomic)

        XCTAssertNil(store.readCredentials())
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tempRoot.appendingPathComponent("credentials.enc").path
        ))
    }

    func testReadWithGarbledEnvelopeReturnsNil() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)

        let dataURL = tempRoot.appendingPathComponent("credentials.enc")
        try Data("not valid json".utf8).write(to: dataURL, options: .atomic)

        XCTAssertNil(store.readCredentials())
    }

    func testReadWithTamperedCiphertextReturnsNil() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        try store.writeCredentials(LocalCredentialPayload(workspaceID: "wrk"))

        let dataURL = tempRoot.appendingPathComponent("credentials.enc")
        var raw = try Data(contentsOf: dataURL)
        guard var json = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let ciphertextB64 = json["ciphertext"] as? String,
              var ct = Data(base64Encoded: ciphertextB64),
              !ct.isEmpty
        else {
            XCTFail("could not parse envelope")
            return
        }

        ct[ct.count / 2] ^= 0xFF
        json["ciphertext"] = ct.base64EncodedString()
        raw = try JSONSerialization.data(withJSONObject: json)
        try raw.write(to: dataURL, options: .atomic)

        XCTAssertNil(store.readCredentials())
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataURL.path))
    }

    func testReadWithTamperedTagReturnsNil() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        try store.writeCredentials(LocalCredentialPayload(workspaceID: "wrk"))

        let dataURL = tempRoot.appendingPathComponent("credentials.enc")
        var raw = try Data(contentsOf: dataURL)
        guard var json = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let tagB64 = json["tag"] as? String,
              var tag = Data(base64Encoded: tagB64),
              !tag.isEmpty
        else {
            XCTFail("could not parse envelope")
            return
        }

        tag[0] ^= 0xFF
        json["tag"] = tag.base64EncodedString()
        raw = try JSONSerialization.data(withJSONObject: json)
        try raw.write(to: dataURL, options: .atomic)

        XCTAssertNil(store.readCredentials())
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataURL.path))
    }

    // MARK: - Delete

    func testDeleteRemovesDataFilePreservesKey() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        try store.writeCredentials(LocalCredentialPayload(workspaceID: "wrk"))

        try store.deleteCredentials()

        let dataURL = tempRoot.appendingPathComponent("credentials.enc")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dataURL.path))

        let keyURL = tempRoot.appendingPathComponent(".credential-key")
        XCTAssertTrue(FileManager.default.fileExists(atPath: keyURL.path))
    }

    func testDeleteWhenNoDataFileIsNoop() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        XCTAssertNoThrow(try store.deleteCredentials())
    }

    func testWriteAfterDeleteWorks() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        try store.writeCredentials(LocalCredentialPayload(workspaceID: "first"))
        try store.deleteCredentials()

        try store.writeCredentials(LocalCredentialPayload(workspaceID: "second"))
        XCTAssertEqual(store.readCredentials()?.workspaceID, "second")
    }

    // MARK: - modifyCredentials

    func testModifyCredentialsReadsAndWrites() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        try store.writeCredentials(LocalCredentialPayload(workspaceID: "wrk", goAuthCookie: "go"))

        try store.modifyCredentials { current in
            var next = current ?? LocalCredentialPayload()
            next.ollamaCookie = "added"
            return next
        }

        let result = store.readCredentials()
        XCTAssertEqual(result?.workspaceID, "wrk")
        XCTAssertEqual(result?.goAuthCookie, "go")
        XCTAssertEqual(result?.ollamaCookie, "added")
    }

    func testModifyCredentialsReturnsNilLeavesUnchanged() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        try store.writeCredentials(LocalCredentialPayload(workspaceID: "original"))

        try store.modifyCredentials { _ in nil }

        XCTAssertEqual(store.readCredentials()?.workspaceID, "original")
    }

    func testModifyCredentialsWhenEmpty() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)

        try store.modifyCredentials { current in
            XCTAssertNil(current)
            return LocalCredentialPayload(workspaceID: "fresh")
        }

        XCTAssertEqual(store.readCredentials()?.workspaceID, "fresh")
    }

    // MARK: - Atomic write integrity

    func testAtomicWriteNeverLeavesDataFileMissing() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        try store.writeCredentials(LocalCredentialPayload(workspaceID: "wrk"))

        let dataURL = tempRoot.appendingPathComponent("credentials.enc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataURL.path))

        let raw = try Data(contentsOf: dataURL)
        XCTAssertGreaterThan(raw.count, 0, "data file must contain valid envelope")

        let tmpURL = tempRoot.appendingPathComponent("credentials.enc.tmp")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tmpURL.path),
            "stray temporary file must not remain"
        )
    }

    func testAtomicOverwritePreservesDataIntegrity() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)

        let first = LocalCredentialPayload(workspaceID: "first")
        try store.writeCredentials(first)
        XCTAssertEqual(store.readCredentials()?.workspaceID, "first")

        let second = LocalCredentialPayload(workspaceID: "second", goAuthCookie: "go")
        try store.writeCredentials(second)
        XCTAssertEqual(store.readCredentials()?.workspaceID, "second")
        XCTAssertEqual(store.readCredentials()?.goAuthCookie, "go")
    }

    // MARK: - defaultRoot

    func testDefaultRootIsInsideApplicationSupport() throws {
        let root = LocalEncryptedCredentialStore.defaultRoot
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        XCTAssertTrue(root.path.hasPrefix(appSupport.path))
        XCTAssertTrue(root.path.contains("CodexTokenCost"))
        XCTAssertTrue(root.path.hasSuffix("credentials"))
    }

    // MARK: - Error types

    func testKeyUnavailableError() {
        XCTAssertNotNil(LocalEncryptedCredentialStoreError.keyUnavailable)
    }

    func testEncryptionFailedError() {
        XCTAssertNotNil(LocalEncryptedCredentialStoreError.encryptionFailed)
    }

    // MARK: - Payload Equatable

    func testPayloadEquality() {
        let a = LocalCredentialPayload(workspaceID: "a", goAuthCookie: "b", ollamaCookie: "c")
        let b = LocalCredentialPayload(workspaceID: "a", goAuthCookie: "b", ollamaCookie: "c")
        let c = LocalCredentialPayload(workspaceID: "a", goAuthCookie: "b", ollamaCookie: "x")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Concurrent writes do not corrupt

    func testConcurrentWritesDoNotCorrupt() throws {
        let store = try LocalEncryptedCredentialStore(rootDirectory: tempRoot)
        let group = DispatchGroup()
        let iterations = 20

        for i in 0..<iterations {
            group.enter()
            DispatchQueue.global().async {
                let payload = LocalCredentialPayload(workspaceID: "wrk-\(i)")
                _ = try? store.writeCredentials(payload)
                group.leave()
            }
        }

        group.wait()

        let result = store.readCredentials()
        XCTAssertNotNil(result)
        XCTAssertNotNil(result?.workspaceID)
    }
}
