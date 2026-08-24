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
    public let requestedSections: [String]?
    public let sectionParams: BalanceRelaySectionParams?

    public init(
        action: String = "balance.refresh",
        issuedAtMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        nonce: String = UUID().uuidString,
        requestedSections: [String]? = nil,
        sectionParams: BalanceRelaySectionParams? = nil
    ) {
        self.action = action
        self.issuedAtMilliseconds = issuedAtMilliseconds
        self.nonce = nonce
        self.requestedSections = requestedSections
        self.sectionParams = sectionParams
    }
}

public struct BalanceRelaySectionParams: Codable, Equatable, Sendable {
    public struct Trend: Codable, Equatable, Sendable {
        public let days: Int?
        public init(days: Int? = nil) { self.days = days }
    }

    public struct Heatmap: Codable, Equatable, Sendable {
        public let weeks: Int?
        public init(weeks: Int? = nil) { self.weeks = weeks }
    }

    public let trend: Trend?
    public let heatmap: Heatmap?

    public init(trend: Trend? = nil, heatmap: Heatmap? = nil) {
        self.trend = trend
        self.heatmap = heatmap
    }
}

public struct BalanceRelayEncodedSection: Codable, Equatable, Sendable {
    public let encoding: String
    public let uncompressedBytes: Int
    public let data: String

    public init(encoding: String = "json+zlib", uncompressedBytes: Int, data: String) {
        self.encoding = encoding
        self.uncompressedBytes = uncompressedBytes
        self.data = data
    }
}

public struct BalanceRelayWireError: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct BalanceRelayResponse: Codable, Sendable {
    public let generatedAtMilliseconds: Int64
    public let requestNonce: String
    public let snapshots: [BalanceSnapshot]
    public let compression: String?
    public let sections: [String: BalanceRelayEncodedSection]?
    public let error: BalanceRelayWireError?

    public init(
        generatedAtMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        requestNonce: String,
        snapshots: [BalanceSnapshot],
        compression: String? = nil,
        sections: [String: BalanceRelayEncodedSection]? = nil,
        error: BalanceRelayWireError? = nil
    ) {
        self.generatedAtMilliseconds = generatedAtMilliseconds
        self.requestNonce = requestNonce
        self.snapshots = snapshots
        self.compression = compression
        self.sections = sections
        self.error = error
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
    case duplicateSection
    case unknownSection
    case invalidSectionParams
}

public struct BalanceRelayReplayCache: Sendable {
    private var expirations: [String: Int64] = [:]
    public let capacity: Int
    public let ttlMilliseconds: Int64

    public init(capacity: Int = 1_000, ttlMilliseconds: Int64 = 300_000) {
        self.capacity = capacity
        self.ttlMilliseconds = ttlMilliseconds
    }

    public var count: Int { expirations.count }

    public mutating func insert(_ nonce: String, nowMilliseconds: Int64) throws {
        expirations = expirations.filter { $0.value > nowMilliseconds }
        guard expirations[nonce] == nil else { throw BalanceRelayQueryValidationError.replay }
        if expirations.count >= capacity, let earliest = expirations.min(by: { $0.value < $1.value })?.key {
            expirations.removeValue(forKey: earliest)
        }
        expirations[nonce] = nowMilliseconds + ttlMilliseconds
    }

    public mutating func removeAll() {
        expirations.removeAll(keepingCapacity: true)
    }
}

public enum BalanceRelayQueryValidator {
    public static let allowedSections = Set([
        "overview", "cache", "cost", "usage", "modelDistribution", "trend", "heatmap",
    ])

    public static func validate(
        _ query: BalanceRelayQuery,
        nowMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        replayCache: inout BalanceRelayReplayCache
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
        if let sections = query.requestedSections {
            guard Set(sections).count == sections.count else {
                throw BalanceRelayQueryValidationError.duplicateSection
            }
            guard sections.count <= allowedSections.count,
                  sections.allSatisfy(allowedSections.contains)
            else { throw BalanceRelayQueryValidationError.unknownSection }
        }
        if let days = query.sectionParams?.trend?.days, !(1...90).contains(days) {
            throw BalanceRelayQueryValidationError.invalidSectionParams
        }
        if let weeks = query.sectionParams?.heatmap?.weeks, !(1...52).contains(weeks) {
            throw BalanceRelayQueryValidationError.invalidSectionParams
        }
        try replayCache.insert(query.nonce, nowMilliseconds: nowMilliseconds)
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
