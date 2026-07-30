import AppKit
import SwiftUI

struct TokenWindowStyleConfigurator: NSViewRepresentable {
    let usesWorkshopStyle: Bool

    func makeNSView(context: Context) -> TokenWindowStyleProbeView {
        let view = TokenWindowStyleProbeView()
        view.usesWorkshopStyle = usesWorkshopStyle
        return view
    }

    func updateNSView(_ nsView: TokenWindowStyleProbeView, context: Context) {
        nsView.usesWorkshopStyle = usesWorkshopStyle
        nsView.applyWindowStyleIfPossible()
    }
}

final class TokenWindowStyleProbeView: NSView {
    var usesWorkshopStyle = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowStyleIfPossible()
    }

    func applyWindowStyleIfPossible() {
        guard let window else { return }

        if usesWorkshopStyle {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbarStyle = .unifiedCompact
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = .textBackgroundColor
        } else {
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
            window.toolbarStyle = .automatic
            window.titlebarSeparatorStyle = .automatic
            window.backgroundColor = .windowBackgroundColor
        }
    }
}

extension View {
    func tokenWindowStyle(usesWorkshopStyle: Bool) -> some View {
        background {
            TokenWindowStyleConfigurator(usesWorkshopStyle: usesWorkshopStyle)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
