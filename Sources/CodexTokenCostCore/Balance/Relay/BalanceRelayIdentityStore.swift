import CryptoKit
import Foundation

/// 持久化的中继身份 + 端到端密钥。e2eKey 与 identity 用同一把本地密钥加密落盘，
/// 使 App 重启后能自动重连中继，无需重新扫码配对。
public struct BalanceRelayStoredIdentity: Codable, Sendable {
    public let identity: BalanceRelayIdentity
    public let e2eKey: Data

    public init(identity: BalanceRelayIdentity, e2eKey: Data) {
        self.identity = identity
        self.e2eKey = e2eKey
    }
}

public final class BalanceRelayIdentityStore: @unchecked Sendable {
    public static var defaultRoot: URL {
        TokenCostPaths.runtimeRoot.appendingPathComponent("relay", isDirectory: true)
    }

    private struct Envelope: Codable {
        let nonce: Data
        let ciphertext: Data
        let tag: Data
    }

    private let root: URL
    private let lock = NSLock()
    private var keyURL: URL { root.appendingPathComponent(".identity-key") }
    private var dataURL: URL { root.appendingPathComponent("identity.enc") }

    public init(root: URL = BalanceRelayIdentityStore.defaultRoot) throws {
        self.root = root
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if !FileManager.default.fileExists(atPath: keyURL.path) {
            let key = BalanceRelayCrypto.generateKey()
            try key.write(to: keyURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        }
    }

    public func load() -> BalanceRelayIdentity? {
        loadStored()?.identity
    }

    /// 读取持久化的身份与端到端密钥。兼容旧版仅存 identity 的信封（e2eKey 返回 nil）。
    public func loadStored() -> BalanceRelayStoredIdentity? {
        lock.withLock {
            guard let key = try? Data(contentsOf: keyURL), key.count == 32,
                  let data = try? Data(contentsOf: dataURL),
                  let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
                  let nonce = try? AES.GCM.Nonce(data: envelope.nonce),
                  let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: envelope.ciphertext, tag: envelope.tag),
                  let plaintext = try? AES.GCM.open(box, using: SymmetricKey(data: key))
            else { return nil }
            if let stored = try? JSONDecoder().decode(BalanceRelayStoredIdentity.self, from: plaintext) {
                return stored
            }
            if let identity = try? JSONDecoder().decode(BalanceRelayIdentity.self, from: plaintext) {
                return BalanceRelayStoredIdentity(identity: identity, e2eKey: Data())
            }
            return nil
        }
    }

    public func save(_ identity: BalanceRelayIdentity) throws {
        try save(BalanceRelayStoredIdentity(identity: identity, e2eKey: Data()))
    }

    public func save(_ stored: BalanceRelayStoredIdentity) throws {
        try lock.withLock {
            let key = try Data(contentsOf: keyURL)
            guard key.count == 32 else { throw BalanceRelayCryptoError.invalidKey }
            let plaintext = try JSONEncoder().encode(stored)
            let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key))
            let envelope = Envelope(
                nonce: Data(box.nonce),
                ciphertext: box.ciphertext,
                tag: box.tag
            )
            try JSONEncoder().encode(envelope).write(to: dataURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dataURL.path)
        }
    }

    public func delete() throws {
        try lock.withLock {
            if FileManager.default.fileExists(atPath: dataURL.path) {
                try FileManager.default.removeItem(at: dataURL)
            }
        }
    }
}
