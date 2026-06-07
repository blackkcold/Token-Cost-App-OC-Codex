import Foundation

/// Developer Mode file access policy — allowlist/blocklist gate.
/// Ensures developer tools cannot access credential or sensitive files.
public enum DeveloperFileAccessPolicy: Sendable {

    /// Decision returned by the access check.
    public enum AccessDecision: Equatable, Sendable {
        case allowed
        case denied(reason: String)
    }

    // MARK: - Allowlist roots (paths under which access is permitted)

    private static let allowedRoots: [String] = [
        NSHomeDirectory() + "/Library/Application Support/com.yanghaoran.CodexTokenCost",
        NSHomeDirectory() + "/.codex/sessions",
        NSHomeDirectory() + "/.codex/archived_sessions",
        NSHomeDirectory() + "/.local/share/opencode",
        NSHomeDirectory() + "/Library/Application Support/OpenCode"
    ]

    // MARK: - Blocklist (paths that are explicitly forbidden)

    private static let blockedSuffixes: [String] = [
        "/auth.json",
        "/oh-my-openagent.json",
        "/credentials",
        "/opencode.jsonc",
        "/opencode.json"
    ]

    private static let blockedPathComponents: [String] = [
        ".config/opencode"
    ]

    // MARK: - Public API

    /// Quick check: is the path accessible?
    public static func isAccessible(_ path: String) -> Bool {
        if case .allowed = checkAccess(to: path) {
            return true
        }
        return false
    }

    /// Full check returning a decision with reason.
    public static func checkAccess(to path: String) -> AccessDecision {
        let canonical = TokenCostPathUtilities.canonicalPathString(from: path)

        // Blocklist takes priority — check first
        for suffix in blockedSuffixes {
            if canonical.hasSuffix(suffix) {
                return .denied(reason: "Path matches blocked suffix: \(suffix)")
            }
        }
        for component in blockedPathComponents {
            if canonical.contains("/\(component)/") || canonical.hasSuffix("/\(component)") {
                return .denied(reason: "Path contains blocked component: \(component)")
            }
        }

        // Check allowlist
        for root in allowedRoots {
            let canonicalRoot = TokenCostPathUtilities.canonicalPathString(from: root)
            if canonical == canonicalRoot || canonical.hasPrefix(canonicalRoot + "/") {
                return .allowed
            }
        }

        return .denied(reason: "Path not in allowed roots")
    }
}
