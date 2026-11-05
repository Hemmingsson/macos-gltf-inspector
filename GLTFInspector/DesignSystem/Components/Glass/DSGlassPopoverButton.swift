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
struct DSGlassPopoverButton<PopoverContent: View>: View {
    private let title: String
    private let systemImage: String?
    private let help: String?
    private let value: String?
    private let popoverContent: () -> PopoverContent

    @State private var isPresented = false

    /// - Parameters:
    ///   - title: What the popover adjusts ("Lighting"): accessibility label and, unless `help` is
    ///     given, the tooltip.
    ///   - systemImage: SF Symbol. Nil draws `value` (or the title) and the chevron, as the
    ///     field-of-view chip does.
    ///   - value: Optional current reading announced as the accessibility value ("35°").
    ///   - help: Tooltip override.
    ///   - content: The popover body, built lazily when it opens.
    init(
        _ title: String,
        systemImage: String? = nil,
        value: String? = nil,
        help: String? = nil,
        @ViewBuilder content: @escaping () -> PopoverContent
    ) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.help = help
        self.popoverContent = content
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label
        }
        .buttonStyle(.plain)
        .dsGlassControlSurface(isEngaged: isPresented)
        .help(help ?? title)
        .accessibilityLabel(title)
        .accessibilityValue(value ?? "")
        .accessibilityAddTraits(isPresented ? .isSelected : [])
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            popoverContent()
        }
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: systemImage)
                    .dsGlassPrimaryGlyph(isHighlighted: isPresented)
                DSGlassChevron()
            }
            .dsGlassControlLabel(.wide, isHighlighted: isPresented)
        } else {
            HStack(spacing: DS.Spacing.s) {
                Text(value ?? title)
                    .font(.body)
                    .foregroundStyle(HierarchicalShapeStyle.primary)
                    .lineLimit(1)
                    .contentTransition(.identity)
                    .transaction { $0.animation = nil }
                DSGlassChevron()
            }
            .dsGlassControlLabel(.titled, isHighlighted: isPresented)
        }
    }
}
