import Foundation

@MainActor
public final class BalanceRelayCoordinator: ObservableObject {
    @Published public private(set) var connectionState: BalanceRelayConnectionState
    @Published public private(set) var identity: BalanceRelayIdentity?
    @Published public private(set) var pairingPayload: BalanceRelayPairingPayload?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isPaired: Bool = false
    @Published public private(set) var registered: Bool?
    @Published public private(set) var needsRepair: Bool = false
    @Published public private(set) var appOnline: Bool = false
    @Published public private(set) var appLastSeenAt: Int64 = 0
    /// 服务器认为本机 WebSocket 是否在线；nil 表示未知/未配对。用于识别僵尸连接。
    @Published public private(set) var serverOnline: Bool?

    private let balanceManager: BalanceManager
    private let analyticsProvider: (any RelayAnalyticsProviding)?
    private let client: BalanceRelayClient?
    private let configuredServerBaseURL: URL?

    /// 僵尸连接自检周期；自检仅当本地 connected 而服务器 offline 时强制重连。
    private static let selfCheckIntervalSeconds: UInt64 = 10
    private static let reconnectCooldownSeconds: UInt64 = 15
    private var selfCheckTask: Task<Void, Never>?
    private var selfCheckInFlight = false
    private var lastForcedReconnectAt: Date = .distantPast
    private var refreshTask: Task<Void, Never>?

    public init(
        balanceManager: BalanceManager,
        analyticsProvider: (any RelayAnalyticsProviding)? = nil,
        identityStore: BalanceRelayIdentityStore? = nil,
        configuredServerBaseURL: URL? = BalanceRelayEndpoint.configuredURL()
    ) {
        self.balanceManager = balanceManager
        self.analyticsProvider = analyticsProvider
        self.configuredServerBaseURL = configuredServerBaseURL
        let store = identityStore ?? (try? BalanceRelayIdentityStore())
        if let store {
            var stored = store.loadStored()
            if let identity = stored?.identity,
               let configuredServerBaseURL,
               !BalanceRelayEndpoint.matches(identity.serverBaseURL, configuredServerBaseURL) {
                try? store.delete()
                stored = nil
            }
            self.client = BalanceRelayClient(identityStore: store)
            let loadedIdentity = stored?.identity
            self.identity = loadedIdentity
            self.connectionState = loadedIdentity == nil ? .unconfigured : .disconnected
            self.needsRepair = loadedIdentity != nil && (stored?.e2eKey.isEmpty ?? true)
        } else {
            self.client = nil
            self.identity = nil
            self.connectionState = .unconfigured
            self.needsRepair = false
            self.errorMessage = "无法初始化中继设备身份存储"
        }
    }

    public var isEndpointConfigured: Bool {
        configuredServerBaseURL != nil
    }

    public func register(serverBaseURL: URL? = nil, deviceName: String) async {
        do {
            guard let client else { throw BalanceRelayClientError.unconfigured }
            let endpoint: URL
#if DEBUG
            guard let resolvedEndpoint = serverBaseURL ?? configuredServerBaseURL else {
                throw BalanceRelayClientError.unconfigured
            }
            endpoint = resolvedEndpoint
#else
            guard let configuredServerBaseURL else {
                throw BalanceRelayClientError.unconfigured
            }
            endpoint = configuredServerBaseURL
#endif
            let newIdentity = try await client.register(serverBaseURL: endpoint, deviceName: deviceName)
            identity = newIdentity
            connectionState = .disconnected
            isPaired = false
            serverOnline = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 查询服务器端配对状态并更新 UI 三态。
    public func refreshPairingStatus() async {
        guard let client, identity != nil else {
            isPaired = false
            return
        }
        do {
            isPaired = try await client.isPaired()
            errorMessage = nil
        } catch {
            // 查询失败不阻塞 UI，保持上次状态。
        }
    }

    /// 刷新手机端在线状态（从服务器查询），供设置卡片显示"手机在线/离线"。
    public func refreshAppOnlineStatus() async {
        guard let client, identity != nil else {
            appOnline = false
            return
        }
        do {
            let status = try await client.deviceStatus()
            appOnline = status.appOnline
            appLastSeenAt = status.appLastSeenAt
            serverOnline = status.selfOnline
        } catch {
            // 查询失败不阻塞 UI，保持上次状态。
        }
    }

    /// 设置中继详细日志开关，透传给底层客户端（供设置面板调用）。
    public func setRelayLoggingEnabled(_ enabled: Bool) {
        guard let client else { return }
        Task { await client.setLoggingEnabled(enabled) }
    }

    /// 注册状态检测（3 态）：设备不存在（404）时清除本地身份并回到注册表单。
    public func refreshRegistrationStatus() async {
        guard let client, identity != nil else {
            registered = false
            isPaired = false
            return
        }
        do {
            switch try await client.registrationStatus() {
            case .registered(let paired, let disabled):
                registered = true
                isPaired = paired
                if disabled { connectionState = .disconnected }
                errorMessage = nil
            case .deviceNotFound:
                stopSelfCheck()
                registered = false
                isPaired = false
                pairingPayload = nil
                try await client.forgetIdentity()
                identity = nil
                connectionState = .unconfigured
                serverOnline = nil
                errorMessage = "设备已在其他端删除，请重新注册"
            case .invalidCredentials:
                // token 失效但设备存在，标记已注册但可能需重新配对。
                registered = true
            }
        } catch {
            // 网络失败不阻塞 UI，保持上次状态。
        }
    }

    public func startPairing() async {
        do {
            guard let client else { throw BalanceRelayClientError.unconfigured }
            pairingPayload = try await client.startPairing()
            errorMessage = nil
            needsRepair = false
            // 生成二维码 ≠ 已配对；保持配对表单展示二维码，直至手机扫码成功。
            isPaired = false
            try await client.connect(
                queryHandler: { [weak self] query in
                    guard let self else { throw CancellationError() }
                    return try await self.execute(query)
                },
                stateHandler: { [weak self] state in
                    await MainActor.run {
                        self?.connectionState = state
                        if state == .connected { self?.startSelfCheck() }
                    }
                }
            )
        } catch BalanceRelayClientError.alreadyPaired {
            errorMessage = BalanceRelayClientError.alreadyPaired.localizedDescription
            pairingPayload = nil
            // 保持配对表单可操作：用户可"忘记设备"后重新生成二维码。
            isPaired = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 启动周期自检：每 [Self.selfCheckIntervalSeconds] 秒核对服务器端本机在线状态。
    /// 仅在"本地已连接而服务器判离线"时强制重连，绝不在查询失败/网络抖动时重连。
    private func startSelfCheck() {
        stopSelfCheck()
        guard identity != nil, connectionState == .connected || connectionState == .connecting else { return }
        selfCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.selfCheckIntervalSeconds))
                if Task.isCancelled { break }
                await self?.runSelfCheck()
            }
        }
    }

    private func stopSelfCheck() {
        selfCheckTask?.cancel()
        selfCheckTask = nil
    }

    private func runSelfCheck() async {
        guard let client, identity != nil else {
            stopSelfCheck()
            return
        }
        guard connectionState == .connected else { return }
        guard !selfCheckInFlight else { return }
        guard Date().timeIntervalSince(lastForcedReconnectAt) >= TimeInterval(Self.reconnectCooldownSeconds) else { return }

        selfCheckInFlight = true
        defer { selfCheckInFlight = false }

        let serverOnlineResult: Bool
        do {
            serverOnlineResult = try await client.serverSelfOnline()
        } catch {
            return
        }
        serverOnline = serverOnlineResult
        if serverOnlineResult {
            return
        }
        BalanceLog.relay.error("僵尸连接自检：本地 connected 但服务器判本机 offline，强制重连")
        await client.disconnect()
        await autoConnect()
        lastForcedReconnectAt = Date()
    }

    public func disconnect() async {
        stopSelfCheck()
        await client?.disconnect()
        connectionState = identity == nil ? .unconfigured : .disconnected
    }

    /// 已配对设备重新连接中继（不重置端到端密钥）。
    public func connectRelay() async {
        guard let client, identity != nil else { return }
        do {
            try await client.connect(
                queryHandler: { [weak self] query in
                    guard let self else { throw CancellationError() }
                    return try await self.execute(query)
                },
                stateHandler: { [weak self] state in
                    await MainActor.run {
                        self?.connectionState = state
                        if state == .connected { self?.startSelfCheck() }
                    }
                }
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 已配对且持有 e2eKey 时自动建立中继连接；未配对或缺少 e2eKey 时静默返回。
    public func autoConnect() async {
        guard let client else { return }
        await client.autoConnect(
            queryHandler: { [weak self] query in
                guard let self else { throw CancellationError() }
                return try await self.execute(query)
            },
            stateHandler: { [weak self] state in
                await MainActor.run {
                    self?.connectionState = state
                    if state == .connected { self?.startSelfCheck() }
                }
            }
        )
    }

    /// 生命周期感知重连：仅当已配对但当前未连接（休眠/网络切换后掉线）时重建连接。
    /// 已连接时静默返回，避免重复建立 WebSocket。
    public func reconnectIfNeeded() async {
        guard connectionState != .connected, connectionState != .connecting else { return }
        await autoConnect()
    }

    /// 休眠时主动断开 WebSocket，避免进入僵尸连接。
    public func suspendConnection() async {
        guard connectionState == .connected || connectionState == .connecting || connectionState == .reconnecting else { return }
        await disconnect()
    }

    public func forgetIdentity() async {
        stopSelfCheck()
        // 服务器删除为 best-effort（deleteIdentity 内部已兜底）；即使失败也必须清理本地身份，保证能重新配对。
        try? await client?.deleteIdentity()
        identity = nil
        pairingPayload = nil
        isPaired = false
        registered = false
        needsRepair = false
        connectionState = .unconfigured
        serverOnline = nil
        errorMessage = nil
    }

    /// 处理手机端发来的余额查询。
    ///
    /// 关键约束：本方法运行在 `BalanceRelayClient`（actor）的 receive 循环派生的 Task 里，
    /// 若在此同步等待 `balanceManager.refresh()` 完成（最长 30s），会占用该 Task，
    /// 但仍不影响 receive 循环本身（handleMessage 已在独立 Task 中执行），
    /// 因此不会阻塞心跳，也不会重现服务器 terminate 的问题。
    ///
    /// 采用「缓存即时返回 + 后台异步刷新」：
    /// - 有缓存时直接返回，query 秒回；
    /// - 首次查询缓存为空时，后台触发一次全量刷新并短时等待（上限 [freshWaitSeconds]），
    ///   拿到非空结果即返回，避免手机端首次查询拿到空列表；
    /// - 无论是否等到，都在后台继续刷新，使下次查询拿到最新数据。
    private func execute(_ query: BalanceRelayQuery) async throws -> BalanceRelayResponse {
        guard query.action == "balance.refresh" else {
            throw BalanceRelayQueryValidationError.unsupportedAction
        }
        triggerBackgroundRefresh()
        let snapshots: [BalanceSnapshot]
        if balanceManager.snapshots.isEmpty {
            snapshots = await waitForSnapshots(timeout: freshWaitSeconds)
        } else {
            snapshots = balanceManager.snapshots
        }
        guard let requestedSections = query.requestedSections, !requestedSections.isEmpty else {
            return BalanceRelayResponse(requestNonce: query.nonce, snapshots: snapshots)
        }
        guard let analytics = await analyticsProvider?.currentAnalytics() else {
            return BalanceRelayResponse(
                requestNonce: query.nonce,
                snapshots: snapshots,
                error: BalanceRelayWireError(code: "ANALYTICS_UNAVAILABLE", message: "Analytics are not available")
            )
        }
        do {
            let sections = try RelaySectionBuilder.build(
                requestedSections: requestedSections,
                params: query.sectionParams,
                analytics: analytics
            )
            return BalanceRelayResponse(
                requestNonce: query.nonce,
                snapshots: snapshots,
                compression: "zlib",
                sections: sections
            )
        } catch RelaySectionBuildError.sectionTooLarge {
            return BalanceRelayResponse(
                requestNonce: query.nonce,
                snapshots: snapshots,
                error: BalanceRelayWireError(code: "SECTION_TOO_LARGE", message: "An analytics section exceeds the plaintext limit")
            )
        } catch RelaySectionBuildError.invalidNumber {
            return BalanceRelayResponse(
                requestNonce: query.nonce,
                snapshots: snapshots,
                error: BalanceRelayWireError(code: "INVALID_SECTION_DATA", message: "An analytics section contains invalid numeric data")
            )
        }
    }

    /// 首次空数据时的短等待上限：远小于服务器 QUERY_TIMEOUT_SECONDS（45s），
    /// 且 handleMessage 在独立 Task 中，不会阻塞心跳。
    private var freshWaitSeconds: TimeInterval { 4 }

    /// 每 200ms 轮询 balanceManager.snapshots，直到非空或超时；返回当前快照（可能仍为空）。
    private func waitForSnapshots(timeout: TimeInterval) async -> [BalanceSnapshot] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !balanceManager.snapshots.isEmpty {
                return balanceManager.snapshots
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return balanceManager.snapshots
    }

    /// 在后台触发全量刷新，不阻塞中继响应；`refresh` 自带并发保护，重复触发会安全合并。
    private func triggerBackgroundRefresh() {
        guard refreshTask == nil else { return }
        let manager = balanceManager
        refreshTask = Task { @MainActor [weak self] in
            await manager.refresh(force: true)
            self?.refreshTask = nil
        }
    }
}
