import Foundation
import GLTFKit2
import RealityKit

enum EntityLoader {
    /// A converted model plus the cheap glTF-header stats shown in the preview overlay.
    struct LoadedModel {
        let entity: Entity
        let stats: PreviewStats
        let document: GLTFSessionDocument
        let debugModes: [PreviewDebugMode]
        /// Computed once at load; avoid re-walking the entity tree on every host view refresh.
        let studioIBLExponent: Float
        /// What prepare/convert did. Empty for plain metal-rough assets.
        let pipelineReport: PreparePipelineReport
        /// Convert losses (missing textures, dropped primitives, ignored extensions).
        let convertProblems: ConvertProblemReport
        /// `KHR_materials_variants` names from GLTFKit2 (`materialVariants`). Empty when absent.
        let materialVariantNames: [String]
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

    private struct PreparedLoad {
        let loadURL: URL
        let originalURL: URL
        let assetDirectory: URL
        let fallbackDirectory: URL
        let sourceJSON: [String: Any]
        let fileSize: Int64?
        var pipelineReport: PreparePipelineReport
    }

    /// Loads a self-contained `.glb` or a sidecar `.gltf` (buffers/textures next to the JSON).
    /// Thumbnails should use `loadThumbnail` — Finder icons never play clips,
    /// and GLTFKit2 still traps on some zero-stride Sketchfab “Default Take” channels
    /// that slip past the duration filter.
    /// File IO and `GLTFAsset` stay off the main actor so Spacebar can show the loading
    /// view while the file is parsed; RealityKit convert hops to the main actor.
    static func load(
        from url: URL,
        includeAnimations: Bool = true,
        materialVariantIndex: Int? = nil
    ) async throws -> LoadedModel {
        try await withPreparedAsset(from: url) { prepared in
            let (entity, document, variantNames) = try await convertPreparedOrOriginal(
                prepared,
                includeAnimations: includeAnimations,
                name: url.lastPathComponent,
                sceneIndex: nil,
                buildDocument: true,
                materialVariantIndex: materialVariantIndex
            )
            return await loadedModel(
                entity: entity,
                document: document,
                json: prepared.sourceJSON,
                fileSizeBytes: prepared.fileSize,
                resourceURL: prepared.loadURL,
                pipelineReport: prepared.pipelineReport,
                materialVariantNames: variantNames
            )
        }
    }

    /// Thumbnail path: Entity + studio IBL exponent only. Skips session document,
    /// PreviewStats, and PreviewDebugMode. Animations are always stripped.
    static func loadThumbnail(from url: URL) async throws -> ThumbnailModel {
        try await withPreparedAsset(from: url) { prepared in
            let (entity, _, _) = try await convertPreparedOrOriginal(
                prepared,
                includeAnimations: false,
                name: url.lastPathComponent,
                sceneIndex: nil,
                buildDocument: false,
                materialVariantIndex: nil
            )
            let exponent = await MainActor.run {
                PreviewEmissive.studioIBLExponent(
                    punctualLightCount: punctualLightCount(in: entity)
                )
            }
            return ThumbnailModel(entity: entity, studioIBLExponent: exponent)
        }
    }

    /// Converts one scene from the same prepared asset path as `load`, without
    /// rebuilding `LoadedModel`. Host scene switching uses this after listing
    /// `document.scenes`; Quick Look keeps calling `load` only.
    static func convertScene(
        index: Int,
        from url: URL,
        includeAnimations: Bool = true,
        materialVariantIndex: Int? = nil
    ) async throws -> Entity {
        try await withPreparedAsset(from: url) { prepared in
            let (entity, _, _) = try await convertPreparedOrOriginal(
                prepared,
                includeAnimations: includeAnimations,
                name: url.lastPathComponent,
                sceneIndex: index,
                buildDocument: false,
                materialVariantIndex: materialVariantIndex
            )
            return entity
        }
    }

    private static func convertPreparedOrOriginal(
        _ prepared: PreparedLoad,
        includeAnimations: Bool,
        name: String,
        sceneIndex: Int?,
        buildDocument: Bool,
        materialVariantIndex: Int?
    ) async throws -> (Entity, GLTFSessionDocument, [String]) {
        do {
            return try await convertAsset(
                at: prepared.loadURL,
                assetDirectory: prepared.assetDirectory,
                includeAnimations: includeAnimations,
                name: name,
                sceneIndex: sceneIndex,
                buildDocument: buildDocument,
                materialVariantIndex: materialVariantIndex
            )
        } catch {
            guard prepared.loadURL != prepared.originalURL else { throw error }
            AppLog.error(AppLog.prepare, "prepared GLB produced no mesh, retrying original")
            return try await convertAsset(
                at: prepared.originalURL,
                assetDirectory: prepared.fallbackDirectory,
                includeAnimations: includeAnimations,
                name: name,
                sceneIndex: sceneIndex,
                buildDocument: buildDocument,
                materialVariantIndex: materialVariantIndex
            )
        }
    }

    private static func withPreparedAsset<T>(
        from url: URL,
        work: (PreparedLoad) async throws -> T
    ) async throws -> T {
        GLTFAsset.dracoDecompressorClassName = "GLBDracoDecompressor"

        let directoryURL = URL(
            fileURLWithPath: url.deletingLastPathComponent().path,
            isDirectory: true
        )
        let accessedDirectory = directoryURL.startAccessingSecurityScopedResource()
        let accessedFile = url.startAccessingSecurityScopedResource()
        defer {
            if accessedDirectory {
                directoryURL.stopAccessingSecurityScopedResource()
            }
            if accessedFile {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Parse the glTF header once for prepare gates, then keep the JSON that
        // actually gets converted so overlay stats match RealityKit.
        let isGLB = url.pathExtension.lowercased() == "glb"
        let (fileSize, loadURL, assetDirectory, statsJSON, pipelineReport) = try {
            let fileSize = fileSizeBytes(of: url)
            if isGLB {
                let sourceJSON = (try? GLBBox.peekJSON(from: url)) ?? [:]
                let prepared = prepareGLB(url, json: sourceJSON)
                return (fileSize, prepared.url, directoryURL, prepared.json, prepared.report)
            } else {
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                let sourceJSON = try GLBBox.parseJSON(data)
                let prepared = try packAndPrepareGLTF(
                    from: url,
                    directoryURL: directoryURL,
                    json: sourceJSON
                )
                return (fileSize, prepared.url, prepared.assetDirectory, prepared.json, prepared.report)
            }
        }()
        // Prepared/packed GLBs are throwaway temp files; the retry path below only ever
        // reopens the original `url`, so the temp is safe to delete once loading finishes.
        defer {
            if loadURL != url {
                try? FileManager.default.removeItem(at: loadURL)
            }
        }

        return try await work(
            PreparedLoad(
                loadURL: loadURL,
                originalURL: url,
                assetDirectory: assetDirectory,
                fallbackDirectory: directoryURL,
                sourceJSON: statsJSON,
                fileSize: fileSize,
                pipelineReport: pipelineReport
            )
        )
    }

    private static func fileSizeBytes(of url: URL) -> Int64? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        return size.map(Int64.init)
    }

    @MainActor
    private static func loadedModel(
        entity: Entity,
        document: GLTFSessionDocument,
        json: [String: Any],
        fileSizeBytes: Int64?,
        resourceURL: URL,
        pipelineReport: PreparePipelineReport,
        materialVariantNames: [String]
    ) -> LoadedModel {
        var report = pipelineReport
        let exponent = PreviewEmissive.studioIBLExponent(
            punctualLightCount: punctualLightCount(in: entity)
        )
        report.dimmedStudioIBL = exponent < 0
        report.droppedBakedEmissive = RealityKitConvert.lastDroppedBakedEmissive
        let convertProblems = RealityKitConvert.lastProblems
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

    /// Spec/gloss then RealityKit-safe rewrite, fused into one parse → serialize → write.
    /// Fully best-effort: if neither rewrite applies, or any step (parse, a rewrite, the
    /// final serialize/write) fails, the original URL is returned so `convertAsset` still
    /// gets a chance on the untouched bytes.
    private static func prepareGLB(_ url: URL, json: [String: Any]) -> (url: URL, json: [String: Any], report: PreparePipelineReport) {
        var report = seedPipelineReport(from: json)
        guard MetalRoughPrepare.needsConversion(json) || RealityPrepare.needsPrepare(json) else {
            return (url, json, report)
        }
        do {
            let prepared = applyPrepares(try GLBBox.parse(Data(contentsOf: url)), report: &report)
            let data = try GLBBox.serialize(json: prepared.json, bin: prepared.bin)
            return (try GLBBox.writePrepared(data, prefix: "glb-prepared"), prepared.json, report)
        } catch {
            AppLog.error(AppLog.prepare, "prepare failed, using original: \(error)")
            return (url, json, report)
        }
    }

    private static func applyPrepares(_ glb: GLBBox, report: inout PreparePipelineReport) -> GLBBox {
        var out = glb
        if MetalRoughPrepare.needsConversion(out.json) {
            do {
                out = try MetalRoughPrepare.transformed(out, report: &report)
            } catch {
                AppLog.error(AppLog.prepare, "metal-rough failed, using original: \(error)")
            }
        }
        if RealityPrepare.needsPrepare(out.json) {
            do {
                out = try RealityPrepare.transformed(out, report: &report)
            } catch {
                AppLog.error(AppLog.prepare, "reality prepare failed, using previous: \(error)")
            }
        }
        return out
    }

    /// Source extensions + Draco flag before prepare strips lists.
    private static func seedPipelineReport(from json: [String: Any]) -> PreparePipelineReport {
        var report = PreparePipelineReport()
        report.extensionsUsed = PreparePipelineReport.captureExtensions(from: json)
        report.decompressedDraco = PreparePipelineReport.sourceHadDraco(json)
        return report
    }

    /// Sidecar `.gltf` is JSON, not a GLB. Pack + prepare only when a rewrite will
    /// apply; otherwise load the original URL with its parent as `assetDirectory`.
    private static func packAndPrepareGLTF(
        from url: URL,
        directoryURL: URL,
        json: [String: Any]
    ) throws -> (url: URL, json: [String: Any], assetDirectory: URL, report: PreparePipelineReport) {
        var report = seedPipelineReport(from: json)
        guard MetalRoughPrepare.needsConversion(json) || RealityPrepare.needsPrepare(json) else {
            return (url, json, directoryURL, report)
        }
        let packed = try GLBBox.packSidecar(json) { uri in
            guard isAllowedSidecarURI(uri, assetDirectory: directoryURL) else {
                throw GLTFInspectorError.make(1021, "glTF sidecar URI is not a safe relative path")
            }
            let decoded = uri.removingPercentEncoding ?? uri
            // Derive from the previewed file URL so a security-scoped .gltf
            // can still reach same-folder `model.bin` / `textures/`.
            let sidecar = url.deletingLastPathComponent().appendingPathComponent(decoded)
            do {
                return try Data(contentsOf: sidecar)
            } catch {
                AppLog.error(AppLog.load, "sidecar \(decoded): \(error.localizedDescription)")
                throw error
            }
        }
        // Prepare is best-effort; fall back to the unprepared packed GLB on any failure.
        do {
            let prepared = applyPrepares(try GLBBox.parse(packed), report: &report)
            let out = try GLBBox.serialize(json: prepared.json, bin: prepared.bin)
            let temp = try GLBBox.writePrepared(out, prefix: "gltf-prepared")
            return (temp, prepared.json, temp.deletingLastPathComponent(), report)
        } catch {
            AppLog.error(AppLog.prepare, "gltf prepare failed, using packed: \(error)")
            let temp = try GLBBox.writePrepared(packed, prefix: "gltf-packed")
            return (temp, json, temp.deletingLastPathComponent(), report)
        }
    }

    private static func convertAsset(
        at loadURL: URL,
        assetDirectory: URL,
        includeAnimations: Bool,
        name: String,
        sceneIndex: Int?,
        buildDocument: Bool,
        materialVariantIndex: Int?
    ) async throws -> (Entity, GLTFSessionDocument, [String]) {
        let asset = try GLTFAsset(
            url: loadURL,
            options: [GLTFAssetLoadingOption.assetDirectoryURLKey: assetDirectory]
        )
        let variantNames = MaterialVariants.names(from: asset)
        if let materialVariantIndex {
            MaterialVariants.apply(variantIndex: materialVariantIndex, to: asset)
        }
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
        let retryWithoutAnimations = includeAnimations && !asset.animations.isEmpty
        return try await MainActor.run {
            let (entity, document) = try convertOrRetry(
                scene: scene,
                asset: asset,
                retryWithoutAnimations: retryWithoutAnimations,
                buildDocument: buildDocument
            )
            return (entity, document, variantNames)
        }
    }

    /// Empty results (zero `ModelComponent`s) retry once without animations when
    /// the first pass still had clips — some Draco + skin + animation assets trap
    /// or yield a blank entity otherwise. NSException is caught by `GLBTry`.
    @MainActor
    private static func convertOrRetry(
        scene: GLTFScene,
        asset: GLTFAsset,
        retryWithoutAnimations: Bool,
        buildDocument: Bool
    ) throws -> (Entity, GLTFSessionDocument) {
        var lastError: Error?
        let attempts = retryWithoutAnimations ? 2 : 1
        for pass in 0..<attempts {
            if pass == 1 {
                asset.animations = []
            }
            do {
                return try convertVisible(scene: scene, asset: asset, buildDocument: buildDocument)
            } catch {
                lastError = error
                AppLog.error(AppLog.load, error.localizedDescription)
            }
        }
        throw convertFailure(from: lastError ?? GLTFInspectorError.make(1022, "Failed to convert the glTF asset"))
    }

    @MainActor
    private static func convertVisible(
        scene: GLTFScene,
        asset: GLTFAsset,
        buildDocument: Bool
    ) throws -> (Entity, GLTFSessionDocument) {
        var converted: Entity?
        var document = GLTFSessionDocument()
        try GLBTry.run {
            converted = RealityKitConvert.convert(
                scene: scene,
                asset: asset,
                document: &document,
                buildDocument: buildDocument
            )
        }
        guard let converted, modelComponentCount(in: converted) > 0 else {
            throw GLTFInspectorError.make(1022, "The glTF asset has no visible mesh")
        }
        if buildDocument, document.animations.isEmpty {
            // Fallback when convert stamped no animations — same usable filter as playback.
            document.animations = PreviewClip.usable(on: converted).map(\.documentAnimation)
        }
        return (converted, document)
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
