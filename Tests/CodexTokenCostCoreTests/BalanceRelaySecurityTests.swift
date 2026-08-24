import CryptoKit
import XCTest
@testable import CodexTokenCostCore

final class BalanceRelaySecurityTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    private var contractFixtureRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/RelayContract/v1", isDirectory: true)
    }

    override func tearDownWithError() throws {
        for directory in temporaryDirectories where FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testOpaqueEnvelopeRoundTripAndTamperDetection() throws {
        let key = BalanceRelayCrypto.generateKey()
        let query = BalanceRelayQuery(
            issuedAtMilliseconds: 1_700_000_000_000,
            nonce: "security-query-nonce-0001"
        )
        let envelope = try BalanceRelayCrypto.seal(query, keyData: key)
        let decoded = try BalanceRelayCrypto.open(envelope, keyData: key, as: BalanceRelayQuery.self)
        XCTAssertEqual(decoded, query)

        let altered = BalanceRelayOpaqueEnvelope(
            nonce: envelope.nonce,
            ciphertext: envelope.ciphertext.dropLast() + (envelope.ciphertext.last == "A" ? "B" : "A"),
            tag: envelope.tag
        )
        XCTAssertThrowsError(try BalanceRelayCrypto.open(altered, keyData: key, as: BalanceRelayQuery.self))
        XCTAssertThrowsError(try BalanceRelayCrypto.open(envelope, keyData: BalanceRelayCrypto.generateKey(), as: BalanceRelayQuery.self))
    }

    func testPairingPayloadQRRejectsExpiredAndInvalidKey() throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let valid = BalanceRelayPairingPayload(
            deviceID: "device_security_0001",
            pairCode: "pair_security_code_0001",
            e2eKey: Data(repeating: 0x42, count: 32),
            expiresAtMilliseconds: now + 300_000
        )
        XCTAssertEqual(BalanceRelayPairingPayload.parse(qrString: try XCTUnwrap(valid.qrString)), valid)
        let encoded = try XCTUnwrap(
            URLComponents(string: try XCTUnwrap(valid.qrString))?
                .queryItems?
                .first(where: { $0.name == "data" })?
                .value
        )
        var normalized = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        normalized += String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        let qrData = try XCTUnwrap(Data(base64Encoded: normalized))
        let qrObject = try XCTUnwrap(JSONSerialization.jsonObject(with: qrData) as? [String: Any])
        XCTAssertNil(qrObject["serverBaseURL"])

        let expired = BalanceRelayPairingPayload(
            deviceID: valid.deviceID,
            pairCode: valid.pairCode,
            e2eKey: valid.e2eKey,
            expiresAtMilliseconds: now - 1
        )
        XCTAssertNil(BalanceRelayPairingPayload.parse(qrString: try XCTUnwrap(expired.qrString)))

        let shortKey = BalanceRelayPairingPayload(
            deviceID: valid.deviceID,
            pairCode: valid.pairCode,
            e2eKey: Data(repeating: 0x42, count: 16),
            expiresAtMilliseconds: now + 300_000
        )
        XCTAssertNil(BalanceRelayPairingPayload.parse(qrString: try XCTUnwrap(shortKey.qrString)))
    }

    func testPairingPayloadRejectsLegacyServerOverride() throws {
        let payload: [String: Any] = [
            "version": 1,
            "serverBaseURL": "https://relay.example.invalid",
            "deviceID": "device_security_0001",
            "pairCode": "pair_security_code_0001",
            "e2eKey": Data(repeating: 0x42, count: 32).base64EncodedString(),
            "expiresAtMilliseconds": Int64(Date().timeIntervalSince1970 * 1000) + 300_000,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertNil(BalanceRelayPairingPayload.parse(qrString: "balance-relay://pair?data=\(encoded)"))
    }

    func testRelayEndpointValidation() {
        XCTAssertNotNil(BalanceRelayEndpoint.validatedURL("https://relay.example.invalid", allowInsecure: false))
        XCTAssertNil(BalanceRelayEndpoint.validatedURL("http://relay.example.invalid", allowInsecure: false))
        XCTAssertNotNil(BalanceRelayEndpoint.validatedURL("http://127.0.0.1:8787", allowInsecure: true))
        XCTAssertNil(BalanceRelayEndpoint.validatedURL("https://relay.example.invalid?target=other", allowInsecure: false))
    }

    func testContractPairingFixtureMatchesSwiftModel() throws {
        let data = try Data(contentsOf: contractFixtureRoot.appendingPathComponent("pairing-valid.json"))
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let payload = try XCTUnwrap(
            BalanceRelayPairingPayload.parse(qrString: "balance-relay://pair?data=\(encoded)")
        )
        XCTAssertEqual(payload.version, 1)
        XCTAssertEqual(payload.deviceID, "device_contract_0001")
        XCTAssertEqual(payload.e2eKey.count, 32)
    }

    func testContractAESGCMVectorDecrypts() throws {
        let data = try Data(contentsOf: contractFixtureRoot.appendingPathComponent("aes-gcm-vector.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let key = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(object["key"] as? String)))
        let envelopeObject = try XCTUnwrap(object["envelope"] as? [String: Any])
        let envelope = BalanceRelayOpaqueEnvelope(
            v: try XCTUnwrap(envelopeObject["v"] as? Int),
            nonce: try XCTUnwrap(envelopeObject["nonce"] as? String),
            ciphertext: try XCTUnwrap(envelopeObject["ciphertext"] as? String),
            tag: try XCTUnwrap(envelopeObject["tag"] as? String)
        )
        let query = try BalanceRelayCrypto.open(envelope, keyData: key, as: BalanceRelayQuery.self)
        XCTAssertEqual(query.action, "balance.refresh")
        XCTAssertEqual(query.issuedAtMilliseconds, 1_700_000_000_000)
        XCTAssertEqual(query.nonce, "contract-query-nonce-0001")
    }

    func testContractV11RequestResponseVectors() throws {
        let decoder = JSONDecoder()
        let requestData = try Data(contentsOf: contractFixtureRoot.appendingPathComponent("request-v1.1.json"))
        let query = try decoder.decode(BalanceRelayQuery.self, from: requestData)
        XCTAssertEqual(query.action, "balance.refresh")
        XCTAssertEqual(query.nonce, "contract-query-nonce-0001")
        XCTAssertEqual(Set(try XCTUnwrap(query.requestedSections)), BalanceRelayQueryValidator.allowedSections)
        XCTAssertEqual(query.sectionParams?.trend?.days, 30)
        XCTAssertEqual(query.sectionParams?.heatmap?.weeks, 52)

        var replayCache = BalanceRelayReplayCache()
        XCTAssertNoThrow(try BalanceRelayQueryValidator.validate(
            query,
            nowMilliseconds: query.issuedAtMilliseconds,
            replayCache: &replayCache
        ))

        let responseData = try Data(contentsOf: contractFixtureRoot.appendingPathComponent("response-v1.1.json"))
        let response = try decoder.decode(BalanceRelayResponse.self, from: responseData)
        XCTAssertEqual(response.requestNonce, query.nonce)
        let encodedOverview = try XCTUnwrap(response.sections?["overview"])
        let compressed = try XCTUnwrap(Data(base64Encoded: encodedOverview.data))
        let overviewData = try RelayCompression.zlibDecompress(compressed)
        XCTAssertEqual(overviewData.count, encodedOverview.uncompressedBytes)
        XCTAssertEqual(overviewData.count, 143)

        let overview = try decoder.decode(RelayOverviewSection.self, from: overviewData)
        XCTAssertEqual(overview.totalTokens, 2_000)
        XCTAssertEqual(overview.totalActualTokens, 1_500)
        XCTAssertEqual(overview.totalCostUSD, 1.25)
        XCTAssertEqual(overview.dailyAverageTokens, 750)
        XCTAssertEqual(overview.monthlyEstimateTokens, 22_500)
        XCTAssertEqual(overview.activeDays, 2)

        let overviewObject = try XCTUnwrap(JSONSerialization.jsonObject(with: overviewData) as? [String: Any])
        XCTAssertEqual(Set(overviewObject.keys), [
            "totalTokens",
            "totalActualTokens",
            "totalCostUSD",
            "dailyAverageTokens",
            "monthlyEstimateTokens",
            "activeDays",
        ])
    }

    func testContractZlibVectorDecompresses() throws {
        let data = try Data(contentsOf: contractFixtureRoot.appendingPathComponent("section-zlib-vector.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let compressed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(object["data"] as? String)))
        let plaintext = try XCTUnwrap((object["plaintext"] as? String)?.data(using: .utf8))
        XCTAssertEqual(try RelayCompression.zlibDecompress(compressed), plaintext)
        XCTAssertEqual(try RelayCompression.zlibDecompress(try RelayCompression.zlibCompress(plaintext)), plaintext)
    }

    func testAllAnalyticsSectionsBuildAndRoundTrip() throws {
        let analytics = TokenCostDashboardAnalytics(payload: .empty())
        let requested = ["overview", "cache", "cost", "usage", "modelDistribution", "trend", "heatmap"]
        let sections = try RelaySectionBuilder.build(
            requestedSections: requested,
            params: .init(trend: .init(days: 30), heatmap: .init(weeks: 52)),
            analytics: analytics,
            timeZoneIdentifier: "UTC"
        )
        XCTAssertEqual(Set(sections.keys), Set(requested))
        for section in sections.values {
            let compressed = try XCTUnwrap(Data(base64Encoded: section.data))
            let plaintext = try RelayCompression.zlibDecompress(compressed)
            XCTAssertEqual(plaintext.count, section.uncompressedBytes)
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: plaintext))
        }
    }

    func testContractPairingFieldsExcludeServerOverride() throws {
        let data = try Data(contentsOf: contractFixtureRoot.appendingPathComponent("contract.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let fields = try XCTUnwrap(object["pairingFields"] as? [String])
        XCTAssertEqual(fields, ["version", "deviceID", "pairCode", "e2eKey", "expiresAtMilliseconds"])
        XCTAssertFalse(fields.contains("serverBaseURL"))
    }

    func testQueryValidationRejectsReplayStaleAndUnsupportedRequests() throws {
        let now: Int64 = 1_700_000_000_000
        var replayCache = BalanceRelayReplayCache()
        let valid = BalanceRelayQuery(
            issuedAtMilliseconds: now,
            nonce: "security-query-nonce-0002"
        )
        XCTAssertNoThrow(try BalanceRelayQueryValidator.validate(valid, nowMilliseconds: now, replayCache: &replayCache))
        XCTAssertThrowsError(try BalanceRelayQueryValidator.validate(valid, nowMilliseconds: now, replayCache: &replayCache)) {
            XCTAssertEqual($0 as? BalanceRelayQueryValidationError, .replay)
        }

        let stale = BalanceRelayQuery(
            issuedAtMilliseconds: now - 300_001,
            nonce: "security-query-nonce-0003"
        )
        XCTAssertThrowsError(try BalanceRelayQueryValidator.validate(stale, nowMilliseconds: now, replayCache: &replayCache)) {
            XCTAssertEqual($0 as? BalanceRelayQueryValidationError, .staleRequest)
        }

        let unsupported = BalanceRelayQuery(
            action: "credentials.export",
            issuedAtMilliseconds: now,
            nonce: "security-query-nonce-0004"
        )
        XCTAssertThrowsError(try BalanceRelayQueryValidator.validate(unsupported, nowMilliseconds: now, replayCache: &replayCache)) {
            XCTAssertEqual($0 as? BalanceRelayQueryValidationError, .unsupportedAction)
        }
    }

    func testReplayCacheExpiresAndEvictsWithoutClearingAllEntries() throws {
        var cache = BalanceRelayReplayCache(capacity: 2, ttlMilliseconds: 100)
        try cache.insert("nonce-000000000001", nowMilliseconds: 1_000)
        try cache.insert("nonce-000000000002", nowMilliseconds: 1_010)
        try cache.insert("nonce-000000000003", nowMilliseconds: 1_020)
        XCTAssertEqual(cache.count, 2)
        XCTAssertThrowsError(try cache.insert("nonce-000000000002", nowMilliseconds: 1_030))
        XCTAssertNoThrow(try cache.insert("nonce-000000000002", nowMilliseconds: 1_111))
    }

    func testQueryLimiterEnforcesBurstWindowAndConcurrencyCaps() throws {
        var perSecond = BalanceRelayQueryLimiter()
        try perSecond.acquire(nowMilliseconds: 10_000)
        perSecond.release()
        try perSecond.acquire(nowMilliseconds: 10_001)
        perSecond.release()
        XCTAssertThrowsError(try perSecond.acquire(nowMilliseconds: 10_002)) {
            XCTAssertEqual($0 as? BalanceRelayQueryProcessingError, .rateLimited)
        }

        var tenSecond = BalanceRelayQueryLimiter()
        for index in 0..<10 {
            try tenSecond.acquire(nowMilliseconds: 20_000 + Int64(index * 1_000))
            tenSecond.release()
        }
        XCTAssertThrowsError(try tenSecond.acquire(nowMilliseconds: 29_999)) {
            XCTAssertEqual($0 as? BalanceRelayQueryProcessingError, .rateLimited)
        }

        var concurrent = BalanceRelayQueryLimiter()
        try concurrent.acquire(nowMilliseconds: 40_000)
        try concurrent.acquire(nowMilliseconds: 41_001)
        XCTAssertThrowsError(try concurrent.acquire(nowMilliseconds: 42_002)) {
            XCTAssertEqual($0 as? BalanceRelayQueryProcessingError, .rateLimited)
        }
        concurrent.release()
        concurrent.release()
    }

    func testSectionValidationRejectsUnknownDuplicateAndOutOfRangeParams() throws {
        let now: Int64 = 1_700_000_000_000
        func validate(_ query: BalanceRelayQuery) throws {
            var cache = BalanceRelayReplayCache()
            try BalanceRelayQueryValidator.validate(query, nowMilliseconds: now, replayCache: &cache)
        }

        XCTAssertThrowsError(try validate(BalanceRelayQuery(
            issuedAtMilliseconds: now,
            nonce: "section-query-nonce-0001",
            requestedSections: ["overview", "unknown"]
        ))) { XCTAssertEqual($0 as? BalanceRelayQueryValidationError, .unknownSection) }

        XCTAssertThrowsError(try validate(BalanceRelayQuery(
            issuedAtMilliseconds: now,
            nonce: "section-query-nonce-0002",
            requestedSections: ["overview", "overview"]
        ))) { XCTAssertEqual($0 as? BalanceRelayQueryValidationError, .duplicateSection) }

        XCTAssertThrowsError(try validate(BalanceRelayQuery(
            issuedAtMilliseconds: now,
            nonce: "section-query-nonce-0003",
            requestedSections: ["trend"],
            sectionParams: .init(trend: .init(days: 91))
        ))) { XCTAssertEqual($0 as? BalanceRelayQueryValidationError, .invalidSectionParams) }
    }

    func testIdentityStoreEncryptsTokenAndUsesRestrictivePermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("balance-relay-identity-security-\(UUID().uuidString)")
        temporaryDirectories.append(directory)
        let store = try BalanceRelayIdentityStore(root: directory)
        let identity = BalanceRelayIdentity(
            serverBaseURL: URL(string: "https://relay.example.invalid")!,
            deviceID: "device_security_0005",
            pcToken: "pc-token-that-must-never-appear-in-plaintext"
        )
        try store.save(identity)
        XCTAssertEqual(store.load(), identity)

        let encryptedURL = directory.appendingPathComponent("identity.enc")
        let encrypted = try Data(contentsOf: encryptedURL)
        XCTAssertFalse(encrypted.contains(Data(identity.pcToken.utf8)))
        let attributes = try FileManager.default.attributesOfItem(atPath: encryptedURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        try store.delete()
        XCTAssertNil(store.load())
        // 忘记设备后必须物理移除加密身份文件，保证下次可重新注册配对。
        XCTAssertFalse(FileManager.default.fileExists(atPath: encryptedURL.path))
    }

    func testIdentityStoreDeleteRemovesCacheForRePairing() throws {
        // 验证删除后仅移除数据文件，密钥文件保留，使下一次注册/配对可复用同一密钥文件，
        // 同时缓存记录被彻底清除（不再被判定为已配对）。
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("balance-relay-identity-repair-\(UUID().uuidString)")
        temporaryDirectories.append(directory)
        let store = try BalanceRelayIdentityStore(root: directory)
        let identity = BalanceRelayIdentity(
            serverBaseURL: URL(string: "https://relay.example.invalid")!,
            deviceID: "device_security_0006",
            pcToken: "pc-token-cache-clean"
        )
        try store.save(identity)
        let keyURL = directory.appendingPathComponent(".identity-key")
        let dataURL = directory.appendingPathComponent("identity.enc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataURL.path))

        try store.delete()

        XCTAssertNil(store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: dataURL.path), "缓存身份记录必须被清除")
        XCTAssertTrue(FileManager.default.fileExists(atPath: keyURL.path), "密钥文件应保留以便复用")
    }

    func testAlreadyPairedErrorMapsToClearLocalizedMessage() {
        XCTAssertEqual(
            BalanceRelayClientError.alreadyPaired.localizedDescription,
            "此 Mac 已与设备配对，请先在手机端忘记设备"
        )
        XCTAssertEqual(
            BalanceRelayClientError.pairingRequired.localizedDescription,
            "需要重新生成配对二维码"
        )
    }

    func testDeviceNotFoundErrorMapsToReRegistrationHint() {
        XCTAssertEqual(
            BalanceRelayClientError.deviceNotFound.localizedDescription,
            "设备已在其他端删除，请重新注册"
        )
    }

    func testRegistrationStatusEnumStatesAreDistinct() {
        // 验证 3 态枚举可区分（不依赖网络，纯类型级断言）。
        let registered = BalanceRelayRegistrationStatus.registered(paired: true, disabled: false)
        let notFound = BalanceRelayRegistrationStatus.deviceNotFound
        let invalid = BalanceRelayRegistrationStatus.invalidCredentials
        switch registered {
        case .registered(let paired, let disabled):
            XCTAssertTrue(paired)
            XCTAssertFalse(disabled)
        default:
            XCTFail("registered state should match .registered")
        }
        switch notFound {
        case .deviceNotFound: break
        default: XCTFail("should be .deviceNotFound")
        }
        switch invalid {
        case .invalidCredentials: break
        default: XCTFail("should be .invalidCredentials")
        }
    }

    func testRelayResponseIsEncodedAsTextFramePayload() throws {
        let envelope = BalanceRelayOpaqueEnvelope(
            nonce: Data(repeating: 0x01, count: 12).base64EncodedString(),
            ciphertext: Data([0x02]).base64EncodedString(),
            tag: Data(repeating: 0x03, count: 16).base64EncodedString()
        )

        let text = try BalanceRelayClient.encodeResponseText(
            requestID: "request_text_frame_0001",
            envelope: envelope
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )

        XCTAssertEqual(object["type"] as? String, "relay.response")
        XCTAssertEqual(object["requestId"] as? String, "request_text_frame_0001")
        XCTAssertEqual((object["envelope"] as? [String: Any])?["v"] as? Int, 1)
    }

    @MainActor
    func testForgetIdentityResetsLocalStateEvenWhenServerUnreachable() async throws {
        // "忘记设备"必须无条件清理本地身份缓存并回到注册表单，
        // 即使服务器不可达（DELETE 失败）也不能留下脏状态导致无法重新配对。
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("balance-relay-forget-\(UUID().uuidString)")
        temporaryDirectories.append(directory)
        let store = try BalanceRelayIdentityStore(root: directory)
        let identity = BalanceRelayIdentity(
            serverBaseURL: URL(string: "https://127.0.0.1:1/unreachable")!,
            deviceID: "device_forget_0001",
            pcToken: "pc-token-forget-test"
        )
        try store.save(identity)
        let coordinator = BalanceRelayCoordinator(balanceManager: BalanceManager(), identityStore: store)
        XCTAssertNotNil(coordinator.identity)

        await coordinator.forgetIdentity()

        XCTAssertNil(coordinator.identity)
        XCTAssertNil(coordinator.pairingPayload)
        XCTAssertFalse(coordinator.isPaired)
        XCTAssertEqual(coordinator.registered, false)
        XCTAssertEqual(coordinator.connectionState, .unconfigured)
        XCTAssertNil(store.load())
    }

    @MainActor
    func testStartPairingDoesNotMarkPaired() async throws {
        // 生成二维码 ≠ 已配对：修复后 startPairing 成功不置 isPaired = true，
        // 否则 UI 会直接切到"已配对"并隐藏二维码（原 bug）。
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("balance-relay-pairing-\(UUID().uuidString)")
        temporaryDirectories.append(directory)
        let store = try BalanceRelayIdentityStore(root: directory)
        let identity = BalanceRelayIdentity(
            serverBaseURL: URL(string: "https://127.0.0.1:1/unreachable")!,
            deviceID: "device_pairing_0001",
            pcToken: "pc-token-pairing-test"
        )
        try store.save(identity)
        let coordinator = BalanceRelayCoordinator(balanceManager: BalanceManager(), identityStore: store)

        // 服务器不可达：startPairing 会抛错并走 catch 分支，此时不应是已配对。
        await coordinator.startPairing()
        XCTAssertFalse(coordinator.isPaired, "生成二维码失败或进行中都不应判定为已配对")
    }
}
