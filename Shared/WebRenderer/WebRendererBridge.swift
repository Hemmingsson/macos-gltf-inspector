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
        case fit
        case setToneMapping
        case setExposure
        case setEnvironmentRotation
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
    var value: Double?

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

    static func fit(id: Int) -> Self {
        Self(id: id, kind: .fit)
    }

    static func setToneMapping(id: Int, name: String) -> Self {
        var command = Self(id: id, kind: .setToneMapping)
        command.name = name
        return command
    }

    /// Exposure compensation in stops; the page converts to a linear factor.
    static func setExposure(id: Int, stops: Double) -> Self {
        var command = Self(id: id, kind: .setExposure)
        command.value = stops
        return command
    }

    static func setEnvironmentRotation(id: Int, degrees: Double) -> Self {
        var command = Self(id: id, kind: .setEnvironmentRotation)
        command.value = degrees
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
        if let value { object["value"] = value }
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
        }
    }
}
