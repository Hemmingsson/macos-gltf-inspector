import Foundation
import GLTFCore

// Values that cross the page bridge. The page exposes five async functions on `window.__viewer`
// (`open`, `apply`, `camera`, `still`, `stats`); `WebRendererHost.call` sends one JSON argument
// and decodes one JSON result. Mode and still size are in the page URL.

public enum WebRendererMode: String {
    /// No window, render one frame, hand back pixels. Finder thumbnails.
    case still
    /// Hosted in a view, continuous rendering. Document window and Quick Look.
    case live
}

/// A camera stated completely: where it looks, from how far, at what angles, through which
/// projection. Every field the renderer reads is here, so replaying a pose does not depend on
/// scene extents or on `UserCamera.fitViewToScene`.
///
/// Angles are degrees, `yfov` is radians — that split matches the page, which converts the
/// orbit angles and hands `yfov` straight to the projection.
struct CameraPose: Equatable, Codable, Sendable {
    var azimuth: Double
    var elevation: Double
    var distance: Double
    /// Scene-space point the camera looks at.
    var target: [Double]
    var yfov: Double
    var znear: Double
    var zfar: Double

    /// False for anything the renderer could not express as finite numbers — the page reports an
    /// unfitted camera's infinite `zfar` as 0, which no recorded pose should contain either.
    var isFinite: Bool {
        ([azimuth, elevation, distance, yfov, znear, zfar] + target).allSatisfy(\.isFinite) && zfar > 0
    }
}

/// `camera(...)`: one of four operations. Every one answers with the resulting camera state.
struct CameraCommand: Encodable, Equatable {
    var op: String
    var azimuth: Double?
    var elevation: Double?
    /// `orbit` only; nil keeps the current dolly.
    var distance: Double?
    var pose: CameraPose?

    /// Frames the scene and returns to the front view.
    static let fit = Self(op: "fit")
    /// Reads the current state without moving anything.
    static let get = Self(op: "get")

    /// Absolute orbit angles in degrees, keeping the target (and the dolly unless given).
    static func orbit(azimuth: Double, elevation: Double, distance: Double? = nil) -> Self {
        Self(op: "orbit", azimuth: azimuth, elevation: elevation, distance: distance)
    }

    /// The whole camera, nothing inherited from the fit heuristic — how goldens replay.
    static func pose(_ pose: CameraPose) -> Self {
        Self(op: "pose", pose: pose)
    }
}

/// The world-space box the renderer measured for the current scene, and the pose it is looking
/// at it from.
///
/// The bounds come along because a caller that wants to frame the model on its own terms needs
/// them: `pose.distance` only reports where this version of the renderer put the camera.
struct RendererCameraState: Equatable, Decodable, Sendable {
    var camera: CameraPose
    var sceneMin: [Double]
    var sceneMax: [Double]

    var pose: CameraPose { camera }

    /// Centre of the measured box.
    var sceneCenter: [Double] {
        (0..<3).map { (sceneMin[$0] + sceneMax[$0]) / 2 }
    }

    /// Radius of the sphere enclosing the measured box.
    ///
    /// Framing to a sphere rather than to the box is what makes a recorded pose independent of
    /// the angle it is viewed from — a box that just fits the frame head on will not fit once
    /// the camera orbits off axis.
    var boundingRadius: Double {
        let diagonal = (0..<3).map { sceneMax[$0] - sceneMin[$0] }
        return (diagonal.reduce(0) { $0 + $1 * $1 }).squareRoot() / 2
    }

    var isMeasurable: Bool {
        sceneMin.count == 3 && sceneMax.count == 3
            && (sceneMin + sceneMax).allSatisfy(\.isFinite)
            && boundingRadius > 0
    }

    /// Camera distance that frames the measured box when seen from `preset`.
    ///
    /// The page's fit (`fitDistanceToExtents`) sizes the distance to the larger of the box's X
    /// and Y extent — a front view. Distance is linear in that extent, so another view scales
    /// the fitted distance by its own on-screen extent: Z/Y from the side, X/Z from above, the
    /// full diagonal for the three-quarter view (all three axes are visible at once).
    func distance(framing preset: CameraPreset) -> Double {
        let size = (0..<3).map { sceneMax[$0] - sceneMin[$0] }
        let front = max(size[0], size[1])
        guard front > 0, pose.distance.isFinite else { return pose.distance }
        let extent: Double = switch preset {
        case .front, .back: front
        case .left, .right: max(size[2], size[1])
        case .top, .bottom: max(size[0], size[2])
        case .isometric: boundingRadius * 2
        }
        return pose.distance * extent / front
    }
}

extension CameraPreset {
    /// Page orbit angles in degrees. `UserCamera` places the eye at
    /// `R_y(azimuth) · R_x(elevation) · (0, 0, +d)`, so azimuth +90 looks from +X and a
    /// *negative* elevation looks from above. Same views as the RealityKit presets
    /// (yaw 0 = +Z front, +90 = +X right; pitch +90 = top).
    var webOrbitAngles: (azimuth: Double, elevation: Double) {
        switch self {
        case .front: (0, 0)
        case .back: (180, 0)
        case .right: (90, 0)
        case .left: (-90, 0)
        case .top: (0, -90)
        case .bottom: (0, 90)
        case .isometric: (35, -18)
        }
    }
}

/// `errorDescription` is what a person sees (the canvas's failure state); the case and its
/// payload, which keep the page's raw message, are what the log records (`String(describing:)`).
public enum WebRendererError: LocalizedError, Equatable {
    /// A call (or the page start) got no answer within its own budget.
    case timedOut
    /// WebContent died: a crash, jetsam on a huge file, or a sandbox denial.
    case webContentTerminated
    /// The page lost its WebGL context.
    case contextLost
    case navigationFailed(String)
    /// A page function threw; the payload is the function and the page's own message.
    case callFailed(String)
    /// Something broke in the page outside any call.
    case pageError(String)
    /// A call was made before the page reported `ready`.
    case notReady
    case missingRendererBundle
    /// The page answered with something that does not decode (a PNG, a pose, a result).
    case undecodableResult(String)
    /// The renderer measured a scene with no size — nothing to frame.
    case unmeasurableScene

    public var errorDescription: String? {
        switch self {
        case .timedOut:
            "The renderer took too long to respond."
        case .webContentTerminated:
            "The renderer stopped unexpectedly."
        case .contextLost:
            "The renderer lost its graphics context."
        case .navigationFailed, .missingRendererBundle:
            "The renderer couldn't start."
        case .callFailed, .pageError:
            "The model couldn't be displayed. The file may be damaged or use features the renderer doesn't support."
        case .notReady:
            "The renderer isn't ready yet."
        case .undecodableResult:
            "The renderer returned something unexpected."
        case .unmeasurableScene:
            "The model has no visible extent."
        }
    }

    /// User-facing text for any error a web canvas can end in. Anything that is not ours
    /// (a WebKit error, say) gets the generic renderer message rather than its raw text.
    public static func userMessage(for error: Error) -> String {
        (error as? WebRendererError)?.errorDescription ?? "The renderer couldn't display this model."
    }
}
