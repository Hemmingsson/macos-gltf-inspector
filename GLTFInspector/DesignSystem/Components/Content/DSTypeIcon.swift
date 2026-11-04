import SwiftUI

extension NodeKind {
    /// SF Symbol for the role. SF Symbols only — no bundled art — so weight and appearance track
    /// the system font.
    var systemImage: String {
        switch self {
        case .scene: "square.stack.3d.up"
        case .mesh: "cube"
        case .camera: "video"
        case .light: "sun.max"
        case .material: "circle.lefthalf.filled"
        case .animation: "waveform.path"
        case .skin: "point.3.connected.trianglepath.dotted"
        case .morph: "slider.horizontal.3"
        case .empty: "circle.dotted"
        }
    }

    /// Meaning-colour from `DS.Color.Role`. Only the five content roles get a hue; structural
    /// roles (scene, skin, morph, empty) stay graphite with meshes — they are scaffolding.
    var tint: SwiftUI.Color {
        switch self {
        case .camera: DS.Color.Role.camera
        case .light: DS.Color.Role.light
        case .material: DS.Color.Role.material
        case .animation: DS.Color.Role.animation
        case .scene, .mesh, .skin, .morph, .empty: DS.Color.Role.mesh
        }
    }
}

/// The glTF-type glyph: one monochrome SF Symbol tinted with its role colour, in a fixed square
/// box (`DS.Metrics.typeIcon`, scaled with the text size) so row titles line up down a column.
///
/// DESIGN.md — colour is meaning: a reader learns the hues once (camera blue, light amber,
/// material purple, animation green, mesh graphite) and scans the outliner without reading. Every
/// type glyph comes from here. Pass `isSelected` on a selected row so the glyph uses the label
/// colour, which turns light on the system highlight. A fixed role colour, mesh graphite
/// included, fails contrast on that blue. Hidden from VoiceOver: the row's label already names
/// the type.
struct DSTypeIcon: View {
    private let role: NodeKind
    private let isGroup: Bool
    private let isSelected: Bool
    private let font: Font

    @ScaledMetric(relativeTo: .body) private var side = DS.Metrics.typeIcon

    /// - Parameters:
    ///   - isGroup: an empty node that holds children — drawn as a folder, like a layer group.
    ///   - font: glyph size; a compact row passes `Font.subheadline`.
    init(
        _ role: NodeKind,
        isGroup: Bool = false,
        isSelected: Bool = false,
        font: Font = Font.body
    ) {
        self.role = role
        self.isGroup = isGroup
        self.isSelected = isSelected
        self.font = font
    }

    private var systemImage: String {
        isGroup && role == .empty ? "folder" : role.systemImage
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(font)
            .foregroundStyle(isSelected ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(role.tint))
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}
