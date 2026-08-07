import CryptoKit
import Foundation

public enum BalanceRelayCryptoError: Error, Equatable {
    case invalidKey
    case invalidEnvelope
    case authenticationFailed
}

public enum BalanceRelayCrypto {
    public static func generateKey() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    public static func seal<Value: Encodable>(
        _ value: Value,
        keyData: Data,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> BalanceRelayOpaqueEnvelope {
        guard keyData.count == 32 else { throw BalanceRelayCryptoError.invalidKey }
        let plaintext = try encoder.encode(value)
        let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: keyData))
        return BalanceRelayOpaqueEnvelope(
            nonce: Data(box.nonce).base64EncodedString(),
            ciphertext: box.ciphertext.base64EncodedString(),
            tag: box.tag.base64EncodedString()
        )
    }

    public static func open<Value: Decodable>(
        _ envelope: BalanceRelayOpaqueEnvelope,
        keyData: Data,
        as type: Value.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> Value {
        guard keyData.count == 32 else { throw BalanceRelayCryptoError.invalidKey }
        guard envelope.v == 1,
              let nonceData = Data(base64Encoded: envelope.nonce), nonceData.count == 12,
              let ciphertext = Data(base64Encoded: envelope.ciphertext), !ciphertext.isEmpty,
              let tag = Data(base64Encoded: envelope.tag), tag.count == 16
        else { throw BalanceRelayCryptoError.invalidEnvelope }
        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonceData),
                ciphertext: ciphertext,
                tag: tag
            )
            let plaintext = try AES.GCM.open(box, using: SymmetricKey(data: keyData))
            return try decoder.decode(type, from: plaintext)
        } catch is CryptoKitError {
            throw BalanceRelayCryptoError.authenticationFailed
        }
    }
}
