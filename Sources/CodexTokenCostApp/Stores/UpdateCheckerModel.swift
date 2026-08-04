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
    private var pendingRelease: GitHubRelease?
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
                } else {
                    state = .upToDate(version: UpdateChecker.currentVersion)
                }
                return
            }
        }
    
        performReleaseFetch(silent: true)
    }

    // MARK: - Download

    func manualCheck() {
        state = .checking
        performReleaseFetch(silent: false)
    }
    
    private func performReleaseFetch(silent: Bool) {
        checkTask?.cancel()
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
                    self.pendingRelease = release
                    self.releasePageURL = URL(string: release.htmlUrl)
                    self.state = .updateAvailable(version: release.tagName)
                } else {
                    self.state = .upToDate(version: UpdateChecker.currentVersion)
                }
            } catch {
                #if DEBUG
                print("[UpdateCheckerModel] \(silent ? "Auto" : "Manual") check failed: \(error.localizedDescription)")
                #endif
                if silent {
                    self.state = .upToDate(version: UpdateChecker.currentVersion)
                } else {
                    self.state = .error(message: error.localizedDescription)
                }
            }
        }
    }

    func dismissUpdate() {
        if case .upToDate = state {
            state = .idle
        }
    }

    func startDownload() {
        state = .downloading(progress: 0)

        Task { [weak self] in
            guard let self else { return }
            do {
                let release: GitHubRelease?
                if let pendingRelease = self.pendingRelease {
                    release = pendingRelease
                } else {
                    release = try await UpdateChecker.checkLatestRelease()
                }
                guard let release else {
                    throw UpdateError.noReleaseAsset
                }
                self.pendingRelease = release
                self.releasePageURL = URL(string: release.htmlUrl)
                do {
                    let verifiedUpdate = try await UpdateChecker.prepareVerifiedUpdate(from: release)
                    let _ = try await UpdateChecker.downloadUpdate(verifiedUpdate) { progress in
                        Task { @MainActor [weak self] in
                            self?.state = .downloading(progress: progress)
                        }
                    }
                } catch UpdateError.manifestMissing {
                    // Release ships a zip but no signed update manifest (the
                    // release pipeline skips it when signing keys are absent).
                    // Fall back to the direct download path, which still
                    // verifies SHA-256, size, and code signature.
                    let _ = try await UpdateChecker.downloadDirect(from: release) { progress in
                        Task { @MainActor [weak self] in
                            self?.state = .downloading(progress: progress)
                        }
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

    func installUpdate() {
        guard let newAppURL = UpdateChecker.downloadedAppURL() else {
            state = .error(message: AppLocalization.text("update.error.appNotFound"))
            return
        }
        let currentAppURL = Bundle.main.bundleURL

        #if DEBUG
        print("[UpdateCheckerModel] Replacing \(currentAppURL.path) with \(newAppURL.path)")
        #endif

        do {
            let replacedURL = try UpdateChecker.replaceAppBundle(
                currentAppURL: currentAppURL,
                newAppURL: newAppURL
            )
            persistBeforeRelaunch()
            try UpdateChecker.scheduleRelaunch(at: replacedURL)
            NSApp.terminate(nil)
        } catch {
            #if DEBUG
            print("[UpdateCheckerModel] Install failed: \(error.localizedDescription)")
            #endif
            state = .error(message: AppLocalization.text("update.error.installFailed"))
        }
    }

    private func persistBeforeRelaunch() {
        NotificationCenter.default.post(name: .appWillRelaunchForUpdate, object: nil)
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
                self.pendingRelease = release
                self.releasePageURL = URL(string: release.htmlUrl)
                if UpdateChecker.findZipAsset(in: release) == nil || UpdateChecker.findManifestAsset(in: release) == nil {
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

extension Notification.Name {
    static let appWillRelaunchForUpdate = Notification.Name("appWillRelaunchForUpdate")
}
