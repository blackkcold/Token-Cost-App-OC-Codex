import Foundation

/// Provider-scoped price for one model, expressed in USD per 1M tokens.
///
/// The catalog is the only place that knows what a model costs. Model ranking
/// reads it; provider-level billing fallbacks keep their own legacy snapshot so
/// that adding a price can never silently move a provider total.
public struct ModelPrice: Codable, Equatable, Sendable {
    public var input: Double
    public var output: Double
    /// When absent, reasoning tokens are billed at the output rate.
    public var reasoning: Double?
    public var cacheRead: Double
    public var cacheWrite: Double

    public init(
        input: Double,
        output: Double,
        reasoning: Double? = nil,
        cacheRead: Double = 0,
        cacheWrite: Double = 0
    ) {
        self.input = input
        self.output = output
        self.reasoning = reasoning
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }

    public var isFree: Bool {
        input == 0 && output == 0 && (reasoning ?? 0) == 0 && cacheRead == 0 && cacheWrite == 0
    }

    init(legacy table: [String: Double]) {
        self.input = table["input"] ?? 0
        self.output = table["output"] ?? 0
        self.reasoning = table["reasoning"]
        self.cacheRead = table["cacheRead"] ?? 0
        self.cacheWrite = table["cacheWrite"] ?? 0
    }

    public func cost(
        input: Double,
        output: Double,
        reasoning: Double,
        cacheRead: Double,
        cacheWrite: Double
    ) -> Double {
        func valid(_ value: Double) -> Double {
            value.isFinite && value > 0 ? value : 0
        }
        let outputPrice = self.output
        let reasoningPrice = self.reasoning ?? outputPrice
        let sum = valid(input) * self.input
            + valid(output) * outputPrice
            + valid(reasoning) * reasoningPrice
            + valid(cacheRead) * self.cacheRead
            + valid(cacheWrite) * self.cacheWrite
        return sum / 1_000_000
    }
}

/// A model-price directory that discovers model IDs from data instead of a
/// hand-maintained list, and merges build/edition variants onto one family key.
public struct ModelPricingCatalog: Sendable {
    public enum Match: String, Codable, Sendable {
        case override
        case exact
        case alias
        case variant
        case family
        case prefix
        case crossProvider
        case freeInferred
        case unknown
    }

    public struct Resolution: Equatable, Sendable {
        public var providerKey: String
        public var rawKey: String
        /// Grouping/display key. Build tags (`:1017`, `-cloud`, `-preview`) are merged away.
        public var canonicalKey: String
        /// The catalog entry that actually supplied the price, when any.
        public var matchedKey: String?
        public var price: ModelPrice?
        public var match: Match
        public var variantTags: [String]

        public var isPriced: Bool { price != nil }
        public var isFree: Bool {
            if let price { return price.isFree }
            return match == .freeInferred
        }
        /// True when the price was borrowed from a related key rather than read verbatim.
        public var isInherited: Bool {
            switch match {
            case .variant, .family, .prefix, .crossProvider: return true
            default: return false
            }
        }
    }

    public struct Metadata: Equatable, Sendable {
        public var sourceLabel: String
        public var asOf: Date?
        public var providerCount: Int
        public var modelCount: Int

        public init(sourceLabel: String, asOf: Date?, providerCount: Int, modelCount: Int) {
            self.sourceLabel = sourceLabel
            self.asOf = asOf
            self.providerCount = providerCount
            self.modelCount = modelCount
        }

        public static let empty = Metadata(sourceLabel: "", asOf: nil, providerCount: 0, modelCount: 0)
    }

    public var metadata: Metadata

    /// `[providerKey: [modelKey: price]]`
    private let providers: [String: [String: ModelPrice]]
    /// Per provider, catalog keys sorted longest-first for prefix matching.
    private let sortedKeys: [String: [String]]
    /// `"provider|model"` → price, from the user's override file.
    private let overrides: [String: ModelPrice]

    public init(
        providers: [String: [String: ModelPrice]],
        overrides: [String: ModelPrice] = [:],
        metadata: Metadata = .empty
    ) {
        var normalizedProviders: [String: [String: ModelPrice]] = [:]
        var normalizedSorted: [String: [String]] = [:]
        for (provider, models) in providers {
            let providerKey = Self.normalizedProviderKey(provider)
            var table: [String: ModelPrice] = normalizedProviders[providerKey] ?? [:]
            for (model, price) in models {
                table[Self.normalizedModelKey(model)] = price
            }
            normalizedProviders[providerKey] = table
            normalizedSorted[providerKey] = table.keys.sorted { lhs, rhs in
                lhs.count == rhs.count ? lhs < rhs : lhs.count > rhs.count
            }
        }
        var normalizedOverrides: [String: ModelPrice] = [:]
        for (key, price) in overrides {
            normalizedOverrides[key.lowercased()] = price
        }
        self.providers = normalizedProviders
        self.sortedKeys = normalizedSorted
        self.overrides = normalizedOverrides
        self.metadata = metadata
    }

    public var isEmpty: Bool { providers.isEmpty }

    public func priceTable(for provider: String) -> [String: ModelPrice]? {
        providers[Self.normalizedProviderKey(provider)]
    }

    // MARK: — Resolution

    public func resolve(provider: String, model: String) -> Resolution {
        let providerKey = Self.normalizedProviderKey(provider)
        let rawKey = Self.normalizedModelKey(model)
        let split = Self.splitVariants(rawKey)
        let isFreeNamed = rawKey.hasSuffix("free")

        func make(_ canonical: String, _ matched: String?, _ price: ModelPrice?, _ match: Match) -> Resolution {
            Resolution(
                providerKey: providerKey,
                rawKey: rawKey,
                canonicalKey: canonical,
                matchedKey: matched,
                price: price,
                match: match,
                variantTags: split.tags
            )
        }

        // 1. User override, keyed by the exact provider|model pair.
        if let override = overrides["\(providerKey)|\(rawKey)"] {
            return make(split.family, rawKey, override, .override)
        }

        let table = providers[providerKey] ?? [:]

        // 2. Verbatim catalog entry.
        if let price = table[rawKey] {
            return make(split.family, rawKey, price, .exact)
        }

        // 3. Legacy rename (deepseek-chat → deepseek-v4-flash, …).
        if let alias = TokenCostPricingCatalog.modelAliases[rawKey], let price = table[alias] {
            return make(Self.splitVariants(alias).family, alias, price, .alias)
        }

        // 4. A model whose name says "free" must never inherit a paid price.
        if isFreeNamed {
            return make(split.family, nil, nil, .freeInferred)
        }

        // 5. Strip one build/edition qualifier at a time, most specific first.
        for key in split.progressiveKeys {
            if let price = table[key] {
                return make(split.family, key, price, .variant)
            }
        }

        // 6. The merged family itself.
        if let price = table[split.family] {
            return make(split.family, split.family, price, .family)
        }

        // 7. Longest catalog key that prefixes this id (`:0731-cloud` → `…:0731`).
        if let keys = sortedKeys[providerKey] {
            for key in keys where rawKey.count > key.count && rawKey.hasPrefix(key) {
                if let price = table[key] {
                    return make(split.family, key, price, .prefix)
                }
            }
        }

        // 8. Cross-provider inheritance, only when the family is unambiguous.
        let candidates = providers.compactMap { key, value -> (String, ModelPrice)? in
            guard key != providerKey, let price = value[split.family] else { return nil }
            return (key, price)
        }
        if candidates.count == 1, let candidate = candidates.first {
            return make(split.family, split.family, candidate.1, .crossProvider)
        }

        return make(split.family, nil, nil, .unknown)
    }

    public func canonicalKey(provider: String, model: String) -> String {
        resolve(provider: provider, model: model).canonicalKey
    }

    // MARK: — Key normalization

    public static func normalizedProviderKey(_ provider: String) -> String {
        let trimmed = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed.lowercased()
    }

    public static func normalizedModelKey(_ model: String) -> String {
        var normalized = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        normalized = normalized
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        if let slashIndex = normalized.lastIndex(of: "/") {
            normalized = String(normalized[normalized.index(after: slashIndex)...])
        }
        return normalized
    }

    /// Splits a model id into a family key plus the build/edition qualifiers that
    /// were removed. `-free` and `-exp` are *not* stripped: they are distinct
    /// offerings whose price must never be borrowed from the paid base model.
    public struct VariantSplit: Equatable, Sendable {
        public var family: String
        public var tags: [String]
        /// Intermediate keys from most to least specific, excluding the raw id
        /// and ending with `family`.
        public var progressiveKeys: [String]
    }

    public static func splitVariants(_ model: String) -> VariantSplit {
        var current = model
        var tags: [String] = []
        var keys: [String] = []
        while let stripped = strippedSuffix(current) {
            current = stripped.remainder
            tags.append(stripped.tag)
            keys.append(current)
        }
        return VariantSplit(family: current, tags: tags, progressiveKeys: keys)
    }

    private static func strippedSuffix(_ value: String) -> (remainder: String, tag: String)? {
        if let colon = value.lastIndex(of: ":") {
            let token = String(value[value.index(after: colon)...])
            if !token.isEmpty,
               token.count <= 24,
               token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_") }) {
                let remainder = String(value[..<colon])
                if !remainder.isEmpty {
                    return (remainder, ":\(token)")
                }
            }
        }
        for suffix in buildQualifiers where value.hasSuffix(suffix) && value.count > suffix.count {
            return (String(value.dropLast(suffix.count)), suffix)
        }
        if let range = value.range(of: #"-\d{4,8}$"#, options: .regularExpression), range.lowerBound > value.startIndex {
            return (String(value[..<range.lowerBound]), String(value[range]))
        }
        return nil
    }

    /// Only qualifiers that name a build or a deployment of the same model.
    /// Semantic identity markers (`-mini`, `-pro`, `-max`, `-exp`, `-free`) are
    /// deliberately absent: merging those would misprice the model.
    private static let buildQualifiers = [
        "-cloud",
        "-fast",
        "-preview",
        "-latest",
        "-edge",
        "-thinking"
    ]

    // MARK: — Bundled fallback

    /// Deterministic snapshot used when no catalog file is available (and the
    /// default for tests). Mirrors the legacy hand-maintained tables exactly, so
    /// adding the catalog cannot change existing figures unless a file-backed
    /// catalog is supplied.
    public static let bundledSnapshot = ModelPricingCatalog(
        providers: TokenCostPricingCatalog.bundledProviderTables,
        metadata: Metadata(
            sourceLabel: "bundled",
            asOf: nil,
            providerCount: TokenCostPricingCatalog.bundledProviderTables.count,
            modelCount: TokenCostPricingCatalog.bundledProviderTables.values.reduce(0) { $0 + $1.count }
        )
    )

    /// Catalog backed by models.dev data on disk. Falls back to the bundled
    /// snapshot when nothing is readable.
    public static var shared: ModelPricingCatalog { ModelPricingCatalogStore.shared.current }
}

/// Holds the live catalog and refreshes it from models.dev at most once a day.
public final class ModelPricingCatalogStore: @unchecked Sendable {
    public static let shared = ModelPricingCatalogStore()
    public static let didUpdateNotification = Notification.Name("TokenCostModelPricingDidUpdate")

    private static let refreshInterval: TimeInterval = 24 * 60 * 60
    private static let remoteURL = URL(string: "https://models.dev/api.json")!

    private let lock = NSLock()
    private let fileManager: FileManager
    private let appSupportRoot: URL
    private let openCodeCacheURL: URL
    private var catalog: ModelPricingCatalog
    private var isRefreshing = false

    init(
        fileManager: FileManager = .default,
        appSupportRoot: URL = TokenCostPaths.applicationSupportRoot,
        openCodeCacheURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.appSupportRoot = appSupportRoot
        self.openCodeCacheURL = openCodeCacheURL
            ?? ModelPricingCatalog.defaultOpenCodeCacheURL(fileManager: fileManager)
        self.catalog = ModelPricingCatalog.load(
            fileManager: fileManager,
            openCodeCacheURL: self.openCodeCacheURL,
            appSupportRoot: appSupportRoot
        )
    }

    public var current: ModelPricingCatalog {
        lock.lock()
        defer { lock.unlock() }
        return catalog
    }

    /// Re-reads the catalog files. Cheap enough to call after an override edit.
    @discardableResult
    public func reloadFromDisk() -> ModelPricingCatalog {
        let reloaded = ModelPricingCatalog.load(
            fileManager: fileManager,
            openCodeCacheURL: openCodeCacheURL,
            appSupportRoot: appSupportRoot
        )
        lock.lock()
        let changed = reloaded.metadata != catalog.metadata
        catalog = reloaded
        lock.unlock()
        if changed {
            NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
        }
        return reloaded
    }

    /// Fetches models.dev when the on-disk index is older than a day (or `force`).
    /// Failures are silent: the previous catalog stays in place.
    public func refreshIfNeeded(force: Bool = false) async {
        guard beginRefresh() else { return }
        defer { endRefresh() }

        let indexURL = appSupportRoot.appendingPathComponent("model-price-index.json")
        if !force, let asOf = Self.indexTimestamp(at: indexURL), Date().timeIntervalSince(asOf) < Self.refreshInterval {
            return
        }

        guard let fresh = await Self.fetchRemoteProviders() else { return }
        guard let encoded = ModelPricingCatalog.encodeCompactIndex(providers: fresh, fetchedAt: Date()) else { return }
        try? fileManager.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)
        try? encoded.write(to: indexURL, options: .atomic)
        reloadFromDisk()
    }

    private func beginRefresh() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isRefreshing { return false }
        isRefreshing = true
        return true
    }

    private func endRefresh() {
        lock.lock()
        isRefreshing = false
        lock.unlock()
    }

    private static func indexTimestamp(at url: URL) -> Date? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fetchedAt = root["fetchedAt"] as? Double else {
            return nil
        }
        return Date(timeIntervalSince1970: fetchedAt)
    }

    private static func fetchRemoteProviders() async -> [String: [String: ModelPrice]]? {
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return ModelPricingCatalog.decodeModelsDevData(data)
        } catch {
            return nil
        }
    }
}

// MARK: — Loading

extension ModelPricingCatalog {
    /// Sources, in increasing priority: bundled snapshot, OpenCode's models.dev
    /// cache, this app's refreshed index, then the user's override file.
    public static func load(
        fileManager: FileManager = .default,
        openCodeCacheURL: URL? = nil,
        appSupportRoot: URL? = nil
    ) -> ModelPricingCatalog {
        let openCodeURL = openCodeCacheURL ?? defaultOpenCodeCacheURL(fileManager: fileManager)
        let appRoot = appSupportRoot ?? TokenCostPaths.applicationSupportRoot
        let indexURL = appRoot.appendingPathComponent("model-price-index.json")
        let overrideURL = appRoot.appendingPathComponent("model-prices.json")

        var providers = TokenCostPricingCatalog.bundledProviderTables
        var sourceLabel = "bundled"
        var asOf: Date?

        if let decoded = decodeModelsDevFile(at: openCodeURL, fileManager: fileManager) {
            providers = decoded.providers
            sourceLabel = "opencode-cache"
            asOf = decoded.asOf
        }
        if let decoded = decodeCompactIndex(at: indexURL, fileManager: fileManager) {
            providers = merged(providers, with: decoded.providers)
            sourceLabel = "models.dev"
            asOf = decoded.asOf ?? asOf
        }
        let overrides = decodeOverrides(at: overrideURL, fileManager: fileManager)

        let modelCount = providers.values.reduce(0) { $0 + $1.count }
        return ModelPricingCatalog(
            providers: providers,
            overrides: overrides,
            metadata: Metadata(
                sourceLabel: sourceLabel,
                asOf: asOf,
                providerCount: providers.count,
                modelCount: modelCount
            )
        )
    }

    private static func merged(
        _ base: [String: [String: ModelPrice]],
        with overlay: [String: [String: ModelPrice]]
    ) -> [String: [String: ModelPrice]] {
        var result = base
        for (provider, models) in overlay {
            var table = result[provider] ?? [:]
            for (model, price) in models {
                table[model] = price
            }
            result[provider] = table
        }
        return result
    }

    static func defaultOpenCodeCacheURL(fileManager: FileManager) -> URL {
        let base = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("opencode", isDirectory: true)
        return base.appendingPathComponent("models.json")
    }

    private static func decodeModelsDevFile(
        at url: URL,
        fileManager: FileManager
    ) -> (providers: [String: [String: ModelPrice]], asOf: Date?)? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let providers = decodeModelsDevData(data) else { return nil }
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (providers, attributes?[.modificationDate] as? Date)
    }

    /// Parses the models.dev shape: `{providerID: {models: {modelID: {cost: …}}}}`
    /// (a `providers` wrapper is accepted too).
    static func decodeModelsDevData(_ data: Data) -> [String: [String: ModelPrice]]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let providerEntries: [String: Any]
        if let nested = root["providers"] as? [String: Any] {
            providerEntries = nested
        } else {
            providerEntries = root
        }
        var providers: [String: [String: ModelPrice]] = [:]
        for (providerID, value) in providerEntries {
            guard let providerObject = value as? [String: Any],
                  let models = providerObject["models"] as? [String: Any] else { continue }
            var table: [String: ModelPrice] = [:]
            for (modelID, modelValue) in models {
                guard let modelObject = modelValue as? [String: Any],
                      let costObject = modelObject["cost"] as? [String: Any] else { continue }
                table[modelID] = price(fromCostObject: costObject)
            }
            if !table.isEmpty {
                providers[providerID] = table
            }
        }
        guard !providers.isEmpty else { return nil }
        return providers
    }

    private static func decodeCompactIndex(
        at url: URL,
        fileManager: FileManager
    ) -> (providers: [String: [String: ModelPrice]], asOf: Date?)? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providerEntries = root["providers"] as? [String: Any] else {
            return nil
        }
        var providers: [String: [String: ModelPrice]] = [:]
        for (providerID, value) in providerEntries {
            guard let models = value as? [String: Any] else { continue }
            var table: [String: ModelPrice] = [:]
            for (modelID, priceValue) in models {
                guard let object = priceValue as? [String: Any] else { continue }
                table[modelID] = ModelPrice(
                    input: number(object["input"]),
                    output: number(object["output"]),
                    reasoning: object["reasoning"] == nil ? nil : number(object["reasoning"]),
                    cacheRead: number(object["cache_read"]),
                    cacheWrite: number(object["cache_write"])
                )
            }
            if !table.isEmpty {
                providers[providerID] = table
            }
        }
        let asOf = (root["fetchedAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
        return providers.isEmpty ? nil : (providers, asOf)
    }

    private static func decodeOverrides(
        at url: URL,
        fileManager: FileManager
    ) -> [String: ModelPrice] {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var overrides: [String: ModelPrice] = [:]
        if let providers = root["providers"] as? [String: Any] {
            for (providerID, value) in providers {
                guard let models = value as? [String: Any] else { continue }
                for (modelID, priceValue) in models {
                    guard let object = priceValue as? [String: Any] else { continue }
                    let key = "\(normalizedProviderKey(providerID))|\(normalizedModelKey(modelID))"
                    overrides[key] = price(fromFlatObject: object)
                }
            }
        }
        if let flat = root["models"] as? [String: Any] {
            for (key, value) in flat {
                guard let object = value as? [String: Any] else { continue }
                overrides[key.lowercased()] = price(fromFlatObject: object)
            }
        }
        return overrides
    }

    private static func price(fromCostObject object: [String: Any]) -> ModelPrice {
        ModelPrice(
            input: number(object["input"]),
            output: number(object["output"]),
            reasoning: object["reasoning"] == nil ? nil : number(object["reasoning"]),
            cacheRead: number(object["cache_read"]),
            cacheWrite: number(object["cache_write"])
        )
    }

    private static func price(fromFlatObject object: [String: Any]) -> ModelPrice {
        price(fromCostObject: object)
    }

    private static func number(_ value: Any?) -> Double {
        if let double = value as? Double, double.isFinite { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        return 0
    }

    static func encodeCompactIndex(
        providers: [String: [String: ModelPrice]],
        fetchedAt: Date
    ) -> Data? {
        var payload: [String: Any] = ["version": 1, "fetchedAt": fetchedAt.timeIntervalSince1970]
        var providerPayload: [String: [String: [String: Double]]] = [:]
        for (provider, models) in providers {
            var table: [String: [String: Double]] = [:]
            for (model, price) in models {
                var object: [String: Double] = [
                    "input": price.input,
                    "output": price.output,
                    "cache_read": price.cacheRead,
                    "cache_write": price.cacheWrite
                ]
                if let reasoning = price.reasoning { object["reasoning"] = reasoning }
                table[model] = object
            }
            providerPayload[provider] = table
        }
        payload["providers"] = providerPayload
        return try? JSONSerialization.data(withJSONObject: payload)
    }
}
