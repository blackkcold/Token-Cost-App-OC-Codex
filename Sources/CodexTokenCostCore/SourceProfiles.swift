import Foundation

public enum TokenCostSourceFamily: String, Codable, CaseIterable, Sendable {
    case opencode
    case codex

    public var displayName: String {
        switch self {
        case .opencode:
            return AppLocalization.text("source.family.opencode")
        case .codex:
            return AppLocalization.text("source.family.codex")
        }
    }
}

public enum TokenCostSourceLocationKind: String, Codable, CaseIterable, Sendable {
    case file
    case directory

    public var displayName: String {
        switch self {
        case .file:
            return AppLocalization.text("source.location.file")
        case .directory:
            return AppLocalization.text("source.location.directory")
        }
    }
}

public struct TokenCostSourceProfile: Hashable, Sendable {
    public var family: TokenCostSourceFamily
    public var displayNameKey: String
    public var sourceRootsLabelKey: String
    public var manualEntriesLabelKey: String
    public var defaultSourceRoots: [String]
    public var defaultManualSourcePaths: [String]
    public var filenameHints: [String]
    public var allowedExtensions: Set<String>
    public var preferredLocationKind: TokenCostSourceLocationKind
    public var maxScanDepth: Int
    public var maxScanCandidates: Int

    public init(
        family: TokenCostSourceFamily,
        displayNameKey: String,
        sourceRootsLabelKey: String,
        manualEntriesLabelKey: String,
        defaultSourceRoots: [String],
        defaultManualSourcePaths: [String],
        filenameHints: [String],
        allowedExtensions: Set<String>,
        preferredLocationKind: TokenCostSourceLocationKind,
        maxScanDepth: Int,
        maxScanCandidates: Int
    ) {
        self.family = family
        self.displayNameKey = displayNameKey
        self.sourceRootsLabelKey = sourceRootsLabelKey
        self.manualEntriesLabelKey = manualEntriesLabelKey
        self.defaultSourceRoots = defaultSourceRoots
        self.defaultManualSourcePaths = defaultManualSourcePaths
        self.filenameHints = filenameHints
        self.allowedExtensions = allowedExtensions
        self.preferredLocationKind = preferredLocationKind
        self.maxScanDepth = maxScanDepth
        self.maxScanCandidates = maxScanCandidates
    }

    public var displayName: String {
        AppLocalization.text(displayNameKey)
    }

    public var sourceRootsLabel: String {
        AppLocalization.text(sourceRootsLabelKey)
    }

    public var manualEntriesLabel: String {
        AppLocalization.text(manualEntriesLabelKey)
    }

    public static let opencode = TokenCostSourceProfile(
        family: .opencode,
        displayNameKey: "source.family.opencode",
        sourceRootsLabelKey: "source.profile.opencode.sourceRoots",
        manualEntriesLabelKey: "source.profile.opencode.manualEntries",
        defaultSourceRoots: [
            "~/.local/share/opencode",
            "~/Library/Application Support/OpenCode",
            "~/Library/Application Support/OpenCode Desktop",
            "~/Library/Application Support/opencode"
        ],
        defaultManualSourcePaths: [
            "~/.local/share/opencode/opencode.db"
        ],
        filenameHints: ["opencode", "open-code", "open code", "opencodedesktop"],
        allowedExtensions: ["db", "sqlite", "sqlite3"],
        preferredLocationKind: .directory,
        maxScanDepth: 3,
        maxScanCandidates: 32
    )

    public static let codex = TokenCostSourceProfile(
        family: .codex,
        displayNameKey: "source.family.codex",
        sourceRootsLabelKey: "source.profile.codex.sourceRoots",
        manualEntriesLabelKey: "source.profile.codex.manualEntries",
        defaultSourceRoots: [
            "~/.codex/sessions",
            "~/.codex/archived_sessions"
        ],
        defaultManualSourcePaths: [],
        filenameHints: ["codex", "session"],
        allowedExtensions: ["jsonl"],
        preferredLocationKind: .directory,
        maxScanDepth: 6,
        maxScanCandidates: 256
    )

    public static func profile(for family: TokenCostSourceFamily) -> TokenCostSourceProfile {
        switch family {
        case .opencode:
            return .opencode
        case .codex:
            return .codex
        }
    }

    public func matchesCandidateFile(_ url: URL) -> Bool {
        let fileName = url.lastPathComponent.lowercased()
        let extensionName = url.pathExtension.lowercased()

        guard allowedExtensions.isEmpty == false else {
            return true
        }
        guard allowedExtensions.contains(extensionName) else {
            return false
        }

        switch family {
        case .codex:
            return true
        case .opencode:
            if filenameHints.isEmpty {
                return true
            }
            return filenameHints.contains { fileName.contains($0) } || fileName == "opencode.db"
        }
    }
}
