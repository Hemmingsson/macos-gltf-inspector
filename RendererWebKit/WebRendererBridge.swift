import Foundation
import GLTFCore

/// Typed Swift side of the `viewer.html` command channel.
///
/// Every command must be expressible as JSON — if something needs a live object reference the
/// design is wrong and the work belongs in the page instead. Commands carry an `id` so replies
/// can be correlated; the page echoes it back on `result` and `failed`.
struct WebRendererCommand: Equatable {
    enum Kind: String {
        case configure
        case apply
        case load
        case setCamera
        case setCameraPose
        case getCamera
        case fit
        case renderStill
    }

    var id: Int
    var kind: Kind
    var mode: String?
    var size: Int?
    var url: String?
    var azimuth: Double?
    var elevation: Double?
    var distance: Double?
    var pose: CameraPose?
    var look: PageLook?

    private init(id: Int, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    static func configure(id: Int, mode: WebRendererMode, size: Int?) -> Self {
        var command = Self(id: id, kind: .configure)
        command.mode = mode.rawValue
        command.size = size
        return command
    }

    /// The whole look; the page decides what actually changed.
    static func apply(id: Int, look: PageLook) -> Self {
        var command = Self(id: id, kind: .apply)
        command.look = look
        return command
    }

    static func load(id: Int, url: String) -> Self {
        var command = Self(id: id, kind: .load)
        command.url = url
        return command
    }

    /// Angles in degrees; the page converts. `distance` nil leaves the current dolly alone.
    static func setCamera(id: Int, azimuth: Double, elevation: Double, distance: Double?) -> Self {
        var command = Self(id: id, kind: .setCamera)
        command.azimuth = azimuth
        command.elevation = elevation
        command.distance = distance
        return command
    }

    /// The whole camera stated outright, so a change to the renderer's fit heuristic cannot
    /// move it. `setCamera` above deliberately inherits distance and target from the last fit;
    /// this one inherits nothing.
    static func setCameraPose(id: Int, pose: CameraPose) -> Self {
        var command = Self(id: id, kind: .setCameraPose)
        command.pose = pose
        return command
    }

    /// Reads the current pose back, for recording one after a fit.
    static func getCamera(id: Int) -> Self {
        Self(id: id, kind: .getCamera)
    }

    static func fit(id: Int) -> Self {
        Self(id: id, kind: .fit)
    }

    static func renderStill(id: Int) -> Self {
        Self(id: id, kind: .renderStill)
    }

    /// JSON object literal for `__viewer.exec(...)`. Nil fields are omitted so the page can use
    /// plain `undefined` checks rather than distinguishing null from absent.
    func jsonObject() -> [String: Any] {
        var object: [String: Any] = ["id": id, "type": kind.rawValue]
        if let mode { object["mode"] = mode }
        if let size { object["size"] = size }
        if let url { object["url"] = url }
        if let azimuth { object["azimuth"] = azimuth }
        if let elevation { object["elevation"] = elevation }
        if let distance { object["distance"] = distance }
        if let look,
           let data = try? JSONEncoder().encode(look),
           let json = try? JSONSerialization.jsonObject(with: data) {
            object["look"] = json
        }
        if let pose {
            object["target"] = pose.target
            object["distance"] = pose.distance
            object["azimuth"] = pose.azimuth
            object["elevation"] = pose.elevation
            object["yfov"] = pose.yfov
            object["znear"] = pose.znear
            object["zfar"] = pose.zfar
        }
        return object
    }

    /// `__viewer.exec({...})` with the payload inlined, ready for `evaluateJavaScript`.
    ///
    /// `void` is load-bearing: `exec` is async, and handing `evaluateJavaScript` a Promise fails
    /// with `WKError 5, "JavaScript execution returned a result of an unsupported type"`. The
    /// real reply arrives on the message handler, not from this call.
    func javaScript() throws -> String {
        let data = try JSONSerialization.data(withJSONObject: jsonObject(), options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw WebRendererError.unencodableCommand(kind.rawValue)
        }
        return "void window.__viewer.exec(\(json))"
    }
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

    /// Nil for anything the renderer could not express as finite numbers — an unfitted camera
    /// carries `zfar == .infinity`, which no recorded pose should contain.
    init?(json: [String: Any]) {
        guard
            let azimuth = json["azimuth"] as? Double,
            let elevation = json["elevation"] as? Double,
            let distance = json["distance"] as? Double,
            let target = json["target"] as? [Double], target.count == 3,
            let yfov = json["yfov"] as? Double,
            let znear = json["znear"] as? Double,
            let zfar = json["zfar"] as? Double
        else { return nil }

        self.azimuth = azimuth
        self.elevation = elevation
        self.distance = distance
        self.target = target
        self.yfov = yfov
        self.znear = znear
        self.zfar = zfar
        guard isFinite else { return nil }
    }

    init(
        azimuth: Double,
        elevation: Double,
        distance: Double,
        target: [Double],
        yfov: Double,
        znear: Double,
        zfar: Double
    ) {
        self.azimuth = azimuth
        self.elevation = elevation
        self.distance = distance
        self.target = target
        self.yfov = yfov
        self.znear = znear
        self.zfar = zfar
    }

    var isFinite: Bool {
        ([azimuth, elevation, distance, yfov, znear, zfar] + target).allSatisfy(\.isFinite)
    }
}

/// The world-space box the renderer measured for the current scene, and the pose it is looking
/// at it from.
///
/// The bounds come along because a caller that wants to frame the model on its own terms needs
/// them: `pose.distance` only reports where this version of the renderer put the camera.
struct RendererCameraState: Equatable, Sendable {
    var pose: CameraPose
    var sceneMin: [Double]
    var sceneMax: [Double]

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

    init?(json: [String: Any]) {
        guard
            let camera = json["camera"] as? [String: Any],
            let pose = CameraPose(json: camera),
            let sceneMin = json["sceneMin"] as? [Double],
            let sceneMax = json["sceneMax"] as? [Double]
        else { return nil }
        self.pose = pose
        self.sceneMin = sceneMin
        self.sceneMax = sceneMax
    }
}

extension RendererCameraState {
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

public enum WebRendererMode: String {
    /// No window, render one frame, hand back pixels. Finder thumbnails.
    case still
    /// Hosted in a view, continuous rendering. Document window and Quick Look.
    case live
}

/// One message from the page.
struct WebRendererEvent: Equatable {
    enum Name: String {
        /// Page is up and `__viewer` is installed.
        case ready
        /// A command succeeded; `id` matches.
        case result
        /// A command threw; `id` matches.
        case failed
        /// Something outside a command handler broke.
        case error
        /// Load-stage ping from the page. Not tied to a command id.
        case progress
        /// A `console.error` from the renderer — Khronos reports many load problems that way.
        case warning
        /// `webglcontextlost`: nothing the page holds on the GPU is valid any more.
        case contextLost = "contextlost"
    }

    var name: Name
    var id: Int?
    var message: String?
    var stage: String?
    var png: String?
    var triangles: Int?
    var meshes: Int?
    var sceneCount: Int?
    var animationCount: Int?
    var mode: String?
    var width: Int?
    var height: Int?
    var parseMs: Int?
    var fitMs: Int?
    /// Live `load` only: first `renderFrame` after parse. Zero in still mode.
    var firstFrameMs: Int?
    var camera: RendererCameraState?

    /// Returns nil for a body that is not a recognisable event, so the host can report a
    /// malformed message rather than silently ignoring it.
    init?(body: Any) {
        guard
            let object = body as? [String: Any],
            let raw = object["event"] as? String,
            let name = Name(rawValue: raw)
        else { return nil }

        self.name = name
        self.id = object["id"] as? Int
        self.message = object["message"] as? String
        self.stage = object["stage"] as? String
        self.png = object["png"] as? String
        self.triangles = object["triangles"] as? Int
        self.meshes = object["meshes"] as? Int
        self.sceneCount = object["sceneCount"] as? Int
        self.animationCount = object["animationCount"] as? Int
        self.mode = object["mode"] as? String
        self.width = Self.intValue(object, "width")
        self.height = Self.intValue(object, "height")
        self.parseMs = Self.intValue(object, "parseMs")
        self.fitMs = Self.intValue(object, "fitMs")
        self.firstFrameMs = Self.intValue(object, "firstFrameMs")
        self.camera = RendererCameraState(json: object)
    }

    /// JS numbers arrive as `Int` or `Double` depending on the bridge.
    private static func intValue(_ object: [String: Any], _ key: String) -> Int? {
        if let value = object[key] as? Int { return value }
        if let value = object[key] as? Double { return Int(value) }
        return nil
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
    /// A command handler in the page threw.
    case commandFailed(String)
    /// Something broke outside a command handler.
    case pageError(stage: String, message: String)
    /// A command was sent before the page reported `ready`.
    case notReady
    case malformedMessage
    case missingRendererBundle
    case undecodableImage
    case unencodableCommand(String)
    /// The page answered `getCamera` with something that is not a complete, finite pose.
    case undecodableCameraPose
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
        case .navigationFailed, .missingRendererBundle, .malformedMessage:
            "The renderer couldn't start."
        case .commandFailed, .pageError:
            "The model couldn't be displayed. The file may be damaged or use features the renderer doesn't support."
        case .notReady:
            "The renderer isn't ready yet."
        case .undecodableImage, .unencodableCommand, .undecodableCameraPose:
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
