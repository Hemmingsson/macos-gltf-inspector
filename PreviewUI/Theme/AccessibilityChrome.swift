import AppKit
import SwiftUI

// MARK: - Reduced motion

public extension Animation {
    /// `easeInOut` for chrome transitions, or `nil` when Reduce Motion is on.
    static func previewChrome(_ reduceMotion: Bool, duration: TimeInterval = 0.15) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: duration)
    }
}

// MARK: - Increase Contrast

public extension Theme {
    /// Panel / column hairline — stronger under Increase Contrast.
    static func border(contrast: ColorSchemeContrast) -> Color {
        contrast == .increased
            ? Color.dynamic(light: NSColor.srgbBlack(0.22), dark: NSColor.srgbWhite(0.28))
            : border
    }

    /// Quiet interior rule — stronger under Increase Contrast.
    static func hair(contrast: ColorSchemeContrast) -> Color {
        contrast == .increased
            ? Color.dynamic(light: NSColor.srgbBlack(0.14), dark: NSColor.srgbWhite(0.18))
            : hair
    }
}

/// Reads Increase Contrast and substitutes Theme border/hair for the subtree.
public struct ThemeContrastEnvironment: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    public func body(content: Content) -> some View {
        content
            .environment(\.previewBorder, Theme.border(contrast: contrast))
            .environment(\.previewHair, Theme.hair(contrast: contrast))
    }
}

private struct PreviewBorderKey: EnvironmentKey {
    static let defaultValue = Theme.border
}

private struct PreviewHairKey: EnvironmentKey {
    static let defaultValue = Theme.hair
}

public extension EnvironmentValues {
    /// Contrast-aware stand-in for `Theme.border`.
    var previewBorder: Color {
        get { self[PreviewBorderKey.self] }
        set { self[PreviewBorderKey.self] = newValue }
    }

    /// Contrast-aware stand-in for `Theme.hair`.
    var previewHair: Color {
        get { self[PreviewHairKey.self] }
        set { self[PreviewHairKey.self] = newValue }
    }
}

public extension View {
    func themeContrastEnvironment() -> some View {
        modifier(ThemeContrastEnvironment())
    }
}

private extension NSColor {
    static func srgbBlack(_ alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha)
    }

    static func srgbWhite(_ alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha)
    }
}
