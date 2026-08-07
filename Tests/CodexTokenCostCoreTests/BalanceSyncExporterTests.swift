import XCTest
import CryptoKit
@testable import CodexTokenCostCore
import CCryptoBridge

final class BalanceSyncExporterTests: XCTestCase {

    /// 验证 PBKDF2-HMAC-SHA256 派生密钥长度正确。
    func testDeriveKeyLength() throws {
        let salt = Data(repeating: 0xAA, count: 16)
        let key = try BalanceSyncExporter.deriveKey(
            passphrase: "test-passphrase",
            salt: salt,
            rounds: 210_000
        )
        // SymmetricKey 不暴露字节长度，通过加密验证可用性。
        let sealed = try AES.GCM.seal(
            Data("payload".utf8),
            using: key,
            nonce: AES.GCM.Nonce()
        )
        let opened = try AES.GCM.open(sealed, using: key)
        XCTAssertEqual(opened, Data("payload".utf8))
    }

    /// 验证加密→解密往返（用相同的派生+解密逻辑）。
    func testEncryptDecryptRoundTrip() throws {
        var providers = SyncPayload.Providers()
        providers.opencodeGo = SyncPayload.GoCredentials(
            workspaceID: "wk_test",
            cookie: "auth=abc",
            apiKey: "sk-go"
        )
        providers.deepseek = SyncPayload.TokenCredentials(apiKey: "sk-ds")
        let payload = SyncPayload(version: 1, updatedAt: Date(), providers: providers)

        let envelope = try BalanceSyncExporter.encrypt(payload, passphrase: "correct-horse")

        // 解密（与 Android 端相同的算法：PBKDF2-SHA256 + AES-GCM）。
        let salt = envelope.kdfSalt
        let keyData = try deriveKeyData(passphrase: "correct-horse", salt: salt, rounds: envelope.kdfRounds)
        let key = SymmetricKey(data: keyData)
        let sealed = try AES.GCM.SealedBox(
            nonce: try AES.GCM.Nonce(data: envelope.nonce),
            ciphertext: envelope.ciphertext,
            tag: envelope.tag
        )
        let openedData = try AES.GCM.open(sealed, using: key)
        let decoded = try JSONDecoder().decode(SyncPayload.self, from: openedData)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.providers.opencodeGo?.workspaceID, "wk_test")
        XCTAssertEqual(decoded.providers.opencodeGo?.cookie, "auth=abc")
        XCTAssertEqual(decoded.providers.opencodeGo?.apiKey, "sk-go")
        XCTAssertEqual(decoded.providers.deepseek?.apiKey, "sk-ds")
    }

    /// 验证错误口令解密失败（AES-GCM 认证失败）。
    func testDecryptWithWrongPassphraseFails() throws {
        var providers = SyncPayload.Providers()
        providers.ollama = SyncPayload.CookieCredentials(cookie: "auth=x")
        let payload = SyncPayload(version: 1, updatedAt: Date(), providers: providers)

        let envelope = try BalanceSyncExporter.encrypt(payload, passphrase: "right-pass")

        let salt = envelope.kdfSalt
        let keyData = try deriveKeyData(passphrase: "wrong-pass", salt: salt, rounds: envelope.kdfRounds)
        let key = SymmetricKey(data: keyData)
        let sealed = try AES.GCM.SealedBox(
            nonce: try AES.GCM.Nonce(data: envelope.nonce),
            ciphertext: envelope.ciphertext,
            tag: envelope.tag
        )
        XCTAssertThrowsError(try AES.GCM.open(sealed, using: key))
    }

    /// 验证收集到的凭证组装（依赖本机环境，仅验证结构完整性，不校验敏感值）。
    func testCollectCredentialsShape() {
        let providers = BalanceSyncExporter.collectCredentials()
        XCTAssertNotNil(providers.opencodeGo)
        XCTAssertNotNil(providers.ollama)
        XCTAssertNotNil(providers.codex)
        XCTAssertNotNil(providers.deepseek)
    }

    /// 用与 CCryptoBridge 相同的派生逻辑，复算密钥字节（用于 Android 交叉验证）。
    private func deriveKeyData(passphrase: String, salt: Data, rounds: Int) throws -> Data {
        var dk = Data(count: 32)
        let status = dk.withUnsafeMutableBytes { dkPtr -> Int32 in
            guard let dkRaw = dkPtr.baseAddress else { return -1 }
            return cc_pbkdf2_sha256(
                passphrase, passphrase.utf8.count,
                [UInt8](salt), salt.count,
                Int32(rounds),
                dkRaw.assumingMemoryBound(to: UInt8.self), 32
            )
        }
        XCTAssertEqual(status, 0)
        return dk
    }
}
