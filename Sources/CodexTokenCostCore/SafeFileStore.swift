import Foundation

public enum SafeFileStoreError: LocalizedError {
    case outsideAllowedRoot(URL)
    case encodeFailed

    public var errorDescription: String? {
        switch self {
        case .outsideAllowedRoot(let url):
            return "Refusing to write outside the allowed root: \(url.path)"
        case .encodeFailed:
            return "Failed to encode or decode payload."
        }
    }
}

public struct SafeFileStore {
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func resolve(_ relativePath: String) throws -> URL {
        let candidate = relativeURL(relativePath)
        return try validate(candidate)
    }

    public func ensureDirectory(_ relativePath: String) throws {
        let url = try resolve(relativePath)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func writeData(_ data: Data, to relativePath: String) throws {
        let url = try resolve(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    public func writeCodable<T: Codable>(_ value: T, to relativePath: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(value)
#if DEBUG
        if let jsonString = String(data: data, encoding: .utf8) {
            print("[SafeFileStore] writeCodable → \(relativePath):\n\(jsonString.prefix(500))")
        }
#endif
        try writeData(data, to: relativePath)
    }

    public func readCodable<T: Codable>(_ type: T.Type, from relativePath: String) throws -> T {
        let url = try resolve(relativePath)
        let data = try Data(contentsOf: url)
#if DEBUG
        if let jsonString = String(data: data, encoding: .utf8) {
            print("[SafeFileStore] readCodable ← \(relativePath):\n\(jsonString.prefix(500))")
        }
#endif
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    public func removeFile(_ relativePath: String) throws {
        let url = try resolve(relativePath)
        try FileManager.default.removeItem(at: url)
    }

    public func contentsOfDirectory(_ relativePath: String) throws -> [URL] {
        let url = try resolve(relativePath)
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
    }

    private func relativeURL(_ relativePath: String) -> URL {
        let components = relativePath.split(separator: "/")
        // Reject path traversal attempts early
        guard !components.contains(".."), !relativePath.hasPrefix("/") else {
            // Return root to ensure validate() will catch it
            return root.appendingPathComponent("..")
        }
        return components.reduce(root) { current, component in
            current.appendingPathComponent(String(component))
        }
    }

    private func validate(_ url: URL) throws -> URL {
        let allowedRoot = root.standardizedFileURL.resolvingSymlinksInPath().path
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath().path
        if candidate == allowedRoot {
            return url.standardizedFileURL.resolvingSymlinksInPath()
        }
        let prefix = allowedRoot.hasSuffix("/") ? allowedRoot : allowedRoot + "/"
        guard candidate.hasPrefix(prefix) else {
            throw SafeFileStoreError.outsideAllowedRoot(url)
        }
        return url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
