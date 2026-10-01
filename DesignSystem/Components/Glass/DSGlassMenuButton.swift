import SwiftUI

/// A glass control that opens a menu: the camera presets circle, the view-mode "Shaded ▾" chip,
/// the playback clip picker.
///
/// Three label styles:
/// - `.icon` — icon-only `DS.Metrics.glassControl` circle, no chevron (a menu whose glyph already
///   says "pick one", like camera presets).
/// - `.iconWithChevron` — icon + small `.secondary` chevron in a `DS.Metrics.glassControlWide`
///   capsule.
/// - `.titled(value)` — icon + the current choice + chevron in a content-sized capsule. The
///   button's `title` stays the accessibility label ("View mode") and `value` is announced as its
///   accessibility value ("Shaded").
///
/// Placement follows `DSGlassPlacement`: standalone draws one `DS.Glass.control` layer
/// (tinted while `isEngaged`, e.g. a non-default view mode); inside a `DSGlassIsland` it draws none.
///
/// Built as `Menu` + `.menuStyle(.button)` + `.buttonStyle(.plain)` with the native indicator
/// hidden and a DS chevron in the label. The AppKit-backed `.borderlessButton` menu style flattens
/// custom labels (drops the frame, the chevron and the ink), which would shrink the hit target to
/// the glyph; this keeps the whole capsule clickable and matches `DSGlassPopoverButton`.
public struct DSGlassMenuButton<MenuContent: View>: View {
    /// How the label is drawn. See the type documentation.
    public enum Style: Equatable, Sendable {
        case icon
        case iconWithChevron
        case titled(String)
    }

    private let title: String
    private let systemImage: String
    private let style: Style
    private let isEngaged: Bool
    private let help: String?
    private let menuContent: MenuContent

    /// - Parameters:
    ///   - title: What the menu picks ("Camera presets", "View mode"): accessibility label and,
    ///     unless `help` is given, the tooltip.
    ///   - systemImage: SF Symbol name.
    ///   - style: Label style. Defaults to `.icon`.
    ///   - isEngaged: Tints the control while the menu holds a non-default choice.
    ///   - help: Tooltip override (e.g. "Camera presets — Front · Top · Isometric…").
    ///   - content: The menu items. Prefer an inline `Picker` for pick-one menus so AppKit draws
    ///     the checkmark column.
    public init(
        _ title: String,
        systemImage: String,
        style: Style = .icon,
        isEngaged: Bool = false,
        help: String? = nil,
        @ViewBuilder content: () -> MenuContent
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.isEngaged = isEngaged
        self.help = help
        self.menuContent = content()
    }

    public var body: some View {
        Menu {
            menuContent
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
    private var label: some View {
        switch style {
        case .icon:
            Image(systemName: systemImage)
                .dsGlassControlLabel(.circle, isHighlighted: isEngaged)
        case .iconWithChevron:
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: systemImage)
                    .dsGlassPrimaryGlyph(isHighlighted: isEngaged)
                DSGlassChevron()
            }
            .dsGlassControlLabel(.wide, isHighlighted: isEngaged)
        case .titled(let value):
            HStack(spacing: DS.Spacing.s) {
                Image(systemName: systemImage)
                    .dsGlassPrimaryGlyph(isHighlighted: isEngaged)
                Text(value)
                    .font(DS.Font.body)
                    .foregroundStyle(
                        isEngaged
                            ? AnyShapeStyle(DS.Color.selectionText)
                            : AnyShapeStyle(DS.Color.textPrimary)
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
        if case .titled(let value) = style { value } else { "" }
    }
}

// MARK: - Previews

private struct DSGlassMenuButtonPreview: View {
    @State private var mode = "Shaded"

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            HStack(spacing: DS.Metrics.clusterSpacing) {
                DSGlassMenuButton("Camera presets", systemImage: "cube") {
                    Button("Front") {}
                    Button("Top") {}
                }
                DSGlassMenuButton("Camera presets", systemImage: "cube", isEngaged: true) {
                    Button("Front") {}
                }
                DSGlassMenuButton("Open in", systemImage: "square.and.arrow.up", style: .iconWithChevron) {
                    Button("Finder") {}
                }
                DSGlassMenuButton(
                    "View mode",
                    systemImage: "circle.lefthalf.filled",
                    style: .titled(mode)
                ) {
                    Picker("View mode", selection: $mode) {
                        Text("Shaded").tag("Shaded")
                        Text("Wireframe").tag("Wireframe")
                        Text("Ambient Occlusion").tag("Ambient Occlusion")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }

            DSGlassIsland {
                DSGlassMenuButton(
                    "View mode",
                    systemImage: "cube",
                    style: .titled("Ambient Occlusion"),
                    isEngaged: true
                ) {
                    Button("Shaded") {}
                }
                DSGlassIslandDivider()
                DSGlassMenuButton("Lighting preset", systemImage: "sun.max", style: .iconWithChevron) {
                    Button("Studio") {}
                }
                DSGlassMenuButton("Presets", systemImage: "cube") {
                    Button("Front") {}
                }
            }
        }
    }
}

#Preview("menu button states", traits: .sizeThatFitsLayout) {
    DSGlassPreviewBackdrops {
        DSGlassMenuButtonPreview()
    }
    .frame(width: 460)
}
