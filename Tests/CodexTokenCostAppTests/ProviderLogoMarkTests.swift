import XCTest
import SwiftUI
@testable import CodexTokenCostApp
@testable import CodexTokenCostCore

final class ProviderLogoMarkTests: XCTestCase {
    // MARK: - Asset name mapping

    func testAssetNameForOpenCodeGo() {
        XCTAssertEqual(ProviderLogoAsset.asset(for: .opencodeGo).rawValue, "opencode_go")
    }

    func testAssetNameForOpenCodeZen() {
        XCTAssertEqual(ProviderLogoAsset.asset(for: .opencodeZen).rawValue, "opencode_zen")
    }

    func testAssetNameForCodex() {
        XCTAssertEqual(ProviderLogoAsset.asset(for: .codex).rawValue, "codex")
    }

    func testAssetNameForDeepSeek() {
        XCTAssertEqual(ProviderLogoAsset.asset(for: .deepseek).rawValue, "deepseek")
    }

    func testAssetNameForOllama() {
        XCTAssertEqual(ProviderLogoAsset.asset(for: .ollama).rawValue, "ollama")
    }

    // MARK: - Fallback symbol mapping

    func testFallbackSymbolForOpenCodeGo() {
        XCTAssertEqual(ProviderLogoAsset.asset(for: .opencodeGo).fallbackSymbolName, "arrow.triangle.branch")
    }

    func testFallbackSymbolForOpenCodeZen() {
        XCTAssertEqual(ProviderLogoAsset.asset(for: .opencodeZen).fallbackSymbolName, "leaf.fill")
    }

    func testFallbackSymbolForCodex() {
        XCTAssertEqual(ProviderLogoAsset.asset(for: .codex).fallbackSymbolName, "curlybraces")
    }

    func testFallbackSymbolForDeepSeek() {
        XCTAssertEqual(ProviderLogoAsset.asset(for: .deepseek).fallbackSymbolName, "waveform")
    }

    func testFallbackSymbolForOllama() {
        XCTAssertEqual(ProviderLogoAsset.asset(for: .ollama).fallbackSymbolName, "cube.fill")
    }

    // MARK: - View property propagation

    func testProviderLogoMarkDefaultSize() {
        let view = ProviderLogoMark(provider: .opencodeGo)
        XCTAssertEqual(view.size, 22)
    }

    func testProviderLogoMarkDefaultTint() {
        let view = ProviderLogoMark(provider: .codex)
        XCTAssertEqual(view.tint, .primary)
    }

    func testProviderLogoMarkCustomSize() {
        let view = ProviderLogoMark(provider: .deepseek, size: 44)
        XCTAssertEqual(view.size, 44)
    }

    func testProviderLogoMarkCustomTint() {
        let view = ProviderLogoMark(provider: .ollama, size: 16, tint: .red)
        XCTAssertEqual(view.tint, .red)
    }

    // MARK: - Completeness

    func testAllProviderKindsHaveAssetMapping() {
        for provider in BalanceProviderKind.allCases {
            let asset = ProviderLogoAsset.asset(for: provider)
            XCTAssertFalse(asset.rawValue.isEmpty)
            XCTAssertFalse(asset.fallbackSymbolName.isEmpty)
        }
    }
}
