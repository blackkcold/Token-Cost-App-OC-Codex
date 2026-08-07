import Foundation

public struct BalanceRelayIdentity: Codable, Equatable, Sendable {
    public let serverBaseURL: URL
    public let deviceID: String
    public let pcToken: String

    public init(serverBaseURL: URL, deviceID: String, pcToken: String) {
        self.serverBaseURL = serverBaseURL
        self.deviceID = deviceID
        self.pcToken = pcToken
    }
}

public struct BalanceRelayPairingPayload: Codable, Equatable, Sendable {
    public let version: Int
    public let deviceID: String
    public let pairCode: String
    public let e2eKey: Data
    public let expiresAtMilliseconds: Int64

    public init(
        version: Int = 1,
        deviceID: String,
        pairCode: String,
        e2eKey: Data,
        expiresAtMilliseconds: Int64
    ) {
        self.version = version
        self.deviceID = deviceID
        self.pairCode = pairCode
        self.e2eKey = e2eKey
        self.expiresAtMilliseconds = expiresAtMilliseconds
    }

    public var qrString: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return "balance-relay://pair?data=\(data.base64URLEncodedString())"
    }

    public static func parse(qrString: String) -> BalanceRelayPairingPayload? {
        guard let components = URLComponents(string: qrString),
              components.scheme == "balance-relay",
              components.host == "pair",
              let encoded = components.queryItems?.first(where: { $0.name == "data" })?.value,
              let data = Data(base64URLString: encoded),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["serverBaseURL"] == nil,
              let payload = try? JSONDecoder().decode(Self.self, from: data),
              payload.version == 1,
              payload.e2eKey.count == 32,
              payload.expiresAtMilliseconds > Int64(Date().timeIntervalSince1970 * 1000)
        else { return nil }
        return payload
    }
}

public struct BalanceRelayOpaqueEnvelope: Codable, Equatable, Sendable {
    public let v: Int
    public let nonce: String
    public let ciphertext: String
    public let tag: String

    public init(v: Int = 1, nonce: String, ciphertext: String, tag: String) {
        self.v = v
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }
}

public struct BalanceRelayQuery: Codable, Equatable, Sendable {
    public let action: String
    public let issuedAtMilliseconds: Int64
    public let nonce: String

    public init(
        action: String = "balance.refresh",
        issuedAtMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        nonce: String = UUID().uuidString
    ) {
        self.action = action
        self.issuedAtMilliseconds = issuedAtMilliseconds
        self.nonce = nonce
    }
}

public struct BalanceRelayResponse: Codable, Sendable {
    public let generatedAtMilliseconds: Int64
    public let snapshots: [BalanceSnapshot]

    public init(
        generatedAtMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        snapshots: [BalanceSnapshot]
    ) {
        self.generatedAtMilliseconds = generatedAtMilliseconds
        self.snapshots = snapshots
    }
}

public enum BalanceRelayConnectionState: String, Sendable {
    case unconfigured
    case disconnected
    case connecting
    case connected
    case reconnecting
}

/// Mac 端从服务器查询到的设备状态（含手机端在线情况）。
public struct BalanceRelayDeviceStatus: Sendable, Equatable {
    public let appOnline: Bool
    public let appLastSeenAt: Int64
    /// 本机 WebSocket 在服务器 pcSockets 中的在线状态（用于僵尸连接自检）。
    public let selfOnline: Bool

    public init(appOnline: Bool, appLastSeenAt: Int64, selfOnline: Bool) {
        self.appOnline = appOnline
        self.appLastSeenAt = appLastSeenAt
        self.selfOnline = selfOnline
    }
}

public enum BalanceRelayQueryValidationError: Error, Equatable {
    case unsupportedAction
    case staleRequest
    case invalidNonce
    case replay
}

public enum BalanceRelayQueryValidator {
    public static func validate(
        _ query: BalanceRelayQuery,
        nowMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        seenNonces: inout Set<String>
    ) throws {
        guard query.action == "balance.refresh" else {
            throw BalanceRelayQueryValidationError.unsupportedAction
        }
        guard abs(nowMilliseconds - query.issuedAtMilliseconds) <= 300_000 else {
            throw BalanceRelayQueryValidationError.staleRequest
        }
        guard query.nonce.count >= 16, query.nonce.count <= 100 else {
            throw BalanceRelayQueryValidationError.invalidNonce
        }
        guard seenNonces.insert(query.nonce).inserted else {
            throw BalanceRelayQueryValidationError.replay
        }
        if seenNonces.count > 1_000 {
            seenNonces.removeAll(keepingCapacity: true)
            seenNonces.insert(query.nonce)
        }
    }
}

extension Data {
    fileprivate func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    fileprivate init?(base64URLString: String) {
        var value = base64URLString
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        self.init(base64Encoded: value)
    }
}
