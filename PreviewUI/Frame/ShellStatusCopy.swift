import Foundation

/// Canvas / panel copy for non-ready document states.
///
/// Quiet chrome, DS tokens, no fake progress on `.failed` (AGENTS.md).
public enum ShellStatusCopy {
    public static let emptyTitle = "Open a glTF file"
    public static let emptySidebarDetail = "No file open"
    /// Content-unavailable title. Sentence-style description is `emptyOpenHint`.
    public static let emptyCanvasTitle = "No File"
    public static let emptyOpenHint = "Drop a .glb or .gltf file here."
    /// Kept for call sites that still want one drop sentence.
    public static let emptyDetail = emptyOpenHint
    public static let loadingTitle = "Loading model…"
    public static let failedTitle = "Couldn’t load model"
    /// Debug fixture for `.failed` — keep one string so previews and tests stay in sync.
    public static let invalidFileDetail = "The file isn’t a valid glTF / GLB."
}
