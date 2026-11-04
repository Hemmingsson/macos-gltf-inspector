import AppKit
import Darwin
import Foundation
import GLTFCore
import Testing
@testable import GLTFInspector
@testable import RendererWebKit

/// The one renderer switch: Metal by default for every surface, `GLTF_RENDERER` as a dev override.
@MainActor
struct CanvasRendererFactoryTests {
    @Test
    func defaultsToNativeMetal() {
        #expect(CanvasRenderer.backend(environment: [:]) == .metal)
        #expect(CanvasRenderer.backend(environment: ["GLTF_RENDERER": ""]) == .metal)
        #expect(CanvasRenderer.backend(environment: ["GLTF_RENDERER": "vulkan"]) == .metal)
    }

    @Test(arguments: [
        ("metal", CanvasRenderer.Backend.metal),
        ("filament", .filament),
        ("webkit", .webkit),
        ("WebKit", .webkit),
    ])
    func honoursTheOverride(value: String, backend: CanvasRenderer.Backend) {
        #expect(CanvasRenderer.backend(environment: ["GLTF_RENDERER": value]) == backend)
    }

    @Test
    func buildsTheNamedHost() throws {
        #expect(try CanvasRenderer.makeHost(mode: .still, backend: .metal) is KhronosMetalRendererHost)
        #expect(try CanvasRenderer.makeHost(mode: .still, backend: .filament) is FilamentRendererHost)
        #expect(try CanvasRenderer.makeHost(mode: .still, backend: .webkit) is WebRendererHost)
        // With no backend the process environment decides (the test scheme sets webkit).
        let implicit = try CanvasRenderer.makeHost(mode: .still)
        let named = try CanvasRenderer.makeHost(mode: .still, backend: CanvasRenderer.backend())
        #expect(ObjectIdentifier(type(of: implicit)) == ObjectIdentifier(type(of: named)))
    }
}

/// The Finder thumbnail end to end, in-process, through `ThumbnailRenderer` — the exact type
/// `ThumbnailProvider` calls — on the shipped default backend. qlmanage hangs headless.
@MainActor
@Suite(.serialized)
struct ThumbnailRenderPathTests {
    private let shipped = CanvasRenderer.backend(environment: [:])

    @Test
    func rendersTheDefaultBackendThumbnail() async throws {
        #expect(shipped == .metal)
        let footprintBefore = physicalFootprintMB()
        let renderer = ThumbnailRenderer(backend: shipped)
        let result = try await renderer.render(url: TestFixtures.cube, pixel: 256)
        let footprintAfter = physicalFootprintMB()

        #expect(result.rendererName.hasPrefix("Metal"))
        #expect(result.info.triangles > 0)
        let image = try #require(NSBitmapImageRep(data: result.png)?.cgImage)
        #expect(image.width == 256 && image.height == 256)
        #expect(try centreAlpha(image) > 200, "the framed model covers the centre")
        #expect(result.markedPNG != result.png, "Finder's icon carries the renderer mark")
        let marked = try #require(NSBitmapImageRep(data: result.markedPNG)?.cgImage)
        #expect(marked.width == 256 && marked.height == 256)

        if let footprintBefore, let footprintAfter {
            print("thumbnail footprint before=\(Int(footprintBefore))MB after=\(Int(footprintAfter))MB delta=\(Int(footprintAfter - footprintBefore))MB")
        }
    }

    /// Finder asks for a folder at once: requests serialize on one warm host, a rejected file
    /// fails alone, and the next file still renders. Draco goes through DracoSwift.
    @Test
    func serializesRequestsAndSurvivesARejectedFile() async throws {
        let manifest = try PixelDiffManifest.load()
        let draco = try #require(manifest.entries.first(where: { $0.name == "BoxDraco" })).modelURL
        let renderer = ThumbnailRenderer(backend: shipped)

        async let first = renderer.render(url: TestFixtures.boxAnimated, pixel: 128)
        async let second = renderer.render(url: draco, pixel: 128)
        let (a, b) = try await (first, second)
        for result in [a, b] {
            let image = try #require(NSBitmapImageRep(data: result.png)?.cgImage)
            #expect(image.width == 128)
            #expect(try centreAlpha(image) > 200)
        }

        await #expect(throws: WebRendererError.self) {
            try await renderer.render(url: TestFixtures.corrupt, pixel: 128)
        }
        let after = try await renderer.render(url: TestFixtures.tiny, pixel: 128)
        #expect(NSBitmapImageRep(data: after.png)?.pixelsWide == 128)
    }
}

/// The Quick Look preview's path in-process: a prestarted live host from the factory, handed to
/// the canvas controller `PreviewViewController` mounts, with the preview's stored look.
@MainActor
@Suite(.serialized)
struct QuickLookCanvasPathTests {
    private func prestartedHost() async throws -> any CanvasRendererHost {
        let host = try CanvasRenderer.makeHost(mode: .live, backend: CanvasRenderer.backend(environment: [:]))
        #expect(host is KhronosMetalRendererHost)
        try await host.start()
        return host
    }

    @Test
    func liveCanvasReachesReadyAndExportsAtCanvasSize() async throws {
        let canvas = WebCanvasController()
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        canvas.attach(
            to: container, url: TestFixtures.cube, look: .stored(showsFloor: true), placeholder: nil,
            existing: try await prestartedHost()
        )
        container.layoutSubtreeIfNeeded()
        _ = try await WebKitTest.waitUntil { canvas.phase != .loading }
        #expect(canvas.phase == .ready)

        try await canvas.apply(preset: .isometric)
        let frame = try await canvas.snapshot()
        // Export PNG follows the live canvas, not the 512² still default.
        #expect(frame.width * 240 == frame.height * 320)
        #expect(try centreAlpha(frame) > 200)
    }

    @Test
    func rejectedFileFailsWithTheRendererCopy() async throws {
        let canvas = WebCanvasController()
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        canvas.attach(
            to: container, url: TestFixtures.corrupt, look: .stored(showsFloor: true), placeholder: nil,
            existing: try await prestartedHost()
        )
        _ = try await WebKitTest.waitUntil { canvas.phase != .loading }
        #expect(canvas.phase == .failed(WebRendererError.callFailed("").errorDescription!))
    }
}

/// Alpha of the centre pixel of `image`.
@MainActor
private func centreAlpha(_ image: CGImage) throws -> UInt8 {
    try alpha(of: image, at: CGPoint(x: image.width / 2, y: image.height / 2))
}

@MainActor
private func alpha(of image: CGImage, at point: CGPoint) throws -> UInt8 {
    let context = try #require(CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.draw(image, in: CGRect(x: -point.x, y: -point.y, width: CGFloat(image.width), height: CGFloat(image.height)))
    return try #require(context.data?.assumingMemoryBound(to: UInt8.self))[3]
}

private func physicalFootprintMB() -> Double? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), raw, &count)
        }
    }
    guard result == KERN_SUCCESS else { return nil }
    return Double(info.phys_footprint) / 1_048_576
}
