import Foundation
import os

public enum BalanceRelayClientError: Error, LocalizedError {
    case unconfigured
    case pairingRequired
    case alreadyPaired
    case deviceNotFound
    case invalidServerResponse
    case server(status: Int, code: String?, message: String)

    public var errorDescription: String? {
        switch self {
        case .unconfigured: return "中继设备尚未注册"
        case .pairingRequired: return "需要重新生成配对二维码"
        case .alreadyPaired: return "此 Mac 已与设备配对，请先在手机端忘记设备"
        case .deviceNotFound: return "设备已在其他端删除，请重新注册"
        case .invalidServerResponse: return "中继服务器响应无效"
        case .server(let status, _, let message): return "中继服务器 HTTP \(status)：\(message)"
        }
    }
}

/// 注册状态检测结果（3 态）。
public enum BalanceRelayRegistrationStatus: Sendable {
    case registered(paired: Bool, disabled: Bool)
    case deviceNotFound
    case invalidCredentials
}

public actor BalanceRelayClient {
    public typealias QueryHandler = @Sendable (BalanceRelayQuery) async throws -> BalanceRelayResponse
    public typealias StateHandler = @Sendable (BalanceRelayConnectionState) async -> Void

    private static let logger = Logger(subsystem: "com.yanghaoran.CodexTokenCost", category: "relay-client")

    private struct RegistrationResponse: Decodable {
        let deviceId: String
        let pcToken: String
    }

    private struct PairingResponse: Decodable {
        let deviceId: String
        let pairCode: String
        let expiresAt: Int64
    }

    private struct ServerMessage: Decodable {
        let type: String
        let requestId: String
        let envelope: BalanceRelayOpaqueEnvelope
    }

    private struct ClientMessage: Encodable {
        let type: String
        let requestId: String
        let envelope: BalanceRelayOpaqueEnvelope
    }

    private struct ErrorResponse: Decodable {
        let code: String?
        let error: String
    }

    private let identityStore: BalanceRelayIdentityStore
    private let session: URLSession
    private var identity: BalanceRelayIdentity?
    private var e2eKey: Data?
    private var socket: URLSessionWebSocketTask?
    private var connectionTask: Task<Void, Never>?
    private var connectionGeneration: UInt64 = 0
    private var queryHandler: QueryHandler?
    private var stateHandler: StateHandler?
    private var seenQueryNonces: Set<String> = []

    /// 是否输出详细中继日志（连接/断连/心跳/查询事件）。
    /// 由设置面板的"中继日志"开关控制，默认关闭；关闭时仍保留 error 级日志以利排查。
    private var loggingEnabled = false

    public init(identityStore: BalanceRelayIdentityStore) {
        self.identityStore = identityStore
        let stored = identityStore.loadStored()
        self.identity = stored?.identity
        self.e2eKey = (stored?.e2eKey.isEmpty == false) ? stored?.e2eKey : nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpShouldSetCookies = false
        self.session = URLSession(configuration: configuration)
    }

    /// 设置详细中继日志开关（幂等，供设置面板调用）。
    public func setLoggingEnabled(_ enabled: Bool) {
        loggingEnabled = enabled
    }

    private func logInfo(_ message: String) {
        guard loggingEnabled else { return }
        BalanceLog.relay.info("\(message, privacy: .public)")
    }

    private func logError(_ message: String) {
        BalanceLog.relay.error("\(message, privacy: .public)")
    }

    public func savedIdentity() -> BalanceRelayIdentity? {
        identity
    }

    /// 查询服务器端本机 WebSocket 在线状态（PC token 认证），用于僵尸连接自检。
    /// 仅当 HTTP 查询成功且服务器明确返回 online 时才返回该值；网络/HTTP 失败直接抛错，
    /// 调用方绝不能把失败当作"离线"来触发重连。
    public func serverSelfOnline() async throws -> Bool {
        guard let identity else { throw BalanceRelayClientError.unconfigured }
        let data = try await request(
            baseURL: identity.serverBaseURL,
            path: "/api/v1/device/pairing-status",
            method: "GET",
            body: Data(),
            identity: identity
        )
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let online = object["online"] as? Bool
        else { throw BalanceRelayClientError.invalidServerResponse }
        return online
    }

    /// 查询服务器端配对状态（PC token 认证），用于 UI 三态判断。
    public func isPaired() async throws -> Bool {
        guard let identity else { throw BalanceRelayClientError.unconfigured }
        let data = try await request(
            baseURL: identity.serverBaseURL,
            path: "/api/v1/device/pairing-status",
            method: "GET",
            body: Data(),
            identity: identity
        )
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let paired = object["paired"] as? Bool
        else { throw BalanceRelayClientError.invalidServerResponse }
        return paired
    }

    /// 查询服务器端设备状态（PC token 认证），含手机端在线情况，用于 UI 显示。
    public func deviceStatus() async throws -> BalanceRelayDeviceStatus {
        guard let identity else { throw BalanceRelayClientError.unconfigured }
        let data = try await request(
            baseURL: identity.serverBaseURL,
            path: "/api/v1/device/pairing-status",
            method: "GET",
            body: Data(),
            identity: identity
        )
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BalanceRelayClientError.invalidServerResponse
        }
        return BalanceRelayDeviceStatus(
            appOnline: object["appOnline"] as? Bool ?? false,
            appLastSeenAt: (object["appLastSeenAt"] as? NSNumber)?.int64Value ?? 0,
            selfOnline: object["online"] as? Bool ?? false
        )
    }

    /// 注册状态检测（3 态）：区分 registered / device_not_found / invalid_credentials。
    public func registrationStatus() async throws -> BalanceRelayRegistrationStatus {
        guard let identity else { throw BalanceRelayClientError.unconfigured }
        var request = URLRequest(url: apiURL(baseURL: identity.serverBaseURL, path: "/api/v1/device/registration-status"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(identity.pcToken)", forHTTPHeaderField: "Authorization")
        request.setValue(identity.deviceID, forHTTPHeaderField: "X-Device-Id")
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BalanceRelayClientError.invalidServerResponse
        }
        switch http.statusCode {
        case 200:
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["registered"] is Bool
            else { throw BalanceRelayClientError.invalidServerResponse }
            return .registered(paired: object["paired"] as? Bool ?? false, disabled: object["disabled"] as? Bool ?? false)
        case 404:
            return .deviceNotFound
        case 401:
            return .invalidCredentials
        default:
            let error = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw BalanceRelayClientError.server(
                status: http.statusCode,
                code: error?.code,
                message: error?.error ?? "检测失败"
            )
        }
    }

    /// 彻底删除设备：撤销服务器记录（best-effort）并保证清理本地身份缓存。
    /// 服务器删除失败不抛出，以便"忘记设备"始终能清除本地缓存、允许重新配对。
    public func deleteIdentity() async throws {
        guard let identity else { throw BalanceRelayClientError.unconfigured }
        do {
            var request = URLRequest(url: apiURL(baseURL: identity.serverBaseURL, path: "/api/v1/devices"))
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(identity.pcToken)", forHTTPHeaderField: "Authorization")
            request.setValue(identity.deviceID, forHTTPHeaderField: "X-Device-Id")
            _ = try await session.data(for: request)
        } catch {
            // 服务器删除失败（如网络中断）：忽略，继续本地清理。
        }
        await disconnect()
        try identityStore.delete()
        self.identity = nil
        e2eKey = nil
        seenQueryNonces.removeAll()
        await stateHandler?(.unconfigured)
    }

    @discardableResult
    public func register(serverBaseURL: URL, deviceName: String) async throws -> BalanceRelayIdentity {
        let body = try JSONSerialization.data(withJSONObject: ["name": deviceName])
        let data = try await request(
            baseURL: serverBaseURL,
            path: "/api/v1/devices/register",
            method: "POST",
            body: body
        )
        let response = try JSONDecoder().decode(RegistrationResponse.self, from: data)
        let newIdentity = BalanceRelayIdentity(
            serverBaseURL: serverBaseURL,
            deviceID: response.deviceId,
            pcToken: response.pcToken
        )
        try identityStore.save(newIdentity)
        identity = newIdentity
        return newIdentity
    }

    public func startPairing() async throws -> BalanceRelayPairingPayload {
        guard let identity else { throw BalanceRelayClientError.unconfigured }
        let data: Data
        do {
            data = try await request(
                baseURL: identity.serverBaseURL,
                path: "/api/v1/pair/start",
                method: "POST",
                body: Data("{}".utf8),
                identity: identity
            )
        } catch BalanceRelayClientError.server(let status, let code, _)
            where status == 409 && (code == nil || code == "ALREADY_PAIRED") {
            throw BalanceRelayClientError.alreadyPaired
        }
        let response = try JSONDecoder().decode(PairingResponse.self, from: data)
        let key = BalanceRelayCrypto.generateKey()
        e2eKey = key
        seenQueryNonces.removeAll(keepingCapacity: true)
        // 持久化 e2eKey，使 App 重启后能自动重连中继，无需重新扫码配对。
        try? identityStore.save(BalanceRelayStoredIdentity(identity: identity, e2eKey: key))
        return BalanceRelayPairingPayload(
            deviceID: response.deviceId,
            pairCode: response.pairCode,
            e2eKey: key,
            expiresAtMilliseconds: response.expiresAt
        )
    }

    public func connect(queryHandler: @escaping QueryHandler, stateHandler: @escaping StateHandler) async throws {
        guard identity != nil else { throw BalanceRelayClientError.unconfigured }
        guard e2eKey != nil else { throw BalanceRelayClientError.pairingRequired }
        self.queryHandler = queryHandler
        self.stateHandler = stateHandler
        startConnectionLoopIfNeeded()
    }

    /// 已配对且持有 e2eKey 时自动建立中继连接；未配对或缺少 e2eKey 时静默返回，不报错。
    public func autoConnect(queryHandler: @escaping QueryHandler, stateHandler: @escaping StateHandler) async {
        guard identity != nil, e2eKey != nil else {
            Self.logger.info("autoConnect skipped: identity=\(self.identity != nil), e2eKey=\(self.e2eKey != nil)")
            return
        }
        Self.logger.info("autoConnect starting relay connection")
        self.queryHandler = queryHandler
        self.stateHandler = stateHandler
        startConnectionLoopIfNeeded()
    }

    public func disconnect() async {
        connectionGeneration &+= 1
        let task = connectionTask
        let activeSocket = socket
        connectionTask = nil
        socket = nil
        task?.cancel()
        activeSocket?.cancel(with: .normalClosure, reason: nil)
        await stateHandler?(.disconnected)
    }

    public func forgetIdentity() async throws {
        await disconnect()
        try identityStore.delete()
        identity = nil
        e2eKey = nil
        seenQueryNonces.removeAll()
        await stateHandler?(.unconfigured)
    }

    /// 撤销服务器记录并清除本地身份，保证"忘记设备"的唯一性。
    /// 服务器用 PC token 撤销该设备，同时断开其已配对 WS。
    public func revokeIdentity() async throws {
        guard let identity else { throw BalanceRelayClientError.unconfigured }
        var request = URLRequest(url: apiURL(baseURL: identity.serverBaseURL, path: "/api/v1/devices/revoke"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(identity.pcToken)", forHTTPHeaderField: "Authorization")
        request.setValue(identity.deviceID, forHTTPHeaderField: "X-Device-Id")
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BalanceRelayClientError.invalidServerResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw BalanceRelayClientError.server(
                status: http.statusCode,
                code: error?.code,
                message: error?.error ?? "撤销失败"
            )
        }
        await disconnect()
        try identityStore.delete()
        self.identity = nil
        e2eKey = nil
        seenQueryNonces.removeAll()
        await stateHandler?(.unconfigured)
    }

    private func startConnectionLoopIfNeeded() {
        guard connectionTask == nil else { return }
        connectionGeneration &+= 1
        let generation = connectionGeneration
        connectionTask = Task { await connectionLoop(generation: generation) }
    }

    private func connectionLoop(generation: UInt64) async {
        var attempt = 0
        while !Task.isCancelled, generation == connectionGeneration {
            await stateHandler?(attempt == 0 ? .connecting : .reconnecting)
            do {
                try await openAndReceive()
                attempt = 0
            } catch {
                if Task.isCancelled { break }
                attempt += 1
                logInfo("relay connection failed (attempt \(attempt))")
            }
            if Task.isCancelled { break }
            // 收紧退避：初始 1s、上限 10s + 25% 抖动，缩短掉线后手机端可见的 offline 窗口。
            let base = min(pow(2.0, Double(attempt)), 10.0)
            let jitter = Double.random(in: 0...(base * 0.25))
            try? await Task.sleep(for: .seconds(base + jitter))
        }
        if generation == connectionGeneration {
            connectionTask = nil
            await stateHandler?(.disconnected)
        }
    }

    private func openAndReceive() async throws {
        guard let identity else { throw BalanceRelayClientError.unconfigured }
        var request = URLRequest(url: websocketURL(baseURL: identity.serverBaseURL))
        request.setValue("Bearer \(identity.pcToken)", forHTTPHeaderField: "Authorization")
        request.setValue(identity.deviceID, forHTTPHeaderField: "X-Device-Id")
        let task = session.webSocketTask(with: request)
        socket = task
        task.resume()
        try await sendPing(task)
        try Task.checkCancellation()
        await stateHandler?(.connected)
        logInfo("relay websocket connected")
        let heartbeatWorker = Task { await heartbeat(task) }
        defer {
            heartbeatWorker.cancel()
            if socket === task { socket = nil }
        }
        while !Task.isCancelled {
            let message = try await task.receive()
            let data: Data
            switch message {
            case .data(let value): data = value
            case .string(let value): data = Data(value.utf8)
            @unknown default: throw BalanceRelayClientError.invalidServerResponse
            }
            // 业务处理与接收循环解耦：不阻塞 `receive()`，确保服务器心跳 ping 与
            // 后续消息始终能被及时读取并回应，避免单条慢处理导致连接被服务器 terminate。
            // 业务查询异常已在 handleMessage 内部隔离为失败响应；此处仅处理协议级错误，
            // 记录并取消连接以驱动重连，等价于原顺序 await 时抛错导致的断开行为。
            Task {
                do {
                    try await handleMessage(data, task: task)
                } catch {
                    Self.logger.error("relay handleMessage failed")
                    task.cancel(with: .protocolError, reason: "handleMessage failure".data(using: .utf8))
                }
            }
        }
    }

    private func heartbeat(_ task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(25))
            if Task.isCancelled { return }
            do {
                try await sendPing(task)
            } catch {
                logError("relay heartbeat failed")
                task.cancel(with: .goingAway, reason: nil)
                return
            }
        }
    }

    private func sendPing(_ task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func handleMessage(_ data: Data, task: URLSessionWebSocketTask) async throws {
        guard data.count <= 65_536, let key = e2eKey, let queryHandler else {
            throw BalanceRelayClientError.invalidServerResponse
        }
        let message = try JSONDecoder().decode(ServerMessage.self, from: data)
        guard message.type == "relay.request" else { throw BalanceRelayClientError.invalidServerResponse }
        let query = try BalanceRelayCrypto.open(message.envelope, keyData: key, as: BalanceRelayQuery.self)
        try BalanceRelayQueryValidator.validate(query, seenNonces: &seenQueryNonces)
        logInfo("relay received query requestId=\(message.requestId)")
        // queryHandler（业务查询）异常必须隔离，不能因此关闭 WS 连接；
        // 否则服务器会 detach 本设备，后续手机端请求全部返回 "PC offline"。
        let response: BalanceRelayResponse
        do {
            response = try await queryHandler(query)
        } catch {
            let failure = BalanceRelayResponse(snapshots: [BalanceSnapshot.unavailable(
                .opencodeGo,
                reason: "Mac 端查询失败：\(error.localizedDescription)"
            )])
            let failureEnvelope = try BalanceRelayCrypto.seal(failure, keyData: key)
            let failureText = try Self.encodeResponseText(
                requestID: message.requestId,
                envelope: failureEnvelope
            )
            try await task.send(.string(failureText))
            logError("relay query failed for requestId=\(message.requestId)")
            return
        }
        let envelope = try BalanceRelayCrypto.seal(response, keyData: key)
        let replyText = try Self.encodeResponseText(requestID: message.requestId, envelope: envelope)
        try await task.send(.string(replyText))
        logInfo("relay sent response requestId=\(message.requestId) snapshots=\(response.snapshots.count)")
    }

    static func encodeResponseText(
        requestID: String,
        envelope: BalanceRelayOpaqueEnvelope
    ) throws -> String {
        let data = try JSONEncoder().encode(
            ClientMessage(type: "relay.response", requestId: requestID, envelope: envelope)
        )
        guard let text = String(data: data, encoding: .utf8) else {
            throw BalanceRelayClientError.invalidServerResponse
        }
        return text
    }

    private func request(
        baseURL: URL,
        path: String,
        method: String,
        body: Data,
        identity: BalanceRelayIdentity? = nil
    ) async throws -> Data {
        var request = URLRequest(url: apiURL(baseURL: baseURL, path: path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let identity {
            request.setValue("Bearer \(identity.pcToken)", forHTTPHeaderField: "Authorization")
            request.setValue(identity.deviceID, forHTTPHeaderField: "X-Device-Id")
        }
        let (data, response) = try await session.data(for: request)
        guard data.count <= 65_536, let http = response as? HTTPURLResponse else {
            throw BalanceRelayClientError.invalidServerResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw BalanceRelayClientError.server(
                status: http.statusCode,
                code: error?.code,
                message: error?.error ?? "请求失败"
            )
        }
        return data
    }

    private func apiURL(baseURL: URL, path: String) -> URL {
        baseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private func websocketURL(baseURL: URL) -> URL {
        var components = URLComponents(url: apiURL(baseURL: baseURL, path: "/ws/pc"), resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        return components.url!
    }
}
