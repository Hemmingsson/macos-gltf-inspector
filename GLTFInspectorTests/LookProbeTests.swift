import AppKit
import CoreGraphics
import Foundation
import GLTFCore
@preconcurrency import Metal
import RealityKit
import simd
import Testing
@testable import GLTFInspector
@testable import RendererRealityKit

/// Look probes (renderer-separation seam 5): measure what each renderer does with one look
/// quantity at a time, so `RenderLook` → renderer mappings are numbers rather than guesses.
///
/// Opt-in, like the pixel-diff generator — a sentinel file, because `xcodebuild test` does not
/// forward the shell environment:
///
///     ./scripts/testdata/run-look-probes.sh
///
/// Prints `lookprobe …` lines and writes renders + `results.json` to
/// `/tmp/GLTFInspector-look-probes/`. Fixtures: `scripts/testdata/make_look_probes.py`.
/// Results and the derived constants: `.agents/research/2026-09-30-look-probes.md`.
///
/// Instrumentation only: the RealityKit side builds its own `RealityRenderer` here (tone map
/// on/off, float target, no studio IBL) around the shipping `EntityLoader.loadThumbnail`
/// convert; the web side drives the shipping `WebRendererHost` page with the typed commands.
enum LookProbeGate {
    static let sentinelURL = TestFixtures.url("TestModels/Fixture Models/probes/RUN_LOOK_PROBES")
    static var isRequested: Bool { FileManager.default.fileExists(atPath: sentinelURL.path) }
}

@MainActor
@Suite(.serialized, .enabled(if: LookProbeGate.isRequested))
struct LookProbeTests {
    static let size = 256
    static let outputDirectory = URL(fileURLWithPath: "/tmp/GLTFInspector-look-probes")
    static let webLinearToneMap = "None (Linear mapping, clamped at 1.0)"

    static func probe(_ name: String) -> URL { TestFixtures.fixture("probes/\(name)") }

    // MARK: - 1. Environment yaw

    /// Mirror sphere under `env-wheel.hdr`. The centre pixel reflects the direction back toward
    /// the camera, so for a camera at azimuth `a` (eye on `Ry(a)·+Z`) it decodes the equirect
    /// longitude that renderer maps onto that world direction.
    @Test func environmentYaw() async throws {
        let azimuths: [Double] = [0, 45, 90, 135, 180, 225, 270, 315]
        var results: [String: Any] = [:]

        // Web: the Khronos page at its default (90) and at 180 to get the rotation's sign.
        let host = try WebRendererHost(mode: .still, timeout: .seconds(60))
        try await host.start(size: Self.size)
        try await host.send { .setToneMapping(id: $0, name: Self.webLinearToneMap) }
        try await host.send { .setExposure(id: $0, stops: 0) }
        _ = try await host.load(model: Self.probe("mirror-sphere.gltf"))
        // Served next to the model by the scheme handler (`/model/<sibling>`).
        try await host.send { .setEnvironment(id: $0, url: "gltf-inspector:///model/env-wheel.hdr") }
        for rotation in [0.0, 90, 180] {
            try await host.send { .setEnvironmentRotation(id: $0, degrees: rotation) }
            var row: [String] = []
            for a in azimuths {
                try await host.setCameraPose(Self.sphereCamera(azimuth: a))
                let image = try await host.renderStill()
                if a == 0 { try Self.save(image, "web-mirror-rot\(Int(rotation))-az0") }
                let linear = Self.webToLinear(Self.centre(of: image))
                let longitude = Self.decodeLongitude(linear)
                row.append(String(format: "%.1f", longitude))
                print("lookprobe yaw web rot=\(rotation) az=\(a) longitude=\(String(format: "%.2f", longitude)) linear=\(Self.fmt(linear))")
            }
            results["web_rot\(Int(rotation))"] = row
        }

        // RealityKit: native yaw 0, then quarter turns, tone map off, float target.
        let model = try await EntityLoader.loadThumbnail(from: Self.probe("mirror-sphere.gltf"))
        let environment = try #require(
            await PreviewLighting.loadEnvironmentResource(from: Self.probe("env-wheel.hdr"))
        )
        let rig = try ProbeRealityRenderer(root: model.entity, toneMapping: false, format: .rgba16Float)
        rig.setIBL(environment, yaw: 0)
        for yawDegrees in [0.0, 90, 180, 270] {
            rig.setIBL(environment, yaw: Float(yawDegrees * .pi / 180))
            var row: [String] = []
            for a in azimuths {
                rig.setCamera(Self.stillPose(Self.sphereCamera(azimuth: a)))
                let pixels = try await rig.render(size: Self.size)
                if a == 0 { try Self.save(pixels, "rk-mirror-yaw\(Int(yawDegrees))-az0") }
                let linear = pixels.centre()
                let longitude = Self.decodeLongitude(linear)
                row.append(String(format: "%.1f", longitude))
                print("lookprobe yaw rk yaw=\(yawDegrees) az=\(a) longitude=\(String(format: "%.2f", longitude)) linear=\(Self.fmt(linear))")
            }
            results["rk_yaw\(Int(yawDegrees))"] = row
        }
        try Self.record("environmentYaw", results)
    }

    // MARK: - 2/3. Light scale, point vs spot

    /// White plane, one file light, no IBL, linear output. Web at the file's own 1 lux / 1 cd;
    /// RealityKit swept over a multiplier on the converted component so the linear range and
    /// the photometric scale both show.
    @Test func lightScale() async throws {
        var results: [String: Any] = [:]
        let files = ["plane-directional.gltf", "plane-point.gltf", "plane-spot.gltf"]

        let host = try WebRendererHost(mode: .still, timeout: .seconds(60))
        try await host.start(size: Self.size)
        try await host.send { .setToneMapping(id: $0, name: Self.webLinearToneMap) }
        try await host.send { .setExposure(id: $0, stops: 0) }
        for file in files {
            _ = try await host.load(model: Self.probe(file))
            try await host.setCameraPose(Self.planeCamera)
            let image = try await host.renderStill()
            try Self.save(image, "web-\(file)")
            let raster = Self.bytes(of: image)
            let centre = Self.centre(of: image)
            let linear = Self.webToLinear(centre)
            let profile = Self.profile(width: image.width) { x in
                Self.webToLinear(Self.pixel(raster, width: image.width, x: x, y: image.height / 2)).x
            }
            print("lookprobe light web \(file) srgb=\(Self.fmt(centre)) linear=\(Self.fmt(linear)) profile=\(profile)")
            results["web_\(file)"] = ["srgb": centre.x, "linear": linear.x, "profile": profile]
        }

        let multipliers: [Float] = [1, 10, 100, 1_000, 10_000, 100_000]
        for file in files {
            var rows: [[String: Any]] = []
            var base: Float = 0
            for toneMapping in [false, true] {
                // A fresh entity per renderer: one entity cannot live in two scenes.
                let model = try await EntityLoader.loadThumbnail(from: Self.probe(file))
                let light = try #require(Self.firstLight(in: model.entity))
                base = Self.lightIntensity(light)
                let rig = try ProbeRealityRenderer(
                    root: model.entity,
                    toneMapping: toneMapping,
                    format: toneMapping ? .bgra8Unorm : .rgba16Float
                )
                rig.setCamera(Self.stillPose(Self.planeCamera))
                for multiplier in multipliers {
                    Self.setLightIntensity(light, base * multiplier)
                    let pixels = try await rig.render(size: Self.size)
                    let centre = pixels.centre()
                    let profile = toneMapping ? [] : Self.profile(width: Self.size) { x in
                        pixels.at(x: x, y: Self.size / 2).x
                    }
                    if multiplier == 1_000 { try Self.save(pixels, "rk-\(file)-tm\(toneMapping)-x1000") }
                    print("lookprobe light rk \(file) tonemap=\(toneMapping) component=\(base * multiplier) value=\(Self.fmt(centre)) profile=\(profile)")
                    rows.append(["toneMapping": toneMapping, "component": base * multiplier, "value": centre.x, "profile": profile])
                }
            }
            results["rk_\(file)"] = ["convertedIntensity": base, "rows": rows]
        }
        try Self.record("lightScale", results)
    }

    /// RealityKit only: how `SpotLightComponent` reads its cone angles and whether its on-axis
    /// candela depends on the cone. Same lumens, outer angle swept, inner 0.
    @Test func spotCone() async throws {
        var results: [String: Any] = [:]
        for outer: Float in [45, 90, 120] {
            let model = try await EntityLoader.loadThumbnail(from: Self.probe("plane-spot.gltf"))
            let light = try #require(Self.firstLight(in: model.entity))
            var spot = try #require(light.components[SpotLightComponent.self])
            spot.intensity = 4 * .pi * 1_000
            spot.innerAngleInDegrees = 0
            spot.outerAngleInDegrees = outer
            light.components.set(spot)
            let rig = try ProbeRealityRenderer(root: model.entity, toneMapping: false, format: .rgba16Float)
            rig.setCamera(Self.stillPose(Self.planeCamera))
            let pixels = try await rig.render(size: Self.size)
            let profile = Self.profile(width: Self.size) { pixels.at(x: $0, y: Self.size / 2).x }
            print("lookprobe spotcone rk outer=\(outer) onAxis=\(pixels.centre().x) profile=\(profile)")
            results["outer\(Int(outer))"] = ["onAxis": pixels.centre().x, "profile": profile]
        }
        try Self.record("spotCone", results)
    }

    // MARK: - 4. Tone-map-off linearity

    /// Emissive ramp, no lights, no IBL. Web through the converter-free page; RealityKit both
    /// through the converter (glTF factor × strength) and with hand-built materials (white
    /// emissive × `emissiveIntensity`) so a colour-space slip in convert cannot pass as a
    /// renderer non-linearity.
    @Test func toneMapOffLinearity() async throws {
        var results: [String: Any] = [:]
        let factors: [Float] = [0.0125, 0.025, 0.05, 0.1, 0.2, 0.4]
        let strength: Float = 2

        let host = try WebRendererHost(mode: .still, timeout: .seconds(60))
        try await host.start(size: Self.size)
        try await host.send { .setToneMapping(id: $0, name: Self.webLinearToneMap) }
        try await host.send { .setExposure(id: $0, stops: 0) }
        _ = try await host.load(model: Self.probe("emissive-ramp.gltf"))
        try await host.setCameraPose(Self.rampCamera)
        let image = try await host.renderStill()
        try Self.save(image, "web-emissive-ramp")
        let raster = Self.bytes(of: image)
        let web = Self.rampPixels().map { Self.webToLinear(Self.pixel(raster, width: image.width, x: $0, y: image.height / 2)).x }
        print("lookprobe ramp web expected=\(factors.map { $0 * strength }) linear=\(web)")
        results["web"] = web

        for label in ["convert", "handBuilt"] {
            for (format, toneMapping) in [(MTLPixelFormat.rgba16Float, false), (.bgra8Unorm, false), (.bgra8Unorm, true), (.bgra8Unorm_srgb, false)] {
                let root = label == "convert"
                    ? try await EntityLoader.loadThumbnail(from: Self.probe("emissive-ramp.gltf")).entity
                    : Self.handBuiltRamp(intensities: factors.map { $0 * strength })
                let rig = try ProbeRealityRenderer(root: root, toneMapping: toneMapping, format: format)
                rig.setCamera(Self.stillPose(Self.rampCamera))
                let pixels = try await rig.render(size: Self.size)
                let formatName = switch format {
                case .rgba16Float: "f16"
                case .bgra8Unorm_srgb: "u8srgb"
                default: "u8"
                }
                try Self.save(pixels, "rk-ramp-\(label)-\(formatName)-tm\(toneMapping)")
                let values = Self.rampPixels().map { pixels.at(x: $0, y: Self.size / 2).x }
                let key = "\(label)_\(formatName)_tm\(toneMapping)"
                print("lookprobe ramp rk \(key) values=\(values)")
                results[key] = values
            }
        }
        try Self.record("toneMapOffLinearity", results)
    }

    // MARK: - Scenes

    static func sphereCamera(azimuth: Double) -> CameraPose {
        CameraPose(azimuth: azimuth, elevation: 0, distance: 4, target: [0, 0, 0],
                   yfov: 30 * .pi / 180, znear: 0.1, zfar: 100)
    }

    static let planeCamera = CameraPose(azimuth: 0, elevation: 0, distance: 3, target: [0, 0, 0],
                                        yfov: 60 * .pi / 180, znear: 0.1, zfar: 100)

    static let rampCamera = CameraPose(azimuth: 0, elevation: 0, distance: 6, target: [0, 0, 0],
                                       yfov: 60 * .pi / 180, znear: 0.1, zfar: 100)

    /// Quad centres at x = −2.5 … 2.5 on z = 0, projected for ``rampCamera``.
    static func rampPixels() -> [Int] {
        (0..<6).map { i in
            let x = -2.5 + Double(i)
            let ndc = x / (6 * tan(30 * Double.pi / 180))
            return Int((Double(size) / 2 * (1 + ndc)).rounded(.down))
        }
    }

    /// Same camera convention as the pixel-diff harness.
    static func stillPose(_ pose: CameraPose) -> StillCameraPose {
        PixelDiffRealityKit.stillPose(pose)
    }

    @MainActor
    static func handBuiltRamp(intensities: [Float]) -> Entity {
        let root = Entity()
        let mesh = MeshResource.generatePlane(width: 0.8, height: 0.8)
        for (i, intensity) in intensities.enumerated() {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .black)
            material.roughness = .init(floatLiteral: 1)
            material.metallic = .init(floatLiteral: 0)
            material.emissiveColor = .init(color: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            material.emissiveIntensity = intensity
            let quad = ModelEntity(mesh: mesh, materials: [material])
            quad.position = [Float(-2.5 + Double(i)), 0, 0]
            root.addChild(quad)
        }
        return root
    }

    // MARK: - Lights

    @MainActor
    static func firstLight(in entity: Entity) -> Entity? {
        if entity.components[DirectionalLightComponent.self] != nil
            || entity.components[PointLightComponent.self] != nil
            || entity.components[SpotLightComponent.self] != nil { return entity }
        for child in entity.children {
            if let found = firstLight(in: child) { return found }
        }
        return nil
    }

    @MainActor
    static func lightIntensity(_ entity: Entity) -> Float {
        entity.components[DirectionalLightComponent.self]?.intensity
            ?? entity.components[PointLightComponent.self]?.intensity
            ?? entity.components[SpotLightComponent.self]?.intensity ?? 0
    }

    @MainActor
    static func setLightIntensity(_ entity: Entity, _ value: Float) {
        if var light = entity.components[DirectionalLightComponent.self] {
            light.intensity = value
            entity.components.set(light)
        }
        if var light = entity.components[PointLightComponent.self] {
            light.intensity = value
            entity.components.set(light)
        }
        if var light = entity.components[SpotLightComponent.self] {
            light.intensity = value
            entity.components.set(light)
        }
    }

    // MARK: - Decoding

    /// `env-wheel.hdr`: R = 0.4(1 + cos φ), G = 0.4(1 + sin φ), B = 0.4, φ = 2πu.
    /// Scale-free as long as the output is linear with the same gain on every channel.
    static func decodeLongitude(_ linear: SIMD4<Float>) -> Double {
        let b = Double(max(linear.z, 1e-6))
        let degrees = atan2(Double(linear.y) / b - 1, Double(linear.x) / b - 1) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Samples every 8th pixel from the centre to the right edge along the middle row, as
    /// (plane x in scene units, linear value) for ``planeCamera``.
    static func profile(width: Int, value: (Int) -> Float) -> [[Double]] {
        stride(from: width / 2, to: width, by: 8).map { x in
            let ndc = (Double(x) + 0.5 - Double(width) / 2) / (Double(width) / 2)
            let planeX = ndc * tan(30 * Double.pi / 180) * 3
            return [(planeX * 1000).rounded() / 1000, Double(value(x))]
        }
    }

    /// The Khronos page encodes with `pow(c, 1/2.2)` (`linearTosRGB`, GAMMA 2.2), not the
    /// piecewise sRGB curve — decoding with the sRGB curve reads 0.025 back as 0.0296.
    static func webToLinear(_ c: SIMD4<Float>) -> SIMD4<Float> {
        SIMD4(pow(c.x, 2.2), pow(c.y, 2.2), pow(c.z, 2.2), c.w)
    }

    static func bytes(of image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    /// 0–1 sRGB-encoded 5×5 average.
    static func pixel(_ raster: [UInt8], width: Int, x: Int, y: Int) -> SIMD4<Float> {
        var sum = SIMD4<Float>.zero
        for dy in -2...2 {
            for dx in -2...2 {
                let base = ((y + dy) * width + (x + dx)) * 4
                sum += SIMD4(Float(raster[base]), Float(raster[base + 1]), Float(raster[base + 2]), Float(raster[base + 3]))
            }
        }
        return sum / 25 / 255
    }

    static func centre(of image: CGImage) -> SIMD4<Float> {
        pixel(bytes(of: image), width: image.width, x: image.width / 2, y: image.height / 2)
    }

    static func fmt(_ v: SIMD4<Float>) -> String {
        String(format: "(%.4f, %.4f, %.4f)", v.x, v.y, v.z)
    }

    // MARK: - Output

    static func save(_ image: CGImage, _ name: String) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try PNGWriter.write(image, to: outputDirectory.appendingPathComponent("\(name).png"))
    }

    static func save(_ pixels: ProbePixels, _ name: String) throws {
        try save(pixels.previewImage(), name)
    }

    static func record(_ name: String, _ results: [String: Any]) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: outputDirectory.appendingPathComponent("\(name).json"))
    }
}

/// Values as stored in the render target: raw unorm/255 for `bgra8Unorm` (whatever encoding the
/// renderer wrote), raw half floats for `rgba16Float`. RGBA order.
struct ProbePixels {
    var width: Int
    var height: Int
    var values: [SIMD4<Float>]
    var isFloat: Bool

    func at(x: Int, y: Int) -> SIMD4<Float> {
        var sum = SIMD4<Float>.zero
        for dy in -2...2 {
            for dx in -2...2 {
                sum += values[(y + dy) * width + (x + dx)]
            }
        }
        return sum / 25
    }

    func centre() -> SIMD4<Float> { at(x: width / 2, y: height / 2) }

    /// For eyeballing only: float values are clamped and sRGB-encoded, unorm values copied.
    func previewImage() throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for (i, v) in values.enumerated() {
            for c in 0..<3 {
                var x = min(max(v[c], 0), 1)
                if isFloat { x = x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1 / 2.4) - 0.055 }
                bytes[i * 4 + c] = UInt8((x * 255).rounded())
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }
}

/// A `RealityRenderer` set up like `StillRenderer`, minus the studio look, with the knobs the
/// probes need: tone mapping and the target format. Test-only instrumentation.
@MainActor
final class ProbeRealityRenderer {
    private let renderer: RealityRenderer
    private let root: Entity
    private let camera = Entity()
    private var ibl: Entity?
    private let format: MTLPixelFormat

    init(root: Entity, toneMapping: Bool, format: MTLPixelFormat) throws {
        renderer = try RealityRenderer()
        renderer.cameraSettings.colorBackground = .color(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        renderer.cameraSettings.antialiasing = .multisample4X
        renderer.cameraSettings.isToneMappingEnabled = toneMapping
        renderer.extendedDynamicRangeOutput = false
        renderer.entities.append(root)
        renderer.entities.append(camera)
        renderer.activeCamera = camera
        self.root = root
        self.format = format
    }

    func setCamera(_ pose: StillCameraPose) {
        let posed = pose.makeCameraEntity()
        camera.transform = posed.transform
        if let perspective = posed.components[PerspectiveCameraComponent.self] {
            camera.components.set(perspective)
        }
    }

    /// Same entity + receiver shape as `PreviewLighting.makeIBLEntity`.
    func setIBL(_ resource: EnvironmentResource, yaw: Float) {
        if ibl == nil {
            let entity = Entity()
            var light = ImageBasedLightComponent(source: .single(resource), intensityExponent: 0)
            light.inheritsRotation = true
            entity.components.set(light)
            renderer.entities.append(entity)
            Self.applyReceivers(from: entity, to: root)
            ibl = entity
        }
        ibl?.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
    }

    private static func applyReceivers(from light: Entity, to entity: Entity) {
        entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
        for child in entity.children { applyReceivers(from: light, to: child) }
    }

    func render(size: Int) async throws -> ProbePixels {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: size, height: size, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        let isFloat = format == .rgba16Float
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in
                    continuation.resume(returning: Self.read(texture, size: size, isFloat: isFloat))
                })
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    nonisolated private static func read(_ texture: MTLTexture, size: Int, isFloat: Bool) -> ProbePixels {
        let region = MTLRegionMake2D(0, 0, size, size)
        var values: [SIMD4<Float>] = []
        values.reserveCapacity(size * size)
        if isFloat {
            var halves = [Float16](repeating: 0, count: size * size * 4)
            texture.getBytes(&halves, bytesPerRow: size * 8, from: region, mipmapLevel: 0)
            for i in 0..<(size * size) {
                values.append(SIMD4(Float(halves[i * 4]), Float(halves[i * 4 + 1]), Float(halves[i * 4 + 2]), Float(halves[i * 4 + 3])))
            }
        } else {
            // `bgra8Unorm` and `bgra8Unorm_srgb`: raw stored bytes, no decode.
            var bytes = [UInt8](repeating: 0, count: size * size * 4)
            texture.getBytes(&bytes, bytesPerRow: size * 4, from: region, mipmapLevel: 0)
            for i in 0..<(size * size) {
                // BGRA → RGBA
                values.append(SIMD4(Float(bytes[i * 4 + 2]), Float(bytes[i * 4 + 1]), Float(bytes[i * 4]), Float(bytes[i * 4 + 3])) / 255)
            }
        }
        return ProbePixels(width: size, height: size, values: values, isFloat: isFloat)
    }
}
