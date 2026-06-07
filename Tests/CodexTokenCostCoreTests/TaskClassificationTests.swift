import XCTest
@testable import CodexTokenCostCore

final class TaskClassificationTests: XCTestCase {
    private func makeRow(
        input: Double = 100, output: Double = 50, reasoning: Double = 0,
        cacheRead: Double = 0, cacheWrite: Double = 0,
        total: Double = 150, cost: Double = 0.1, msgCount: Int = 5,
        model: String = "test", date: String = "2026-01-01"
    ) -> DashboardPayload.RawRow {
        DashboardPayload.RawRow(
            date: date, model: model, provider: "test",
            input: input, output: output, reasoning: reasoning,
            cacheRead: cacheRead, cacheWrite: cacheWrite,
            cacheWriteMissingCount: 0, cacheWriteReportedCount: 0,
            total: total, cost: cost, msgCount: msgCount
        )
    }

    func testReasoningRule() {
        let row = makeRow(input: 100, output: 10, reasoning: 30, total: 140)
        let result = TaskClassificationEngine.classify(row)
        XCTAssertEqual(result.rule, .reasoning)
        XCTAssertEqual(result.confidence, 0.8)
    }

    func testCacheHeavyRule() {
        let row = makeRow(input: 50, output: 10, cacheRead: 30, cacheWrite: 20, total: 110)
        let result = TaskClassificationEngine.classify(row)
        XCTAssertEqual(result.rule, .cacheHeavy)
    }

    func testLongOutputRule() {
        let row = makeRow(input: 10, output: 25, total: 35)
        let result = TaskClassificationEngine.classify(row)
        XCTAssertEqual(result.rule, .longOutput)
    }

    func testHighFrequencyRule() {
        let row = makeRow(msgCount: 25)
        let result = TaskClassificationEngine.classify(row)
        XCTAssertEqual(result.rule, .highFrequency)
    }

    func testHighCostRule() {
        let row = makeRow(cost: 6.0)
        let result = TaskClassificationEngine.classify(row)
        XCTAssertEqual(result.rule, .highCost)
    }

    func testUnclassifiedRule() {
        let row = makeRow(input: 100, output: 10, reasoning: 0, total: 110, cost: 0.1, msgCount: 5)
        let result = TaskClassificationEngine.classify(row)
        XCTAssertEqual(result.rule, .unclassified)
        XCTAssertEqual(result.confidence, 0.0)
    }

    func testRulePriorityReasoningOverCache() {
        // Both reasoning > 20% and cache > 30% — reasoning should win (higher priority)
        let row = makeRow(input: 100, output: 10, reasoning: 30, cacheRead: 40, cacheWrite: 20, total: 200)
        let result = TaskClassificationEngine.classify(row)
        XCTAssertEqual(result.rule, .reasoning)
    }

    func testClassifyMultipleRows() {
        let rows = [
            makeRow(input: 100, output: 10, reasoning: 30, total: 140, model: "model-a"), // reasoning
            makeRow(msgCount: 30, model: "model-b"), // highFrequency
        ]
        let results = TaskClassificationEngine.classify(rows: rows)
        XCTAssertEqual(results.count, 2)
    }
}
