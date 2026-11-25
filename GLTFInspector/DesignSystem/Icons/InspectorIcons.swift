import AppKit
import GLTFCore
import Renderer
import SwiftUI

/// A chrome glyph: the drawn inspector icon (`InspectorIcons.xcassets`, `inspector.<name>`) with
/// the SF Symbol that stands in when the catalog has not got it.
///
/// Every glyph in chrome resolves through here, so redrawing one is a catalog change rather than a
/// view change, and no call site names an image. The drawn set and the metaphor system behind it
/// follow the drawing guide in `assets/icons/inspector/STYLEGUIDE.md`.
struct DSGlyph: Equatable {
    /// Catalog name including the `inspector.` prefix, or nil when the symbol is the only art.
    let asset: String?
    /// SF Symbol drawn when the catalog image is missing.
    let symbol: String

    init(_ name: String?, fallback symbol: String) {
        self.asset = name.map { "inspector.\($0)" }
        self.symbol = symbol
    }

    /// The catalog image, or nil when it is absent and the symbol should draw instead. Components
    /// that already take `systemImage:` / `assetImage:` read both halves straight off the glyph.
    var assetImage: String? {
        guard let asset, NSImage(named: asset) != nil else { return nil }
        return asset
    }
}

extension DSIcon {
    /// Draws a glyph: catalog art when present, otherwise the SF Symbol.
    init(_ glyph: DSGlyph, font: Font = .body) {
        self.init(glyph.asset, fallback: glyph.symbol, font: font)
    }
}

/// The app's glyph vocabulary, grouped the way the icons were drawn.
enum DSGlyphs {
    static let sharedMesh = DSGlyph("node-shared-mesh", fallback: "square.stack.3d.up")
    static let defaultScene = DSGlyph("node-scene-default", fallback: "house")

    // Viewport controls
    static let fit = DSGlyph("fit", fallback: "viewfinder")
    static let frameSelection = DSGlyph("frame-selection", fallback: "viewfinder.rectangular")
    static let zoomIn = DSGlyph("zoom-in", fallback: "plus.magnifyingglass")
    static let zoomOut = DSGlyph("zoom-out", fallback: "minus.magnifyingglass")
    static let resetView = DSGlyph("reset-view", fallback: "arrow.counterclockwise")
    static let autoRotate = DSGlyph("auto-rotate", fallback: "arrow.trianglehead.counterclockwise.rotate.90")
    static let floor = DSGlyph("floor-grid", fallback: "circle.grid.cross")
    static let showRig = DSGlyph("show-rig", fallback: "camera.viewfinder")
    static let lighting = DSGlyph("light-env", fallback: "sun.max")
    static let view = DSGlyph("fit", fallback: "viewfinder")

    // Projection — the toolbar toggle reuses the camera glyph, one metaphor for one idea.
    static let perspective = DSGlyph("proj-perspective", fallback: "video")
    static let orthographic = DSGlyph("proj-orthographic", fallback: "perspective")

    // Animation
    static let play = DSGlyph("play", fallback: "play.fill")
    static let pause = DSGlyph("pause", fallback: "pause.fill")
    static let loop = DSGlyph("loop", fallback: "repeat")
    static let speed = DSGlyph("speed", fallback: "gauge.with.dots.needle.67percent")
    static let animated = DSGlyph("animated", fallback: "figure.walk.motion")

    // Chrome and document actions
    static let openIn = DSGlyph("open-in", fallback: "square.and.arrow.up")
    static let copy = DSGlyph("copy", fallback: "doc.on.doc")
    static let exportStill = DSGlyph("export-png", fallback: "camera")
    static let exportMovie = DSGlyph("export-mp4", fallback: "photo.stack")
    static let settings = DSGlyph("settings", fallback: "gearshape")
    static let inspector = DSGlyph("inspector", fallback: "sidebar.right")
    static let visible = DSGlyph("visible", fallback: "eye")
    static let hidden = DSGlyph("hidden", fallback: "eye.slash")
    static let chevronDown = DSGlyph("chevron-down", fallback: "chevron.down")
    static let chevronRight = DSGlyph("chevron-right", fallback: "chevron.right")

    /// Punctual lights, keyed by the glTF `type` string.
    static func light(_ type: String) -> DSGlyph {
        switch type {
        case "point": DSGlyph("light-point", fallback: "ring.light")
        case "spot": DSGlyph("light-spot", fallback: "light.overhead.right")
        case "area": DSGlyph("light-area", fallback: "lamp.desk")
        default: DSGlyph("light-sun", fallback: "lamp.desk")
        }
    }
}

extension RenderViewMode {
    /// The drawn glyph: one cube rendered five ways, then the ball for every channel.
    var glyph: DSGlyph {
        switch self {
        case .shaded: DSGlyph("view-shaded", fallback: "circle.lefthalf.filled")
        case .wireframe: DSGlyph("view-wireframe", fallback: "grid")
        case .wireframeOnShaded: DSGlyph("view-wireframe-shaded", fallback: "square.grid.3x3.topleft.filled")
        case .xray: DSGlyph("view-xray", fallback: "cube.transparent")
        case .clay: DSGlyph("view-clay", fallback: "circle.fill")
        case .channel(let channel): channel.glyph
        }
    }
}

extension RenderViewMode.Channel {
    /// One ball per channel; the mark is the same one its texture map carries.
    var glyph: DSGlyph {
        switch self {
        case .baseColor: DSGlyph("channel-base-color", fallback: "paintpalette")
        case .metallic: DSGlyph("channel-metallic", fallback: "circle.bottomhalf.filled")
        case .roughness: DSGlyph("channel-roughness", fallback: "cloud")
        case .normals: DSGlyph("channel-normals", fallback: "arrow.up.and.down.and.arrow.left.and.right")
        case .tangents: DSGlyph("channel-tangents", fallback: "arrow.left.and.right")
        case .textureCoordinates: DSGlyph("channel-uv", fallback: "square.grid.3x3")
        case .ambientOcclusion: DSGlyph("channel-occlusion", fallback: "circle.dashed")
        case .emissive: DSGlyph("channel-emissive", fallback: "sun.max")
        case .alpha: DSGlyph("channel-alpha", fallback: "square.split.2x2")
        case .specular: DSGlyph("channel-specular", fallback: "sparkle")
        case .clearcoat: DSGlyph("channel-clearcoat", fallback: "circle.circle")
        case .clearcoatRoughness: DSGlyph("channel-clearcoat-roughness", fallback: "circle.circle.fill")
        case .clearcoatNormal:
            DSGlyph("channel-clearcoat-normal", fallback: "arrow.up.and.down.and.arrow.left.and.right")
        }
    }
}

extension NodeKind {
    /// Outliner and identity-row glyph. Material is the bare ball the channels are built on.
    var glyph: DSGlyph {
        switch self {
        case .scene: DSGlyph("node-scene", fallback: "square.stack.3d.up")
        case .mesh: DSGlyph("node-mesh", fallback: "cube")
        case .camera: DSGlyph("node-camera", fallback: "video")
        case .light: DSGlyph("node-light", fallback: "lamp.desk")
        case .material: DSGlyph("node-material", fallback: "circle.lefthalf.filled")
        case .animation: DSGlyph("node-animation", fallback: "stopwatch")
        case .skin: DSGlyph("node-skin", fallback: "point.3.connected.trianglepath.dotted")
        case .morph: DSGlyph("node-morph", fallback: "slider.horizontal.3")
        case .empty: DSGlyph("node-empty", fallback: "circle.dotted")
        }
    }
}

extension GLTFDocument.TextureSlot.Kind {
    /// The frame holding the same mark the matching channel puts on the ball.
    var glyph: DSGlyph {
        switch self {
        case .baseColor: DSGlyph("map-base-color", fallback: "paintpalette")
        case .normal, .clearcoatNormal:
            DSGlyph("map-normal", fallback: "arrow.up.and.down.and.arrow.left.and.right")
        case .occlusion: DSGlyph("map-occlusion", fallback: "circle.dashed")
        case .metallicRoughness: DSGlyph("map-metal-rough", fallback: "circle.bottomhalf.filled")
        case .emissive: DSGlyph("map-emissive", fallback: "sun.max")
        case .specular: DSGlyph("map-specular", fallback: "sparkle")
        case .clearcoat, .clearcoatRoughness: DSGlyph("map-clearcoat", fallback: "circle.circle")
        }
    }
}

extension CameraPreset {
    /// One frame per angle, with the face that meets you marked.
    var glyph: DSGlyph {
        switch self {
        case .front: DSGlyph("view-front", fallback: "arrow.up.to.line")
        case .back: DSGlyph("view-back", fallback: "arrow.down.to.line")
        case .left: DSGlyph("view-left", fallback: "arrow.left.to.line")
        case .right: DSGlyph("view-right", fallback: "arrow.right.to.line")
        case .top: DSGlyph("view-top", fallback: "arrow.up.to.line.compact")
        case .bottom: DSGlyph("view-bottom", fallback: "arrow.down.to.line.compact")
        case .isometric: DSGlyph("view-iso", fallback: "cube")
        }
    }
}

extension DSStatus {
    /// Validator badge. Shape differs per status, so it never relies on colour alone.
    var glyph: DSGlyph {
        switch self {
        case .valid: DSGlyph("status-valid", fallback: "checkmark.circle")
        case .warning: DSGlyph("status-warning", fallback: "exclamationmark.triangle")
        case .error: DSGlyph("status-error", fallback: "xmark.octagon")
        case .pending: DSGlyph("status-pending", fallback: "ellipsis.circle")
        case .note: DSGlyph("status-note", fallback: "info.circle")
        }
    }
}
