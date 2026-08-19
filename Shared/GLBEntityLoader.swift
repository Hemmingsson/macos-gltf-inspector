import Foundation
import GLTFKit2
import RealityKit

enum GLBEntityLoader {
    /// A converted model plus the cheap glTF-header stats shown in the preview overlay.
    struct LoadedModel {
        let entity: Entity
        let stats: GLBPreviewStats
        let document: GLTFSessionDocument

        @MainActor var punctualLightCount: Int {
            GLBPreviewScenery.punctualLightCount(in: entity)
        }

        @MainActor var studioIBLExponent: Float {
            GLBPreviewEmissive.studioIBLExponent(punctualLightCount: punctualLightCount)
        }
    }

    /// Loads a self-contained `.glb` or a sidecar `.gltf` (buffers/textures next to the JSON).
    /// Thumbnails should pass `includeAnimations: false` — Finder icons never play clips,
    /// and GLTFKit2 still traps on some zero-stride Sketchfab “Default Take” channels
    /// that slip past the duration filter.
    /// File IO and `GLTFAsset` stay off the main actor so Spacebar can show the loading
    /// view while the file is parsed; RealityKit convert hops to the main actor.
    static func load(from url: URL, includeAnimations: Bool = true) async throws -> LoadedModel {
        try await withPreparedAsset(from: url) { loadURL, assetDirectory, sourceJSON, fileSize, originalURL, directoryURL in
            let (entity, document) = try await convertPreparedOrOriginal(
                loadURL: loadURL,
                originalURL: originalURL,
                assetDirectory: assetDirectory,
                fallbackDirectory: directoryURL,
                includeAnimations: includeAnimations,
                name: url.lastPathComponent,
                sceneIndex: nil
            )
            return await loadedModel(entity: entity, document: document, json: sourceJSON, fileSizeBytes: fileSize)
        }
    }

    /// Converts one scene from the same prepared asset path as `load`, without
    /// rebuilding `LoadedModel`. Host scene switching uses this after listing
    /// `document.scenes`; Quick Look keeps calling `load` only.
    static func convertScene(index: Int, from url: URL, includeAnimations: Bool = true) async throws -> Entity {
        try await withPreparedAsset(from: url) { loadURL, assetDirectory, _, _, originalURL, directoryURL in
            let (entity, _) = try await convertPreparedOrOriginal(
                loadURL: loadURL,
                originalURL: originalURL,
                assetDirectory: assetDirectory,
                fallbackDirectory: directoryURL,
                includeAnimations: includeAnimations,
                name: url.lastPathComponent,
                sceneIndex: index
            )
            return entity
        }
    }

    private static func convertPreparedOrOriginal(
        loadURL: URL,
        originalURL: URL,
        assetDirectory: URL,
        fallbackDirectory: URL,
        includeAnimations: Bool,
        name: String,
        sceneIndex: Int?
    ) async throws -> (Entity, GLTFSessionDocument) {
        do {
            return try await convertAsset(
                at: loadURL,
                assetDirectory: assetDirectory,
                includeAnimations: includeAnimations,
                name: name,
                sceneIndex: sceneIndex
            )
        } catch {
            guard loadURL != originalURL else { throw error }
            GLBLog.error(GLBLog.prepare, "prepared GLB produced no mesh, retrying original")
            return try await convertAsset(
                at: originalURL,
                assetDirectory: fallbackDirectory,
                includeAnimations: includeAnimations,
                name: name,
                sceneIndex: sceneIndex
            )
        }
    }

    private static func withPreparedAsset<T>(
        from url: URL,
        work: (URL, URL, [String: Any], Int64?, URL, URL) async throws -> T
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

        // Parse the glTF header once and reuse it for stats and the prepare gates,
        // instead of re-opening the file for each concern.
        let isGLB = url.pathExtension.lowercased() == "glb"
        let sourceJSON: [String: Any]
        if isGLB {
            sourceJSON = (try? GLBBox.peekJSON(from: url)) ?? [:]
        } else {
            sourceJSON = try GLBBox.parseJSON(try Data(contentsOf: url, options: [.mappedIfSafe]))
        }
        let fileSize = fileSizeBytes(of: url)

        let loadURL: URL
        let assetDirectory: URL
        if isGLB {
            loadURL = prepareGLB(url, json: sourceJSON)
            assetDirectory = directoryURL
        } else {
            loadURL = try packAndPrepareGLTF(from: url, directoryURL: directoryURL)
            assetDirectory = loadURL.deletingLastPathComponent()
        }
        // Prepared/packed GLBs are throwaway temp files; the retry path below only ever
        // reopens the original `url`, so the temp is safe to delete once loading finishes.
        defer {
            if loadURL != url {
                try? FileManager.default.removeItem(at: loadURL)
            }
        }

        return try await work(loadURL, assetDirectory, sourceJSON, fileSize, url, directoryURL)
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
        fileSizeBytes: Int64?
    ) -> LoadedModel {
        LoadedModel(
            entity: entity,
            stats: GLBPreviewStats.from(
                json: json,
                usableAnimations: entity.availableAnimations,
                fileSizeBytes: fileSizeBytes
            ),
            document: document
        )
    }

    /// Spec/gloss then RealityKit-safe rewrite, fused into one parse → serialize → write.
    /// Fully best-effort: if neither rewrite applies, or any step (parse, a rewrite, the
    /// final serialize/write) fails, the original URL is returned so `convertAsset` still
    /// gets a chance on the untouched bytes.
    private static func prepareGLB(_ url: URL, json: [String: Any]) -> URL {
        guard GLBMetalRoughPrepare.needsConversion(json) || GLBRealityPrepare.needsPrepare(json) else {
            return url
        }
        do {
            let prepared = applyPrepares(try GLBBox.parse(Data(contentsOf: url)))
            let data = try GLBBox.serialize(json: prepared.json, bin: prepared.bin)
            return try GLBBox.writePrepared(data, prefix: "glb-prepared")
        } catch {
            GLBLog.error(GLBLog.prepare, "prepare failed, using original: \(error)")
            return url
        }
    }

    private static func applyPrepares(_ glb: GLBBox) -> GLBBox {
        var out = glb
        if GLBMetalRoughPrepare.needsConversion(out.json) {
            do {
                out = try GLBMetalRoughPrepare.transformed(out)
            } catch {
                GLBLog.error(GLBLog.prepare, "metal-rough failed, using original: \(error)")
            }
        }
        if GLBRealityPrepare.needsPrepare(out.json) {
            do {
                out = try GLBRealityPrepare.transformed(out)
            } catch {
                GLBLog.error(GLBLog.prepare, "reality prepare failed, using previous: \(error)")
            }
        }
        return out
    }

    /// Sidecar `.gltf` is JSON, not a GLB. Pack buffers/images into a GLB in memory,
    /// run the same prepares, and write one temp file.
    private static func packAndPrepareGLTF(from url: URL, directoryURL: URL) throws -> URL {
        let data = try Data(contentsOf: url)
        let json = try GLBBox.parseJSON(data)
        let packed = try GLBBox.packSidecar(json) { uri in
            guard isAllowedSidecarURI(uri, assetDirectory: directoryURL) else {
                throw GLBPreviewError.make(1021, "glTF sidecar URI is not a safe relative path")
            }
            let decoded = uri.removingPercentEncoding ?? uri
            // Derive from the previewed file URL so a security-scoped .gltf
            // can still reach same-folder `model.bin` / `textures/`.
            let sidecar = url.deletingLastPathComponent().appendingPathComponent(decoded)
            do {
                return try Data(contentsOf: sidecar)
            } catch {
                GLBLog.error(GLBLog.load, "sidecar \(decoded): \(error.localizedDescription)")
                throw error
            }
        }
        // Prepare is best-effort; fall back to the unprepared packed GLB on any failure.
        do {
            let prepared = applyPrepares(try GLBBox.parse(packed))
            let out = try GLBBox.serialize(json: prepared.json, bin: prepared.bin)
            return try GLBBox.writePrepared(out, prefix: "gltf-prepared")
        } catch {
            GLBLog.error(GLBLog.prepare, "gltf prepare failed, using packed: \(error)")
            return try GLBBox.writePrepared(packed, prefix: "gltf-packed")
        }
    }

    private static func convertAsset(
        at loadURL: URL,
        assetDirectory: URL,
        includeAnimations: Bool,
        name: String,
        sceneIndex: Int?
    ) async throws -> (Entity, GLTFSessionDocument) {
        let asset = try GLTFAsset(
            url: loadURL,
            options: [GLTFAssetLoadingOption.assetDirectoryURLKey: assetDirectory]
        )
        // Sketchfab/FBX often embeds a 1-keyframe "Default Take". GLTFKit2 then
        // calls stride(from:through:by: 0) and traps.
        if includeAnimations {
            asset.animations = asset.animations.filter { hasPositiveDuration($0) }
        } else {
            asset.animations = []
        }
        let scene: GLTFScene
        if let sceneIndex {
            guard sceneIndex >= 0, sceneIndex < asset.scenes.count else {
                GLBLog.error(GLBLog.load, "scene index \(sceneIndex) out of range for \(name)")
                throw GLBPreviewError.make(1020, "The glTF asset does not contain scene index \(sceneIndex)")
            }
            scene = asset.scenes[sceneIndex]
        } else if let defaultScene = asset.defaultScene {
            scene = defaultScene
        } else {
            GLBLog.error(GLBLog.load, "no default scene for \(name)")
            throw GLBPreviewError.make(1020, "The glTF asset did not specify a default scene")
        }
        let retryWithoutAnimations = includeAnimations && !asset.animations.isEmpty
        return try await MainActor.run {
            try convertOrRetry(
                scene: scene,
                asset: asset,
                retryWithoutAnimations: retryWithoutAnimations
            )
        }
    }

    /// Empty results (zero `ModelComponent`s) retry once without animations when
    /// the first pass still had clips — some Draco + skin + animation assets trap
    /// or yield a blank entity otherwise. NSException is caught by `GLBTry`.
    @MainActor
    private static func convertOrRetry(
        scene: GLTFScene,
        asset: GLTFAsset,
        retryWithoutAnimations: Bool
    ) throws -> (Entity, GLTFSessionDocument) {
        var lastError: Error?
        let attempts = retryWithoutAnimations ? 2 : 1
        for pass in 0..<attempts {
            if pass == 1 {
                asset.animations = []
            }
            do {
                return try convertVisible(scene: scene, asset: asset)
            } catch {
                lastError = error
                GLBLog.error(GLBLog.load, error.localizedDescription)
            }
        }
        throw convertFailure(from: lastError ?? GLBPreviewError.make(1022, "Failed to convert the glTF asset"))
    }

    @MainActor
    private static func convertVisible(scene: GLTFScene, asset: GLTFAsset) throws -> (Entity, GLTFSessionDocument) {
        var converted: Entity?
        var document = GLTFSessionDocument()
        try GLBTry.run {
            converted = GLBRealityKitConvert.convert(scene: scene, asset: asset, document: &document)
        }
        guard let converted, modelComponentCount(in: converted) > 0 else {
            throw GLBPreviewError.make(1022, "The glTF asset has no visible mesh")
        }
        if document.animations.isEmpty {
            document.animations = usableClips(from: converted)
        }
        return (converted, document)
    }

    @MainActor
    private static func usableClips(from entity: Entity) -> [GLTFSessionDocument.Animation] {
        entity.availableAnimations.compactMap { resource in
            let probe = entity.playAnimation(resource, startsPaused: true)
            let duration = probe.duration
            probe.stop()
            guard duration.isFinite, duration > 0 else { return nil }
            return GLTFSessionDocument.Animation(name: resource.name ?? "", duration: duration)
        }
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
        if nsError.domain == GLBPreviewError.domain, nsError.code == 1022 || nsError.code == 1023 {
            return nsError
        }
        return GLBPreviewError.make(1022, "Failed to convert the glTF asset")
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

    private static func hasPositiveDuration(_ animation: GLTFAnimation) -> Bool {
        var minTime = Float.infinity
        var maxTime = -Float.infinity
        var sampleCount = 0
        for sampler in animation.samplers {
            sampleCount = max(sampleCount, sampler.input.count)
            if let lo = sampler.input.minValues.first?.floatValue {
                minTime = min(minTime, lo)
            }
            if let hi = sampler.input.maxValues.first?.floatValue {
                maxTime = max(maxTime, hi)
            }
        }
        return sampleCount > 1 && maxTime - minTime > 1e-4
    }
}
