import AppKit
import Foundation
import RealityKit
import simd

/// Windowless 360° turntable frames for the README GIF. Never opens the host app.
final class GLBPromo: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        for window in NSApp.windows {
            window.orderOut(nil)
        }
        Task { @MainActor in
            do {
                try await run()
                NSApp.terminate(nil)
            } catch {
                GLBLog.error(GLBLog.host, "promo failed \(error)")
                fputs("\(error)\n", stderr)
                exit(1)
            }
        }
    }
}

let promoDelegate = GLBPromo()
let promoApp = NSApplication.shared
promoApp.setActivationPolicy(.prohibited)
promoApp.delegate = promoDelegate
promoApp.run()

@MainActor
private func run() async throws {
    let args = Args.parse(CommandLine.arguments)
    let entity = try await GLBEntityLoader.load(from: args.model, includeAnimations: false)
    let assembled = GLBPreviewCamera.makeTurntable(for: entity)
    let bg = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    let still = try await GLBStillRenderer(
        root: assembled.pivot,
        bounds: assembled.bounds,
        width: args.width,
        height: args.height,
        background: bg,
        padding: args.padding,
        cameraAspect: args.aspect,
        fillBackdrop: true
    )
    try FileManager.default.createDirectory(at: args.outDir, withIntermediateDirectories: true)
    _ = try await still.capture()
    for i in 0..<args.frames {
        let turns = Float(i) / Float(args.frames)
        assembled.pivot.orientation = simd_quatf(angle: turns * 2 * .pi, axis: [0, 1, 0])
        let image = try await still.capture()
        let url = args.outDir.appendingPathComponent(String(format: "frame-%03d.png", i))
        try GLBStillRenderer.writePNG(image, to: url)
    }
}

private struct Args {
    var model: URL
    var outDir: URL
    var frames: Int
    var width: Int
    var height: Int
    var aspect: Float
    var padding: Float

    static func parse(_ argv: [String]) -> Args {
        var model: URL?
        var outDir: URL?
        var frames = 48
        var width = 960
        var height = 540
        var aspect: Float = 1
        var padding: Float = 1
        var i = 1
        while i < argv.count {
            let key = argv[i]
            func take() -> String {
                i += 1
                precondition(i < argv.count, "missing value for \(key)")
                return argv[i]
            }
            switch key {
            case "--model": model = URL(fileURLWithPath: take())
            case "--out-dir": outDir = URL(fileURLWithPath: take(), isDirectory: true)
            case "--frames": frames = Int(take()) ?? frames
            case "--width": width = Int(take()) ?? width
            case "--height": height = Int(take()) ?? height
            case "--aspect": aspect = Float(take()) ?? aspect
            case "--padding": padding = Float(take()) ?? padding
            default:
                fputs("unknown arg \(key)\n", stderr)
                exit(2)
            }
            i += 1
        }
        guard let model, let outDir else {
            fputs("usage: GLBPromo --model file.glb --out-dir dir [--frames 48] [--width 960] [--height 540] [--aspect 1] [--padding 1]\n", stderr)
            exit(2)
        }
        return Args(model: model, outDir: outDir, frames: frames, width: width, height: height, aspect: aspect, padding: padding)
    }
}
