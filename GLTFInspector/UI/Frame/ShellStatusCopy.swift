import Foundation

/// Canvas / panel copy for non-ready document states.
///
/// Quiet chrome, DS tokens, no fake progress on `.failed` (AGENTS.md).
enum ShellStatusCopy {
    static let emptyTitle = "Open a glTF file"
    static let emptySidebarDetail = "No file open"
    /// Content-unavailable title. Sentence-style description is `emptyOpenHint`.
    static let emptyCanvasTitle = "No File"
    static let emptyOpenHint = "Drop a .glb or .gltf file here."
    /// Kept for call sites that still want one drop sentence.
    static let emptyDetail = emptyOpenHint
    static let loadingTitle = "Loading model…"
    static let failedTitle = "Couldn’t load model"
    /// Debug fixture for `.failed` — keep one string so previews and tests stay in sync.
    static let invalidFileDetail = "The file isn’t a valid glTF / GLB."
}
