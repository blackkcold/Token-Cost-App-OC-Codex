import XCTest
import Security
@testable import CodexTokenCostCore

final class BalanceSyncPreferencesSecurityTests: XCTestCase {
    final class MemorySecretStore: BalanceSyncSecretStoring, @unchecked Sendable {
        var value: BalanceSyncSecrets?
        var saveError: Error?

        func load() throws -> BalanceSyncSecrets? { value }
        func save(_ secrets: BalanceSyncSecrets) throws {
            if let saveError { throw saveError }
            value = secrets
        }
        func delete() throws { value = nil }
    }

    func testLegacySecretsMigrateAndAreRemovedFromJSON() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileStore = SafeFileStore(root: root)
        let legacy = Data("""
        {"enabled":true,"server_base_url":"https://sync.example.invalid","device_id":"device-1","sync_token":"secret-token","passphrase":"secret-passphrase","auto_push_seconds":3600}
        """.utf8)
        try fileStore.writeData(legacy, to: "config/balance-sync.json")
        let secrets = MemorySecretStore()
        let store = BalanceSyncPreferencesStore(runtimeRoot: root, secretStore: secrets)

        let prefs = store.load()

        XCTAssertTrue(prefs.enabled)
        XCTAssertEqual(secrets.value, BalanceSyncSecrets(syncToken: "secret-token", passphrase: "secret-passphrase"))
        let migrated = try Data(contentsOf: fileStore.resolve("config/balance-sync.json"))
        XCTAssertFalse(migrated.contains(Data("secret-token".utf8)))
        XCTAssertFalse(migrated.contains(Data("secret-passphrase".utf8)))
        XCTAssertFalse(migrated.contains(Data("passphrase".utf8)))
    }

    func testMigrationFailurePreservesLegacySecrets() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileStore = SafeFileStore(root: root)
        let legacy = Data("""
        {"enabled":true,"server_base_url":"https://sync.example.invalid","device_id":"device-1","sync_token":"keep-token","passphrase":"keep-passphrase","auto_push_seconds":3600}
        """.utf8)
        try fileStore.writeData(legacy, to: "config/balance-sync.json")
        let secrets = MemorySecretStore()
        secrets.saveError = BalanceSyncSecretStoreError.keychain(errSecNotAvailable)
        let store = BalanceSyncPreferencesStore(runtimeRoot: root, secretStore: secrets)

        _ = store.load()

        let preserved = try Data(contentsOf: fileStore.resolve("config/balance-sync.json"))
        XCTAssertTrue(preserved.contains(Data("keep-token".utf8)))
        XCTAssertTrue(preserved.contains(Data("keep-passphrase".utf8)))
    }

    func testNewPreferencesEncodingContainsNoSecretFields() throws {
        let data = try JSONEncoder().encode(BalanceSyncPreferences(enabled: true, deviceID: "device-1"))
        XCTAssertFalse(data.contains(Data("syncToken".utf8)))
        XCTAssertFalse(data.contains(Data("passphrase".utf8)))
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("balance-sync-security-\(UUID().uuidString)", isDirectory: true)
    }
}
