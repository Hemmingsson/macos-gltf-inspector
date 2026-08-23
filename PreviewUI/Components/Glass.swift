import SwiftUI

public extension View {
    /// `.buttonStyle` is not a `@ViewBuilder`-friendly value across `.glass` and
    /// `.glassProminent` (different types), so branch on the view instead.
    ///
    /// Cribbed from Shared QL chrome glass styling rather than imported: `PreviewUI` must not
    /// depend on `Shared/`.
    func previewGlassButtonStyle(prominent: Bool) -> some View {
        modifier(PreviewGlassButtonStyleModifier(prominent: prominent))
    }

    /// A toggle inside a canvas pill (`.tbtn` / `.tbtn.on`).
    ///
    /// Off is always `.plain`: these sit **inside** a pill that is already glass, and glass cannot
    /// sample glass. On uses an inset `Theme.selection` wash — not `.glassProminent` — so geometry
    /// stays fixed (Sketch-style).
    func pillButtonStyle(active: Bool) -> some View {
        modifier(PillButtonStyleModifier(active: active))
    }
}

private struct PreviewGlassButtonStyleModifier: ViewModifier {
    var prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.glass)
        }
    }
}

private struct PillButtonStyleModifier: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        content.buttonStyle(PillIconButtonStyle(active: active))
    }
}

// MARK: - Previews

#Preview("glass resting") {
    Button("Play") {}
        .previewGlassButtonStyle(prominent: false)
        .padding(24)
}

#Preview("prominent") {
    Button("Play") {}
        .previewGlassButtonStyle(prominent: true)
        .padding(24)
}
