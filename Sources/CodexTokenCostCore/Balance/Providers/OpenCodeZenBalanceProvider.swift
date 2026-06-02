import Foundation

public struct OpenCodeZenBalanceChecker: BalanceChecker {
    public var providerKind: BalanceProviderKind { .opencodeZen }

    public init() {}

    public func fetch(authToken: String) async -> BalanceSnapshot {
        guard let binaryURL = Self.locateBinary() else {
            return .unavailable(.opencodeZen, reason: "未找到 opencode CLI")
        }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["stats", "--days", "90", "--models"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var launchError: Error?

        let workItem = DispatchWorkItem {
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                launchError = error
            }
        }

        let queue = DispatchQueue(label: "com.tokencost.opencode-zen")
        queue.async(execute: workItem)

        if workItem.wait(timeout: .now() + 60) == .timedOut {
            workItem.cancel()
            process.terminate()
            return .unavailable(.opencodeZen, reason: "opencode CLI 超时")
        }

        if let error = launchError {
            return .unavailable(.opencodeZen, reason: "无法启动 opencode: \(error.localizedDescription)")
        }

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? "未知错误"
            return .unavailable(.opencodeZen, reason: "opencode CLI 失败: \(stderr)")
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: stdoutData, encoding: .utf8) ?? ""

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

// MARK: - Binary discovery

extension OpenCodeZenBalanceChecker {
    private static func locateBinary() -> URL? {
        var unsignedFallback: URL?

        for url in binaryCandidates() {
            guard FileManager.default.isExecutableFile(atPath: url.path) else { continue }
            if verifyBinarySignature(url) { return url }
            if unsignedFallback == nil { unsignedFallback = url }
        }

        return unsignedFallback
    }

    private static func binaryCandidates() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fixedPaths = [
            "/opt/homebrew/bin/opencode",
            "/usr/local/bin/opencode",
            home.appendingPathComponent(".opencode/bin/opencode").path,
            home.appendingPathComponent(".local/bin/opencode").path,
            home.appendingPathComponent("bin/opencode").path,
        ]

        let discoveredPaths = [findBinaryViaWhich(), findBinaryViaLoginShell()]
            .compactMap { $0?.path }

        var seen = Set<String>()
        return (fixedPaths + discoveredPaths).compactMap { path in
            guard !path.isEmpty, seen.insert(path).inserted else { return nil }
            return URL(fileURLWithPath: path)
        }
    }

    private static func findBinaryViaWhich() -> URL? {
        runPathLookup(executable: "/usr/bin/which", arguments: ["opencode"])
    }

    private static func findBinaryViaLoginShell() -> URL? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }
        return runPathLookup(executable: shell, arguments: ["-lc", "which opencode 2>/dev/null"])
    }

    private static func runPathLookup(executable: String, arguments: [String]) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            let firstLine = output.split(separator: "\n").first,
            !firstLine.isEmpty
        else { return nil }

        let path = String(firstLine)
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func verifyBinarySignature(_ url: URL) -> Bool {
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
