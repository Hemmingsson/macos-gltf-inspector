import Foundation

/// Typed Swift side of the `viewer.html` command channel.
///
/// Every command must be expressible as JSON — if something needs a live object reference the
/// design is wrong and the work belongs in the page instead. Commands carry an `id` so replies
/// can be correlated; the page echoes it back on `result` and `failed`.
struct WebRendererCommand: Equatable {
    enum Kind: String {
        case configure
        case setEnvironment
        case load
        case setScene
        case setCamera
        case setCameraPose
        case getCamera
        case fit
        case setToneMapping
        case setDebugChannel
        case renderStill
    }

    var id: Int
    var kind: Kind
    var mode: String?
    var size: Int?
    var url: String?
    var index: Int?
    var azimuth: Double?
    var elevation: Double?
    var distance: Double?
    var name: String?
    var pose: CameraPose?

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

    static func setEnvironment(id: Int, url: String) -> Self {
        var command = Self(id: id, kind: .setEnvironment)
        command.url = url
        return command
    }

    static func load(id: Int, url: String) -> Self {
        var command = Self(id: id, kind: .load)
        command.url = url
        return command
    }

    static func setScene(id: Int, index: Int) -> Self {
        var command = Self(id: id, kind: .setScene)
        command.index = index
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

    static func setToneMapping(id: Int, name: String) -> Self {
        var command = Self(id: id, kind: .setToneMapping)
        command.name = name
        return command
    }

    static func setDebugChannel(id: Int, name: String) -> Self {
        var command = Self(id: id, kind: .setDebugChannel)
        command.name = name
        return command
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
        if let index { object["index"] = index }
        if let azimuth { object["azimuth"] = azimuth }
        if let elevation { object["elevation"] = elevation }
        if let distance { object["distance"] = distance }
        if let name { object["name"] = name }
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

enum WebRendererMode: String {
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
        self.camera = RendererCameraState(json: object)
    }
}

enum WebRendererError: LocalizedError, Equatable {
    /// The page never answered. Usually a WebContent that could not start.
    case timedOut
    /// WebContent died — the shape a sandbox denial takes.
    case webContentTerminated
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

    var errorDescription: String? {
        switch self {
        case .timedOut:
            "Web renderer did not respond"
        case .webContentTerminated:
            "Web content process terminated (sandbox denial?)"
        case .navigationFailed(let message):
            "Web renderer navigation failed: \(message)"
        case .commandFailed(let message):
            "Web renderer command failed: \(message)"
        case .pageError(let stage, let message):
            "Web renderer failed at \(stage): \(message)"
        case .notReady:
            "Web renderer is not ready yet"
        case .malformedMessage:
            "Web renderer sent a message that could not be understood"
        case .missingRendererBundle:
            "web-renderer resources missing from bundle"
        case .undecodableImage:
            "Web renderer returned an image that could not be decoded"
        case .unencodableCommand(let kind):
            "Could not encode '\(kind)' as JSON"
        case .undecodableCameraPose:
            "Web renderer returned an incomplete camera pose"
        case .unmeasurableScene:
            "Web renderer measured a scene with no extent"
        }
    }
}
