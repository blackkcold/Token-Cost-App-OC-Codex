import AppKit
import Foundation
import CodexTokenCostCore

@MainActor
final class BackupScheduler: ObservableObject {
    private let preferencesModel: AppPreferencesModel
    private var backupTask: Task<Void, Never>?
    private var terminationObserver: SchedulerObservationToken?

    init(preferencesModel: AppPreferencesModel) {
        self.preferencesModel = preferencesModel
        terminationObserver = SchedulerObservationToken(
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.stop()
                }
            }
        )
    }

    deinit {
        backupTask?.cancel()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver.rawValue)
        }
    }

    func start() {
        guard backupTask == nil else { return }
        backupTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                } catch {
                    break
                }
                guard let self else { break }
                let shouldBackup = await MainActor.run {
                    let prefs = self.preferencesModel.preferences.backup
                    // 当 launchd 定时任务已接管时，由外部调度器负责定时触发，应用内调度器仅作兜底避免重复备份。
                    return prefs.autoBackupEnabled && !prefs.scheduledTaskEnabled
                }
                guard shouldBackup else { continue }
                let intervalElapsed = await MainActor.run {
                    self.intervalElapsed()
                }
                guard intervalElapsed else { continue }
                await self.preferencesModel.performFullLayeredBackup()
            }
        }
    }

    private func intervalElapsed() -> Bool {
        let prefs = preferencesModel.preferences.backup
        guard let last = prefs.lastBackupDate else { return true }
        return Date().timeIntervalSince(last) >= prefs.autoBackupInterval.timeInterval
    }

    func stop() {
        backupTask?.cancel()
        backupTask = nil
    }
}

private final class SchedulerObservationToken: @unchecked Sendable {
    let rawValue: NSObjectProtocol

    init(_ rawValue: NSObjectProtocol) {
        self.rawValue = rawValue
    }
}
