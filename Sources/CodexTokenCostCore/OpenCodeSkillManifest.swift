import Foundation

// MARK: - Parser

public enum OpenCodeSkillManifestParser {

    // Official OpenCode skill name regex: ^[a-z0-9]+(-[a-z0-9]+)*$
    private static let nameRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "^[a-z0-9]+(-[a-z0-9]+)*$",
        options: []
    )

    // Secret-like substrings that trigger value redaction
    private static let secretPatterns: [String] = [
        "token", "secret", "apikey", "api_key", "authorization",
        "cookie", "password", "bearer"
    ]

    private static let maxNameLength = 64
    private static let maxDescriptionLength = 1024
    private static let maxDisplayLength = 2048
    private static let maxFileSizeBytes = 1_048_576 // 1MB

    // Official recognized fields (values are safe to display)
    private static let officialFields: Set<String> = [
        "name", "description", "license", "compatibility", "metadata"
    ]

    private static let scalarOfficialFields: Set<String> = [
        "name", "description", "license", "compatibility"
    ]

    private static let safeExtraFieldKeys: Set<String> = [
        "tags", "triggers", "version", "author", "homepage", "allowed-tools"
    ]

    private static let maxBodyLength = 65_536

    // MARK: - Public API

    /// Parse SKILL.md content and return validated manifest
    public static func parse(skillMDContent: String, sourcePath: String, parentDirectoryName: String? = nil) -> OpenCodeSkillManifest {
        let trimmed = skillMDContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let emptyManifest = OpenCodeSkillManifest(
            name: nil, description: nil, license: nil, compatibility: nil, metadata: nil,
            state: .invalid,
            issues: [OpenCodeSkillValidationIssue(field: nil, message: "Empty SKILL.md", severity: .error)],
            sourcePath: sourcePath
        )

        guard !trimmed.isEmpty else { return emptyManifest }

        if let data = skillMDContent.data(using: .utf8), data.count > maxFileSizeBytes {
            var manifest = parseFrontmatter(content: trimmed, sourcePath: sourcePath, parentDirectoryName: parentDirectoryName)
            var issues = manifest.issues
            issues.append(OpenCodeSkillValidationIssue(
                field: nil,
                message: "Large manifest file (\(data.count) bytes)",
                severity: .warning
            ))
            manifest = OpenCodeSkillManifest(
                name: manifest.name, description: manifest.description,
                license: manifest.license, compatibility: manifest.compatibility,
                metadata: manifest.metadata,
                extraFields: manifest.extraFields,
                unknownFieldKeys: manifest.unknownFieldKeys,
                bodyContent: manifest.bodyContent,
                state: manifest.state == .valid ? .warning : manifest.state,
                issues: issues, sourcePath: sourcePath
            )
            return manifest
        }

        return parseFrontmatter(content: trimmed, sourcePath: sourcePath, parentDirectoryName: parentDirectoryName)
    }
