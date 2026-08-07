import CoreImage.CIFilterBuiltins
import SwiftUI
import CodexTokenCostCore

struct BalanceRelaySettingsCard: View {
    @ObservedObject private var coordinator: BalanceRelayCoordinator
    @State private var serverURL = ProcessInfo.processInfo.environment[BalanceRelayEndpoint.environmentKey] ?? ""
    @State private var deviceName = Host.current().localizedName ?? "Mac"
    @State private var isWorking = false
    let palette: TokenCostPalette
    var relayLoggingBinding: Binding<Bool>?

    init(
        relayCoordinator: BalanceRelayCoordinator,
        palette: TokenCostPalette,
        relayLoggingBinding: Binding<Bool>? = nil
    ) {
        _coordinator = ObservedObject(wrappedValue: relayCoordinator)
        self.palette = palette
        self.relayLoggingBinding = relayLoggingBinding
    }

    var body: some View {
        SettingsSurfaceCard(
            title: "手机安全中继",
            subtitle: "凭证留在当前 Mac；云端只转发端到端加密的查询信封",
            role: .secondary,
            palette: palette
        ) {
            VStack(alignment: .leading, spacing: 14) {
                statusRow
                if coordinator.needsRepair {
                    repairBanner
                }
                if coordinator.identity == nil {
                    registrationForm
                } else if coordinator.isPaired {
                    pairedControls
                } else {
                    pairingForm
                }
                if let errorMessage = coordinator.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(palette.danger)
                        .textSelection(.enabled)
                }
                if let relayLoggingBinding {
                    HStack(spacing: 8) {
                        Toggle("中继日志", isOn: relayLoggingBinding)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Text("开启后记录连接/断连/心跳/查询事件，供排查")
                            .font(.caption2)
                            .foregroundStyle(palette.subtitle)
                    }
                    .onChange(of: relayLoggingBinding.wrappedValue) { _, enabled in
                        coordinator.setRelayLoggingEnabled(enabled)
                    }
                }
            }
        }
        .task {
            // 启动时应用日志开关偏好到中继客户端。
            if let enabled = relayLoggingBinding?.wrappedValue {
                coordinator.setRelayLoggingEnabled(enabled)
            }
            // 启动时检测注册状态与配对状态（设备若已在其他端删除会自动回到注册表单）。
            await coordinator.refreshRegistrationStatus()
            await coordinator.refreshPairingStatus()
            await coordinator.refreshAppOnlineStatus()
            // 处于配对表单（已生成二维码但未配对）时轮询服务器，手机扫码成功后自动切到"已配对"并隐藏二维码。
            while !Task.isCancelled {
                if coordinator.identity != nil && !coordinator.isPaired {
                    await coordinator.refreshPairingStatus()
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.7), radius: 5)
            Text(statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.title)
            Spacer()
            if coordinator.identity != nil {
                Text(appStatusText)
                    .font(.caption2)
                    .foregroundStyle(coordinator.appOnline ? palette.success : palette.subtitle)
                    .textSelection(.enabled)
                Text(serverStatusText)
                    .font(.caption2)
                    .foregroundStyle(serverStatusColor)
                    .textSelection(.enabled)
            }
            if let identity = coordinator.identity {
                Text(verbatim: identity.deviceID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(palette.subtitle)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("中继状态：\(statusText)")
    }

    private var appStatusText: String {
        coordinator.appOnline ? "手机在线" : "手机离线"
    }

    private var serverStatusText: String {
        guard let serverOnline = coordinator.serverOnline else { return "服务器状态未知" }
        return serverOnline ? "服务器在线" : "服务器离线"
    }

    private var serverStatusColor: Color {
        guard let serverOnline = coordinator.serverOnline else { return palette.subtitle }
        return serverOnline ? palette.success : palette.warning
    }

    private var repairBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(palette.warning)
            VStack(alignment: .leading, spacing: 6) {
                Text("检测到旧配对，缺少端到端密钥，无法自动连接中继。")
                    .font(.caption)
                    .foregroundStyle(palette.title)
                Text("请重新生成配对二维码并让手机端重新扫码，以恢复连接。")
                    .font(.caption2)
                    .foregroundStyle(palette.subtitle)
                Button {
                    isWorking = true
                    Task {
                        await coordinator.startPairing()
                        isWorking = false
                    }
                } label: {
                    Label("重新配对", systemImage: "qrcode")
                }
                .settingsGlassButtonStyle(prominent: true)
                .disabled(isWorking)
            }
            Spacer()
        }
        .padding(12)
        .settingsInsetSurface(
            in: RoundedRectangle(cornerRadius: TokenRadius.compact, style: .continuous),
            palette: palette
        )
    }

    private var registrationForm: some View {
        VStack(alignment: .leading, spacing: 10) {
#if DEBUG
            TextField("中继服务器", text: $serverURL)
                .textFieldStyle(.roundedBorder)
#else
            Label(
                coordinator.isEndpointConfigured ? "Production Relay 已配置" : "Production Relay 配置缺失",
                systemImage: coordinator.isEndpointConfigured ? "checkmark.shield" : "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(coordinator.isEndpointConfigured ? palette.success : palette.danger)
#endif
            TextField("设备名称", text: $deviceName)
                .textFieldStyle(.roundedBorder)
            Button {
#if DEBUG
                guard let url = validatedServerURL else { return }
#endif
                isWorking = true
                Task {
#if DEBUG
                    await coordinator.register(serverBaseURL: url, deviceName: deviceName)
#else
                    await coordinator.register(deviceName: deviceName)
#endif
                    isWorking = false
                }
            } label: {
                Label("注册此 Mac", systemImage: "desktopcomputer.and.arrow.down")
            }
            .settingsGlassButtonStyle(prominent: true)
            .disabled(isWorking || !registrationInputValid || deviceName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var registrationInputValid: Bool {
#if DEBUG
        validatedServerURL != nil
#else
        coordinator.isEndpointConfigured
#endif
    }

    private var pairingForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                isWorking = true
                Task {
                    await coordinator.startPairing()
                    isWorking = false
                }
            } label: {
                Label("生成配对二维码", systemImage: "qrcode")
            }
            .settingsGlassButtonStyle(prominent: true)
            .disabled(isWorking)

            if let payload = coordinator.pairingPayload,
               let qrString = payload.qrString {
                pairingPanel(payload: payload, qrString: qrString)
            }

            Button(role: .destructive) {
                Task { await coordinator.forgetIdentity() }
            } label: {
                Label("忘记设备", systemImage: "trash")
            }
            .settingsGlassButtonStyle(prominent: false)
        }
    }

    private var pairedControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let identity = coordinator.identity {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(palette.success)
                    Text(verbatim: "已配对设备：\(identity.deviceID)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.title)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        await coordinator.connectRelay()
                        // 连接刷新后复检注册状态：设备若已被其他端删除则自动回到注册表单。
                        await coordinator.refreshRegistrationStatus()
                        await coordinator.refreshPairingStatus()
                    }
                } label: {
                    Label("连接中继", systemImage: "network")
                }
                .settingsGlassButtonStyle(prominent: true)
                .disabled(coordinator.connectionState == .connected)

                Button {
                    Task { await coordinator.disconnect() }
                } label: {
                    Label("断开", systemImage: "network.slash")
                }
                .settingsGlassButtonStyle(prominent: false)
                .disabled(coordinator.connectionState == .disconnected || coordinator.connectionState == .unconfigured)

                Button(role: .destructive) {
                    Task { await coordinator.forgetIdentity() }
                } label: {
                    Label("忘记设备", systemImage: "trash")
                }
                .settingsGlassButtonStyle(prominent: false)
            }
        }
    }

    private func pairingPanel(payload: BalanceRelayPairingPayload, qrString: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            RelayQRCodeView(value: qrString)
                .frame(width: 176, height: 176)
                .accessibilityLabel("手机配对二维码")
            VStack(alignment: .leading, spacing: 8) {
                Text("用 Android App 扫描")
                    .font(.headline)
                    .foregroundStyle(palette.title)
                Text("二维码五分钟有效且只能使用一次。二维码包含本地生成的端到端密钥；服务器不会获得该密钥。")
                    .font(.caption)
                    .foregroundStyle(palette.subtitle)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Mac 重启后需重新配对，Provider 凭证不会经由中继落盘或上传。")
                    .font(.caption2)
                    .foregroundStyle(palette.warning)
            }
            Spacer()
        }
        .padding(12)
        .settingsInsetSurface(
            in: RoundedRectangle(cornerRadius: TokenRadius.compact, style: .continuous),
            palette: palette
        )
    }

    private var validatedServerURL: URL? {
        BalanceRelayEndpoint.validatedURL(serverURL, allowInsecure: true)
    }

    private var statusColor: Color {
        switch coordinator.connectionState {
        case .connected: return palette.success
        case .connecting, .reconnecting: return palette.warning
        case .unconfigured, .disconnected: return palette.subtitle
        }
    }

    private var statusText: String {
        switch coordinator.connectionState {
        case .unconfigured: return "未注册"
        case .disconnected: return "已注册 · 离线"
        case .connecting: return "正在连接"
        case .connected: return "中继在线"
        case .reconnecting: return "正在安全重连"
        }
    }
}

private struct RelayQRCodeView: View {
    let value: String
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    var body: some View {
        Group {
            if let image = qrImage {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 72))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.white)
        .compositingGroup()
        .clipShape(.rect(cornerRadius: 8))
    }

    private var qrImage: NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = context.createCGImage(output, from: output.extent)
        else { return nil }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}
