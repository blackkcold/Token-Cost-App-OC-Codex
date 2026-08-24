import Foundation

/// 余额监控同步配置（独立存储于 `config/balance-sync.json`）。
///
/// 用于把 macOS 端收集的余额凭证加密推送到云端，供 Android 手机端拉取。
/// 该配置与 `AppPreferences` 解耦，避免改动核心偏好结构。
public struct BalanceSyncPreferences: Codable, Equatable, Sendable {
    /// 是否启用同步推送。
    public var enabled: Bool
    /// 云端服务器基础地址（如 `https://sync.example.com`）。
    public var serverBaseURL: String?
    /// 设备 ID（作为云端存储桶 key，两端需一致）。
    public var deviceID: String?
    /// 自动推送间隔（秒），仅当凭证更新或达到间隔时触发。
    public var autoPushSeconds: Int

    public init(
        enabled: Bool = false,
        serverBaseURL: String? = nil,
        deviceID: String? = nil,
        autoPushSeconds: Int = 3600
    ) {
        self.enabled = enabled
        self.serverBaseURL = serverBaseURL
        self.deviceID = deviceID
        self.autoPushSeconds = autoPushSeconds
    }
}

/// `BalanceSyncPreferences` 的本地文件存储。
public final class BalanceSyncPreferencesStore {
    private let fileStore: SafeFileStore
    private let secretStore: any BalanceSyncSecretStoring
    private let relativePath = "config/balance-sync.json"

    public init(
        runtimeRoot: URL = TokenCostPaths.runtimeRoot,
        secretStore: any BalanceSyncSecretStoring = KeychainBalanceSyncSecretStore()
    ) {
        self.fileStore = SafeFileStore(root: runtimeRoot)
        self.secretStore = secretStore
    }

    public func load() -> BalanceSyncPreferences {
        guard let url = try? fileStore.resolve(relativePath),
              let data = try? Data(contentsOf: url),
              let legacy = try? JSONDecoder.snakeCase.decode(LegacyBalanceSyncPreferences.self, from: data)
        else { return BalanceSyncPreferences() }

        if let token = legacy.syncToken, !token.isEmpty,
           let passphrase = legacy.passphrase, !passphrase.isEmpty {
            do {
                let secrets = BalanceSyncSecrets(syncToken: token, passphrase: passphrase)
                try secretStore.save(secrets)
                guard try secretStore.load() == secrets else {
                    throw BalanceSyncSecretStoreError.verificationFailed
                }
                try save(legacy.preferences)
            } catch {
                return legacy.preferences
            }
        }
        return legacy.preferences
    }

    public func save(_ prefs: BalanceSyncPreferences) throws {
        try fileStore.writeCodable(prefs, to: relativePath)
    }

    public func save(_ prefs: BalanceSyncPreferences, secrets: BalanceSyncSecrets) throws {
        try secretStore.save(secrets)
        guard try secretStore.load() == secrets else {
            throw BalanceSyncSecretStoreError.verificationFailed
        }
        try save(prefs)
    }

    public func loadSecrets() throws -> BalanceSyncSecrets? {
        try secretStore.load()
    }
}

private struct LegacyBalanceSyncPreferences: Decodable {
    var enabled: Bool = false
    var serverBaseURL: String?
    var deviceID: String?
    var syncToken: String?
    var passphrase: String?
    var autoPushSeconds: Int = 3600

    var preferences: BalanceSyncPreferences {
        BalanceSyncPreferences(
            enabled: enabled,
            serverBaseURL: serverBaseURL,
            deviceID: deviceID,
            autoPushSeconds: autoPushSeconds
        )
    }
}

private extension JSONDecoder {
    static var snakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
