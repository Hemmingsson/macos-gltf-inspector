import SwiftUI

/// Every number the three canvas pills share.
///
/// One place, because the pills only read as *one* distributed toolbar while they agree on
/// height, radius and rhythm — a 2 pt drift between Stage and Camera is instantly visible when
/// they sit on the same line.
public enum PillMetrics {
    /// Hit / island height — `Theme.chromeControlSize` (Sketch circle islands).
    public static var height: CGFloat { Theme.chromeControlSize }
    /// Full half-height → stadium for multi-control islands, true circle for singles.
    public static var cornerRadius: CGFloat { height / 2 }
    /// Gap between separate islands (Sketch rhythm — tighter than a crammed mega-pill).
    public static let islandSpacing: CGFloat = 8
    /// Horizontal inset from the canvas edges for leading / trailing clusters.
    /// Vertical placement is `chromeBandAligned()`, not a free top pad.
    public static let inset: CGFloat = 14
    /// Gap inside one island.
    public static let itemSpacing: CGFloat = 4
    /// Same as chrome circles — `Theme.chromeControlSize`.
    public static var buttonSize: CGFloat { Theme.chromeControlSize }
    /// Inset selection wash radius inside a multi-control stadium (not used on single circles).
    public static let buttonCornerRadius: CGFloat = 8
    /// Inset of the selected wash from the hit target (keeps fill off the pill glass edge).
    public static let selectionInset: CGFloat = 2
    /// Concentric radius for the inset wash (`buttonCornerRadius − selectionInset`).
    public static let selectionCornerRadius: CGFloat = 6
    /// Inset of an icon toggle's circular on-wash inside its 30 pt target. Small, so the selected
    /// circle sits behind the glyph like a normal macOS selected control — filling most of the
    /// button, not a tiny dot and not spilling to the glass edge.
    public static let toggleWashInset: CGFloat = 3
    /// SF Symbol size inside the control target.
    public static let glyphSize: CGFloat = 13
    /// The chevron on a menu chip.
    public static let chevronSize: CGFloat = 9
    /// Hairline divider height inside a multi-control island.
    public static let dividerHeight: CGFloat = 18
    /// Extra horizontal pad around an in-island divider.
    public static let dividerMargin: CGFloat = 3
    /// Backdrop swatch disc.
    public static let swatchSize: CGFloat = 18
}

/// One floating glass cluster.
///
/// A `GlassEffectContainer` rather than a bare `.glassEffect` so the pill material resolves as
/// one surface. Toggle on-states are an inset `Theme.selection` wash — not nested
/// `.glassProminent` — so they never fight the capsule or grow the pill.
///
/// Modifier order is load-bearing: font/frame → padding → `.glassEffect` **last**.
public struct Pill<Content: View>: View {
    /// `padding: 0 8px` on Stage and Camera, `0 6px` on Look (its chip already carries its own).
    public var horizontalPadding: CGFloat = 8
    /// A single-icon island: force a square so a glyph narrower than the pill height can't collapse
    /// the capsule into a vertical oval — `cornerRadius = height/2` on a square is a true circle.
    public var circle: Bool = false
    @ViewBuilder var content: () -> Content

    public var body: some View {
        GlassEffectContainer(spacing: PillMetrics.itemSpacing) {
            cluster
                .glassEffect(.regular, in: .rect(cornerRadius: PillMetrics.cornerRadius))
        }
    }

    private var cluster: some View {
        HStack(spacing: PillMetrics.itemSpacing) {
            content()
        }
        .padding(.horizontal, circle ? 0 : horizontalPadding)
        .frame(width: circle ? PillMetrics.height : nil, height: PillMetrics.height)
        .focusSection()
    }
}

/// An icon-only toggle or action inside a pill (`.tbtn`).
public struct PillButton: View {
    public var symbol: String
    /// Tooltip and VoiceOver label. Icon-only controls have no other name.
    public var title: String
    /// Nil for a plain action (Fit), which has no on-state to show.
    public var isOn: Bool = false
    public var action: () -> Void

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: PillMetrics.glyphSize, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isOn ? Theme.selectionText : Theme.glyph)
                .frame(width: PillMetrics.buttonSize, height: PillMetrics.buttonSize)
                // Without this the button only responds on the glyph's own ink, which on a
                // 15 pt symbol is a fraction of the 30 pt target.
                .contentShape(.rect)
        }
        .pillButtonStyle(active: isOn)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// `.divv` — the hairline that separates two groups of controls inside one pill.
public struct PillDivider: View {
    @Environment(\.previewHair) private var hair

    public var body: some View {
        hair
            .frame(width: Theme.hairlineWidth, height: PillMetrics.dividerHeight)
            .padding(.horizontal, PillMetrics.dividerMargin)
            .accessibilityHidden(true)
    }
}

/// The label of a pill control that opens a menu: glyph, optional title, chevron.
///
/// Menus are styled apart from toggles on purpose. A toggle answers "is this on?" with an inset
/// `Theme.selection` wash; a menu answers "which one?", so it takes the quiet `controlFill`
/// ground, and shifts to the selection tint only while it holds a *non-default* choice — which is
/// exactly what `Inspect@2x.png` shows for the view-mode chip on Normals.
public struct PillMenuLabel: View {
    public var symbol: String
    public var title: String?
    /// True while the menu holds something other than its default — tints the chip.
    public var isEngaged: Bool = false
    /// Chevron direction; a presented menu points its chevron back at itself.
    public var isExpanded: Bool = false

    public var body: some View {
        HStack(spacing: title == nil ? 3 : 6) {
            Image(systemName: symbol)
                .font(.system(size: title == nil ? PillMetrics.glyphSize : 13, weight: .regular))
                .symbolRenderingMode(.monochrome)

            if let title {
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: PillMetrics.chevronSize, weight: .semibold))
        }
        .foregroundStyle(isEngaged ? Theme.selectionText : Theme.glyph)
        .padding(.leading, title == nil ? 7 : 10)
        .padding(.trailing, title == nil ? 7 : 8)
        .frame(height: PillMetrics.buttonSize)
        .background(
            RoundedRectangle(cornerRadius: PillMetrics.buttonCornerRadius, style: .continuous)
                .fill(isEngaged ? Theme.selection : Theme.controlFill)
        )
        .contentShape(.rect)
    }
}

// MARK: - Previews

#Preview("pill stadium") {
    Pill {
        PillButton(symbol: "viewfinder", title: "Fit") {}
        PillDivider()
        PillButton(symbol: "arrow.up.left.and.arrow.down.right", title: "Framing", isOn: true) {}
    }
    .padding(24)
}

#Preview("pill circle") {
    Pill(circle: true) {
        PillButton(symbol: "circle.grid.cross", title: "Floor", isOn: true) {}
    }
    .padding(24)
}

#Preview("pill button off") {
    PillButton(symbol: "viewfinder", title: "Fit") {}
        .padding(24)
}

#Preview("pill button on") {
    PillButton(symbol: "circle.grid.cross", title: "Floor", isOn: true) {}
        .padding(24)
}

#Preview("pill divider") {
    Pill {
        PillButton(symbol: "sun.max", title: "Lighting") {}
        PillDivider()
        PillButton(symbol: "camera.aperture", title: "Field of view") {}
    }
    .padding(24)
}

#Preview("menu label default") {
    PillMenuLabel(symbol: "sun.max")
        .padding(24)
}

#Preview("menu label engaged") {
    PillMenuLabel(symbol: "eye", title: "Normals", isEngaged: true)
        .padding(24)
}

#Preview("menu label expanded") {
    PillMenuLabel(symbol: "camera.aperture", isExpanded: true)
        .padding(24)
}
