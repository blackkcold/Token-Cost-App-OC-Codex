import XCTest
@testable import CodexTokenCostCore

final class CurrencyServiceTests: XCTestCase {
    func testConvertUSDtoUSD() {
        let result = TokenCostCurrencyService.convert(100, from: .usd, to: .usd)
        XCTAssertEqual(result, 100)
    }

    func testConvertCNYtoCNY() {
        let result = TokenCostCurrencyService.convert(720, from: .cny, to: .cny)
        XCTAssertEqual(result, 720)
    }

    func testConvertUSDtoCNY() {
        let result = TokenCostCurrencyService.convert(100, from: .usd, to: .cny)
        XCTAssertEqual(result, 720, accuracy: 0.01)
    }

    func testConvertCNYtoUSD() {
        let result = TokenCostCurrencyService.convert(720, from: .cny, to: .usd)
        XCTAssertEqual(result, 100, accuracy: 0.01)
    }

    func testCurrencyServiceRoundtrip() {
        let original = 42.5
        let converted = TokenCostCurrencyService.convert(original, from: .usd, to: .cny)
        let roundtrip = TokenCostCurrencyService.convert(converted, from: .cny, to: .usd)
        XCTAssertEqual(roundtrip, original, accuracy: 0.01)
    }

    func testFormatUSD() {
        let result = TokenCostCurrencyService.format(123.45, currency: .usd)
        XCTAssertTrue(result.contains("123.45"))
    }

    func testFormatCNY() {
        let result = TokenCostCurrencyService.format(888.88, currency: .cny)
        XCTAssertTrue(result.contains("888.88"))
    }
}
