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
}
