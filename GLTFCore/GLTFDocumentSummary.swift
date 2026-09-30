import Foundation

/// Everything the inspector chrome needs about a file, read from its JSON alone — no renderer.
///
/// The WebKit window uses this instead of a RealityKit convert. Animation count is the file's
/// clips with a duration (what the outliner lists), not what a converter could play.
public struct GLTFDocumentSummary {
    public var document: GLTFSessionDocument
    public var stats: PreviewStats
    /// Nil when no mesh node has usable `POSITION` bounds.
    public var bounds: ModelBounds?
    public var materialVariantNames: [String]
    public var viewModes: [RenderViewMode]

    public init(
        document: GLTFSessionDocument,
        stats: PreviewStats,
        bounds: ModelBounds?,
        materialVariantNames: [String],
        viewModes: [RenderViewMode]
    ) {
        self.document = document
        self.stats = stats
        self.bounds = bounds
        self.materialVariantNames = materialVariantNames
        self.viewModes = viewModes
    }

    public init(json: [String: Any], fileURL: URL, fileSizeBytes: Int64?) {
        let document = GLTFDocumentJSON.makeDocument(json: json, fileURL: fileURL)
        self.init(
            document: document,
            stats: PreviewStats.from(
                json: json,
                animationCount: document.animations.filter { $0.duration > 0 }.count,
                fileSizeBytes: fileSizeBytes,
                resourceURL: fileURL
            ),
            bounds: ModelBounds.from(json: json),
            materialVariantNames: GLTFDocumentJSON.materialVariantNames(json: json),
            viewModes: ViewModeAvailability(json: json).viewModes
        )
    }

    /// Reads the `.gltf` JSON or the GLB JSON chunk (plus texture headers for the inspector).
    /// Throws for a file that is not glTF.
    public static func load(from url: URL) async throws -> GLTFDocumentSummary {
        try await Task.detached(priority: .userInitiated) {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let json = try GLBBox.peekDocumentJSON(from: url)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
            return GLTFDocumentSummary(json: json, fileURL: url, fileSizeBytes: size)
        }.value
    }
}
