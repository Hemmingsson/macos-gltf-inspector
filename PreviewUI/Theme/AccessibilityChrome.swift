import AppKit
import SwiftUI

// MARK: - Reduced motion

extension Animation {
    /// `easeInOut` for chrome transitions, or `nil` when Reduce Motion is on.
    static func previewChrome(_ reduceMotion: Bool, duration: TimeInterval = 0.15) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: duration)
    }
}

// MARK: - Increase Contrast

extension Theme {
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
struct ThemeContrastEnvironment: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
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

extension EnvironmentValues {
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

extension View {
    func themeContrastEnvironment() -> some View {
        modifier(ThemeContrastEnvironment())
    }
}

// MARK: - Focus rings

enum PreviewFocusRingShape {
    case roundedRect(CGFloat)
    case circle
}

/// Accent focus stroke drawn when the enclosing control is focused.
///
/// Prefers `@Environment(\.isFocused)` (works inside `ButtonStyle` labels). Pass
/// `isFocusedOverride` when the ring sits in an overlay driven by `@FocusState`.
struct PreviewFocusStroke: View {
    var shape: PreviewFocusRingShape
    var isFocusedOverride: Bool? = nil
    @Environment(\.isFocused) private var environmentFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFocused: Bool { isFocusedOverride ?? environmentFocused }

    var body: some View {
        stroke
            .opacity(isFocused ? 1 : 0)
            .animation(Animation.previewChrome(reduceMotion, duration: 0.12), value: isFocused)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var stroke: some View {
        switch shape {
        case .roundedRect(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 2)
        case .circle:
            Circle()
                .strokeBorder(Theme.accent, lineWidth: 2)
        }
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
