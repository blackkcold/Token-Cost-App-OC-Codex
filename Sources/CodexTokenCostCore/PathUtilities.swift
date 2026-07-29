import Foundation

public enum TokenCostPathUtilities {
    public static func expandedURL(from path: String) -> URL {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    public static func canonicalURL(from path: String) -> URL {
        canonicalURL(expandedURL(from: path))
    }

    public static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    public static func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let canonicalRoot = canonicalURL(root).path
        let canonicalCandidate = canonicalURL(candidate).path

        if canonicalCandidate == canonicalRoot {
            return true
        }

        let prefix = canonicalRoot.hasSuffix("/") ? canonicalRoot : canonicalRoot + "/"
        return canonicalCandidate.lowercased().hasPrefix(prefix.lowercased())
    }

    public static func canonicalPathString(from path: String) -> String {
        canonicalURL(from: path).path
    }

    /// Scan roots that must never be traversed for source discovery.
    public static let forbiddenScanRoots: Set<String> = [
        "/", "/System", "/Users", "/Applications",
        "/Library", "/private", "/.Trash"
    ]

    private static var sensitiveScanRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".ssh", isDirectory: true),
            home.appendingPathComponent(".gnupg", isDirectory: true),
            home.appendingPathComponent(".aws", isDirectory: true),
            home.appendingPathComponent(".docker", isDirectory: true),
            home.appendingPathComponent(".kube", isDirectory: true),
            home.appendingPathComponent("Library/Keychains", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/Microsoft Edge", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/BraveSoftware", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/Arc", isDirectory: true)
        ]
    }

    /// Returns `true` when the URL's path is not one of the forbidden scan roots.
    public static func isSafeScanRoot(_ url: URL) -> Bool {
        let canonical = canonicalURL(url)
        guard !forbiddenScanRoots.contains(canonical.path) else {
            return false
        }
        return !sensitiveScanRoots.contains { isDescendant(canonical, of: $0) }
    }
}
