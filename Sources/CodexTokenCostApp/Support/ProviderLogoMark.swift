import AppKit
import SwiftUI
import CodexTokenCostCore

enum ProviderLogoAsset: String {
    case opencodeGo = "opencode_go"
    case opencodeZen = "opencode_zen"
    case codex
    case deepseek
    case ollama

    var fallbackSymbolName: String {
        switch self {
        case .opencodeGo: return "arrow.triangle.branch"
        case .opencodeZen: return "leaf.fill"
        case .codex: return "curlybraces"
        case .deepseek: return "waveform"
        case .ollama: return "cube.fill"
        }
    }

    static func asset(for provider: BalanceProviderKind) -> ProviderLogoAsset {
        switch provider {
        case .opencodeGo: return .opencodeGo
        case .opencodeZen: return .opencodeZen
        case .codex: return .codex
        case .deepseek: return .deepseek
        case .ollama: return .ollama
        }
    }
}

@MainActor
private enum ProviderLogoImageStore {
    private static let cache = NSCache<NSString, NSImage>()

    @MainActor
    static func image(for provider: BalanceProviderKind) -> NSImage? {
        let asset = provider.logoAsset
        let cacheKey = asset.rawValue as NSString

        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        for url in candidateURLs(for: asset) {
            if let image = NSImage(contentsOf: url) {
                // SVGs use fill="currentColor"; template mode lets SwiftUI tint apply
                image.isTemplate = true
                cache.setObject(image, forKey: cacheKey)
                return image
            }
        }

        return nil
    }

    private static func candidateURLs(for asset: ProviderLogoAsset) -> [URL] {
        let fileName = asset.rawValue
        var urls: [URL] = []

        // Prefer Bundle.main for the packaged ProviderLogos directory.
        // Bundle.module is deliberately excluded: it requires the SPM resource
        // bundle (CodexTokenCost_CodexTokenCostApp.bundle) to be present at
        // runtime, which is not guaranteed in a hand-staged .app bundle.
        // The shell script copies Resources/ProviderLogos/ into
        // Contents/Resources/ProviderLogos/, so Bundle.main resolves them.
        if let url = Bundle.main.url(forResource: fileName, withExtension: "svg", subdirectory: "ProviderLogos") {
            urls.append(url)
        }
        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent("ProviderLogos/\(fileName).svg"))
        }

        return urls
    }
}

private extension BalanceProviderKind {
    var logoAsset: ProviderLogoAsset {
        switch self {
        case .opencodeGo: return .opencodeGo
        case .opencodeZen: return .opencodeZen
        case .codex: return .codex
        case .deepseek: return .deepseek
        case .ollama: return .ollama
        }
    }
}

struct ProviderLogoMark: View {
    let provider: BalanceProviderKind
    var size: CGFloat = 22
    var tint: Color = .primary

    var body: some View {
        Group {
            if let image = ProviderLogoImageStore.image(for: provider) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.template)
                    .foregroundStyle(tint)
            } else {
                Image(systemName: provider.logoAsset.fallbackSymbolName)
                    .resizable()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityLabel(Text(provider.displayName))
    }
}
