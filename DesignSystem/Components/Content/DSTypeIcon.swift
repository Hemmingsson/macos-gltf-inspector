import SwiftUI

/// The glTF role an icon stands for. Mirrors PreviewUI's `NodeKind` with identical raw values, so
/// the seam maps with `DSTypeRole(rawValue: kind.rawValue)` (DesignSystem cannot see PreviewUI).
public enum DSTypeRole: String, Sendable, Hashable, CaseIterable {
    case scene
    case mesh
    case camera
    case light
    case material
    case animation
    case skin
    case morph
    /// A transform-only node (glTF "empty"), shown as a group.
    case empty

    /// SF Symbol for the role. SF Symbols only — no bundled art — so weight and appearance track
    /// the system font.
    public var systemImage: String {
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
    public var tint: SwiftUI.Color {
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
/// type glyph comes from here. In a selected custom row pass `isSelected` so the tint yields to
/// `DS.Color.selectionText`. Hidden from VoiceOver: the row's label already names the type.
public struct DSTypeIcon: View {
    private let role: DSTypeRole
    private let isSelected: Bool

    @ScaledMetric(relativeTo: .body) private var side = DS.Metrics.typeIcon

    public init(_ role: DSTypeRole, isSelected: Bool = false) {
        self.role = role
        self.isSelected = isSelected
    }

    public var body: some View {
        Image(systemName: role.systemImage)
            .font(DS.Font.body)
            .foregroundStyle(isSelected ? AnyShapeStyle(DS.Color.selectionText) : AnyShapeStyle(role.tint))
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Type icons") {
    DSContentPreviewStage(width: DS.Metrics.sidebarWidth) {
        ForEach(DSTypeRole.allCases, id: \.self) { role in
            HStack(spacing: DS.Spacing.m) {
                DSTypeIcon(role)
                Text(role.rawValue.capitalized).font(DS.Font.body)
            }
        }
    }
}

#Preview("Type icons selected, dark") {
    DSContentPreviewStage(width: DS.Metrics.sidebarWidth) {
        ForEach(DSTypeRole.allCases, id: \.self) { role in
            HStack(spacing: DS.Spacing.m) {
                DSTypeIcon(role)
                DSTypeIcon(role, isSelected: true)
                Text(role.rawValue.capitalized).font(DS.Font.body)
            }
        }
    }
    .preferredColorScheme(.dark)
}
