import Foundation
import GLTFCore
import GLTFKit2
import RealityKit

public enum EntityLoader {
    /// A converted model plus the cheap glTF-header stats shown in the preview overlay.
    /// Its entity stays inside the renderer; the host reads the neutral fields and calls the
    /// `LoadedModel` helpers.
    public struct LoadedModel {
        let entity: Entity
        public let stats: PreviewStats
        public let document: GLTFSessionDocument
        public let debugModes: [PreviewDebugMode]
        /// Computed once at load; avoid re-walking the entity tree on every host view refresh.
        public let studioIBLExponent: Float
        /// What convert and policy did (spec-gloss, Draco, emissive drop, studio dim).
        public let pipelineReport: PreparePipelineReport
        /// Convert losses (missing textures, dropped primitives, ignored extensions).
        public let convertProblems: ConvertProblemReport
        /// `KHR_materials_variants` names from GLTFKit2 (`materialVariants`). Empty when absent.
        public let materialVariantNames: [String]
    }

    /// Finder thumbnails only need a mesh + IBL exponent — no session document / overlay stats.
    struct ThumbnailModel {
        let entity: Entity
        let studioIBLExponent: Float
    }

    @MainActor
    static func punctualLightCount(in entity: Entity) -> Int {
        var count = 0
        if entity.components[PointLightComponent.self] != nil { count += 1 }
        if entity.components[SpotLightComponent.self] != nil { count += 1 }
        if entity.components[DirectionalLightComponent.self] != nil { count += 1 }
        for child in entity.children {
            count += punctualLightCount(in: child)
        }
        return count
    }

    /// The file as authored: its JSON (sidebar document, overlay stats, debug modes, report) and
    /// the directory GLTFKit2 resolves sidecar buffers and images against.
    private struct Source {
        let url: URL
        let directory: URL
        let json: [String: Any]
        let fileSize: Int64?
    }

    /// One converted scene plus what convert-time rewrites did to it.
    private struct Converted {
        let build: RealityKitConvert.BuildResult
        let specGloss: SpecGlossBake.Result
        var entity: Entity { build.entity }
    }

    /// Loads a self-contained `.glb` or a sidecar `.gltf` (buffers/textures next to the JSON).
    /// Thumbnails should use `loadThumbnail` — Finder icons never play clips,
    /// and GLTFKit2 still traps on some zero-stride Sketchfab “Default Take” channels
    /// that slip past the duration filter.
    /// File IO and `GLTFAsset` stay off the main actor so Spacebar can show the loading
    /// view while the file is parsed; RealityKit convert hops to the main actor.
    public static func load(
        from url: URL,
        includeAnimations: Bool = true,
        materialVariantIndex: Int? = nil,
        sceneIndex: Int? = nil
    ) async throws -> LoadedModel {
        try await withSource(url) { source in
            // Parsed from the file, not harvested from convert: the outliner must list what the
            // file contains even where the renderer drops or rewrites it.
            let document = GLTFDocumentJSON.makeDocument(json: source.json, fileURL: url)
            let variantNames = GLTFDocumentJSON.materialVariantNames(json: source.json)
            let converted = try await convertAsset(
                source,
                includeAnimations: includeAnimations,
                sceneIndex: sceneIndex,
                materialVariantIndex: materialVariantIndex
            )
            var report = PreparePipelineReport()
            report.extensionsUsed = PreparePipelineReport.captureExtensions(from: source.json)
            report.decompressedDraco = PreparePipelineReport.sourceHadDraco(source.json)
            report.specGlossToMetalRough = converted.specGloss.converted
            report.bakedSpecGlossTextures = converted.specGloss.baked
            return await loadedModel(
                build: converted.build,
                document: document,
                json: source.json,
                fileSizeBytes: source.fileSize,
                resourceURL: url,
                pipelineReport: report,
                materialVariantNames: variantNames
            )
        }
    }

    /// Thumbnail path: Entity + studio IBL exponent only. Skips session document,
    /// PreviewStats, and PreviewDebugMode. Animations are always stripped. `maxTextureEdge`
    /// caps uploaded texture size (Finder icons).
    static func loadThumbnail(from url: URL, maxTextureEdge: Int? = nil) async throws -> ThumbnailModel {
        try await withSource(url) { source in
            let entity = try await convertAsset(
                source,
                includeAnimations: false,
                sceneIndex: nil,
                materialVariantIndex: nil,
                maxTextureEdge: maxTextureEdge
            ).entity
            let exponent = await MainActor.run {
                RealityPolicy.studioIBLExponent(
                    punctualLightCount: punctualLightCount(in: entity)
                )
            }
            return ThumbnailModel(entity: entity, studioIBLExponent: exponent)
        }
    }

    /// Converts one scene of the file without rebuilding `LoadedModel`. Host scene switching
    /// uses this after listing `document.scenes`; Quick Look keeps calling `load` only.
    static func convertScene(
        index: Int,
        from url: URL,
        includeAnimations: Bool = true,
        materialVariantIndex: Int? = nil
    ) async throws -> Entity {
        try await withSource(url) { source in
            try await convertAsset(
                source,
                includeAnimations: includeAnimations,
                sceneIndex: index,
                materialVariantIndex: materialVariantIndex
            ).entity
        }
    }

    /// Scoped access to the file and its folder (sidecar `.gltf` buffers / textures), plus the
    /// authored JSON. Sidecar URIs must stay inside the folder.
    private static func withSource<T>(
        _ url: URL,
        work: (Source) async throws -> T
    ) async throws -> T {
        GLTFAsset.dracoDecompressorClassName = "GLBDracoDecompressor"

        let directory = URL(fileURLWithPath: url.deletingLastPathComponent().path, isDirectory: true)
        let accessedDirectory = directory.startAccessingSecurityScopedResource()
        let accessedFile = url.startAccessingSecurityScopedResource()
        defer {
            if accessedDirectory {
                directory.stopAccessingSecurityScopedResource()
            }
            if accessedFile {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let json: [String: Any]
        if url.pathExtension.lowercased() == "glb" {
            json = (try? GLBBox.peekJSON(from: url)) ?? [:]
        } else {
            json = try GLBBox.parseJSON(Data(contentsOf: url, options: [.mappedIfSafe]))
        }
        for uri in externalURIs(in: json) where !isAllowedSidecarURI(uri, assetDirectory: directory) {
            throw GLTFInspectorError.make(1021, "glTF sidecar URI is not a safe relative path")
        }
        return try await work(Source(url: url, directory: directory, json: json, fileSize: fileSizeBytes(of: url)))
    }

    private static func fileSizeBytes(of url: URL) -> Int64? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        return size.map(Int64.init)
    }

    @MainActor
    private static func loadedModel(
        build: RealityKitConvert.BuildResult,
        document: GLTFSessionDocument,
        json: [String: Any],
        fileSizeBytes: Int64?,
        resourceURL: URL,
        pipelineReport: PreparePipelineReport,
        materialVariantNames: [String]
    ) -> LoadedModel {
        let entity = build.entity
        var report = pipelineReport
        let exponent = RealityPolicy.studioIBLExponent(
            punctualLightCount: punctualLightCount(in: entity)
        )
        report.dimmedStudioIBL = exponent < 0
        report.droppedBakedEmissive = build.droppedBakedEmissive
        let convertProblems = build.problems
            .mergingIgnoredExtensions(from: report.extensionsUsed)
        return LoadedModel(
            entity: entity,
            stats: PreviewStats.from(
                json: json,
                animationCount: entity.availableAnimations.count,
                fileSizeBytes: fileSizeBytes,
                resourceURL: resourceURL
            ),
            document: document,
            debugModes: PreviewDebugMode.available(from: json),
            studioIBLExponent: exponent,
            pipelineReport: report,
            convertProblems: convertProblems,
            materialVariantNames: materialVariantNames
        )
    }

    private static func convertAsset(
        _ source: Source,
        includeAnimations: Bool,
        sceneIndex: Int?,
        materialVariantIndex: Int?,
        maxTextureEdge: Int? = nil
    ) async throws -> Converted {
        let name = source.url.lastPathComponent
        let asset = try GLTFAsset(
            url: source.url,
            options: [GLTFAssetLoadingOption.assetDirectoryURLKey: source.directory]
        )
        if let materialVariantIndex {
            MaterialVariants.apply(variantIndex: materialVariantIndex, to: asset)
        }
        let specGloss = SpecGlossBake.apply(to: asset)
        // Drop 1-keyframe "Default Take" clips. Convert also rejects a zero stride,
        // but empty takes are still useless to play.
        if includeAnimations {
            asset.animations = asset.animations.filter { AnimationSampling.hasPositiveDuration($0) }
        } else {
            asset.animations = []
        }
        let scene: GLTFScene
        if let sceneIndex {
            guard sceneIndex >= 0, sceneIndex < asset.scenes.count else {
                AppLog.error(AppLog.load, "scene index \(sceneIndex) out of range for \(name)")
                throw GLTFInspectorError.make(1020, "The glTF asset does not contain scene index \(sceneIndex)")
            }
            scene = asset.scenes[sceneIndex]
        } else if let defaultScene = asset.defaultScene {
            scene = defaultScene
        } else {
            AppLog.error(AppLog.load, "no default scene for \(name)")
            throw GLTFInspectorError.make(1020, "The glTF asset did not specify a default scene")
        }
        let build = try await MainActor.run {
            do {
                return try RealityKitConvert.build(scene: scene, asset: asset, maxTextureEdge: maxTextureEdge)
            } catch {
                AppLog.error(AppLog.load, error.localizedDescription)
                throw convertFailure(from: error)
            }
        }
        return Converted(build: build, specGloss: specGloss)
    }

    @MainActor
    static func clipDuration(_ resource: AnimationResource, on entity: Entity) -> TimeInterval? {
        let probe = entity.playAnimation(resource, startsPaused: true)
        let duration = probe.duration
        probe.stop()
        guard duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    @MainActor
    static func modelComponentCount(in entity: Entity) -> Int {
        var count = entity.components[ModelComponent.self] != nil ? 1 : 0
        for child in entity.children {
            count += modelComponentCount(in: child)
        }
        return count
    }

    private static func convertFailure(from error: Error) -> NSError {
        let nsError = error as NSError
        if nsError.domain == GLTFInspectorError.domain, nsError.code == 1022 || nsError.code == 1023 {
            return nsError
        }
        return GLTFInspectorError.make(1022, "Failed to convert the glTF asset")
    }

    /// Buffer and image URIs other than embedded `data:` payloads.
    private static func externalURIs(in json: [String: Any]) -> [String] {
        let entries = (json["buffers"] as? [[String: Any]] ?? []) + (json["images"] as? [[String: Any]] ?? [])
        return entries.compactMap { $0["uri"] as? String }.filter { !$0.lowercased().hasPrefix("data:") }
    }

    /// Sidecars must stay inside the asset directory: no `..`, no absolute paths,
    /// no `file:` / `http:` / `https:`. Resolved URL must have the standardized
    /// directory path as a prefix (`dir/` not `dir-evil`).
    private static func isAllowedSidecarURI(_ uri: String, assetDirectory: URL) -> Bool {
        let raw = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        let decoded = raw.removingPercentEncoding ?? raw
        let scheme = raw.lowercased()
        if scheme.hasPrefix("file:") || scheme.hasPrefix("http:") || scheme.hasPrefix("https:") {
            return false
        }
        if raw.contains("..") || decoded.contains("..") {
            return false
        }
        if raw.hasPrefix("/") || decoded.hasPrefix("/") {
            return false
        }
        let resolved = assetDirectory.appendingPathComponent(decoded).standardizedFileURL
        var rootPath = assetDirectory.standardizedFileURL.path
        if !rootPath.hasSuffix("/") {
            rootPath.append("/")
        }
        return resolved.path.hasPrefix(rootPath)
    }

}

