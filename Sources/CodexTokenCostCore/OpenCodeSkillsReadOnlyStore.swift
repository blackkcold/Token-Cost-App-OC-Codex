import Foundation

public struct OpenCodeConfigLayerSignal {
    public let name: String
    public let path: String
    public let isPresent: Bool
    public let parseError: String?
    public let isJSONC: Bool
    public let isCompatibilityLayer: Bool
    public let rawJSON: [String: Any]?

    public init(name: String, path: String, isPresent: Bool, parseError: String? = nil, isJSONC: Bool = false, isCompatibilityLayer: Bool = false, rawJSON: [String: Any]? = nil) {
        self.name = name
        self.path = path
        self.isPresent = isPresent
        self.parseError = parseError
        self.isJSONC = isJSONC
        self.isCompatibilityLayer = isCompatibilityLayer
        self.rawJSON = rawJSON
    }
}

public struct OpenCodeEnvSignal {
    public let variable: String
    public let isSet: Bool
    public let valueSummary: String

    public init(variable: String, isSet: Bool, valueSummary: String = "not set") {
        self.variable = variable
        self.isSet = isSet
        self.valueSummary = valueSummary
    }
}

public struct OpenCodeManagedSignal {
    public let detected: Bool
    public let sources: [String]

    public init(detected: Bool = false, sources: [String] = []) {
        self.detected = detected
        self.sources = sources
    }
}

public struct OpenCodeSkillsReadOnlySnapshot {
    public let discoveredSkills: [OpenCodeSkillRecord]
    public let builtinSkills: [OpenCodeSkillRecord]
    public let configLayers: [OpenCodeConfigLayerSignal]
    public let envSignals: [OpenCodeEnvSignal]
    public let managedSignal: OpenCodeManagedSignal
    public let agentMatrix: [OpenCodeAgentSkillAvailability]
    public let scopeWarnings: [String]
    public let scanTimestamp: Date
    public let openCodeInstalled: Bool
    public let skillsPathsEntries: [String]
    public let skillsUrlsEntries: [String]
    public let desktopLocalStateIgnored: Bool
    public let ohMyOpenAgentDetected: Bool
    public let historicalBakCount: Int

    public init(
        discoveredSkills: [OpenCodeSkillRecord] = [],
        builtinSkills: [OpenCodeSkillRecord] = [],
        configLayers: [OpenCodeConfigLayerSignal] = [],
        envSignals: [OpenCodeEnvSignal] = [],
        managedSignal: OpenCodeManagedSignal = OpenCodeManagedSignal(),
        agentMatrix: [OpenCodeAgentSkillAvailability] = [],
        scopeWarnings: [String] = [],
        openCodeInstalled: Bool = false,
        skillsPathsEntries: [String] = [],
        skillsUrlsEntries: [String] = [],
        desktopLocalStateIgnored: Bool = false,
        ohMyOpenAgentDetected: Bool = false,
        historicalBakCount: Int = 0
    ) {
        self.discoveredSkills = discoveredSkills
        self.builtinSkills = builtinSkills
        self.configLayers = configLayers
        self.envSignals = envSignals
        self.managedSignal = managedSignal
        self.agentMatrix = agentMatrix
        self.scopeWarnings = scopeWarnings
        self.scanTimestamp = Date()
        self.openCodeInstalled = openCodeInstalled
        self.skillsPathsEntries = skillsPathsEntries
        self.skillsUrlsEntries = skillsUrlsEntries
        self.desktopLocalStateIgnored = desktopLocalStateIgnored
        self.ohMyOpenAgentDetected = ohMyOpenAgentDetected
        self.historicalBakCount = historicalBakCount
    }
}

public enum OpenCodeSkillsReadOnlyStore {

    nonisolated(unsafe) private static let fm = FileManager.default
    private static let homeDir = fm.homeDirectoryForCurrentUser

    private static let opencodeConfigDir: URL = {
        homeDir.appendingPathComponent(".config/opencode", isDirectory: true)
    }()

    public static func buildReadOnlySnapshot() -> OpenCodeSkillsReadOnlySnapshot {
        var scopeWarnings: [String] = []

        let openCodeInstalled = fm.fileExists(atPath: opencodeConfigDir.path)

        let layers = readConfigLayers()
        let envSignals = detectEnvSignals()
        let managedSignal = detectManagedConfig()

        var skillsPaths: [String] = []
        var skillsUrls: [String] = []

        let mergedConfig = mergeConfigLayers(layers)
        if let sp = mergedConfig["skillsPaths"] as? [String] {
            skillsPaths = sp
        }
        if let su = mergedConfig["skillsUrls"] as? [String] {
            skillsUrls = su
        }
        if !skillsUrls.isEmpty {
            scopeWarnings.append("Remote skill index URLs detected (\(skillsUrls.count)) — not fetched in v0.7.0")
        }

        let desktopLocalState = checkDesktopLocalState()
        let ohMyAgentDetected = checkOhMyOpenAgent()
        let bakCount = countHistoricalBakFiles()

        if desktopLocalState {
            scopeWarnings.append("Desktop local state (ai.opencode.desktop) detected but not parsed")
        }
        if ohMyAgentDetected {
            scopeWarnings.append("Agent-level overrides in oh-my-openagent.json not scanned in v0.7.0")
        }
        if bakCount > 0 {
            scopeWarnings.append("\(bakCount) historical backup files detected in OpenCode config directory")
        }

        let discoverResult = OpenCodeSkillDiscovery.discoverStandardSkills()
        var allSkills = discoverResult.records
        if !skillsPaths.isEmpty {
            let customResult = OpenCodeSkillDiscovery.discoverFromCustomPaths(skillsPaths)
            allSkills.append(contentsOf: customResult.records)
            scopeWarnings.append(contentsOf: customResult.warnings)
        }

        if envSignals.contains(where: { $0.variable == "OPENCODE_CONFIG_DIR" && $0.isSet }) {
            let envPath = ProcessInfo.processInfo.environment["OPENCODE_CONFIG_DIR"] ?? ""
            if !envPath.isEmpty {
                let customDirResult = OpenCodeSkillDiscovery.discoverFromCustomConfigDir(envPath)
                allSkills.append(contentsOf: customDirResult.records)
                scopeWarnings.append(contentsOf: customDirResult.warnings)
            }
        }

        scopeWarnings.append(contentsOf: discoverResult.warnings)

        let permissionConfig = mergedConfig["permission"]

        let agentOverrides = extractAgentOverrides(from: mergedConfig)
        let legacyTools = extractLegacyTools(from: mergedConfig)

        let agentMatrix = OpenCodeSkillPermissionResolver.buildAgentMatrix(
            permissionConfig: permissionConfig,
            agentOverrides: agentOverrides,
            legacyTools: legacyTools
        )

        scopeWarnings.append("Project-level skills and config not scanned — this is global baseline only")

        return OpenCodeSkillsReadOnlySnapshot(
            discoveredSkills: allSkills,
            builtinSkills: discoverResult.builtinSkills,
            configLayers: layers,
            envSignals: envSignals,
            managedSignal: managedSignal,
            agentMatrix: agentMatrix,
            scopeWarnings: scopeWarnings,
            openCodeInstalled: openCodeInstalled,
            skillsPathsEntries: skillsPaths,
            skillsUrlsEntries: skillsUrls,
            desktopLocalStateIgnored: desktopLocalState,
            ohMyOpenAgentDetected: ohMyAgentDetected,
            historicalBakCount: bakCount
        )
    }

    private static func readConfigLayers() -> [OpenCodeConfigLayerSignal] {
        var layers: [OpenCodeConfigLayerSignal] = []

        let candidates: [(name: String, filename: String, isCompatibility: Bool)] = [
            ("config.json", "config.json", true),
            ("opencode.json", "opencode.json", false),
            ("opencode.jsonc", "opencode.jsonc", false),
        ]

        for (name, filename, isCompat) in candidates {
            let fileURL = opencodeConfigDir.appendingPathComponent(filename)
            guard fm.fileExists(atPath: fileURL.path) else {
                layers.append(OpenCodeConfigLayerSignal(
                    name: name, path: fileURL.path, isPresent: false,
                    isCompatibilityLayer: isCompat
                ))
                continue
            }

            let isJSONC = filename.hasSuffix(".jsonc")

            guard let data = try? Data(contentsOf: fileURL),
                  let rawString = String(data: data, encoding: .utf8) else {
                layers.append(OpenCodeConfigLayerSignal(
                    name: name, path: fileURL.path, isPresent: true,
                    parseError: "Cannot read file or non-UTF-8 encoding",
                    isJSONC: isJSONC, isCompatibilityLayer: isCompat
                ))
                continue
            }

            let hasComments = rawString.contains("//") || rawString.contains("/*")
            let useJSONCParser = isJSONC || hasComments

            let parseResult = parseJSONConfig(rawString, useJSONC: useJSONCParser)

            switch parseResult {
            case .success(let dict):
                layers.append(OpenCodeConfigLayerSignal(
                    name: name, path: fileURL.path, isPresent: true,
                    isJSONC: isJSONC || hasComments,
                    isCompatibilityLayer: isCompat,
                    rawJSON: dict
                ))
            case .failure(let error):
                layers.append(OpenCodeConfigLayerSignal(
                    name: name, path: fileURL.path, isPresent: true,
                    parseError: String(error.prefix(200)),
                    isJSONC: isJSONC || hasComments,
                    isCompatibilityLayer: isCompat
                ))
            }
        }

        return layers
    }

    private enum JSONParseResult {
        case success([String: Any])
        case failure(String)
    }

    private static func parseJSONConfig(_ raw: String, useJSONC: Bool) -> JSONParseResult {
        var cleaned = raw

        if useJSONC {
            cleaned = cleaned.replacingOccurrences(
                of: "//.*",
                with: "",
                options: .regularExpression
            )
            cleaned = cleaned.replacingOccurrences(
                of: "/\\*[\\s\\S]*?\\*/",
                with: "",
                options: .regularExpression
            )
            cleaned = cleaned.replacingOccurrences(
                of: ",\\s*}",
                with: "}",
                options: .regularExpression
            )
            cleaned = cleaned.replacingOccurrences(
                of: ",\\s*]",
                with: "]",
                options: .regularExpression
            )
        }

        guard let data = cleaned.data(using: .utf8) else {
            return .failure("Cannot encode config as UTF-8")
        }

        do {
            if let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                return .success(redactSecrets(in: dict))
            }
            return .failure("Config is not a JSON object")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func redactSecrets(in dict: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        let secretKeys = ["token", "secret", "apikey", "api_key", "authorization", "cookie", "password", "bearer"]

        for (key, value) in dict {
            let lowerKey = key.lowercased()
            let isSecret = secretKeys.contains(where: { lowerKey.contains($0) })

            if isSecret, let _ = value as? String {
                result[key] = "[REDACTED]"
            } else if let nestedDict = value as? [String: Any] {
                result[key] = redactSecrets(in: nestedDict)
            } else if let nestedArray = value as? [[String: Any]] {
                result[key] = nestedArray.map { redactSecrets(in: $0) }
            } else {
                result[key] = value
            }
        }

        return result
    }

    private static func mergeConfigLayers(_ layers: [OpenCodeConfigLayerSignal]) -> [String: Any] {
        var merged: [String: Any] = [:]

        for layer in layers {
            guard layer.isPresent, layer.parseError == nil, let dict = layer.rawJSON else {
                continue
            }
            for (key, value) in dict {
                merged[key] = value
            }
        }

        return merged
    }

    private static func extractAgentOverrides(from config: [String: Any]) -> [OpenCodeAgentKind: [String: Any]] {
        var overrides: [OpenCodeAgentKind: [String: Any]] = [:]

        guard let agents = config["agent"] as? [String: Any] else {
            return overrides
        }

        for (agentName, agentConfig) in agents {
            guard let kind = OpenCodeAgentKind(rawValue: agentName),
                  let configDict = agentConfig as? [String: Any] else {
                continue
            }
            overrides[kind] = configDict
        }

        return overrides
    }

    private static func extractLegacyTools(from config: [String: Any]) -> [String: Any] {
        var tools: [String: Any] = [:]

        if let globalTools = config["tools"] as? [String: Any] {
            tools["_global"] = globalTools
        }

        guard let agents = config["agent"] as? [String: Any] else {
            return tools
        }

        for (agentName, agentConfig) in agents {
            guard let configDict = agentConfig as? [String: Any],
                  let agentTools = configDict["tools"] as? [String: Any] else {
                continue
            }
            tools[agentName] = agentTools
        }

        return tools
    }

    private static func detectEnvSignals() -> [OpenCodeEnvSignal] {
        let env = ProcessInfo.processInfo.environment
        var signals: [OpenCodeEnvSignal] = []

        let varsToCheck: [(String, String)] = [
            ("OPENCODE_CONFIG", "present (path hidden)"),
            ("OPENCODE_CONFIG_DIR", "present (path hidden)"),
            ("OPENCODE_CONFIG_CONTENT", "present (content hidden)"),
            ("OPENCODE_DISABLE_CLAUDE_CODE", "present"),
            ("OPENCODE_DISABLE_CLAUDE_CODE_SKILLS", "present"),
        ]

        for (variable, summary) in varsToCheck {
            signals.append(OpenCodeEnvSignal(
                variable: variable,
                isSet: env[variable] != nil,
                valueSummary: env[variable] != nil ? summary : "not set"
            ))
        }

        return signals
    }

    private static func detectManagedConfig() -> OpenCodeManagedSignal {
        var detected = false
        var sources: [String] = []

        let managedPaths: [String] = [
            "/Library/Application Support/opencode",
        ]
        for path in managedPaths {
            if fm.fileExists(atPath: path) {
                detected = true
                sources.append(path)
            }
        }

        let mdmBundleIDs = [
            "ai.opencode.desktop",
            "ai.opencode.desktop.beta",
            "ai.opencode.desktop.dev",
        ]
        for bundleID in mdmBundleIDs {
            let plistPath = "/Library/Managed Preferences/\(bundleID).managed.plist"
            if fm.fileExists(atPath: plistPath) {
                detected = true
                sources.append(plistPath)
            }
        }

        return OpenCodeManagedSignal(detected: detected, sources: sources)
    }

    private static func checkDesktopLocalState() -> Bool {
        let desktopAppSupport = homeDir
            .appendingPathComponent("Library/Application Support/ai.opencode.desktop", isDirectory: true)
        let lockFile = desktopAppSupport.appendingPathComponent("skills/.skill-lock.json")
        return fm.fileExists(atPath: lockFile.path)
    }

    private static func checkOhMyOpenAgent() -> Bool {
        let path = opencodeConfigDir.appendingPathComponent("oh-my-openagent.json")
        return fm.fileExists(atPath: path.path)
    }

    private static func countHistoricalBakFiles() -> Int {
        guard let contents = try? fm.contentsOfDirectory(atPath: opencodeConfigDir.path) else {
            return 0
        }
        return contents.filter { $0.hasPrefix(".bak-") || $0.contains(".bak-") }.count
    }
}
