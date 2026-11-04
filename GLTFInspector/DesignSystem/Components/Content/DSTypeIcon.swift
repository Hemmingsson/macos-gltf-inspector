import SwiftUI

extension NodeKind {
    /// SF Symbol fallback when no catalog image or material swatch is mapped.
    var systemImage: String {
        switch self {
        case .scene: "square.stack.3d.up"
        case .mesh: "cube"
        case .camera: "video"
        case .light: "lamp.desk"
        case .material: "circle.lefthalf.filled"
        case .animation: "stopwatch"
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

/// Type glyph in a fixed square (`DS.Metrics.typeIcon`). Prefers a material colour swatch, then a
/// catalog image (Blender / Spline), then an SF Symbol. Pass `isSelected` so the glyph reads on
/// the system highlight. Hidden from VoiceOver — the row already names the type.
struct DSTypeIcon: View {
    private let role: NodeKind
    private let systemImage: String
    private let assetImage: String?
    private let swatchColor: Color?
    private let isSelected: Bool
    private let font: Font

    @ScaledMetric(relativeTo: .body) private var side = DS.Metrics.typeIcon

    init(
        _ role: NodeKind,
        systemImage: String? = nil,
        assetImage: String? = nil,
        swatchColor: Color? = nil,
        isSelected: Bool = false,
        font: Font = Font.body
    ) {
        self.role = role
        self.systemImage = systemImage ?? role.systemImage
        self.assetImage = assetImage ?? (swatchColor == nil ? SplineIcons.nodeKind(role) : nil)
        self.swatchColor = swatchColor
        self.isSelected = isSelected
        self.font = font
    }

    private var ink: AnyShapeStyle {
        isSelected
            ? AnyShapeStyle(HierarchicalShapeStyle.primary)
            : AnyShapeStyle(role.tint)
    }

    var body: some View {
        Group {
            if let swatchColor {
                // Material ball: tinted sphere (radial highlight), not a flat SF glyph.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                swatchColor.mix(with: .white, by: 0.35),
                                swatchColor,
                                swatchColor.mix(with: .black, by: 0.25),
                            ],
                            center: .init(x: 0.32, y: 0.28),
                            startRadius: 0,
                            endRadius: side * 0.75
                        )
                    )
                    .overlay {
                        Circle().strokeBorder(.primary.opacity(isSelected ? 0.35 : 0.18), lineWidth: 0.5)
                    }
                    .opacity(isSelected ? 0.92 : 1)
            } else if let assetImage {
                // Blender SVGs are white-on-transparent templates; Spline PNGs/SVGs stay original.
                if assetImage.hasPrefix("blender.") {
                    Image(assetImage)
                        .renderingMode(.template)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(ink)
                } else {
                    Image(assetImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .opacity(isSelected ? 0.92 : 1)
                }
            } else {
                Image(systemName: systemImage)
                    .font(font)
                    .foregroundStyle(ink)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
