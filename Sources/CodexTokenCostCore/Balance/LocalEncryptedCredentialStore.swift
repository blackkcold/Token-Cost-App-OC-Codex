import Foundation
import CryptoKit

// MARK: - Error

public enum LocalEncryptedCredentialStoreError: Error, Equatable {
    /// The key file is missing or has an unexpected size.
    case keyUnavailable
    /// The key file is missing while encrypted data still exists — a new key
    /// is refused to avoid silently making existing ciphertext unrecoverable.
    case keyMissingWithExistingData
    /// AES-GCM encryption failed (cryptographic error).
    case encryptionFailed
}

// MARK: - Credential Payload

/// The cleartext credentials persisted inside the encrypted envelope.
public struct LocalCredentialPayload: Codable, Equatable, Sendable {
    public var workspaceID: String?
    public var goAuthCookie: String?
    public var ollamaCookie: String?

    public init(
        workspaceID: String? = nil,
        goAuthCookie: String? = nil,
        ollamaCookie: String? = nil
    ) {
        self.workspaceID = workspaceID
        self.goAuthCookie = goAuthCookie
        self.ollamaCookie = ollamaCookie
    }
}

// MARK: - Encrypted Envelope (internal)

/// The on-disk JSON envelope — only `version`, `nonce`, `ciphertext`, and `tag`.
private struct EncryptedEnvelope: Codable {
    let version: Int
    let nonce: Data
    let ciphertext: Data
    let tag: Data
}

// MARK: - Store

/// A local AES-256-GCM encrypted credential store.
///
/// Credentials are encrypted with a random 256-bit key stored in a separate
/// file (``.credential-key``) and persisted as a versioned JSON envelope
/// (``credentials.enc``).  Every write uses a fresh 12-byte nonce.
///
/// - Important: This type **never** accesses the Keychain or Security framework.
///   The key file is generated via `CryptoKit.SymmetricKey` and never leaves
///   the configured root directory.
///
/// ## File layout (inside `rootDirectory`)
///
/// | Path               | Permissions | Content                          |
/// |--------------------|-------------|----------------------------------|
/// | `.credential-key`  | `0600`      | 32 random bytes (raw)            |
/// | `credentials.enc`  | `0600`      | `EncryptedEnvelope` JSON         |
///
/// Directory permissions are set to `0700`.
///
/// ## Thread safety
///
/// All file read-modify-write operations are serialised through an `NSLock`.
///
/// ## Error handling
///
/// Missing key, corrupted envelope, and AES-GCM authentication failures all
/// return `nil` from ``readCredentials()`` **without** deleting on-disk data.
public final class LocalEncryptedCredentialStore: @unchecked Sendable {

    // MARK: - Static helpers

    /// The production root directory (derived from `TokenCostPaths`).
    public static var defaultRoot: URL {
        TokenCostPaths.runtimeRoot.appendingPathComponent("credentials", isDirectory: true)
    }

    // MARK: - Properties

    private let rootDirectory: URL
    private let lock = NSLock()

    private var keyFileURL: URL {
        rootDirectory.appendingPathComponent(".credential-key", isDirectory: false)
    }

    private var dataFileURL: URL {
        rootDirectory.appendingPathComponent("credentials.enc", isDirectory: false)
    }

    // MARK: - Init

    /// Creates (or opens) an encrypted store rooted at `rootDirectory`.
    ///
    /// If the directory does not exist it is created with `0700` permissions.
    /// If the key file is missing a fresh 32-byte key is generated.
    ///
    /// - Parameter rootDirectory: Writable directory that will contain the
    ///   key file and encrypted payload.
    public init(rootDirectory: URL) throws {
        self.rootDirectory = rootDirectory
        try ensureDirectory()
        try ensureKeyFile()
    }

    // MARK: - Public API

    /// Reads and decrypts the stored credentials.
    ///
    /// - Returns: The decrypted payload, or `nil` when no data file exists,
    ///   the key is missing/corrupted, or decryption / authentication fails.
    public func readCredentials() -> LocalCredentialPayload? {
        lock.lock()
        defer { lock.unlock() }
        return readPayload()
    }

    /// Encrypts and persists `payload` to disk (atomic write).
    ///
    /// - Parameter payload: The credentials to store.
    /// - Throws: `LocalEncryptedCredentialStoreError` on encryption or I/O failure.
    public func writeCredentials(_ payload: LocalCredentialPayload) throws {
        lock.lock()
        defer { lock.unlock() }
        try writePayload(payload)
    }

    /// Atomically reads, modifies, and writes credentials.
    ///
    /// The provided `handler` receives the current payload (or `nil` if no
    /// data exists).  Return a non-`nil` value to persist the new payload;
    /// return `nil` to leave the store unchanged.  The entire read–modify–write
    /// cycle is guarded by the internal lock.
    ///
    /// - Parameter handler: A closure that transforms the current payload.
    /// - Throws: Re-throws errors from `handler` or from the underlying write.
    public func modifyCredentials(
        _ handler: (LocalCredentialPayload?) throws -> LocalCredentialPayload?
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        let current = readPayload()
        guard let next = try handler(current) else { return }
        try writePayload(next)
    }

    /// Deletes the encrypted data file (the key file is preserved).
    public func deleteCredentials() throws {
        lock.lock()
        defer { lock.unlock() }
        let fm = FileManager.default
        if fm.fileExists(atPath: dataFileURL.path) {
            try fm.removeItem(at: dataFileURL)
        }
    }

    // MARK: - Private: directory & key management

    private func ensureDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: rootDirectory.path) {
            try fm.createDirectory(
                at: rootDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } else {
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootDirectory.path)
        }
    }

    private func ensureKeyFile() throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: keyFileURL.path) else { return }

        if fm.fileExists(atPath: dataFileURL.path) {
            throw LocalEncryptedCredentialStoreError.keyMissingWithExistingData
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try keyData.write(to: keyFileURL, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFileURL.path)
    }

    /// Loads the symmetric key from disk.
    /// - Throws: `LocalEncryptedCredentialStoreError.keyUnavailable` if the file
    ///   is missing or has an unexpected length.
    private func readKey() throws -> SymmetricKey {
        let fm = FileManager.default
        guard fm.fileExists(atPath: keyFileURL.path) else {
            throw LocalEncryptedCredentialStoreError.keyUnavailable
        }
        let keyData = try Data(contentsOf: keyFileURL)
        guard keyData.count == 32 else {
            throw LocalEncryptedCredentialStoreError.keyUnavailable
        }
        return SymmetricKey(data: keyData)
    }

    // MARK: - Private: encrypt / decrypt

    private func readPayload() -> LocalCredentialPayload? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dataFileURL.path) else { return nil }

        // Read envelope from disk
        let envelopeData: Data
        do {
            envelopeData = try Data(contentsOf: dataFileURL)
        } catch {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .base64
        let envelope: EncryptedEnvelope
        do {
            envelope = try decoder.decode(EncryptedEnvelope.self, from: envelopeData)
        } catch {
            return nil
        }

        // Version check
        guard envelope.version == 1 else { return nil }
        // Sanity-check field sizes
        guard envelope.nonce.count == 12 else { return nil }
        guard envelope.tag.count == 16 else { return nil }

        // Read key
        let key: SymmetricKey
        do {
            key = try readKey()
        } catch {
            return nil
        }

        // Reconstruct nonce
        let nonce: AES.GCM.Nonce
        do {
            nonce = try AES.GCM.Nonce(data: envelope.nonce)
        } catch {
            return nil
        }

        // Reconstruct sealed box
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: envelope.ciphertext,
                tag: envelope.tag
            )
        } catch {
            return nil
        }

        // Decrypt (authentication failure → nil)
        let decryptedData: Data
        do {
            decryptedData = try AES.GCM.open(sealedBox, using: key)
        } catch {
            return nil
        }

        // Decode payload
        do {
            return try JSONDecoder().decode(LocalCredentialPayload.self, from: decryptedData)
        } catch {
            return nil
        }
    }

    private func writePayload(_ payload: LocalCredentialPayload) throws {
        let payloadData = try JSONEncoder().encode(payload)

        let key = try readKey()
        let nonce = AES.GCM.Nonce() // fresh random 12-byte nonce

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.seal(payloadData, using: key, nonce: nonce)
        } catch {
            throw LocalEncryptedCredentialStoreError.encryptionFailed
        }

        let envelope = EncryptedEnvelope(
            version: 1,
            nonce: Data(sealedBox.nonce),
            ciphertext: sealedBox.ciphertext,
            tag: sealedBox.tag
        )

        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .base64
        let envelopeData = try encoder.encode(envelope)

        try envelopeData.write(to: dataFileURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: dataFileURL.path
        )
    }
}
