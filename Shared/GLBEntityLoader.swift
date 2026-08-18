import Foundation
import GLTFKit2
import RealityKit

enum GLBEntityLoader {
    /// Loads a self-contained `.glb` or a sidecar `.gltf` (buffers/textures next to the JSON).
    /// Thumbnails should pass `includeAnimations: false` — Finder icons never play clips,
    /// and GLTFKit2 still traps on some zero-stride Sketchfab “Default Take” channels
    /// that slip past the duration filter.
    /// File IO and `GLTFAsset` stay off the main actor so Spacebar can show the loading
    /// view while the file is parsed; RealityKit convert hops to the main actor.
    static func load(from url: URL, includeAnimations: Bool = true) async throws -> Entity {
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

        let loadURL: URL
        let assetDirectory: URL
        if url.pathExtension.lowercased() == "glb" {
            loadURL = prepareGLB(url)
            assetDirectory = directoryURL
        } else {
            loadURL = try packAndPrepareGLTF(from: url, directoryURL: directoryURL)
            assetDirectory = loadURL.deletingLastPathComponent()
        }

        do {
            return try await convertAsset(
                at: loadURL,
                assetDirectory: assetDirectory,
                includeAnimations: includeAnimations,
                name: url.lastPathComponent
            )
        } catch {
            guard loadURL != url else { throw error }
            GLBLog.error(GLBLog.prepare, "prepared GLB produced no mesh, retrying original")
            return try await convertAsset(
                at: url,
                assetDirectory: directoryURL,
                includeAnimations: includeAnimations,
                name: url.lastPathComponent
            )
        }
    }

    /// Spec/gloss then RealityKit-safe rewrite. Either step is best-effort.
    private static func prepareGLB(_ url: URL) -> URL {
        var prepared = url
        do {
            prepared = try GLBMetalRoughPrepare.preparedURL(from: prepared)
        } catch {
            GLBLog.error(GLBLog.prepare, "metal-rough failed, using original: \(error)")
        }
        do {
            prepared = try GLBRealityPrepare.preparedURL(from: prepared)
        } catch {
            GLBLog.error(GLBLog.prepare, "reality prepare failed, using previous: \(error)")
        }
        return prepared
    }

    /// Sidecar `.gltf` is JSON, not a GLB. Pack buffers/images into a temp GLB, then
    /// run the same prepare path as a native `.glb`.
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
        let packedURL = try GLBBox.writePrepared(packed, prefix: "gltf-packed")
        return prepareGLB(packedURL)
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
