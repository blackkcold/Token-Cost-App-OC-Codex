import XCTest
@testable import CodexTokenCostCore

final class ModelPricingCatalogTests: XCTestCase {
    // MARK: — Fixture

    private func makeCatalog(overrides: [String: ModelPrice] = [:]) -> ModelPricingCatalog {
        ModelPricingCatalog(
            providers: [
                "ollama-cloud": [
                    "deepseek-v4.1-flash": ModelPrice(input: 0.15, output: 0.60, cacheRead: 0.003),
                    "deepseek-v4-flash": ModelPrice(input: 0.22, output: 0.66, cacheRead: 0.007),
                    "deepseek-v4-flash:0731": ModelPrice(input: 0.22, output: 0.66, cacheRead: 0.007),
                    "glm-5.3-flash": ModelPrice(input: 0.15, output: 0.50, cacheRead: 0.03),
                    "deepseek-v4-flash-vision-exp": ModelPrice(input: 0.30, output: 1.20, cacheRead: 0.01)
                ],
                "opencode": [
                    "deepseek-v4.1-flash": ModelPrice(input: 0.30, output: 1.20, cacheRead: 0.006),
                    "deepseek-v4.1-flash-free": ModelPrice(input: 0, output: 0, cacheRead: 0)
                ],
                "deepseek": [
                    "deepseek-v4-flash": ModelPrice(input: 0.15, output: 0.60, cacheRead: 0.003)
                ],
                "openai": [
                    "gpt-6-luna": ModelPrice(input: 0.10, output: 0.50, cacheRead: 0.01)
                ]
            ],
            overrides: overrides,
            metadata: .init(sourceLabel: "fixture", asOf: nil, providerCount: 4, modelCount: 8)
        )
    }

    // MARK: — Variant merging

    func testVersionBuildTagMergesIntoBaseFamily() {
        let resolution = makeCatalog().resolve(provider: "ollama-cloud", model: "deepseek-v4.1-flash:1017")

        XCTAssertEqual(resolution.canonicalKey, "deepseek-v4.1-flash")
        XCTAssertEqual(resolution.matchedKey, "deepseek-v4.1-flash")
        XCTAssertEqual(resolution.match, .variant)
        XCTAssertEqual(resolution.price?.input ?? 0, 0.15, accuracy: 0.0001)
        XCTAssertEqual(resolution.variantTags, [":1017"])
    }

    func testCloudDeploymentSuffixUsesMostSpecificBuildPrice() {
        let resolution = makeCatalog().resolve(provider: "ollama-cloud", model: "deepseek-v4-flash:0731-cloud")

        XCTAssertEqual(resolution.canonicalKey, "deepseek-v4-flash")
        XCTAssertEqual(resolution.matchedKey, "deepseek-v4-flash:0731")
        XCTAssertEqual(resolution.match, .variant)
        XCTAssertEqual(resolution.price?.input ?? 0, 0.22, accuracy: 0.0001)
        XCTAssertTrue(resolution.isInherited)
    }

    func testColonEditionSuffixMergesToBaseModel() {
        let resolution = makeCatalog().resolve(provider: "ollama-cloud", model: "glm-5.3-flash:cloud")

        XCTAssertEqual(resolution.canonicalKey, "glm-5.3-flash")
        XCTAssertEqual(resolution.matchedKey, "glm-5.3-flash")
        XCTAssertEqual(resolution.match, .variant)
        XCTAssertEqual(resolution.price?.cacheRead ?? 0, 0.03, accuracy: 0.0001)
    }

    func testMinorVersionIsNotMergedIntoOlderVersion() {
        let catalog = makeCatalog()
        let newer = catalog.resolve(provider: "ollama-cloud", model: "deepseek-v4.1-flash")
        let older = catalog.resolve(provider: "ollama-cloud", model: "deepseek-v4-flash")

        XCTAssertNotEqual(newer.canonicalKey, older.canonicalKey)
        XCTAssertEqual(newer.price?.input ?? 0, 0.15, accuracy: 0.0001)
        XCTAssertEqual(older.price?.out ?? 0, 0.66, accuracy: 0.0001)
    }

    func testExperimentalModelKeepsItsOwnIdentity() {
        let resolution = makeCatalog().resolve(provider: "ollama-cloud", model: "deepseek-v4-flash-vision-exp")

        XCTAssertEqual(resolution.canonicalKey, "deepseek-v4-flash-vision-exp")
        XCTAssertEqual(resolution.match, .exact)
    }

    // MARK: — Free models

    func testFreeModelWithCatalogEntryIsPricedAtZero() {
        let resolution = makeCatalog().resolve(provider: "opencode", model: "deepseek-v4.1-flash-free")

        XCTAssertEqual(resolution.canonicalKey, "deepseek-v4.1-flash-free")
        XCTAssertEqual(resolution.match, .exact)
        XCTAssertTrue(resolution.isFree)
        XCTAssertEqual(resolution.price?.cost(input: 1_000_000, output: 0, reasoning: 0, cacheRead: 0, cacheWrite: 0) ?? -1, 0, accuracy: 0.0001)
    }

    func testFreeModelWithoutCatalogEntryIsNeverPricedAsPaidBase() {
        let resolution = makeCatalog().resolve(provider: "ollama-cloud", model: "deepseek-v4.1-flash-free")

        XCTAssertEqual(resolution.canonicalKey, "deepseek-v4.1-flash-free")
        XCTAssertEqual(resolution.match, .freeInferred)
        XCTAssertNil(resolution.price)
        XCTAssertTrue(resolution.isFree)
    }

    // MARK: — Unknown and alias

    func testUnknownModelStaysUnpricedAndKeepsItsOwnKey() {
        let resolution = makeCatalog().resolve(provider: "openai", model: "gpt-6.1-sol")

        XCTAssertEqual(resolution.canonicalKey, "gpt-6.1-sol")
        XCTAssertEqual(resolution.match, .unknown)
        XCTAssertNil(resolution.price)
        XCTAssertFalse(resolution.isFree)
        XCTAssertFalse(resolution.isPriced)
    }

    func testAliasMapsLegacyNameOntoCurrentFamily() {
        let resolution = makeCatalog().resolve(provider: "deepseek", model: "deepseek-chat")

        XCTAssertEqual(resolution.canonicalKey, "deepseek-v4-flash")
        XCTAssertEqual(resolution.matchedKey, "deepseek-v4-flash")
        XCTAssertEqual(resolution.match, .alias)
        XCTAssertEqual(resolution.price?.input ?? 0, 0.15, accuracy: 0.0001)
    }

    func testFastSuffixInheritsBasePriceAndIsMarkedInherited() {
        let resolution = makeCatalog().resolve(provider: "openai", model: "gpt-6-luna-fast")

        XCTAssertEqual(resolution.canonicalKey, "gpt-6-luna")
        XCTAssertEqual(resolution.match, .variant)
        XCTAssertTrue(resolution.isInherited)
        XCTAssertEqual(resolution.price?.output ?? 0, 0.50, accuracy: 0.0001)
    }

    // MARK: — Overrides

    func testUserOverrideWinsOverCatalogAndDiscovery() {
        let catalog = makeCatalog(overrides: [
            "openai|gpt-6.1-sol": ModelPrice(input: 1.25, output: 5.00, cacheRead: 0.125)
        ])

        let resolution = catalog.resolve(provider: "openai", model: "gpt-6.1-sol")

        XCTAssertEqual(resolution.match, .override)
        XCTAssertEqual(resolution.price?.input ?? 0, 1.25, accuracy: 0.0001)
        XCTAssertTrue(resolution.isPriced)
    }

    // MARK: — Cost arithmetic

    func testCostUsesOutputRateForReasoningWhenReasoningPriceIsAbsent() {
        let price = ModelPrice(input: 1.0, output: 2.0, cacheRead: 0.1, cacheWrite: 3.0)

        let cost = price.cost(
            input: 1_000_000,
            output: 1_000_000,
            reasoning: 1_000_000,
            cacheRead: 1_000_000,
            cacheWrite: 1_000_000
        )

        XCTAssertEqual(cost, 1 + 2 + 2 + 0.1 + 3, accuracy: 0.0001)
    }

    // MARK: — Ranking integration

    func testFreeModelRanksFirstPricedSecondAndUnpricedStaysVisibleLast() {
        let payload = makePayload(rows: [
            makeRow(model: "gpt-6.1-sol", provider: "openai", input: 5_000_000),
            makeRow(model: "deepseek-v4.1-flash", provider: "ollama-cloud", input: 1_000_000),
            makeRow(model: "deepseek-v4.1-flash-free", provider: "opencode", input: 1_000_000)
        ])

        let analytics = TokenCostDashboardAnalytics(payload: payload, pricing: makeCatalog())
        let rows = analytics.modelComparisonRows

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].modelKey, "deepseek-v4.1-flash-free")
        XCTAssertTrue(rows[0].isFree)
        XCTAssertEqual(rows[1].modelKey, "deepseek-v4.1-flash")
        XCTAssertEqual(rows[1].allocatedCost, 0.15, accuracy: 0.0001)
        XCTAssertEqual(rows[2].modelKey, "gpt-6.1-sol")
        XCTAssertEqual(rows[2].pricingStatus, .unknown)
        XCTAssertFalse(rows[2].hasPrice)
        XCTAssertEqual(analytics.unpricedModelCount, 1)
    }

    func testBuildVariantsMergeIntoSingleRankedRow() {
        let payload = makePayload(rows: [
            makeRow(model: "deepseek-v4.1-flash", provider: "ollama-cloud", input: 1_000_000),
            makeRow(model: "deepseek-v4.1-flash:1017", provider: "ollama-cloud", input: 2_000_000)
        ])

        let analytics = TokenCostDashboardAnalytics(payload: payload, pricing: makeCatalog())
        let rows = analytics.modelComparisonRows

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].modelKey, "deepseek-v4.1-flash")
        XCTAssertEqual(rows[0].variantCount, 2)
        XCTAssertEqual(rows[0].actualTokens, 3_000_000, accuracy: 0.5)
        XCTAssertEqual(rows[0].allocatedCost, 0.45, accuracy: 0.0001)
    }

    func testInheritedPriceIsLabelledWithTheKeyItWasBorrowedFrom() {
        let payload = makePayload(rows: [
            // cacheRead > 0 keeps the Ollama gross-input estimation out of the way
            makeRow(model: "deepseek-v4-flash:0731-cloud", provider: "ollama-cloud", input: 1_000_000, cacheRead: 1_000)
        ])

        let analytics = TokenCostDashboardAnalytics(payload: payload, pricing: makeCatalog())
        let row = analytics.modelComparisonRows.first

        XCTAssertEqual(row?.modelKey, "deepseek-v4-flash")
        XCTAssertEqual(row?.pricingStatus, .inherited)
        XCTAssertEqual(row?.priceReference, "deepseek-v4-flash:0731")
        XCTAssertEqual(row?.allocatedCost ?? 0, 0.220007, accuracy: 0.0001)
    }

    func testBundledCatalogKeepsLegacyPricingForOfflineParity() {
        let payload = makePayload(rows: [
            makeRow(model: "deepseek-v4-flash", provider: "opencode", input: 1_000_000)
        ])

        let analytics = TokenCostDashboardAnalytics(payload: payload)
        let row = analytics.modelComparisonRows.first

        XCTAssertEqual(row?.allocatedCost ?? 0, 0.14, accuracy: 0.0001)
        XCTAssertEqual(analytics.pricingMetadata.sourceLabel, "bundled")
    }

    // MARK: — Live machine smoke check

    func testLiveCatalogResolvesVersionedModelFromThisMachine() throws {
        let fileManager = FileManager.default
        let url = ModelPricingCatalog.defaultOpenCodeCacheURL(fileManager: fileManager)
        try XCTSkipUnless(
            fileManager.fileExists(atPath: url.path),
            "no OpenCode models.json on this machine"
        )

        let catalog = ModelPricingCatalog.load(fileManager: fileManager)
        let resolution = catalog.resolve(provider: "ollama-cloud", model: "deepseek-v4.1-flash:1017")

        XCTAssertEqual(resolution.canonicalKey, "deepseek-v4.1-flash")
        XCTAssertNotNil(resolution.price, "an installed catalog must price deepseek-v4.1-flash:1017")
    }

    // MARK: — Helpers

    private func makePayload(rows: [DashboardPayload.RawRow]) -> DashboardPayload {
        var payload = DashboardPayload.empty()
        payload.rawData = rows
        return payload
    }

    private func makeRow(
        model: String,
        provider: String,
        input: Double,
        output: Double = 0,
        cacheRead: Double = 0,
        date: String = "2026-10-01"
    ) -> DashboardPayload.RawRow {
        DashboardPayload.RawRow(
            date: date,
            model: model,
            provider: provider,
            input: input,
            output: output,
            reasoning: 0,
            cacheRead: cacheRead,
            cacheWrite: 0,
            cacheWriteMissingCount: 0,
            cacheWriteReportedCount: 0,
            total: input + output + cacheRead,
            cost: 0,
            msgCount: 1
        )
    }
}

private extension ModelPrice {
    var out: Double { output }
}
