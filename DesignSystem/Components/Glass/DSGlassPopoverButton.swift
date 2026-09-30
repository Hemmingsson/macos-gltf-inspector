import SwiftUI

/// A glass control that owns a popover: icon + small `.secondary` chevron (Lighting ▾,
/// Field of View ▾).
///
/// Presents `.popover(isPresented:arrowEdge: .bottom)` with the content as given — **plain**, no
/// background, padding or width of its own; the system draws the popover's glass (use
/// `DSPopoverPanel` for the padded body). While open the control shows its highlighted state
/// (subtle accent-tinted glass standalone, `.tint` glyph in an island), so the anchor of the open
/// popover is visible.
///
/// - Standalone: a `DS.Metrics.glassControlWide` capsule with one `DS.Glass.control` layer.
/// - In an island (`DSGlassPlacement.inIsland`): same size, no glass.
///
/// Owns its presentation state by default; pass `isPresented:` to drive it from outside (e.g. a
/// menu command that opens the popover).
public struct DSGlassPopoverButton<PopoverContent: View>: View {
    private let title: String
    private let systemImage: String
    private let help: String?
    private let value: String?
    private let externalIsPresented: Binding<Bool>?
    private let popoverContent: () -> PopoverContent

    @State private var ownIsPresented = false

    /// A popover button that owns its presentation state.
    ///
    /// - Parameters:
    ///   - title: What the popover adjusts ("Lighting"): accessibility label and, unless `help` is
    ///     given, the tooltip.
    ///   - systemImage: SF Symbol name.
    ///   - value: Optional current reading announced as the accessibility value ("35°").
    ///   - help: Tooltip override.
    ///   - content: The popover body, built lazily when it opens.
    public init(
        _ title: String,
        systemImage: String,
        value: String? = nil,
        help: String? = nil,
        @ViewBuilder content: @escaping () -> PopoverContent
    ) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.help = help
        self.externalIsPresented = nil
        self.popoverContent = content
    }

    /// A popover button whose presentation is driven by `isPresented`.
    public init(
        _ title: String,
        systemImage: String,
        isPresented: Binding<Bool>,
        value: String? = nil,
        help: String? = nil,
        @ViewBuilder content: @escaping () -> PopoverContent
    ) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.help = help
        self.externalIsPresented = isPresented
        self.popoverContent = content
    }

    private var isPresented: Binding<Bool> {
        externalIsPresented ?? $ownIsPresented
    }

    public var body: some View {
        Button {
            isPresented.wrappedValue.toggle()
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: systemImage)
                DSGlassChevron()
            }
            .dsGlassControlLabel(.wide, isHighlighted: isPresented.wrappedValue)
        }
        .buttonStyle(.plain)
        .dsGlassControlSurface(isEngaged: isPresented.wrappedValue)
        .help(help ?? title)
        .accessibilityLabel(title)
        .accessibilityValue(value ?? "")
        .accessibilityAddTraits(isPresented.wrappedValue ? .isSelected : [])
        .popover(isPresented: isPresented, arrowEdge: .bottom) {
            popoverContent()
        }
    }
}

// MARK: - Previews

private struct DSGlassPopoverButtonPreview: View {
    @State private var open = false

    var body: some View {
        HStack(spacing: DS.Metrics.clusterSpacing) {
            DSGlassPopoverButton("Field of View", systemImage: "camera.aperture", value: "35°") {
                Text("Field of view controls")
                    .padding(DS.Spacing.xl)
            }
            DSGlassPopoverButton("Lighting (driven)", systemImage: "sun.max", isPresented: $open) {
                Text("Lighting controls")
                    .padding(DS.Spacing.xl)
            }
            DSGlassIsland {
                DSGlassMenuButton(
                    "View mode",
                    systemImage: "circle.lefthalf.filled",
                    style: .titled("Shaded")
                ) {
                    Button("Shaded") {}
                }
                DSGlassIslandDivider()
                DSGlassPopoverButton("Lighting", systemImage: "sun.max") {
                    Text("Lighting controls")
                        .padding(DS.Spacing.xl)
                }
            }
        }
    }
}

#Preview("popover button states", traits: .sizeThatFitsLayout) {
    DSGlassPreviewBackdrops {
        DSGlassPopoverButtonPreview()
    }
    .frame(width: 420)
}
