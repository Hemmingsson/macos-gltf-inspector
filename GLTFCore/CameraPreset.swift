/// Canned orbit-camera angles. File cameras are separate.
public enum CameraPreset: String, Sendable, Hashable, Codable, CaseIterable {
    case front
    case back
    case left
    case right
    case top
    case bottom
    case isometric
}

public enum RenderCamera {
    /// Vertical field of view of the orbit camera before the user changes it.
    public static let defaultFieldOfViewDegrees: Float = 35
}
