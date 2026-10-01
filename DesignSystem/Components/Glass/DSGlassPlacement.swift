import SwiftUI

/// Where a glass control sits, which decides whether it draws its own glass.
///
/// Glass cannot sample glass, so a control inside an island, a HUD capsule or a system bar must
/// not add a second layer. `DSGlassIsland` and `DSHUDCapsule` set `.inIsland` for their content
/// automatically, so the rule holds by construction; set it by hand with
/// `.dsGlassPlacement(.inIsland)` only where the system already supplies the glass (for example
/// controls hosted as toolbar items).
public enum DSGlassPlacement: Sendable {
    /// The control is its own island: it draws one `DS.Glass.control` layer in its shape.
    case standalone
    /// The control sits on glass that something else drew: no glass of its own, borderless.
    case inIsland
}

extension EnvironmentValues {
    /// Read by every glass control; written by `DSGlassIsland`, `DSHUDCapsule` and
    /// `View.dsGlassPlacement(_:)`.
    @Entry var dsGlassPlacement: DSGlassPlacement = .standalone
}

public extension View {
    /// Tells the glass controls inside this view where they sit. See `DSGlassPlacement`.
    func dsGlassPlacement(_ placement: DSGlassPlacement) -> some View {
        environment(\.dsGlassPlacement, placement)
    }

    /// Pins a floating control to the traffic-light centerline.
    func dsChromeBandAligned() -> some View {
        self
            .padding(.top, DS.Metrics.toolbarCenterY - DS.Metrics.glassControl / 2)
            .frame(height: DS.Metrics.toolbarBandHeight, alignment: .top)
    }
}

// MARK: - Shared control chrome (internal)

/// The shape a glass control occupies. Icon-only controls are circles; anything wider (a chevron,
/// a title) is a capsule of the same height.
enum DSGlassControlShape {
    /// `DS.Metrics.glassControl` square → circle.
    case circle
    /// `DS.Metrics.glassControlWide` × `glassControl` capsule (icon + chevron).
    case wide
    /// Content-sized capsule (icon + title + chevron), padded horizontally.
    case titled

    var width: CGFloat? {
        switch self {
        case .circle: DS.Metrics.glassControl
        case .wide: DS.Metrics.glassControlWide
        case .titled: nil
        }
    }
}

extension View {
    /// Glyph styling shared by every glass control label: text-style font (never a point size),
    /// monochrome symbol, primary ink at rest and `.tint` when on, and a hit / focus shape that
    /// covers the whole control rather than the glyph's ink.
    ///
    /// Circle labels are a single glyph, so font and image scale apply here. Wide / titled labels
    /// style the primary glyph themselves so `DSGlassChevron` can stay `micro` — a body-sized
    /// `chevron.down` reads as a checkmark.
    func dsGlassControlLabel(_ shape: DSGlassControlShape, isHighlighted: Bool) -> some View {
        let ink: AnyShapeStyle = isHighlighted
            ? AnyShapeStyle(DS.Color.selectionText)
            : AnyShapeStyle(DS.Color.textPrimary)

        return Group {
            if shape == .circle {
                self
                    .font(DS.Font.body)
                    .imageScale(.medium)
                    .foregroundStyle(ink)
            } else {
                self
            }
        }
        .symbolRenderingMode(.monochrome)
        .padding(.horizontal, shape == .titled ? DS.Spacing.m : 0)
        .frame(width: shape.width, height: DS.Metrics.glassControl)
        .contentShape(.capsule)
    }

    /// The control's single glass layer — only when it is standalone. `isEngaged` switches to the
    /// subtly accent-tinted variant; the change animates through `DS.Motion` (none under Reduce
    /// Motion).
    func dsGlassControlSurface(isEngaged: Bool) -> some View {
        modifier(DSGlassControlSurface(isEngaged: isEngaged))
    }

    /// Primary glyph in a wide / titled glass label — body size, independent of the chevron.
    func dsGlassPrimaryGlyph(isHighlighted: Bool) -> some View {
        font(DS.Font.body)
            .imageScale(.medium)
            .foregroundStyle(
                isHighlighted
                    ? AnyShapeStyle(DS.Color.selectionText)
                    : AnyShapeStyle(DS.Color.textPrimary)
            )
    }

    /// Small secondary chevron for controls that open a menu or popover.
    func dsGlassChevronStyle() -> some View {
        font(DS.Font.micro.weight(.semibold))
            .imageScale(.small)
            .foregroundStyle(DS.Color.textSecondary)
    }
}

private struct DSGlassControlSurface: ViewModifier {
    var isEngaged: Bool

    @Environment(\.dsGlassPlacement) private var placement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        switch placement {
        case .standalone:
            content
                .glassEffect(isEngaged ? DS.Glass.controlEngaged : DS.Glass.control, in: .capsule)
                .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: isEngaged)
        case .inIsland:
            content
                .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: isEngaged)
        }
    }
}

/// The chevron glyph used by `DSGlassMenuButton` and `DSGlassPopoverButton`.
struct DSGlassChevron: View {
    var body: some View {
        Image(systemName: "chevron.down")
            .dsGlassChevronStyle()
            .accessibilityHidden(true)
    }
}
