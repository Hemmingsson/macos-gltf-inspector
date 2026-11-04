import Foundation
import Testing
@testable import RendererWebKit

/// Adds coverage for the port without touching any existing pinned pose or PNG.
@MainActor
struct MetalSampleReferenceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GLTF_METAL_ADD_SAMPLES"] == "1"))
    func recordOnlyNewKhronosSamples() async throws {
        var manifest = try PixelDiffManifest.load()
        let host = try await PixelDiffWebKit.makeHost(manifest: manifest)
        for index in manifest.entries.indices where manifest.entries[index].camera == nil {
            let url = manifest.entries[index].modelURL
            manifest.entries[index].camera = try await PixelDiffWebKit.recordPose(for: url, on: host)
            manifest.entries[index].requires = PixelDiffSampleFeatures.derive(from: try PixelDiffSampleFeatures.json(of: url))
            let entry = manifest.entries[index]
            try #require(!FileManager.default.fileExists(atPath: entry.referenceURL.path), "Refusing to overwrite \(entry.name)")
            let image = try await PixelDiffWebKit.render(entry, on: host)
            try PixelDiff.write(PixelDiff.raster(from: image), to: entry.referenceURL)
            print("new Khronos reference \(entry.name)")
        }
        try manifest.write()
    }
}
