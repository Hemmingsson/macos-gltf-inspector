import Foundation
import GLTFKit2
import RealityKit

enum GLBEntityLoader {
    /// Loads a self-contained `.glb` or a sidecar `.gltf` (buffers/textures next to the JSON).
    /// Thumbnails should pass `includeAnimations: false` — Finder icons never play clips,
    /// and GLTFKit2 still traps on some zero-stride Sketchfab “Default Take” channels
    /// that slip past the duration filter.
    @MainActor
    static func load(from url: URL, includeAnimations: Bool = true) async throws -> Entity {
        GLBLog.event(
            GLBLog.load,
            "load start includeAnimations=\(includeAnimations) \(GLBLog.describeURL(url))"
        )
        GLTFAsset.dracoDecompressorClassName = "GLBDracoDecompressor"
            GLBLog.event(GLBLog.draco, "dracoDecompressorClassName=\(GLTFAsset.dracoDecompressorClassName)")

        let directoryURL = URL(
            fileURLWithPath: url.deletingLastPathComponent().path,
            isDirectory: true
        )
        let accessedDirectory = directoryURL.startAccessingSecurityScopedResource()
        let accessedFile = url.startAccessingSecurityScopedResource()
        GLBLog.event(
            GLBLog.load,
            "security-scope dir=\(accessedDirectory) file=\(accessedFile) directory=\(directoryURL.path)"
        )
        defer {
            if accessedDirectory {
                directoryURL.stopAccessingSecurityScopedResource()
            }
            if accessedFile {
                url.stopAccessingSecurityScopedResource()
            }
            GLBLog.event(GLBLog.load, "security-scope released for \(url.lastPathComponent)")
        }

        let loadURL: URL
        let assetDirectory: URL
        if url.pathExtension.lowercased() == "glb" {
            // Spec/gloss rewrite is best-effort; fall back to the original GLB.
            do {
                let prepared = try GLBMetalRoughPrepare.preparedURL(from: url)
                loadURL = prepared
                GLBLog.event(
                    GLBLog.prepare,
                    "metal-rough prepared=\(prepared.path) rewritten=\(prepared != url)"
                )
            } catch {
                loadURL = url
                GLBLog.error(GLBLog.prepare, "metal-rough failed, using original: \(error)")
            }
            assetDirectory = directoryURL
        } else {
            let staged = try GLBLog.timed(GLBLog.load, "stageGLTF \(url.lastPathComponent)") {
                try stageGLTF(from: url, directoryURL: directoryURL)
            }
            loadURL = staged.file
            assetDirectory = staged.directory
            GLBLog.event(
                GLBLog.load,
                "staged gltf file=\(loadURL.path) directory=\(assetDirectory.path)"
            )
        }

        GLBLog.event(
            GLBLog.load,
            "GLTFAsset open \(GLBLog.describeURL(loadURL)) assetDirectory=\(assetDirectory.path)"
        )
        let asset = try GLBLog.timed(GLBLog.load, "GLTFAsset \(loadURL.lastPathComponent)") {
            try GLTFAsset(
                url: loadURL,
                options: [GLTFAssetLoadingOption.assetDirectoryURLKey: assetDirectory]
            )
        }
        GLBLog.event(
            GLBLog.load,
            "asset scenes=\(asset.scenes.count) nodes=\(asset.nodes.count) meshes=\(asset.meshes.count) materials=\(asset.materials.count) images=\(asset.images.count) animations=\(asset.animations.count) defaultScene=\(asset.defaultScene?.name ?? "nil")"
        )
        // Sketchfab/FBX often embeds a 1-keyframe "Default Take". GLTFKit2 then
        // calls stride(from:through:by: 0) and traps.
        let rawAnimCount = asset.animations.count
        if includeAnimations {
            asset.animations = asset.animations.filter { hasPositiveDuration($0) }
        } else {
            asset.animations = []
        }
        GLBLog.event(
            GLBLog.load,
            "animation filter raw=\(rawAnimCount) kept=\(asset.animations.count) includeAnimations=\(includeAnimations)"
        )
        guard let scene = asset.defaultScene else {
            GLBLog.error(GLBLog.load, "no default scene for \(url.lastPathComponent)")
            throw NSError(
                domain: "GLBPreview",
                code: 1020,
                userInfo: [NSLocalizedDescriptionKey: "The glTF asset did not specify a default scene"]
            )
        }
        let entity = GLBLog.timed(GLBLog.load, "GLTFRealityKitLoader.convert \(url.lastPathComponent)") {
            GLTFRealityKitLoader.convert(scene: scene, asset: asset)
        }
        GLBLog.event(GLBLog.load, "entity \(GLBLog.describe(entity))")
        return entity
    }

    /// Copies the JSON plus relative `.bin` / image URIs into the sandbox temp
    /// directory so GLTFKit2 can read sidecars after source scopes are released.
    private static func stageGLTF(from url: URL, directoryURL: URL) throws -> (file: URL, directory: URL) {
        let data = try Data(contentsOf: url)
        let relatives = try relativeURIs(in: data, directoryURL: directoryURL)
        GLBLog.event(GLBLog.load, "stageGLTF bytes=\(data.count) sidecars=\(relatives)")
        let stage = FileManager.default.temporaryDirectory
            .appendingPathComponent("gltf-stage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        let stagedFile = stage.appendingPathComponent(url.lastPathComponent)
        try data.write(to: stagedFile)
        for rel in relatives {
            let src = directoryURL.appendingPathComponent(rel)
            let dest = stage.appendingPathComponent(rel)
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            do {
                try FileManager.default.copyItem(at: src, to: dest)
            } catch {
                try Data(contentsOf: src).write(to: dest)
            }
        }
        GLBLog.event(GLBLog.load, "stageGLTF wrote \(stagedFile.path)")
        return (stagedFile, stage)
    }

    private static func relativeURIs(in data: Data, directoryURL: URL) throws -> [String] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var uris: [String] = []
        for key in ["buffers", "images"] {
            guard let items = json[key] as? [[String: Any]] else { continue }
            for item in items {
                guard let uri = item["uri"] as? String, !uri.isEmpty, !uri.hasPrefix("data:") else {
                    continue
                }
                guard isAllowedSidecarURI(uri, assetDirectory: directoryURL) else {
                    throw NSError(
                        domain: "GLBPreview",
                        code: 1021,
                        userInfo: [NSLocalizedDescriptionKey: "glTF sidecar URI is not a safe relative path"]
                    )
                }
                uris.append(uri)
            }
        }
        return uris
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
