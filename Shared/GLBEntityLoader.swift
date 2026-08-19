import Foundation
import GLTFKit2
import RealityKit

enum GLBEntityLoader {
    /// Converted entity plus scenery snapshotted at load (cameras still live).
    struct LoadedModel {
        let entity: Entity
        let stats: GLBPreviewStats
        let usableAnimations: [AnimationResource]
        let punctualLightCount: Int
        let fileCameras: [GLBPreviewScenery.FileCamera]
        let usesBakedEmissive: Bool
        var studioIBLExponent: Float {
            GLBPreviewEmissive.studioIBLExponent(
                punctualLightCount: punctualLightCount,
                fileLooksBaked: usesBakedEmissive
            )
        }
    }

    /// Loads a self-contained `.glb` or a sidecar `.gltf` (buffers/textures next to the JSON).
    /// Thumbnails should pass `includeAnimations: false` — Finder icons never play clips,
    /// and GLTFKit2 still traps on some zero-stride Sketchfab “Default Take” channels
    /// that slip past the duration filter.
    /// File IO and `GLTFAsset` stay off the main actor so Spacebar can show the loading
    /// view while the file is parsed; RealityKit convert hops to the main actor.
    static func load(from url: URL, includeAnimations: Bool = true) async throws -> LoadedModel {
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

        do {
            let entity = try await convertAsset(
                at: loadURL,
                assetDirectory: assetDirectory,
                includeAnimations: includeAnimations,
                name: url.lastPathComponent
            )
            return await attachScenery(entity, json: sourceJSON, fileSizeBytes: fileSizeBytes(of: url))
        } catch {
            guard loadURL != url else { throw error }
            GLBLog.error(GLBLog.prepare, "prepared GLB produced no mesh, retrying original")
            let entity = try await convertAsset(
                at: url,
                assetDirectory: directoryURL,
                includeAnimations: includeAnimations,
                name: url.lastPathComponent
            )
            return await attachScenery(entity, json: sourceJSON, fileSizeBytes: fileSizeBytes(of: url))
        }
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
        name: String
    ) async throws -> Entity {
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
        guard let scene = asset.defaultScene else {
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

    private static func fileSizeBytes(of url: URL) -> Int64? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        return size.map(Int64.init)
    }

    /// Walk lights, live file cameras, and usable clips once. Does not disable cameras.
    @MainActor
    private static func attachScenery(
        _ entity: Entity,
        json: [String: Any],
        fileSizeBytes: Int64?
    ) -> LoadedModel {
        if GLBPreviewScenery.hasUnsupportedFileIBL(json: json) {
            GLBLog.info(GLBLog.lighting, "EXT_lights_image_based is present but not loaded; using studio IBL")
        }
        let usableAnimations = GLBPreviewScenery.usableAnimations(in: entity)
        let punctualLightCount = GLBPreviewScenery.punctualLightCount(in: entity)
        let fileCameras = GLBPreviewScenery.fileCameras(in: entity)
        let usesBakedEmissive = GLBPreviewEmissive.fileLooksBaked(json: json)
        return LoadedModel(
            entity: entity,
            stats: GLBPreviewStats.from(
                json: json,
                usableAnimations: usableAnimations,
                fileSizeBytes: fileSizeBytes
            ),
            usableAnimations: usableAnimations,
            punctualLightCount: punctualLightCount,
            fileCameras: fileCameras,
            usesBakedEmissive: usesBakedEmissive
        )
    }

    /// Empty results (zero `ModelComponent`s) retry once without animations when
    /// the first pass still had clips — some Draco + skin + animation assets trap
    /// or yield a blank entity otherwise. NSException is caught by `GLBTry`.
    @MainActor
    private static func convertOrRetry(
        scene: GLTFScene,
        asset: GLTFAsset,
        retryWithoutAnimations: Bool
    ) throws -> Entity {
        var lastError: Error?
        let attempts = retryWithoutAnimations ? 2 : 1
        for pass in 0..<attempts {
            if pass == 1 {
                // Mesh-recovery retry: drop clips only. File lights stay on the asset.
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
    private static func convertVisible(scene: GLTFScene, asset: GLTFAsset) throws -> Entity {
        var converted: Entity?
        try GLBTry.run {
            converted = GLBRealityKitConvert.convert(scene: scene, asset: asset)
        }
        guard let converted, modelComponentCount(in: converted) > 0 else {
            throw GLBPreviewError.make(1022, "The glTF asset has no visible mesh")
        }
        return converted
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
