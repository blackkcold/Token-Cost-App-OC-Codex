import Foundation

// MARK: - Validation Types

public enum OpenCodeSkillValidationSeverity: String, Codable, Sendable {
    case error
    case warning
    case info
}

public struct OpenCodeSkillValidationIssue: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let field: String?
    public let message: String
    public let severity: OpenCodeSkillValidationSeverity

    public init(field: String?, message: String, severity: OpenCodeSkillValidationSeverity) {
        self.id = UUID().uuidString
        self.field = field
        self.message = message
        self.severity = severity
    }
}

// MARK: - Manifest State

public enum OpenCodeSkillManifestState: String, Codable, Sendable {
    case valid
    case warning
    case invalid
    case yamlParseError
}

// MARK: - Manifest

public struct OpenCodeSkillManifest: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String?
    public let description: String?
    public let license: String?
    public let compatibility: String?
    public let metadata: [String: String]?
    public let extraFields: [String: String]
    public let unknownFieldKeys: [String]
    public let bodyContent: String?
    public let state: OpenCodeSkillManifestState
    public let issues: [OpenCodeSkillValidationIssue]
    public let sourcePath: String

    public init(
        name: String?,
        description: String?,
        license: String?,
        compatibility: String?,
        metadata: [String: String]?,
        extraFields: [String: String] = [:],
        unknownFieldKeys: [String] = [],
        bodyContent: String? = nil,
        state: OpenCodeSkillManifestState,
        issues: [OpenCodeSkillValidationIssue],
        sourcePath: String
    ) {
        self.id = UUID().uuidString
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

    // Official OpenCode skill name regex: ^[a-z0-9]+(-[a-z0-9]+)*$
    private static let nameRegex = try! NSRegularExpression(
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

    // MARK: - Frontmatter Extraction

    private static func parseFrontmatter(content: String, sourcePath: String, parentDirectoryName: String?) -> OpenCodeSkillManifest {
        // Extract first YAML frontmatter block (between --- delimiters)
        guard content.hasPrefix("---") else {
            return OpenCodeSkillManifest(
                name: nil, description: nil, license: nil, compatibility: nil, metadata: nil,
                unknownFieldKeys: [],
                state: .invalid,
                issues: [OpenCodeSkillValidationIssue(field: nil, message: "Missing YAML frontmatter (no --- delimiter)", severity: .error)],
                sourcePath: sourcePath
            )
        }

        let afterFirst = content.dropFirst(3)
        guard let endRange = afterFirst.range(of: "\n---") ?? afterFirst.range(of: "\r\n---") ?? afterFirst.range(of: "---") else {
            return OpenCodeSkillManifest(
                name: nil, description: nil, license: nil, compatibility: nil, metadata: nil,
                unknownFieldKeys: [],
                state: .yamlParseError,
                issues: [OpenCodeSkillValidationIssue(field: nil, message: "Unclosed YAML frontmatter (missing closing ---)", severity: .error)],
                sourcePath: sourcePath
            )
        }

        let frontmatterBlock = String(afterFirst[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

        let bodyContent: String? = {
            let bodyStart = endRange.upperBound
            if bodyStart < afterFirst.endIndex {
                let rawBody = String(afterFirst[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !rawBody.isEmpty {
                    let truncated = String(rawBody.prefix(maxBodyLength))
                    return redactBodyContent(truncated)
                }
            }
            return nil
        }()

        let parsed = parseYamlKeyValues(frontmatterBlock, sourcePath: sourcePath)

        if case .parseError(let msg) = parsed {
            return OpenCodeSkillManifest(
                name: nil, description: nil, license: nil, compatibility: nil, metadata: nil,
                unknownFieldKeys: [],
                state: .yamlParseError,
                issues: [OpenCodeSkillValidationIssue(field: nil, message: msg, severity: .error)],
                sourcePath: sourcePath
            )
        }

        guard case .success(let fields, let unknownKeys) = parsed else {
            return OpenCodeSkillManifest(
                name: nil, description: nil, license: nil, compatibility: nil, metadata: nil,
                unknownFieldKeys: [],
                state: .yamlParseError,
                issues: [OpenCodeSkillValidationIssue(field: nil, message: "YAML parse error", severity: .error)],
                sourcePath: sourcePath
            )
        }

        // Extract values
        let rawName = fields["name"]
        let rawDesc = fields["description"]
        let rawLicense = fields["license"]
        let rawCompat = fields["compatibility"]
        let rawMetadata = parseMetadata(from: frontmatterBlock)

        // Redact and truncate
        let name = rawName.map { redactAndTruncate($0, fieldKey: "name") }
        let desc = rawDesc.map { redactAndTruncate($0, fieldKey: "description") }
        let license = rawLicense.map { redactAndTruncate($0, fieldKey: "license") }
        let compatibility = rawCompat.map { redactAndTruncate($0, fieldKey: "compatibility") }
        let metadata = rawMetadata?.mapValues { redactAndTruncate($0, fieldKey: "metadata") }

        // Validate
        let validationResult = validate(
            name: name, description: desc,
            parentDirectoryName: parentDirectoryName
        )

        let extraFields = extractExtraFields(from: fields)

        return OpenCodeSkillManifest(
            name: name, description: desc,
            license: license, compatibility: compatibility,
            metadata: metadata,
            extraFields: extraFields,
            unknownFieldKeys: unknownKeys,
            bodyContent: bodyContent,
            state: validationResult.state,
            issues: validationResult.issues,
            sourcePath: sourcePath
        )
    }

    // MARK: - YAML Key-Value Parsing

    private enum ParseResult {
        case success(fields: [String: String], unknownKeys: [String])
        case parseError(String)
    }

    private static func parseYamlKeyValues(_ block: String, sourcePath: String) -> ParseResult {
        var fields: [String: String] = [:]
        var unknownKeys: [String] = []
        var inMultilineValue = false
        var currentKey: String?
        var currentValue = ""
        var currentIndent = 0

        let lines = block.components(separatedBy: .newlines)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") { continue }

            if inMultilineValue {
                // Check if this is a new top-level key (no indent) or a sub-key
                let leadingSpaces = line.prefix(while: { $0 == " " }).count
                if let kv = tryParseKeyValue(line), leadingSpaces == 0 {
                    // End multiline, start new key
                    if let key = currentKey {
                        let trimmed = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if officialFields.contains(key) {
                            fields[key] = trimmed
                        } else {
                            unknownKeys.append(key)
                        }
                    }
                    inMultilineValue = false
                    currentKey = kv.key
                    currentValue = kv.value
                } else if leadingSpaces > currentIndent {
                    // Sub-key of multiline map - skip for now (metadata handled separately)
                    continue
                } else {
                    currentValue += "\n" + line
                }
                continue
            }

            // Try simple key: value
            if let kv = tryParseKeyValue(line) {
                if kv.value.isEmpty {
                    // Possible start of multiline/map value
                    inMultilineValue = true
                    currentKey = kv.key
                    currentValue = ""
                    currentIndent = line.prefix(while: { $0 == " " }).count
                } else {
                    if officialFields.contains(kv.key) {
                        fields[kv.key] = kv.value
                    } else {
                        unknownKeys.append(kv.key)
                    }
                }
            }
        }

        // Handle last multiline value
        if inMultilineValue, let key = currentKey {
            let trimmed = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if officialFields.contains(key) {
                fields[key] = trimmed
            } else {
                unknownKeys.append(key)
            }
        }

        return .success(fields: fields, unknownKeys: unknownKeys)
    }

    private static func tryParseKeyValue(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let colonIndex = trimmed.firstIndex(of: ":") else { return nil }
        let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !key.hasPrefix("#") else { return nil }
        let valueStart = trimmed.index(after: colonIndex)
        let rawValue = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespaces)
        // Remove surrounding quotes
        var value = rawValue
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        } else if value.hasPrefix("'") && value.hasSuffix("'") {
            value = String(value.dropFirst().dropLast())
        }
        return (key, value)
    }

    // MARK: - Metadata Parsing

    private static func parseMetadata(from block: String) -> [String: String]? {
        let lines = block.components(separatedBy: .newlines)
        var inMetadata = false
        var metadata: [String: String] = [:]
        var baseIndent: Int?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("metadata:") {
                inMetadata = true
                baseIndent = nil
                continue
            }

            if inMetadata {
                let leadingSpaces = line.prefix(while: { $0 == " " }).count
                if let b = baseIndent {
                    // Check if still in metadata block
                    if leadingSpaces < b && !trimmed.isEmpty {
                        break
                    }
                } else {
                    baseIndent = leadingSpaces
                }
                if let kv = tryParseKeyValue(line) {
                    metadata[kv.key] = kv.value
                }
            }
        }

        return metadata.isEmpty ? nil : metadata
    }

    // MARK: - Validation

    private static func validate(
        name: String?,
        description: String?,
        parentDirectoryName: String?
    ) -> (state: OpenCodeSkillManifestState, issues: [OpenCodeSkillValidationIssue]) {
        var issues: [OpenCodeSkillValidationIssue] = []
        var hasError = false
        var hasWarning = false

        // Name validation (required)
        if let name = name {
            if name.isEmpty {
                issues.append(OpenCodeSkillValidationIssue(
                    field: "name", message: "Name is empty", severity: .error
                ))
                hasError = true
            } else if name.count > maxNameLength {
                issues.append(OpenCodeSkillValidationIssue(
                    field: "name", message: "Name exceeds \(maxNameLength) characters", severity: .error
                ))
                hasError = true
            } else {
                let range = NSRange(location: 0, length: name.utf16.count)
                if nameRegex.firstMatch(in: name, options: [], range: range) == nil {
                    issues.append(OpenCodeSkillValidationIssue(
                        field: "name",
                        message: "Name '\(name)' must match ^[a-z0-9]+(-[a-z0-9]+)*$",
                        severity: .error
                    ))
                    hasError = true
                }
                if name.hasPrefix("-") || name.hasSuffix("-") {
                    issues.append(OpenCodeSkillValidationIssue(
                        field: "name", message: "Name cannot start or end with hyphen", severity: .error
                    ))
                    hasError = true
                }
                if name.contains("--") {
                    issues.append(OpenCodeSkillValidationIssue(
                        field: "name", message: "Name cannot contain consecutive hyphens", severity: .error
                    ))
                    hasError = true
                }
                // Parent directory match
                if let dirName = parentDirectoryName {
                    if name != dirName {
                        issues.append(OpenCodeSkillValidationIssue(
                            field: "name",
                            message: "Name '\(name)' does not match parent directory '\(dirName)'",
                            severity: .error
                        ))
                        hasError = true
                    }
                }
            }
        } else {
            issues.append(OpenCodeSkillValidationIssue(
                field: "name", message: "Required field 'name' is missing", severity: .error
            ))
            hasError = true
        }

        // Description validation (required)
        if let desc = description {
            if desc.isEmpty {
                issues.append(OpenCodeSkillValidationIssue(
                    field: "description", message: "Description is empty", severity: .error
                ))
                hasError = true
            } else if desc.count > maxDescriptionLength {
                issues.append(OpenCodeSkillValidationIssue(
                    field: "description",
                    message: "Description exceeds \(maxDescriptionLength) characters (\(desc.count))",
                    severity: .error
                ))
                hasError = true
            }
        } else {
            issues.append(OpenCodeSkillValidationIssue(
                field: "description", message: "Required field 'description' is missing", severity: .error
            ))
            hasError = true
        }

        return (
            state: hasError ? .invalid : (hasWarning ? .warning : .valid),
            issues: issues
        )
    }

    // MARK: - Redaction & Truncation

    private static func redactAndTruncate(_ value: String, fieldKey: String) -> String {
        let lowerKey = fieldKey.lowercased()
        for pattern in secretPatterns {
            if lowerKey.contains(pattern) {
                return "[REDACTED]"
            }
        }
        if value.count > maxDisplayLength {
            return String(value.prefix(maxDisplayLength))
        }
        return value
    }

    private static func extractExtraFields(from fields: [String: String]) -> [String: String] {
        var extras: [String: String] = [:]
        for key in safeExtraFieldKeys {
            if let value = fields[key] {
                extras[key] = redactAndTruncate(value, fieldKey: key)
            }
        }
        return extras
    }

    private static func redactBodyContent(_ content: String) -> String {
        var result = content
        for pattern in secretPatterns {
            if let regex = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: pattern))\\b.*", options: [.caseInsensitive]) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(location: 0, length: result.utf16.count),
                    withTemplate: "[REDACTED - contains \(pattern)]"
                )
            }
        }
        return result
    }
}
