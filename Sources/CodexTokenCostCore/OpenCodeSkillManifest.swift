import Foundation

// MARK: - Types

public enum ValidationState: String, Codable, Sendable {
    case valid
    case invalid
    case warning
}

public enum ValidationSeverity: String, Codable, Sendable {
    case error
    case warning
}

public struct OpenCodeSkillValidationIssue: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(field ?? "")-\(message)" }
    public let field: String?
    public let message: String
    public let severity: ValidationSeverity

    public init(field: String?, message: String, severity: ValidationSeverity) {
        self.field = field
        self.message = message
        self.severity = severity
    }
}

public struct OpenCodeSkillManifest: Codable, Hashable, Sendable {
    public let name: String?
    public let description: String?
    public let license: String?
    public let compatibility: String?
    public let metadata: [String: String]?
    public let extraFields: [String: String]?
    public let unknownFieldKeys: [String]
    public let bodyContent: String?
    public let state: ValidationState
    public let issues: [OpenCodeSkillValidationIssue]
    public let sourcePath: String

    public init(
        name: String?,
        description: String?,
        license: String?,
        compatibility: String?,
        metadata: [String: String]?,
        extraFields: [String: String]? = nil,
        unknownFieldKeys: [String] = [],
        bodyContent: String? = nil,
        state: ValidationState,
        issues: [OpenCodeSkillValidationIssue],
        sourcePath: String
    ) {
        self.name = name
        self.description = description
        self.license = license
        self.compatibility = compatibility
        self.metadata = metadata
        self.extraFields = extraFields
        self.unknownFieldKeys = unknownFieldKeys
        self.bodyContent = bodyContent
        self.state = state
        self.issues = issues
        self.sourcePath = sourcePath
    }
}

// MARK: - Parser

public enum OpenCodeSkillManifestParser {

    private static let nameRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "^[a-z0-9]+(-[a-z0-9]+)*$",
        options: []
    )

    private static let secretPatterns: [String] = [
        "token", "secret", "apikey", "api_key", "authorization",
        "cookie", "password", "bearer"
    ]

    private static let maxNameLength = 64
    private static let maxDescriptionLength = 1024
    private static let maxDisplayLength = 2048
    private static let maxFileSizeBytes = 1_048_576

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

    // MARK: - Frontmatter Parsing

    private static func parseFrontmatter(content: String, sourcePath: String, parentDirectoryName: String?) -> OpenCodeSkillManifest {
        var issues: [OpenCodeSkillValidationIssue] = []
        var name: String?
        var description: String?
        var license: String?
        var compatibility: String?
        var metadata: [String: String]?
        var extraFields: [String: String]?
        var unknownFieldKeys: [String] = []
        var bodyContent: String?

        let lines = content.components(separatedBy: .newlines)

        guard let firstLine = lines.first, firstLine.trimmingCharacters(in: .whitespaces) == "---" else {
            issues.append(OpenCodeSkillValidationIssue(field: nil, message: "Missing frontmatter delimiter (---)", severity: .error))
            return OpenCodeSkillManifest(
                name: nil, description: nil, license: nil, compatibility: nil, metadata: nil,
                state: .invalid, issues: issues, sourcePath: sourcePath
            )
        }

        var frontmatterEnd = -1
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                frontmatterEnd = i
                break
            }
        }

        guard frontmatterEnd > 0 else {
            issues.append(OpenCodeSkillValidationIssue(field: nil, message: "Unclosed frontmatter block", severity: .error))
            return OpenCodeSkillManifest(
                name: nil, description: nil, license: nil, compatibility: nil, metadata: nil,
                state: .invalid, issues: issues, sourcePath: sourcePath
            )
        }

        let frontmatterLines = Array(lines[1..<frontmatterEnd])
        var currentKey: String?
        var currentValue = ""

        for line in frontmatterLines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.isEmpty { continue }

            if trimmedLine.hasPrefix("  ") || trimmedLine.hasPrefix("\t"), let key = currentKey {
                currentValue += " " + trimmedLine
            } else if let colonIndex = trimmedLine.firstIndex(of: ":") {
                if let key = currentKey {
                    processField(key: key, value: currentValue.trimmingCharacters(in: .whitespaces),
                                 name: &name, description: &description, license: &license,
                                 compatibility: &compatibility, metadata: &metadata,
                                 extraFields: &extraFields, unknownFieldKeys: &unknownFieldKeys,
                                 issues: &issues, sourcePath: sourcePath)
                }
                currentKey = String(trimmedLine[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                currentValue = String(trimmedLine[trimmedLine.index(after: colonIndex)...])
            } else {
                currentValue += " " + trimmedLine
            }
        }

        if let key = currentKey {
            processField(key: key, value: currentValue.trimmingCharacters(in: .whitespaces),
                         name: &name, description: &description, license: &license,
                         compatibility: &compatibility, metadata: &metadata,
                         extraFields: &extraFields, unknownFieldKeys: &unknownFieldKeys,
                         issues: &issues, sourcePath: sourcePath)
        }

        if frontmatterEnd + 1 < lines.count {
            let bodyLines = Array(lines[(frontmatterEnd + 1)...])
            let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                bodyContent = body.count > maxBodyLength ? String(body.prefix(maxBodyLength)) : body
            }
        }

        if let n = name, let regex = nameRegex {
            let range = NSRange(location: 0, length: n.utf16.count)
            if regex.firstMatch(in: n, options: [], range: range) == nil {
                issues.append(OpenCodeSkillValidationIssue(field: "name", message: "Invalid skill name format", severity: .warning))
            }
        }

        if let n = name, n.count > maxNameLength {
            issues.append(OpenCodeSkillValidationIssue(field: "name", message: "Name exceeds \(maxNameLength) characters", severity: .warning))
        }

        if let d = description, d.count > maxDescriptionLength {
            issues.append(OpenCodeSkillValidationIssue(field: "description", message: "Description exceeds \(maxDescriptionLength) characters", severity: .warning))
        }

        let state: ValidationState = issues.contains { $0.severity == .error } ? .invalid
            : issues.contains { $0.severity == .warning } ? .warning : .valid

        return OpenCodeSkillManifest(
            name: name, description: description, license: license, compatibility: compatibility,
            metadata: metadata, extraFields: extraFields, unknownFieldKeys: unknownFieldKeys,
            bodyContent: bodyContent, state: state, issues: issues, sourcePath: sourcePath
        )
    }

    private static func processField(
        key: String, value: String,
        name: inout String?, description: inout String?, license: inout String?,
        compatibility: inout String?, metadata: inout [String: String]?,
        extraFields: inout [String: String]?, unknownFieldKeys: inout [String],
        issues: inout [OpenCodeSkillValidationIssue], sourcePath: String
    ) {
        let lowerKey = key.lowercased()
        let cleanValue = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        if cleanValue.count > maxDisplayLength {
            issues.append(OpenCodeSkillValidationIssue(field: key, message: "Value exceeds display limit", severity: .warning))
        }

        for pattern in secretPatterns {
            if lowerKey.contains(pattern) || cleanValue.lowercased().contains(pattern) {
                issues.append(OpenCodeSkillValidationIssue(field: key, message: "Possible secret detected in \(key)", severity: .warning))
                break
            }
        }

        switch lowerKey {
        case "name": name = cleanValue
        case "description": description = cleanValue
        case "license": license = cleanValue
        case "compatibility": compatibility = cleanValue
        case "metadata":
            if metadata == nil { metadata = [:] }
            metadata?[key] = cleanValue
        default:
            if safeExtraFieldKeys.contains(lowerKey) {
                if extraFields == nil { extraFields = [:] }
                extraFields?[key] = cleanValue
            } else if !officialFields.contains(lowerKey) {
                unknownFieldKeys.append(key)
            }
        }
    }
}
