import SwiftUI

/// A radio group of circular colour swatches in one glass island (the backdrop picker).
///
/// Each swatch is a `DS.Metrics.swatch` disc — a colour or the checkerboard — with a hairline
/// `DS.Color.separator` edge so white still reads on white. The selected swatch takes a
/// `DS.Metrics.swatchRingWidth` accent ring outside a clear `DS.Metrics.swatchRingGap`, so the
/// island's glass shows between disc and ring.
///
/// Accessibility: the island is one container labelled with `title` ("Backdrop"); each swatch is
/// a button labelled with its name and marked `.isSelected` when current. Hit targets span the full
/// island height; the system focus ring follows the disc.
struct DSSwatchPicker<ID: Hashable>: View {
    /// What a swatch paints.
    enum Fill {
        /// A solid colour.
        case color(SwiftUI.Color)
        /// The "no backdrop" checkerboard.
        case checkerboard
    }

    /// One choice.
    struct Swatch: Identifiable {
        let id: ID
        /// Name for the tooltip and VoiceOver ("White").
        let title: String
        let fill: Fill
        /// Stable handle for UI tests; the label is user-facing and localizable.
        let accessibilityIdentifier: String?

        init(id: ID, title: String, fill: Fill, accessibilityIdentifier: String? = nil) {
            self.id = id
            self.title = title
            self.fill = fill
            self.accessibilityIdentifier = accessibilityIdentifier
        }
    }

    private let title: String
    @Binding private var selection: ID
    private let swatches: [Swatch]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The swatch under the pointer, for the hover ring.
    @State private var hovered: ID?

    /// - Parameters:
    ///   - title: Group name for accessibility ("Backdrop").
    ///   - selection: The selected swatch's `id`.
    ///   - swatches: The choices, leading to trailing.
    init(_ title: String, selection: Binding<ID>, swatches: [Swatch]) {
        self.title = title
        self._selection = selection
        self.swatches = swatches
    }

    var body: some View {
        DSGlassIsland(spacing: DS.Spacing.s) {
            ForEach(swatches) { swatch in
                swatchButton(swatch)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: selection)
        // One notch when the backdrop actually changes; nothing on a click that re-picks the
        // current swatch.
        .onChange(of: selection) { DSHaptics.detent() }
    }

    private func swatchButton(_ swatch: Swatch) -> some View {
        let isSelected = swatch.id == selection
        return Button {
            selection = swatch.id
        } label: {
            disc(swatch.fill)
                .overlay {
                    // Pointer over an unselected swatch: a hint of the ring it would take.
                    if hovered == swatch.id, !isSelected {
                        Circle()
                            .strokeBorder(.primary.opacity(0.25), lineWidth: DS.Metrics.swatchRingWidth)
                            .frame(width: Self.ringDiameter, height: Self.ringDiameter)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: DS.Metrics.swatchRingWidth)
                            .frame(width: Self.ringDiameter, height: Self.ringDiameter)
                            .allowsHitTesting(false)
                    }
                }
                // The hit target is the ring, not the disc: a click on the gap the selection
                // ring occupies has to pick the swatch it rings.
                .frame(width: Self.ringDiameter, height: DS.Metrics.glassControl)
                // Canvas is decorative; a painted surface gives its button a hit target.
                .background(Color.white.opacity(0.001))
                .contentShape(.interaction, .rect)
                .contentShape(.focusEffect, .circle)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? swatch.id : (hovered == swatch.id ? nil : hovered) }
        .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: hovered)
        .help(swatch.title)
        .accessibilityLabel(swatch.title)
        .accessibilityIdentifier(swatch.accessibilityIdentifier ?? swatch.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func disc(_ fill: Fill) -> some View {
        Group {
            switch fill {
            case .color(let color): color
            case .checkerboard: Checkerboard()
            }
        }
        .frame(width: DS.Metrics.swatch, height: DS.Metrics.swatch)
        .clipShape(.circle)
        .overlay {
            Circle().strokeBorder(DS.Color.Backdrop.edge, lineWidth: DS.Metrics.hairline)
        }
    }

    private static var ringDiameter: CGFloat {
        DS.Metrics.swatch + 2 * (DS.Metrics.swatchRingGap + DS.Metrics.swatchRingWidth)
    }
}

/// "No backdrop": light-grey squares on white in either appearance.
private struct Checkerboard: View {
    /// Side of one square.
    var cell: CGFloat

    init(cell: CGFloat = DS.Metrics.checkerboardCell) {
        self.cell = cell
    }

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(DS.Color.Backdrop.white))
            let columns = Int((size.width / cell).rounded(.up))
            let rows = Int((size.height / cell).rounded(.up))
            var squares = Path()
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    squares.addRect(CGRect(
                        x: CGFloat(column) * cell,
                        y: CGFloat(row) * cell,
                        width: cell,
                        height: cell
                    ))
                }
            }
            context.fill(squares, with: .color(DS.Color.Backdrop.checker))
        }
        // Decorative: the swatch button owns the hit region.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
