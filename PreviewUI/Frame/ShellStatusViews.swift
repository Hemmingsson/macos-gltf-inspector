import Foundation

/// Canvas / panel copy for non-ready document states.
///
/// Quiet chrome, DS tokens, no fake progress on `.failed` (AGENTS.md).
public enum ShellStatusCopy {
    public static let emptyTitle = "Open a glTF file"
    public static let emptyDetail = "Drop a .glb or .gltf here, or choose File → Open…"
    public static let loadingTitle = "Loading model…"
    public static let failedTitle = "Couldn’t load model"
    /// Debug fixture for `.failed` — keep one string so previews and tests stay in sync.
    public static let invalidFileDetail = "The file isn’t a valid glTF / GLB."
}
