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
    static func loadPayload(settings: TokenCostSettings, timeout: TimeInterval = 30) throws -> CodexDashboardPayload {
        let process = Process()
        process.executableURL = CodexAppPaths.helperBinaryURL
        process.arguments = buildArguments(for: settings)

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
        defer { timeoutItem.cancel() }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

        try process.run()
        process.waitUntilExit()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

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

    private static func buildArguments(for settings: TokenCostSettings) -> [String] {
        var arguments: [String] = []
        for root in settings.effectiveSourceRoots {
            arguments.append(contentsOf: ["--source-root", root])
        }
        for path in settings.effectiveManualSourcePaths {
            arguments.append(contentsOf: ["--manual-source-path", path])
        }
        arguments.append(contentsOf: ["--max-depth", "\(settings.maxScanDepth)"])
        arguments.append(contentsOf: ["--max-candidates", "\(settings.maxScanCandidates)"])
        return arguments
    }
}
