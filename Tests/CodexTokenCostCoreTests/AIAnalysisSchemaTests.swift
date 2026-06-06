import XCTest
@testable import CodexTokenCostCore

final class AIAnalysisSchemaTests: XCTestCase {
    func testAIFindingRoundtrip() throws {
        let finding = AIFinding(
            category: .tokenEfficiency,
            severity: .warning,
            title: "Test Finding",
            detail: "Detail text",
            suggestion: "Suggestion text",
            confidence: 0.85,
            metadata: ["key": "value"]
        )
        let data = try JSONEncoder().encode(finding)
        let decoded = try JSONDecoder().decode(AIFinding.self, from: data)
        XCTAssertEqual(decoded.id, finding.id)
        XCTAssertEqual(decoded.category, .tokenEfficiency)
        XCTAssertEqual(decoded.severity, .warning)
        XCTAssertEqual(decoded.confidence, 0.85)
    }

    func testAIEndpointURLIsNil() {
        XCTAssertNil(AIAnalysisEndpoint.url)
    }

    func testAIEndpointAllowedDomainsIsEmpty() {
        XCTAssertTrue(AIAnalysisEndpoint.allowedDomains.isEmpty)
    }

    func testAIEndpointRequiresExplicitOptIn() {
        XCTAssertEqual(AIAnalysisEndpoint.requiredConsentLevel, .explicitOptIn)
    }

    func testAIFindingRequestRoundtrip() throws {
        let request = AIFindingRequest(
            findings: [],
            anonymizedContext: ["test": "value"],
            consentToken: "test-token"
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(AIFindingRequest.self, from: data)
        XCTAssertEqual(decoded.consentToken, "test-token")
    }

    func testAIFindingCategoriesAreDefined() {
        let categories: [AIFinding.Category] = [
            .tokenEfficiency, .costOptimization, .usagePattern, .providerComparison
        ]
        XCTAssertEqual(categories.count, 4)
    }

    func testAIFindingSeverityLevels() {
        let severities: [AIFinding.Severity] = [.info, .warning, .critical]
        XCTAssertEqual(severities.count, 3)
    }
}
