/// The lighting look applied to a model: what Settings stores and the window's lighting popover
/// edits, in the Khronos Sample Renderer's terms.
public struct RenderLook: Sendable, Hashable, Codable {
    /// Exposure compensation in EV (stops). Scales all light before tone mapping.
    public var exposureEV: Double
    /// Linear multiplier on the image-based light.
    public var environmentIntensity: Double
    /// Environment rotation about +Y in degrees. 0 is the Khronos sample viewer's default view.
    public var environmentYawDegrees: Double
    /// Which bundled lighting environment.
    public var environment: LightingEnvironment
    public var toneMapping: ToneMapping
    public var background: Color

    public static let standard = RenderLook(
        exposureEV: 0,
        environmentIntensity: 1,
        environmentYawDegrees: 0,
        environment: .defaultLook,
        toneMapping: .pbrNeutral,
        background: .clear
    )

    public init(
        exposureEV: Double,
        environmentIntensity: Double,
        environmentYawDegrees: Double,
        environment: LightingEnvironment,
        toneMapping: ToneMapping,
        background: Color
    ) {
        self.exposureEV = exposureEV
        self.environmentIntensity = environmentIntensity
        self.environmentYawDegrees = environmentYawDegrees
        self.environment = environment
        self.toneMapping = toneMapping
        self.background = background
    }

    /// Tone-mapping curve. Raw values are the Khronos sample renderer's names, which is also how
    /// Settings stores them. PBR Neutral is the review default; ACES is offered for DCC parity.
    public enum ToneMapping: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
        case pbrNeutral = "Khronos PBR Neutral"
        case acesHill = "ACES Filmic Tone Mapping (Hill)"
        case acesNarkowicz = "ACES Filmic Tone Mapping (Narkowicz)"
        case none = "None (Linear mapping, clamped at 1.0)"

        public var id: Self { self }

        public var title: String {
            switch self {
            case .pbrNeutral: "Neutral"
            case .acesHill: "ACES"
            case .acesNarkowicz: "ACES Fast"
            case .none: "Linear"
            }
        }
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
