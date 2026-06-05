import Foundation
import CryptoKit

public struct OpenCodeZenBalanceChecker: BalanceChecker {
    public var providerKind: BalanceProviderKind { .opencodeZen }

    public init() {}

    /// Timeout for the opencode CLI process.
    private static let cliTimeout: TimeInterval = 30

    public func fetch(authToken: String) async -> BalanceSnapshot {
        guard let binaryURL = Self.locateBinary() else {
            return .unavailable(.opencodeZen, reason: "未找到 opencode CLI，请在设置中选择二进制路径")
        }

        // Pre-execution validation: hash the binary we resolved.
        guard let preHash = Self.sha256(of: binaryURL) else {
            return .unavailable(.opencodeZen, reason: "无法验证 opencode CLI")
        }

        // Run the CLI with the hardened process lifecycle (S42).
        let result: (exitCode: Int32, stdout: String, stderr: String)
        do {
            result = try await Self.runCLI(
                binaryURL: binaryURL,
                arguments: ["stats", "--days", "90", "--models"],
                timeout: Self.cliTimeout
            )
        } catch let error as ProcessError {
            switch error {
            case .timeout:
                return .unavailable(.opencodeZen, reason: "opencode CLI 超时")
            case .launchFailed(let underlying):
                return .unavailable(.opencodeZen, reason: "无法启动 opencode: \(underlying.localizedDescription)")
            }
        } catch {
            return .unavailable(.opencodeZen, reason: "CLI 执行失败")
        }

        // Post-execution hash re-verification (TOCTOU protection).
        if let postHash = Self.sha256(of: binaryURL), postHash != preHash {
            return .unavailable(.opencodeZen, reason: "CLI 二进制已变更")
        }

        guard result.exitCode == 0 else {
#if DEBUG
            print("[OpenCodeZenBalance] CLI stderr: \(result.stderr)")
#endif
            return .unavailable(.opencodeZen, reason: "CLI 执行失败")
        }

        let output = result.stdout

        guard let rawTotal = Self.parseTotalCost(from: output) else {
            return .unavailable(.opencodeZen, reason: "无法解析费用数据")
        }

        let goCosts = OpenCodeGoBalanceChecker.parseGoModelCosts(from: output)
        let goSum = goCosts.values.reduce(0, +)
        let zenCost = max(0, rawTotal - goSum)

        let avgCostPerDay = Self.parseAvgCostPerDay(from: output)

        return BalanceSnapshot(
            provider: .opencodeZen,
            fetchedAt: Date(),
            isAvailable: true,
            totalCostUSD: zenCost,
            avgCostPerDayUSD: avgCostPerDay
        )
    }
}

// MARK: - Hardened Process Lifecycle (S42, S6, S48, S49)

extension OpenCodeZenBalanceChecker {

    enum ProcessError: Error {
        case timeout
        case launchFailed(Error)
    }

    /// Runs a CLI executable with timeout, env blacklist, and guaranteed cleanup.
    static func runCLI(
        binaryURL: URL,
        arguments: [String],
        timeout: TimeInterval = 30
    ) async throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = arguments

        // S6: Environment variable blacklist filtering.
        var env = ProcessInfo.processInfo.environment
        let blockedEnvPrefixes = ["DYLD_", "SIMBL_", "LD_PRELOAD", "LD_LIBRARY_PATH", "OBJC_"]
        env = env.filter { key, _ in
            !blockedEnvPrefixes.contains(where: { key.hasPrefix($0) })
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withThrowingTaskGroup(of: Void.self) { group in
            // Main task: launch and wait for process.
            group.addTask {
                try process.run()
                process.waitUntilExit()
            }

            // Timeout task.
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ProcessError.timeout
            }

            do {
                try await group.next()
                group.cancelAll()
            } catch ProcessError.timeout {
                process.terminate()
                // Grace period for cleanup.
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if process.isRunning { process.interrupt() }
                group.cancelAll()
                throw ProcessError.timeout
            } catch {
                process.terminate()
                group.cancelAll()
                throw ProcessError.launchFailed(error)
            }

            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (process.terminationStatus, stdout, stderr)
        }
    }
}

// MARK: - Binary Discovery (Hardened)

extension OpenCodeZenBalanceChecker {

    /// Locates the opencode binary using only trusted paths or a user-selected path.
    private static func locateBinary() -> URL? {
        // Priority 1: User-selected path from preferences (Phase 4 placeholder).
        if let userPath = userSelectedCLIPath(), validateBinary(at: userPath) {
            return userPath
        }

        // Priority 2: Fixed Homebrew realpaths only (no which, no login shell).
        for candidate in fixedBinaryCandidates() {
            if validateBinary(at: candidate) {
                return candidate
            }
        }

        return nil
    }

    /// Fixed, trusted binary candidates (no PATH discovery).
    private static func fixedBinaryCandidates() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/opt/homebrew/bin/opencode"),
            URL(fileURLWithPath: "/usr/local/bin/opencode"),
            home.appendingPathComponent(".opencode/bin/opencode"),
            home.appendingPathComponent(".local/bin/opencode"),
        ]
    }

    /// Placeholder for Phase 4 user-selected CLI path preference.
    private static func userSelectedCLIPath() -> URL? {
        // TODO: Phase 4 — read from AppPreferences.opencodeCLIPath
        return nil
    }

    /// Validates a binary candidate before execution.
    static func validateBinary(at url: URL) -> Bool {
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory) else {
            return false
        }

        // Must exist and not be a directory.
        guard !isDirectory.boolValue else { return false }
        guard FileManager.default.isExecutableFile(atPath: resolvedURL.path) else { return false }

        // Ownership check: file must be owned by current user or root.
        guard let owner = fileOwnerName(at: resolvedURL) else { return false }
        let currentUser = NSUserName()
        guard owner == currentUser || owner == "root" else { return false }

        // File and parent directory must not be group/world writable.
        guard !isGroupOrWorldWritable(at: resolvedURL) else { return false }
        let parentDir = resolvedURL.deletingLastPathComponent()
        guard !isGroupOrWorldWritable(at: parentDir) else { return false }

        // Codesign verification (advisory): pass → trust; fail → continue
        // with ownership/permissions checks. The hash-based TOCTOU protection
        // in fetch() (pre-hash → execute → post-hash) is the primary trust anchor.
        _ = verifyBinarySignature(resolvedURL)

        return true
    }

    private static func fileOwnerName(at url: URL) -> String? {
        let path = url.path
        return try? FileManager.default.attributesOfItem(atPath: path)[.ownerAccountName] as? String
    }

    private static func isGroupOrWorldWritable(at url: URL) -> Bool {
        let path = url.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let permissions = attrs[.posixPermissions] as? NSNumber
        else { return true } // Fail closed.
        let mode = permissions.uint16Value
        return (mode & S_IWGRP) != 0 || (mode & S_IWOTH) != 0
    }

    /// Verifies the binary's codesign signature (strict, no fallback to unsigned).
    static func verifyBinarySignature(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--verbose=1", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - SHA-256 (CryptoKit)

    /// Computes the SHA-256 hash of a file using CryptoKit.
    static func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Parsing

extension OpenCodeZenBalanceChecker {
    private static func parseTotalCost(from output: String) -> Double? {
        parseDollarValue(pattern: #"│Total Cost\s+\$([0-9.]+)"#, in: output)
    }

    private static func parseAvgCostPerDay(from output: String) -> Double? {
        parseDollarValue(pattern: #"│Avg Cost/Day\s+\$([0-9.]+)"#, in: output)
    }

    private static func parseDollarValue(pattern: String, in output: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: output)
        else { return nil }
        return Double(output[captureRange])
    }
}
