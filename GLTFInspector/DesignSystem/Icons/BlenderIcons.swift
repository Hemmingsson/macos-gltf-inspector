import Foundation

/// Catalog names for Blender UI icons in `BlenderIcons.xcassets`
/// (`release/datafiles/icons_svg/` from blender/blender, GPL-2.0-or-later — see
/// `BlenderIcons.NOTICE.md`).
enum BlenderIcons {
    /// `KHR_lights_punctual` type → Blender glyph. Area is unused by glTF today but kept ready.
    static func lightType(_ type: String) -> String {
        switch type {
        case "point": "blender.light.point"
        case "spot": "blender.light.spot"
        case "area": "blender.light.area"
        default: "blender.light.sun" // directional
        }
    }
}
