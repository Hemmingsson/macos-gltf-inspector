import SwiftUI

/// Read-only labels and omit-default rules for the material inspector.
/// Kept out of the seam so `MaterialInfo` stays engine-friendly.
enum MaterialInspectorSupport {
    static func workflowTitle(_ workflow: MaterialInfo.Workflow) -> String {
        switch workflow {
        case .metallicRoughness: return "Metallic Roughness"
        case .specularGlossiness: return "Specular Glossiness (converted)"
        case .unlit: return "Unlit"
        }
    }

    static func alphaTitle(_ material: MaterialInfo) -> String {
        switch material.alphaMode {
        case .opaque: return "Opaque"
        case .blend: return "Blend"
        case .mask:
            if let cutoff = material.alphaCutoff {
                return String(format: "Mask (cutoff %.2g)", cutoff)
            }
            return "Mask"
        }
    }

    static func usageTitle(_ material: MaterialInfo) -> String? {
        let names = material.usedByMeshNames
        guard !names.isEmpty else { return nil }
        if names.count <= 3 {
            return names.joined(separator: ", ")
        }
        return "\(names.count) meshes"
    }

    static func hexLabel(_ color: RGBColor) -> String {
        let r = Int((color.red * 255).rounded().clamped(to: 0...255))
        let g = Int((color.green * 255).rounded().clamped(to: 0...255))
        let b = Int((color.blue * 255).rounded().clamped(to: 0...255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    static func scalarLabel(_ value: Double) -> String {
        String(format: "%.2g", value)
    }

    // MARK: Factor visibility (omit calm defaults *and* channels already covered by a map)

    static func showsBaseColorFactor(_ material: MaterialInfo) -> Bool {
        // Map row already names Base Color — don't also print a hex swatch for the same slot.
        if material.maps.contains(.baseColor) { return false }
        guard let factor = material.baseColorFactor else { return false }
        return !factor.isApproximatelyEqual(to: .white)
    }

    static func showsMetallic(_ material: MaterialInfo) -> Bool {
        if material.maps.contains(.metallicRoughness) { return false }
        guard let value = material.metallicFactor else { return false }
        return abs(value - 1) > 0.004
    }

    static func showsRoughness(_ material: MaterialInfo) -> Bool {
        if material.maps.contains(.metallicRoughness) { return false }
        guard let value = material.roughnessFactor else { return false }
        return abs(value - 1) > 0.004
    }

    static func showsEmissive(_ material: MaterialInfo) -> Bool {
        // Emissive map row covers presence; only show a colour row when there is no map.
        if material.maps.contains(.emissive) { return false }
        guard let factor = material.emissiveFactor else { return false }
        return !factor.isApproximatelyEqual(to: .black)
    }

    static func showsNormalScale(_ material: MaterialInfo) -> Bool {
        // Scale only matters as an override on top of a normal map — and even then, skip the
        // default 1. Keep quiet when there is no map (nothing to scale).
        guard material.maps.contains(.normal) else { return false }
        guard let value = material.normalScale else { return false }
        return abs(value - 1) > 0.004
    }

    static func showsOcclusionStrength(_ material: MaterialInfo) -> Bool {
        guard material.maps.contains(.occlusion) else { return false }
        guard let value = material.occlusionStrength else { return false }
        return abs(value - 1) > 0.004
    }
}

extension Color {
    init(rgb: RGBColor) {
        self.init(
            .sRGB,
            red: rgb.red.clamped(to: 0...1),
            green: rgb.green.clamped(to: 0...1),
            blue: rgb.blue.clamped(to: 0...1),
            opacity: 1
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
