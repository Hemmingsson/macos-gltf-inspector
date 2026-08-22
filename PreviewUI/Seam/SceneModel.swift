import Foundation

/// Read-only introspection of one loaded file. Value-type backed: an implementation is a
/// snapshot, never a live object the UI can write to.
///
/// The shell conforms with invented fixtures; the real app conforms with a thin adapter over
/// the converted document (UI-BUILD §0). The UI never learns which one it has.
protocol SceneModel: Sendable {
    /// Display name for the sidebar header ("Duck.glb").
    var fileName: String { get }

    /// Every scene in the file, in file order.
    var scenes: [SceneInfo] { get }
    /// The scene glTF marks as default.
    var defaultSceneID: NodeID? { get }

    /// Typed node hierarchy (mesh / camera / light / skin / empty), roots first.
    var nodeTree: [SceneNode] { get }

    var cameras: [CameraInfo] { get }
    var lights: [LightInfo] { get }
    /// Materials with the set of maps each one actually carries.
    var materials: [MaterialInfo] { get }
    /// Usable clips with their durations.
    var animations: [AnimationInfo] { get }
    var skins: [SkinInfo] { get }
    var morphs: [MorphInfo] { get }
    /// `KHR_materials_variants` names in file order. Empty when the extension is absent.
    var materialVariantNames: [String] { get }

    var stats: Stats { get }
    var dimensions: Dimensions { get }
    /// glTF-validator findings, surfaced as-is.
    var validation: ValidationResult { get }
    /// Everything our import changed, so nothing is silently altered.
    var pipelineReport: PipelineReport { get }
}

extension SceneModel {
    var defaultSceneID: NodeID? { scenes.first?.id }
    var materialVariantNames: [String] { [] }

    /// Depth-first lookup without allocating a full flatten.
    func node(_ id: NodeID) -> SceneNode? {
        func walk(_ nodes: [SceneNode]) -> SceneNode? {
            for node in nodes {
                if node.id == id { return node }
                if let found = walk(node.children) { return found }
            }
            return nil
        }
        return walk(nodeTree)
    }
}
