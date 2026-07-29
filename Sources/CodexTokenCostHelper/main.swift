import Foundation
import CodexTokenCostCore

enum CodexHelperMain {
    static func main() -> Int32 {
        signal(SIGTERM) { _ in
            FileHandle.standardError.write(Data("Helper received SIGTERM, exiting.\n".utf8))
            Darwin.exit(143)
        }

        do {
            let arguments = try parseArguments(Array(CommandLine.arguments.dropFirst()))
            let payload = try CodexSessionCollector(
                sourceRoots: arguments.sourceRoots,
                manualSourcePaths: arguments.manualSourcePaths,
                maxDepth: arguments.maxDepth,
                maxCandidates: arguments.maxCandidates
            ).loadPayload()

            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(payload)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0A]))
            return 0
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            FileHandle.standardError.write(Data((message + "\n").utf8))
            return 1
        }
    }

    private static func parseArguments(_ arguments: [String]) throws -> ParsedArguments {
        var sourceRoots: [URL] = []
        var manualSourcePaths: [URL] = []
        var maxDepth: Int = 6
        var maxCandidates: Int = 256
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--source-root":
                guard let value = iterator.next(), !value.isEmpty else {
                    throw CodexSessionCollectorError.invalidArgument("Missing value for --source-root.")
                }
                let url = TokenCostPathUtilities.canonicalURL(from: value)
                guard TokenCostPathUtilities.isSafeScanRoot(url) else {
                    throw CodexSessionCollectorError.invalidArgument("Unsafe value for --source-root.")
                }
                sourceRoots.append(url)
            case "--manual-source-path":
                guard let value = iterator.next(), !value.isEmpty else {
                    throw CodexSessionCollectorError.invalidArgument("Missing value for --manual-source-path.")
                }
                let url = TokenCostPathUtilities.canonicalURL(from: value)
                guard TokenCostPathUtilities.isSafeScanRoot(url) else {
                    throw CodexSessionCollectorError.invalidArgument("Unsafe value for --manual-source-path.")
                }
                manualSourcePaths.append(url)
            case "--max-depth":
                guard let value = iterator.next(), let parsed = Int(value) else {
                    throw CodexSessionCollectorError.invalidArgument("Missing or invalid value for --max-depth.")
                }
                maxDepth = parsed
            case "--max-candidates":
                guard let value = iterator.next(), let parsed = Int(value) else {
                    throw CodexSessionCollectorError.invalidArgument("Missing or invalid value for --max-candidates.")
                }
                maxCandidates = parsed
            default:
                throw CodexSessionCollectorError.invalidArgument("Unsupported helper argument: \(argument)")
            }
        }

        guard (1...12).contains(maxDepth) else {
            throw CodexSessionCollectorError.invalidArgument("--max-depth must be between 1 and 12.")
        }
        guard (1...1000).contains(maxCandidates) else {
            throw CodexSessionCollectorError.invalidArgument("--max-candidates must be between 1 and 1000.")
        }

        return ParsedArguments(
            sourceRoots: sourceRoots,
            manualSourcePaths: manualSourcePaths,
            maxDepth: maxDepth,
            maxCandidates: maxCandidates
        )
    }
}

private struct ParsedArguments {
    let sourceRoots: [URL]
    let manualSourcePaths: [URL]
    let maxDepth: Int
    let maxCandidates: Int
}

exit(CodexHelperMain.main())
