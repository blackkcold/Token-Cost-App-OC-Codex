import XCTest
@testable import CodexTokenCostCore

final class ModelCategorizationTests: XCTestCase {

    private func normalized(_ model: String) -> String {
        OllamaCloudCacheEstimation.normalizedModelName(model)
    }

    func testExactDeepSeekV4FlashVariantCategorizesToBaseModel() {
        XCTAssertEqual(normalized("deepseek-v4-flash-0731-cloud"), "deepseek-v4-flash")
    }

    func testDeepSeekV4FlashProviderQualifiedVariantCategorizes() {
        XCTAssertEqual(normalized("ollama-cloud/deepseek-v4-flash-0731"), "deepseek-v4-flash")
    }

    func testDeepSeekV4ProVariantCategorizes() {
        XCTAssertEqual(normalized("deepseek-v4-pro-20260731"), "deepseek-v4-pro")
    }

    func testExactAliasStillResolves() {
        XCTAssertEqual(normalized("deepseek-chat"), "deepseek-v4-flash")
        XCTAssertEqual(normalized("deepseek-reasoner"), "deepseek-v4-pro")
    }

    func testExactKnownModelIsUnchanged() {
        XCTAssertEqual(normalized("deepseek-v4-flash"), "deepseek-v4-flash")
        XCTAssertEqual(normalized("gpt-5.4-mini"), "gpt-5.4-mini")
    }

    func testLongestPrefixWins() {
        // "gpt-5.4" and "gpt-5.4-mini" both exist; a gpt-5.4-mini variant must map to gpt-5.4-mini.
        XCTAssertEqual(normalized("gpt-5.4-mini-2026"), "gpt-5.4-mini")
    }

    func testUnknownModelWithoutKnownPrefixIsUnchanged() {
        XCTAssertEqual(normalized("some-brand-new-model"), "some-brand-new-model")
    }

    func testUnknownModelMatchingNoneDoesNotCategorize() {
        XCTAssertEqual(normalized("deepseek-v3"), "deepseek-v3")
    }

    func testEmptyModelReturnsEmpty() {
        XCTAssertEqual(normalized(""), "")
    }

    func testVariantPricingUsesBaseModel() {
        // apiCost is not directly exposed; verify via effectiveCacheRead which keys on normalized name.
        let effective = OllamaCloudCacheEstimation.effectiveCacheRead(
            provider: "ollama-cloud",
            model: "deepseek-v4-flash-0731-cloud",
            cacheRead: 0,
            input: 1000
        )
        XCTAssertGreaterThan(effective, 0)
    }
}
