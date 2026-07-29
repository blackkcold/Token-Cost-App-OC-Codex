import Foundation
import CodexTokenCostCore

enum CodexHelperRunnerError: LocalizedError {
    case processFailed(status: Int32, stderr: String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .processFailed(let status, let stderr):
            if stderr.isEmpty {
                return "Codex helper failed with exit code \(status)."
            }
            return "Codex helper failed with exit code \(status): \(stderr)"
        case .invalidOutput(let message):
            return message
        }
    }
}

private final class PipeBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    func read() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

enum CodexHelperRunner {
    static func loadPayload(settings: TokenCostSettings, timeout: TimeInterval = 60) throws -> CodexDashboardPayload {
        let process = Process()
        process.executableURL = CodexAppPaths.helperBinaryURL
        process.arguments = try buildArguments(for: settings)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBuffer = PipeBuffer()
        let stderrBuffer = PipeBuffer()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
            } else {
                stdoutBuffer.append(data)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stderrPipe.fileHandleForReading.readabilityHandler = nil
            } else {
                stderrBuffer.append(data)
            }
        }

        let timeoutItem = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        defer {
            timeoutItem.cancel()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

        try process.run()
        process.waitUntilExit()

        let finalStdout = stdoutBuffer.read()
        let finalStderr = stderrBuffer.read()

        guard process.terminationStatus == 0 else {
            let stderrText = String(data: finalStderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw CodexHelperRunnerError.processFailed(status: process.terminationStatus, stderr: stderrText)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(CodexDashboardPayload.self, from: finalStdout)
        } catch {
            throw CodexHelperRunnerError.invalidOutput("Codex helper output could not be decoded: \(error.localizedDescription)")
        }
    }

    private static func buildArguments(for settings: TokenCostSettings) throws -> [String] {
        var arguments: [String] = []
        for root in settings.effectiveSourceRoots {
            let canonical = TokenCostPathUtilities.canonicalURL(from: root)
            guard TokenCostPathUtilities.isSafeScanRoot(canonical) else {
                throw CodexHelperRunnerError.invalidOutput("Refusing unsafe Codex source root.")
            }
            arguments.append(contentsOf: ["--source-root", canonical.path])
        }
        for path in settings.effectiveManualSourcePaths {
            let canonical = TokenCostPathUtilities.canonicalURL(from: path)
            guard TokenCostPathUtilities.isSafeScanRoot(canonical) else {
                throw CodexHelperRunnerError.invalidOutput("Refusing unsafe Codex source path.")
            }
            arguments.append(contentsOf: ["--manual-source-path", canonical.path])
        }
        arguments.append(contentsOf: ["--max-depth", "\(min(max(settings.maxScanDepth, 1), 12))"])
        arguments.append(contentsOf: ["--max-candidates", "\(min(max(settings.maxScanCandidates, 1), 1000))"])
        return arguments
    }
}
