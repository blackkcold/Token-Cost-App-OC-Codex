import Foundation
import AppKit
import CodexTokenCostCore

@MainActor
final class UpdateCheckerModel: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(version: String)
        case updateAvailable(version: String)
        case downloading(progress: Double)
        case downloadComplete
        case error(message: String)
    }

    @Published var state: State = .idle
    @Published var latestVersion: String = ""

    private var releasePageURL: URL?
    private var releaseAssetURL: URL?
    private var checkTask: Task<Void, Never>?

    var errorMessage: String {
        if case .error(let msg) = state { return msg }
        return ""
    }

    // MARK: - Check

    func checkForUpdate() {
        if let cache = UpdateChecker.loadCache() {
            if !UpdateChecker.shouldCheckAgain(lastCheck: cache.lastCheckDate) {
                if UpdateChecker.isUpdateAvailable(latestVersion: cache.lastSeenVersion) {
                    latestVersion = cache.lastSeenVersion
                    state = .updateAvailable(version: cache.lastSeenVersion)
                }
                return
            }
        }

        checkTask?.cancel()
        checkTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let release = try await UpdateChecker.checkLatestRelease() else { return }
                let cache = UpdateCheckCache(
                    lastCheckDate: Date(),
                    lastSeenVersion: release.tagName
                )
                UpdateChecker.saveCache(cache)

                if UpdateChecker.isUpdateAvailable(latestVersion: release.tagName) {
                    self.latestVersion = release.tagName
                    self.releasePageURL = URL(string: release.htmlUrl)
                    if let zipAsset = UpdateChecker.findZipAsset(in: release) {
                        self.releaseAssetURL = URL(string: zipAsset.browserDownloadUrl)
                    }
                    self.state = .updateAvailable(version: release.tagName)
                }
            } catch {
                #if DEBUG
                print("[UpdateCheckerModel] Auto-check failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Download

    func manualCheck() {
        checkTask?.cancel()
        state = .checking

        checkTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let release = try await UpdateChecker.checkLatestRelease() else {
                    self.state = .upToDate(version: UpdateChecker.currentVersion)
                    return
                }

                let cache = UpdateCheckCache(
                    lastCheckDate: Date(),
                    lastSeenVersion: release.tagName
                )
                UpdateChecker.saveCache(cache)

                if UpdateChecker.isUpdateAvailable(latestVersion: release.tagName) {
                    self.latestVersion = release.tagName
                    self.releasePageURL = URL(string: release.htmlUrl)
                    if let zipAsset = UpdateChecker.findZipAsset(in: release) {
                        self.releaseAssetURL = URL(string: zipAsset.browserDownloadUrl)
                    }
                    self.state = .updateAvailable(version: release.tagName)
                } else {
                    self.state = .upToDate(version: UpdateChecker.currentVersion)
                }
            } catch {
                #if DEBUG
                print("[UpdateCheckerModel] Manual check failed: \(error.localizedDescription)")
                #endif
                self.state = .upToDate(version: UpdateChecker.currentVersion)
            }
        }
    }

    func dismissUpdate() {
        if case .upToDate = state {
            state = .idle
        }
    }

    func startDownload() {
        guard let url = releaseAssetURL else {
            state = .error(message: AppLocalization.text("update.error.noDownloadUrl"))
            return
        }

        state = .downloading(progress: 0)

        Task { [weak self] in
            guard let self else { return }
            do {
                let _ = try await UpdateChecker.downloadUpdate(from: url) { progress in
                    Task { @MainActor [weak self] in
                        self?.state = .downloading(progress: progress)
                    }
                }
                self.state = .downloadComplete
            } catch {
                #if DEBUG
                print("[UpdateCheckerModel] Download failed: \(error.localizedDescription)")
                #endif
                self.state = .error(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Install

    func openDownloadedApp() {
        guard let appURL = UpdateChecker.downloadedAppURL() else {
            state = .error(message: AppLocalization.text("update.error.appNotFound"))
            return
        }

        #if DEBUG
        print("[UpdateCheckerModel] Opening downloaded app: \(appURL.path)")
        #endif
        NSWorkspace.shared.open(appURL)
    }

    // MARK: - Force download (Developer Mode §2.5)

    func forceDownloadLatest() {
        state = .checking

        Task { [weak self] in
            guard let self else { return }
            do {
                guard let release = try await UpdateChecker.checkLatestRelease() else {
                    self.state = .error(message: AppLocalization.text("settings.developerMode.forceUpdate.noRelease"))
                    return
                }

                self.latestVersion = release.tagName
                self.releasePageURL = URL(string: release.htmlUrl)
                if let zipAsset = UpdateChecker.findZipAsset(in: release) {
                    self.releaseAssetURL = URL(string: zipAsset.browserDownloadUrl)
                } else {
                    self.state = .error(message: AppLocalization.text("settings.developerMode.forceUpdate.noAsset"))
                    return
                }

                self.startDownload()
            } catch {
                self.state = .error(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Open release page (fallback)

    func openReleasePage() {
        guard let url = releasePageURL else { return }
        NSWorkspace.shared.open(url)
    }
}
