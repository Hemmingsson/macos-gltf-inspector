import SwiftUI

/// A glass control that opens a menu: the camera presets circle, the view-mode "Shaded ▾" chip.
///
/// Three label styles:
/// - `.icon` — icon-only `DS.Metrics.glassControl` circle, no chevron (a menu whose glyph already
///   says "pick one", like camera presets).
/// - `.iconWithChevron` — icon + small `.secondary` chevron in a `DS.Metrics.glassControlWide`
///   capsule.
/// - `.titled(value)` — icon + the current choice + chevron in a content-sized capsule. The
///   button's `title` stays the accessibility label ("View mode") and `value` is announced as its
///   accessibility value ("Shaded").
/// - `.text(value)` — the current choice + chevron, no icon (the zoom menu's "90% ▾").
///
/// Placement follows `DSGlassPlacement`: standalone draws one `DS.Glass.control` layer
/// (tinted while `isEngaged`, e.g. a non-default view mode); inside a `DSGlassIsland` it draws none.
///
/// Built as `Menu` + `.menuStyle(.button)` + `.buttonStyle(.plain)` with the native indicator
/// hidden and a DS chevron in the label. The AppKit-backed `.borderlessButton` menu style flattens
/// custom labels (drops the frame, the chevron and the ink), which would shrink the hit target to
/// the glyph; this keeps the whole capsule clickable and matches `DSGlassPopoverButton`.
struct DSGlassMenuButton<MenuContent: View>: View {
    /// How the label is drawn. See the type documentation.
    enum Style: Equatable, Sendable {
        case icon
        case iconWithChevron
        case titled(String)
        case text(String)
    }

    private let title: String
    private let systemImage: String
    private let assetImage: String?
    private let style: Style
    private let isEngaged: Bool
    private let help: String?
    private let menuContent: MenuContent

    /// - Parameters:
    ///   - title: What the menu picks ("Camera presets", "View mode"): accessibility label and,
    ///     unless `help` is given, the tooltip.
    ///   - systemImage: SF Symbol name (used when `assetImage` is nil).
    ///   - assetImage: Catalog image name; drawn instead of the SF Symbol when set.
    ///   - style: Label style. Defaults to `.icon`.
    ///   - isEngaged: Tints the control while the menu holds a non-default choice.
    ///   - help: Tooltip override (e.g. "Camera presets — Front · Top · Isometric…").
    ///   - content: The menu items. Prefer an inline `Picker` for pick-one menus so AppKit draws
    ///     the checkmark column.
    init(
        _ title: String,
        systemImage: String,
        assetImage: String? = nil,
        style: Style = .icon,
        isEngaged: Bool = false,
        help: String? = nil,
        @ViewBuilder content: () -> MenuContent
    ) {
        self.title = title
        self.systemImage = systemImage
        self.assetImage = assetImage
        self.style = style
        self.isEngaged = isEngaged
        self.help = help
        self.menuContent = content()
    }

    var body: some View {
        Menu {
            // macOS 27 draws a menu symbol only when the label style asks for title and icon.
            menuContent
                .labelStyle(.titleAndIcon)
        } label: {
            label
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .dsGlassControlSurface(isEngaged: isEngaged)
        .help(help ?? title)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var glyph: some View {
        if let assetImage {
            Image(assetImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: systemImage)
        }
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .icon:
            glyph
                .dsGlassControlLabel(.circle, isHighlighted: isEngaged)
        case .iconWithChevron:
            HStack(spacing: DS.Spacing.xs) {
                glyph.dsGlassPrimaryGlyph(isHighlighted: isEngaged)
                DSGlassChevron()
            }
            .dsGlassControlLabel(.wide, isHighlighted: isEngaged)
        case .titled(let value), .text(let value):
            HStack(spacing: DS.Spacing.s) {
                if case .titled = style {
                    glyph.dsGlassPrimaryGlyph(isHighlighted: isEngaged)
                }
                Text(value)
                    .font(.body)
                    .foregroundStyle(
                        isEngaged
                            ? AnyShapeStyle(TintShapeStyle.tint)
                            : AnyShapeStyle(HierarchicalShapeStyle.primary)
                    )
                    .lineLimit(1)
                    // Ancestor glass `isEngaged` animation interpolates this string otherwise.
                    .contentTransition(.identity)
                    .transaction { $0.animation = nil }
                DSGlassChevron()
            }
            .dsGlassControlLabel(.titled, isHighlighted: isEngaged)
        }
    }

    private var accessibilityValue: String {
        switch style {
        case .titled(let value), .text(let value): value
        case .icon, .iconWithChevron: ""
        }
    }
}
