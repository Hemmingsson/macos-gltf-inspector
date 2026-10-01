/// Something a renderer can do. Each renderer declares its set; host availability intersects it
/// with what the file offers.
public enum RendererFeature: String, Sendable, Hashable, Codable, CaseIterable {
    case wireframe
    /// Per-channel debug views (`RenderViewMode.channel`).
    case debugChannels
    case orthographicProjection
    case fileLights
    case environmentRotation
    case toneMapping
    case animationPlayback
    case morphTargets
    case skeletonOverlay
    /// Force `faceCulling = .none` on the live preview (RealityKit debug path).
    case doubleSided
    case materialVariants
    case nodeSelection
    /// Hide / solo individual nodes.
    case nodeVisibility
}
