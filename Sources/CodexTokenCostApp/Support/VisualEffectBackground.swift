import AppKit
import SwiftUI

/// SwiftUI wrapper around `NSVisualEffectView` for pre-macOS 26 floating panels.
///
/// Uses `.behindWindow` blending so the view composites the desktop content
/// behind the transparent borderless `NSPanel`. `state = .active` keeps the
/// material crisp even when the app loses focus. The backing layer's
/// `cornerRadius` and `masksToBounds` are set so the blur respects the
/// panel's rounded corners (SwiftUI-level `.clipShape` does not clip
/// AppKit-level rendering).
struct VisualEffectBackground: NSViewRepresentable {
    let cornerRadius: CGFloat
    let material: NSVisualEffectView.Material

    init(
        cornerRadius: CGFloat = BalanceFloatingPanelLayout.shellCornerRadius,
        material: NSVisualEffectView.Material = .hudWindow
    ) {
        self.cornerRadius = cornerRadius
        self.material = material
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        view.isEmphasized = false
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        view.layer?.cornerCurve = .continuous
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.layer?.cornerRadius = cornerRadius
        nsView.layer?.masksToBounds = true
    }
}