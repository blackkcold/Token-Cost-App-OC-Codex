import AppKit
import Foundation
import Network
import CodexTokenCostCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var balanceFloatingPanelCoordinator: BalanceFloatingPanelCoordinator?
    static var relayCoordinator: BalanceRelayCoordinator?

    private var lifecycleManager: WindowLifecycleManager?
    private var observers: [NSObjectProtocol] = []
    private var pathMonitor: NWPathMonitor?
    private var appOnlineTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let parentDir = Bundle.main.bundleURL.deletingLastPathComponent()
        UpdateChecker.cleanupOldBackup(in: parentDir)

        // 已配对设备启动即建立中继 WebSocket 并常驻，不依赖任何窗口状态，
        // 使手机端即使主窗口未打开也能查询余额。
        Task {
            guard let coordinator = AppDelegate.relayCoordinator else { return }
            await coordinator.refreshRegistrationStatus()
            await coordinator.autoConnect()
        }

        registerRelayLifecycleObservers()
        startNetworkPathMonitor()
        startAppOnlinePolling()

        lifecycleManager = WindowLifecycleManager.withDefaultPolicies()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        lifecycleManager?.windowDidOpen(identifier: "main")
        DispatchQueue.main.async {
            AppDelegate.balanceFloatingPanelCoordinator?.requestInitialPresentation()
        }
        lifecycleManager?.startObservingWindows(
            onWillClose: { [weak lifecycleManager] window in
            guard let manager = lifecycleManager else { return }
            guard manager.isManagedWindow(window) else { return }
            if manager.isMainWindow(window) {
                manager.windowWillClose(identifier: "main")
            } else if let identifier = window.identifier?.rawValue {
                manager.windowWillClose(identifier: identifier)
            }
            manager.syncDockPolicyAfterWindowClose()
        }, onDidBecomeKey: { [weak lifecycleManager] window in
            guard let manager = lifecycleManager else { return }
            guard manager.isManagedWindow(window) else { return }
            guard let identifier = window.identifier?.rawValue else { return }
            manager.windowDidOpen(identifier: identifier)
        })
    }

    /// 监听系统休眠/唤醒与应用激活，驱动中继 WebSocket 的断开与重连：
    /// - 休眠时主动断开，避免本地连接进入"僵尸"状态；
    /// - 唤醒/激活时若未连接则重建（幂等，已连接时不重复建连）。
    private func registerRelayLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.relayCoordinator?.suspendConnection()
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.relayCoordinator?.reconnectIfNeeded()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.relayCoordinator?.reconnectIfNeeded()
            }
        })
    }

    /// 监听网络路径变化：网络恢复/切换时主动重连中继，缩短掉线窗口。
    /// 依赖 NWPathMonitor，路径变为可用且中继未连接时触发重建。
    private func startNetworkPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                await self?.relayCoordinator?.reconnectIfNeeded()
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        pathMonitor = monitor
    }

    /// 周期刷新手机端在线状态，供设置卡片显示"手机在线/离线"。
    private func startAppOnlinePolling() {
        appOnlineTimer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.relayCoordinator?.refreshAppOnlineStatus()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        appOnlineTimer = timer
        Task { @MainActor [weak self] in
            await self?.relayCoordinator?.refreshAppOnlineStatus()
        }
    }

    private var relayCoordinator: BalanceRelayCoordinator? { AppDelegate.relayCoordinator }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        lifecycleManager?.hideFromDock()
        return false
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        lifecycleManager?.syncDockPolicy()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appOnlineTimer?.invalidate()
        pathMonitor?.cancel()
        AppDelegate.balanceFloatingPanelCoordinator?.markApplicationTerminating()
    }
}
