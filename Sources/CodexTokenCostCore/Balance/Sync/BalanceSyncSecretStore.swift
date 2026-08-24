import Foundation
import Security

public struct BalanceSyncSecrets: Equatable, Sendable {
    public var syncToken: String
    public var passphrase: String

    public init(syncToken: String, passphrase: String) {
        self.syncToken = syncToken
        self.passphrase = passphrase
    }

    public var isComplete: Bool {
        !syncToken.isEmpty && !passphrase.isEmpty
    }
}

public protocol BalanceSyncSecretStoring: Sendable {
    func load() throws -> BalanceSyncSecrets?
    func save(_ secrets: BalanceSyncSecrets) throws
    func delete() throws
}

public enum BalanceSyncSecretStoreError: LocalizedError {
    case invalidSecret
    case keychain(OSStatus)
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidSecret: return "同步密钥不能为空"
        case .keychain(let status): return "同步密钥 Keychain 操作失败（\(status)）"
        case .verificationFailed: return "同步密钥写入后验证失败"
        }
    }
}

public final class KeychainBalanceSyncSecretStore: BalanceSyncSecretStoring, @unchecked Sendable {
    private let service: String
    private let tokenAccount = "sync-token"
    private let passphraseAccount = "passphrase"

    public init(service: String = "com.yanghaoran.CodexTokenCost.balance-sync") {
        self.service = service
    }

    public func load() throws -> BalanceSyncSecrets? {
        let token = try read(account: tokenAccount)
        let passphrase = try read(account: passphraseAccount)
        if token == nil && passphrase == nil { return nil }
        guard let token, let passphrase else { throw BalanceSyncSecretStoreError.verificationFailed }
        return BalanceSyncSecrets(syncToken: token, passphrase: passphrase)
    }

    public func save(_ secrets: BalanceSyncSecrets) throws {
        guard secrets.isComplete else { throw BalanceSyncSecretStoreError.invalidSecret }
        try upsert(secrets.syncToken, account: tokenAccount)
        do {
            try upsert(secrets.passphrase, account: passphraseAccount)
            guard try load() == secrets else { throw BalanceSyncSecretStoreError.verificationFailed }
        } catch {
            try? delete(account: tokenAccount)
            throw error
        }
    }

    public func delete() throws {
        try delete(account: tokenAccount)
        try delete(account: passphraseAccount)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    private func read(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { throw BalanceSyncSecretStoreError.keychain(status) }
        return value
    }

    private func upsert(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw BalanceSyncSecretStoreError.keychain(updateStatus)
        }
        var add = query
        attributes.forEach { add[$0.key] = $0.value }
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw BalanceSyncSecretStoreError.keychain(addStatus) }
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BalanceSyncSecretStoreError.keychain(status)
        }
    }
}
