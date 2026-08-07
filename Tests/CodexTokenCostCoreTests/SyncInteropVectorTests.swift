import XCTest
import CryptoKit
@testable import CodexTokenCostCore

/// 生成跨端互操作测试向量：Swift 加密 → 输出信封，供 Dart 端解密验证。
/// 此测试在运行时打印固定口令+固定盐下的加密信封 JSON（含随机 nonce，
/// 每次不同，但 Dart 端用它做端到端解密验证）。
final class SyncInteropVectorTests: XCTestCase {

    /// 用固定盐加密固定 payload，验证可被 Dart `SyncDecryptor` 解密。
    /// 断言：解密 round-trip 自洽（Swift 侧验证），Dart 侧用同一逻辑。
    func testEncryptProducesDecryptableEnvelope() throws {
        var providers = SyncPayload.Providers()
        providers.opencodeGo = SyncPayload.GoCredentials(
            workspaceID: "wk_interop",
            cookie: "auth=interop_cookie",
            apiKey: "sk_go_interop"
        )
        providers.ollama = SyncPayload.CookieCredentials(cookie: "auth=ollama_cookie")
        providers.codex = SyncPayload.TokenCredentials(authToken: "codex_token")
        providers.deepseek = SyncPayload.TokenCredentials(apiKey: "sk_ds")
        let payload = SyncPayload(version: 1, updatedAt: Date(), providers: providers)

        // 固定盐保证 Dart 端可复现派生（用于验证算法一致）。
        // 实际加密用随机盐，但这里用固定盐生成一个 Dart 端可解密的确定样例。
        let fixedSalt = Data(repeating: 0x42, count: 16)
        let key = try BalanceSyncExporter.deriveKey(passphrase: "interop-passphrase", salt: fixedSalt, rounds: 210_000)
        let payloadData = try JSONEncoder().encode(payload)
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(payloadData, using: key, nonce: nonce)

        // 输出到标准输出，Dart 测试作为 fixture 使用（人工比对）。
        let envelope: [String: String] = [
            "kdf": "pbkdf2-hmac-sha256",
            "kdf_salt": fixedSalt.base64EncodedString(),
            "kdf_rounds": "210000",
            "nonce": Data(sealed.nonce).base64EncodedString(),
            "ciphertext": sealed.ciphertext.base64EncodedString(),
            "tag": sealed.tag.base64EncodedString(),
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: envelope) {
            print("INTEROP_ENVELOPE=\(String(data: jsonData, encoding: .utf8) ?? "")")
        }

        // 自洽验证：用相同密钥解密成功。
        let sealedBox = try AES.GCM.SealedBox(
            nonce: try AES.GCM.Nonce(data: Data(sealed.nonce)),
            ciphertext: sealed.ciphertext,
            tag: sealed.tag
        )
        let opened = try AES.GCM.open(sealedBox, using: key)
        let decoded = try JSONDecoder().decode(SyncPayload.self, from: opened)
        XCTAssertEqual(decoded.providers.opencodeGo?.workspaceID, "wk_interop")
    }
}
