import XCTest
@testable import CodexTokenCostCore

final class OllamaCacheSplitTests: XCTestCase {
    private func row(_ provider: String = "deepseek", model: String = "deepseek-v4-flash", input: Double = 200, cache: Double = 800, output: Double = 0, reasoning: Double = 0, write: Double = 0, total: Double? = nil, date: String = "2026-09-01") -> DashboardPayload.RawRow {
        .init(date: date, model: model, provider: provider, input: input, output: output, reasoning: reasoning,
              cacheRead: cache, cacheWrite: write, cacheWriteMissingCount: 0, cacheWriteReportedCount: 1,
              total: total ?? input + output + reasoning + cache + write, cost: 0, msgCount: 1)
    }

    private var references: [DashboardPayload.RawRow] {
        [row(date: "2026-09-01"), row(date: "2026-09-02"), row(date: "2026-09-03")]
    }

    private func analytics(_ rows: [DashboardPayload.RawRow]) -> TokenCostDashboardAnalytics {
        var payload = DashboardPayload.empty()
        payload.rawData = rows
        return .init(payload: payload)
    }

    func testRuntimeReferenceAndExclusion() throws {
        let rows = references + [
            row(" OLLAMA-CLOUD ", input: 1_000_000, cache: 9_000_000),
            row(input: 99, cache: 100), row(input: -1, cache: 100),
            row(input: .infinity), row(cache: .nan), row(cache: -1),
            row(input: 100, cache: 99_900), row(cache: 0)
        ]
        let context = OllamaCloudCacheEstimation.Context(rows: rows)
        let reference = try XCTUnwrap(context.reference(for: "deepseek-chat"))
        XCTAssertEqual(reference.rate, 0.8, accuracy: 1e-12)
        XCTAssertEqual(reference.source, .runtime)
        XCTAssertEqual(reference.sampleCount, 3)
        XCTAssertEqual(reference.grossTokens, 3_000)
        XCTAssertEqual(context.reference(for: "deepseek-reasoner")?.source, .snapshot)
        XCTAssertNil(context.reference(for: "unknown"))
    }

    func testFallbackThresholdsAndOverflow() throws {
        for rows in [[], Array(references.prefix(2)), [row(input: 100, cache: 100), row(input: 100, cache: 100), row(input: 100, cache: 100)],
                     [row(input: 5e307, cache: 5e307), row(input: 5e307, cache: 5e307), row(input: 5e307, cache: 5e307)]] {
            let reference = try XCTUnwrap(OllamaCloudCacheEstimation.Context(rows: rows).reference(for: "deepseek-v4-flash"))
            XCTAssertEqual(reference.source, .snapshot)
            XCTAssertEqual(reference.rate, 553_686_784.0 / 600_792_157.0, accuracy: 1e-12)
            XCTAssertTrue(reference.grossTokens.isFinite)
        }
    }

    func testSplitPreservesRawFieldsAndDrivesNetApiCost() throws {
        let target = row("ollama-cloud", input: 1_000, cache: 0, output: 100, reasoning: 50, write: 20)
        let result = analytics(references + [target])
        let provider = try XCTUnwrap(result.providerCacheRows.first { $0.key == "ollama-cloud" })
        XCTAssertEqual(provider.inputTokens, 1_000)
        XCTAssertEqual(provider.actualTokens, 1_150)
        XCTAssertEqual(provider.estimatedCacheReadTokens, 800, accuracy: 1e-10)
        XCTAssertEqual(provider.displayInputTokens, 200, accuracy: 1e-10)
        XCTAssertEqual(provider.displayActualTokens, 350, accuracy: 1e-10)
        XCTAssertEqual(provider.displayedUsageTokens, 1_170, accuracy: 1e-10)
        XCTAssertEqual(provider.displayActualTokens + provider.cacheReadTokens + provider.cacheWriteTokens, 1_170, accuracy: 1e-10)
        XCTAssertEqual(provider.cacheRate, 0.8, accuracy: 1e-12)
        XCTAssertEqual(result.cache.cacheHitRate, 0.8, accuracy: 1e-12)
        let fallback = analytics([target])
        let rank = try XCTUnwrap(result.providerRankRows.first { $0.providerKey == "ollama-cloud" })
        let originalRank = try XCTUnwrap(fallback.providerRankRows.first { $0.providerKey == "ollama-cloud" })
        XCTAssertEqual(rank.actualTokens, originalRank.actualTokens)
        XCTAssertEqual(rank.rawCost, originalRank.rawCost)
        XCTAssertEqual(rank.netActualTokens, 350, accuracy: 1e-10)
        XCTAssertEqual(
            rank.effectiveCost ?? -1,
            (200 * 0.14 + 800 * 0.0028 + 150 * 0.28) / 1_000_000,
            accuracy: 1e-12
        )
        XCTAssertNotEqual(rank.effectiveCost, originalRank.effectiveCost,
                          "runtime and snapshot cache rates must produce their own net API costs")
        XCTAssertNotEqual(rank.tokensPerDollar, originalRank.tokensPerDollar)
        XCTAssertEqual(result.cache.cacheSavedCost, analytics(references).cache.cacheSavedCost)
        XCTAssertEqual(target.input, 1_000)
        XCTAssertEqual(target.cacheRead, 0)
    }

    func testRealBucketAndOtherModelsRemainUnsplit() throws {
        let rows = [row("ollama-cloud", input: 1_000, cache: 300), row("ollama-cloud", model: "unknown", input: 100, cache: 0)]
        let result = analytics(rows)
        XCTAssertFalse(result.cache.hasEstimates)
        let provider = try XCTUnwrap(result.providerCacheRows.first)
        XCTAssertEqual(provider.displayInputTokens, 1_100)
        XCTAssertEqual(provider.cacheReadTokens, 300)
    }

    func testReportedTotalMismatchIsNotSilentlyRewritten() throws {
        let result = analytics([row("ollama-cloud", input: 1_000, cache: 0, total: 777)])
        XCTAssertEqual(result.overview.totalTokens, 777)
        XCTAssertEqual(result.providerCacheRows.first?.displayedUsageTokens, 1_000)
    }

    func testRelayKeepsRealTrendAndConservesHeatmap() throws {
        let result = analytics([row("ollama-cloud", input: 1_000, cache: 0, output: 100, write: 20)])
        let sections = try RelaySectionBuilder.build(requestedSections: ["trend", "heatmap"], params: nil, analytics: result)
        func decode<T: Decodable>(_ key: String, _ type: T.Type) throws -> T {
            let section = try XCTUnwrap(sections[key])
            let data = try XCTUnwrap(Data(base64Encoded: section.data))
            return try JSONDecoder().decode(type, from: RelayCompression.zlibDecompress(data))
        }
        let trend = try decode("trend", RelayTrendSection.self)
        let heatmap = try decode("heatmap", RelayHeatmapSection.self)
        XCTAssertEqual(trend.points.first?.actualTokens, 1_100)
        XCTAssertEqual(try XCTUnwrap(heatmap.days.first?.tokens), 1_120, accuracy: 1e-9)
    }

    func testContextChangesClassificationWithoutChangingRawInput() {
        let target = row("ollama-cloud", input: 1_000, cache: 0)
        let lowRateRows = [row(input: 900, cache: 100), row(input: 900, cache: 100), row(input: 900, cache: 100)]
        XCTAssertEqual(TaskClassificationEngine.classify(target).rule, .cacheHeavy)
        XCTAssertEqual(TaskClassificationEngine.classify(target, context: .init(rows: lowRateRows)).rule, .unclassified)
    }

    func testGateBlocksEstimateWhenOllamaReportedCacheSameModelAndDate() {
        let reported = row("ollama-cloud", input: 5_000, cache: 5_000, date: "2026-09-10")
        let unreported = row("ollama-cloud", input: 100_000, cache: 0, date: "2026-09-10")
        let context = OllamaCloudCacheEstimation.Context(rows: references + [reported, unreported])
        XCTAssertFalse(context.allowsEstimate(model: "deepseek-v4-flash", date: "2026-09-10"))
        XCTAssertTrue(context.allowsEstimate(model: "deepseek-v4-flash", date: "2026-09-02"))

        let gated = analytics(references + [reported, unreported])
        XCTAssertEqual(gated.providerCacheRows.first { $0.key == "ollama-cloud" }?.estimatedCacheReadTokens, 0)
        XCTAssertFalse(gated.overview.hasEstimatedCacheRead)

        let ungated = analytics(references + [reported, row("ollama-cloud", input: 100_000, cache: 0, date: "2026-09-02")])
        XCTAssertGreaterThan(ungated.providerCacheRows.first { $0.key == "ollama-cloud" }?.estimatedCacheReadTokens ?? 0, 0)
    }

    func testGateIsProviderScopedSoOtherProvidersCannotSuppressOllamaEstimate() {
        let otherProvider = row("deepseek", input: 5_000, cache: 5_000, date: "2026-09-10")
        let target = row("ollama-cloud", input: 100_000, cache: 0, date: "2026-09-10")
        let result = analytics(references + [otherProvider, target])
        let provider = result.providerCacheRows.first { $0.key == "ollama-cloud" }
        XCTAssertEqual(provider?.inputTokens ?? 0, 100_000, accuracy: 1e-6)
        // Same (model, date) but a different provider must not populate the gate,
        // so the deduction is still the live reference rate applied to input.
        let rate = result.cacheEstimationContext.reference(for: "deepseek-v4-flash")?.rate ?? 0
        XCTAssertGreaterThan(rate, 0)
        XCTAssertEqual(provider?.estimatedCacheReadTokens ?? 0, 100_000 * rate, accuracy: 1e-6)
    }

    func testOverviewNetExcludesEstimateWhileGrossStaysReported() {
        let target = row("ollama-cloud", input: 1_000, cache: 0, output: 100, reasoning: 50)
        let result = analytics(references + [target])
        XCTAssertEqual(result.overview.totalEstimatedCacheReadTokens, 800, accuracy: 1e-10)
        // Gross keeps the reported actual for all four rows (three references
        // contribute 200 each) and net subtracts only the target's deduction.
        XCTAssertEqual(result.overview.totalActualTokens, 1_750, accuracy: 1e-10)
        XCTAssertEqual(result.overview.netActualTokens, 950, accuracy: 1e-10)
        XCTAssertEqual(
            result.overview.totalActualTokens - result.overview.netActualTokens,
            result.overview.totalEstimatedCacheReadTokens,
            accuracy: 1e-10
        )
    }

    func testGlmFamilyAndUnknownModelsAreNeverEstimated() {
        let rows = references + [
            row("ollama-cloud", model: "glm-5.3-flash", input: 100_000),
            row("ollama-cloud", model: "glm-5.2", input: 100_000),
            row("ollama-cloud", model: "glm-5.3-flash:cloud", input: 100_000),
            row("ollama-cloud", model: "kimi-k3", input: 100_000)
        ]
        let result = analytics(rows)
        XCTAssertFalse(result.overview.hasEstimatedCacheRead)
        XCTAssertEqual(result.providerCacheRows.first { $0.key == "ollama-cloud" }?.estimatedCacheReadTokens, 0)
    }

    func testSplitIsConservedAndAppliedExactlyOnce() {
        let target = row("ollama-cloud", input: 1_000, cache: 0, output: 100, reasoning: 50, write: 20)
        let context = OllamaCloudCacheEstimation.Context(rows: references)
        let split = OllamaCloudCacheEstimation.split(
            provider: "ollama-cloud", model: "deepseek-v4-flash",
            input: target.input, output: target.output, reasoning: target.reasoning,
            cacheRead: target.cacheRead, cacheWrite: target.cacheWrite,
            date: target.date, context: context
        )
        let grossFields = target.input + target.output + target.reasoning + target.cacheRead + target.cacheWrite
        XCTAssertEqual(split.displayActual + target.cacheRead + split.estimatedCacheRead + target.cacheWrite, grossFields, accuracy: 1e-10)
        XCTAssertEqual(split.displayInput, 200, accuracy: 1e-10)

        let result = analytics(references + [target])
        let provider = try? XCTUnwrap(result.providerCacheRows.first { $0.key == "ollama-cloud" })
        XCTAssertEqual(provider?.displayActualTokens, split.displayActual)
    }

    func testEffectiveCacheReadHonorsGateOnlyWhenDateGiven() {
        let reported = row("ollama-cloud", input: 5_000, cache: 5_000, date: "2026-09-10")
        let context = OllamaCloudCacheEstimation.Context(rows: references + [reported])
        XCTAssertEqual(
            OllamaCloudCacheEstimation.effectiveCacheRead(
                provider: "ollama-cloud", model: "deepseek-v4-flash",
                cacheRead: 0, input: 1_000, context: context, date: "2026-09-10"
            ),
            0
        )
        XCTAssertEqual(
            OllamaCloudCacheEstimation.effectiveCacheRead(
                provider: "ollama-cloud", model: "deepseek-v4-flash",
                cacheRead: 0, input: 1_000, context: context, date: "2026-09-02"
            ),
            800,
            accuracy: 1e-10
        )
    }
}
