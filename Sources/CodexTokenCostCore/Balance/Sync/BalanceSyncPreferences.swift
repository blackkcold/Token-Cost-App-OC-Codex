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
    /// 云端鉴权 Token（`X-Sync-Token` 头）。
    public var syncToken: String?
    /// 加密口令（不落盘到云端；本地保存以便自动推送）。
    public var passphrase: String?
    /// 自动推送间隔（秒），仅当凭证更新或达到间隔时触发。
    public var autoPushSeconds: Int

    public init(
        enabled: Bool = false,
        serverBaseURL: String? = nil,
        deviceID: String? = nil,
        syncToken: String? = nil,
        passphrase: String? = nil,
        autoPushSeconds: Int = 3600
    ) {
        self.enabled = enabled
        self.serverBaseURL = serverBaseURL
        self.deviceID = deviceID
        self.syncToken = syncToken
        self.passphrase = passphrase
        self.autoPushSeconds = autoPushSeconds
    }
}

/// `BalanceSyncPreferences` 的本地文件存储。
public final class BalanceSyncPreferencesStore {
    private let fileStore: SafeFileStore
    private let relativePath = "config/balance-sync.json"

    public init(runtimeRoot: URL = TokenCostPaths.runtimeRoot) {
        self.fileStore = SafeFileStore(root: runtimeRoot)
    }

    public func load() -> BalanceSyncPreferences {
        (try? fileStore.readCodable(BalanceSyncPreferences.self, from: relativePath))
            ?? BalanceSyncPreferences()
    }

    public func save(_ prefs: BalanceSyncPreferences) throws {
        try fileStore.writeCodable(prefs, to: relativePath)
    }
}
