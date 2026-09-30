/// The whole look a renderer applies to a model, in renderer-neutral units.
///
/// Each renderer maps this in one place and applies it whole. Nothing reads it yet: this is the
/// contract the renderer mappings move onto.
///
/// Per-renderer mapping constants, from the look probes (`.agents/research/2026-09-30-look-probes.md`).
/// Documented here only; no renderer applies them yet.
///
/// | Field | RealityKit | WebKit (Khronos page) |
/// | --- | --- | --- |
/// | `environmentYawDegrees` Y | IBL yaw = π − Y (radians) | page rotation = 90 + Y |
/// | punctual intensity | ×591 (point/spot) | as authored |
/// | spot cone | intensity ×π, cone angle ×2 | as authored |
public struct RenderLook: Sendable, Hashable, Codable {
    /// Exposure compensation in EV (stops). Scales all light before tone mapping.
    public var exposureEV: Double
    /// Linear multiplier on the image-based light.
    public var environmentIntensity: Double
    /// Environment rotation about +Y in degrees. 0 is the Khronos sample viewer's default view.
    public var environmentYawDegrees: Double
    /// Whether the bundled environment lights the model at all.
    public var usesEnvironment: Bool
    /// Which bundled Khronos environment.
    public var environment: KhronosEnvironments
    public var toneMapping: ToneMapping
    public var background: Color
    /// Use the file's `KHR_lights_punctual` lights (the renderer owns how the studio dims for them).
    public var usesFileLights: Bool

    public static let standard = RenderLook(
        exposureEV: 0,
        environmentIntensity: 1,
        environmentYawDegrees: 0,
        usesEnvironment: true,
        environment: .defaultLook,
        toneMapping: .pbrNeutral,
        background: .clear,
        usesFileLights: false
    )

    public init(
        exposureEV: Double,
        environmentIntensity: Double,
        environmentYawDegrees: Double,
        usesEnvironment: Bool,
        environment: KhronosEnvironments,
        toneMapping: ToneMapping,
        background: Color,
        usesFileLights: Bool
    ) {
        self.exposureEV = exposureEV
        self.environmentIntensity = environmentIntensity
        self.environmentYawDegrees = environmentYawDegrees
        self.usesEnvironment = usesEnvironment
        self.environment = environment
        self.toneMapping = toneMapping
        self.background = background
        self.usesFileLights = usesFileLights
    }

    /// Tone-mapping curve. Raw values are the Khronos sample renderer's names, which is also how
    /// Settings stores them.
    public enum ToneMapping: String, Sendable, Hashable, Codable, CaseIterable {
        case pbrNeutral = "Khronos PBR Neutral"
        case acesHill = "ACES Filmic Tone Mapping (Hill)"
        case acesNarkowicz = "ACES Filmic Tone Mapping (Narkowicz)"
        case none = "None (Linear mapping, clamped at 1.0)"
    }

    /// Straight (not premultiplied) sRGB colour, 0...1.
    public struct Color: Sendable, Hashable, Codable {
        public var red: Double
        public var green: Double
        public var blue: Double
        public var alpha: Double

        public static let clear = Color(red: 0, green: 0, blue: 0, alpha: 0)

        public init(red: Double, green: Double, blue: Double, alpha: Double) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }
    }
}
