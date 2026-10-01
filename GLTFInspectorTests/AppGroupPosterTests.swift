import CoreGraphics
import Foundation
@testable import GLTFCore
import Testing

/// App Group poster cache (Wave P first pixel): a stored PNG is the first-pixel surface when it
/// exists; a miss is a bounding-box proxy, not a spinner-only wait.
struct AppGroupPosterTests {
    @Test
    func cachedPosterPathIsUsedWhenAFileExists() throws {
        let container = try Scratch.make()
        defer { Scratch.remove(container) }
        let url = TestFixtures.cube
        let look = RenderLook.standard

        let png = try #require(solidPNG(red: 1, green: 0, blue: 0))
        let stored = try FirstPixelPreview.store(
            png: png,
            for: url,
            renderer: .webKit,
            look: look,
            container: container
        )

        let surface = FirstPixelPreview.surface(
            for: url,
            renderer: .webKit,
            look: look,
            container: container
        )
        #expect(surface == .cachedPoster(stored))
        #expect(FileManager.default.fileExists(atPath: stored.path))

        let image = FirstPixelPreview.image(
            for: url,
            renderer: .webKit,
            look: look,
            container: container
        )
        #expect(isMostlyRed(image))
    }

    @Test
    func missingPosterYieldsABoundingBoxProxy() throws {
        let container = try Scratch.make()
        defer { Scratch.remove(container) }
        let url = TestFixtures.cube

        let surface = FirstPixelPreview.surface(
            for: url,
            renderer: .realityKit,
            look: .standard,
            container: container
        )
        guard case .boundingBoxProxy(let bounds) = surface else {
            Issue.record("expected a bounding-box proxy, got \(surface)")
            return
        }
        let box = try #require(bounds)
        #expect(box.size.x > 0 && box.size.y > 0 && box.size.z > 0)

        let image = FirstPixelPreview.image(
            for: url,
            renderer: .realityKit,
            look: .standard,
            container: container
        )
        #expect(image.width > 8 && image.height > 8)
        #expect(!isMostlyRed(image), "proxy must be a drawn box, not a cached poster")
    }

    @Test
    func lookAndRendererSplitTheCache() throws {
        let container = try Scratch.make()
        defer { Scratch.remove(container) }
        let url = TestFixtures.cube
        var field = RenderLook.standard
        field.environment = .field

        let web = try FirstPixelPreview.store(
            png: try #require(solidPNG(red: 1, green: 0, blue: 0)),
            for: url,
            renderer: .webKit,
            look: .standard,
            container: container
        )
        let reality = try FirstPixelPreview.store(
            png: try #require(solidPNG(red: 0, green: 0, blue: 1)),
            for: url,
            renderer: .realityKit,
            look: field,
            container: container
        )
        #expect(web != reality)
        #expect(
            FirstPixelPreview.surface(for: url, renderer: .webKit, look: .standard, container: container)
                == .cachedPoster(web)
        )
        #expect(
            FirstPixelPreview.surface(for: url, renderer: .realityKit, look: field, container: container)
                == .cachedPoster(reality)
        )
        #expect(
            FirstPixelPreview.surface(for: url, renderer: .realityKit, look: .standard, container: container)
                != .cachedPoster(reality)
        )
    }
}

private enum Scratch {
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("first-pixel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

private func solidPNG(red: CGFloat, green: CGFloat, blue: CGFloat) -> Data? {
    let width = 16
    let height = 16
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for index in stride(from: 0, to: pixels.count, by: 4) {
        pixels[index] = UInt8(red * 255)
        pixels[index + 1] = UInt8(green * 255)
        pixels[index + 2] = UInt8(blue * 255)
        pixels[index + 3] = 255
    }
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let image = context.makeImage() else { return nil }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("first-pixel-solid-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: url) }
    do {
        try PNGWriter.write(image, to: url)
        return try Data(contentsOf: url)
    } catch {
        return nil
    }
}

private func isMostlyRed(_ image: CGImage) -> Bool {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return false }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var red = 0
    var count = 0
    for index in stride(from: 0, to: pixels.count, by: 4) {
        count += 1
        if pixels[index] > 200 && pixels[index + 1] < 40 && pixels[index + 2] < 40 {
            red += 1
        }
    }
    return count > 0 && Double(red) / Double(count) > 0.8
}
