import Foundation
import CryptoKit
import CCryptoBridge

/// 凭证导出器：收集 macOS 端余额凭证，加密后推送到云端。
///
/// 同步协议见 `android/docs/sync-protocol.md`：
/// - 密钥由口令 + 随机盐经 PBKDF2-HMAC-SHA256 派生；
/// - 明文 payload 用 AES-256-GCM 加密；
/// - 云端仅保存密文信封。
public enum BalanceSyncExporter {

    public enum SyncError: Error, LocalizedError {
        case emptyCredentials
        case invalidServerURL
        case uploadFailed(Int, String)
        case missingConfiguration
        case network(String)

        public var errorDescription: String? {
            switch self {
            case .emptyCredentials:
                return "没有可同步的凭证（请先在设置中配置至少一个 Provider）"
            case .invalidServerURL:
                return "同步服务器地址无效"
            case .missingConfiguration:
                return "同步配置不完整（服务器地址、设备 ID、同步 Token、口令均需配置）"
            case .uploadFailed(let code, let body):
                return "同步上传失败：HTTP \(code) \(body)"
            case .network(let message):
                return "同步网络错误：\(message)"
            }
        }
    }

    /// 收集所有 4 个 Provider 的明文凭证，组装成 payload。
    static func collectCredentials() -> SyncPayload.Providers {
        let goWorkspaceID = CredentialBootstrapService.shared.getCachedGoWorkspaceID()
            ?? LocalCredentialService.shared.getWorkspaceID()
        let goCookie = CredentialBootstrapService.shared.getCachedGoCookie()
            ?? LocalCredentialService.shared.getAuthCookie()
        let ollamaCookie = CredentialBootstrapService.shared.getCachedOllamaCookie()
            ?? LocalCredentialService.shared.getOllamaCookie()
        let codexToken = AuthTokenProvider.token(for: .codex)
        let deepseekKey = AuthTokenProvider.token(for: .deepseek)
        let goAPIKey = AuthTokenProvider.token(for: .opencodeGo)

        return SyncPayload.Providers(
            opencodeGo: SyncPayload.GoCredentials(workspaceID: goWorkspaceID, cookie: goCookie, apiKey: goAPIKey),
            ollama: SyncPayload.CookieCredentials(cookie: ollamaCookie),
            codex: SyncPayload.TokenCredentials(authToken: codexToken),
            deepseek: SyncPayload.TokenCredentials(apiKey: deepseekKey)
        )
    }

    /// 构建明文 payload。
    static func buildPayload(updatedAt: Date = Date()) -> SyncPayload {
        SyncPayload(version: 1, updatedAt: updatedAt, providers: collectCredentials())
    }

    /// 用口令对 payload 做 AES-256-GCM 加密，生成信封。
    static func encrypt(_ payload: SyncPayload, passphrase: String) throws -> SyncEnvelope {
        let salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        let key = try deriveKey(passphrase: passphrase, salt: salt, rounds: 210_000)
        let payloadData = try JSONEncoder().encode(payload)
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(payloadData, using: key, nonce: nonce)
        return SyncEnvelope(
            v: 1,
            kdf: "pbkdf2-hmac-sha256",
            kdfSalt: salt,
            kdfRounds: 210_000,
            nonce: Data(sealed.nonce),
            ciphertext: sealed.ciphertext,
            tag: sealed.tag
        )
    }

    /// PBKDF2-HMAC-SHA256 派生 32 字节密钥。
    static func deriveKey(passphrase: String, salt: Data, rounds: Int) throws -> SymmetricKey {
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
        guard status == 0 else {
            throw SyncError.network("密钥派生失败")
        }
        return SymmetricKey(data: dk)
    }

    /// 校验配置完整性。
    static func validatedConfig(
        _ prefs: BalanceSyncPreferences,
        secretStore: any BalanceSyncSecretStoring
    ) throws -> (baseURL: URL, deviceID: String, token: String, passphrase: String) {
        guard prefs.enabled else { throw SyncError.missingConfiguration }
        guard let base = prefs.serverBaseURL, let baseURL = URL(string: base), baseURL.scheme != nil else {
            throw SyncError.invalidServerURL
        }
        guard let deviceID = prefs.deviceID, !deviceID.isEmpty,
              let secrets = try secretStore.load(), secrets.isComplete
        else { throw SyncError.missingConfiguration }
        return (baseURL, deviceID, secrets.syncToken, secrets.passphrase)
    }

    /// 加密并上传当前凭证。
    @discardableResult
    public static func push(
        _ prefs: BalanceSyncPreferences,
        secretStore: any BalanceSyncSecretStoring = KeychainBalanceSyncSecretStore()
    ) async throws -> Date {
        let (baseURL, deviceID, token, passphrase) = try validatedConfig(prefs, secretStore: secretStore)
        let payload = buildPayload()
        guard !payload.providers.isEmpty else { throw SyncError.emptyCredentials }

        let envelope = try encrypt(payload, passphrase: passphrase)
        let envelopeData = try JSONEncoder().encode(envelope)

        let url = baseURL.appendingPathComponent("v1/sync").appendingPathComponent(deviceID)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-Sync-Token")
        request.timeoutInterval = 30
        request.httpBody = envelopeData

        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SyncError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw SyncError.network("无效响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SyncError.uploadFailed(http.statusCode, body)
        }
        return payload.updatedAt
    }
}
