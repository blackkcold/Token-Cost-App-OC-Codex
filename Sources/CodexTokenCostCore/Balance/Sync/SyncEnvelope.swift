import Foundation

/// 同步加密信封（见 `android/docs/sync-protocol.md` §3）。
///
/// 所有二进制字段以 base64url 无填充编码存储，保证与 Android 端互操作。
public struct SyncEnvelope: Codable, Equatable, Sendable {
    public var v: Int
    public var kdf: String
    public var kdfSalt: Data
    public var kdfRounds: Int
    public var nonce: Data
    public var ciphertext: Data
    public var tag: Data

    public init(
        v: Int,
        kdf: String,
        kdfSalt: Data,
        kdfRounds: Int,
        nonce: Data,
        ciphertext: Data,
        tag: Data
    ) {
        self.v = v
        self.kdf = kdf
        self.kdfSalt = kdfSalt
        self.kdfRounds = kdfRounds
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }

    private enum CodingKeys: String, CodingKey {
        case v, kdf, kdfRounds = "kdf_rounds"
        case kdfSalt = "kdf_salt", nonce, ciphertext, tag
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.v = try c.decode(Int.self, forKey: .v)
        self.kdf = try c.decode(String.self, forKey: .kdf)
        self.kdfRounds = try c.decode(Int.self, forKey: .kdfRounds)
        self.kdfSalt = try c.decode(Data.self, forKey: .kdfSalt)
        self.nonce = try c.decode(Data.self, forKey: .nonce)
        self.ciphertext = try c.decode(Data.self, forKey: .ciphertext)
        self.tag = try c.decode(Data.self, forKey: .tag)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(v, forKey: .v)
        try c.encode(kdf, forKey: .kdf)
        try c.encode(kdfRounds, forKey: .kdfRounds)
        try c.encode(kdfSalt, forKey: .kdfSalt)
        try c.encode(nonce, forKey: .nonce)
        try c.encode(ciphertext, forKey: .ciphertext)
        try c.encode(tag, forKey: .tag)
    }
}
