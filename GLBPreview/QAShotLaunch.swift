import AppKit
import CoreGraphics
import Foundation
import RealityKit
import ScreenCaptureKit
import SwiftUI

/// `GLBPreview --qa-shots OUT file.glb …` — sequential host-canvas PNGs, then quit.
enum QAShotLaunch {
    private(set) static var outputDirectory: URL?
    private(set) static var files: [URL] = []
    private(set) static var settleNanoseconds: UInt64 = 2_500_000_000
    static var isActive: Bool { outputDirectory != nil }

    static func parse(_ args: [String]) -> (output: URL, files: [URL], settle: UInt64)? {
        var remaining = Array(args.dropFirst())
        var out: URL?
        var settle: UInt64 = 2_500_000_000
        var files: [URL] = []
        while let arg = remaining.first {
            remaining.removeFirst()
            if arg == "--qa-shots", let dir = remaining.first {
                remaining.removeFirst()
                out = URL(fileURLWithPath: dir, isDirectory: true)
            } else if arg == "--settle-ms", let raw = remaining.first, let ms = UInt64(raw) {
                remaining.removeFirst()
                settle = ms * 1_000_000
            } else if arg.hasPrefix("-") {
                continue
            } else {
                let url = URL(fileURLWithPath: arg)
                let ext = url.pathExtension.lowercased()
                if ext == "glb" || ext == "gltf" {
                    files.append(url)
                }
            }
        }
        guard let out, !files.isEmpty else { return nil }
        return (out, files, settle)
    }

    static func parseCommandLine(_ args: [String] = CommandLine.arguments) {
        guard let parsed = parse(args) else { return }
        try? FileManager.default.createDirectory(at: parsed.output, withIntermediateDirectories: true)
        outputDirectory = parsed.output
        files = parsed.files
        settleNanoseconds = parsed.settle
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        note("qa parsed files=\(files.count) out=\(parsed.output.path)")
    }

    /// Runs from `applicationDidFinishLaunching` so a SwiftUI window that never
    /// `onAppear`s cannot stall capture (AppKit idle, no `qa start`).
    @MainActor
    static func runStandalone() async {
        guard let out = outputDirectory else { return }
        var rows: [[String: Any]] = []
        var failed = false
        note("qa start files=\(files.count) out=\(out.path)")
        for (index, url) in files.enumerated() {
            let name = url.lastPathComponent
            note("qa file \(index + 1)/\(files.count) \(name)")
            GLBLoadFailure.reset()
            let state = await GLBPreviewView.State.loaded(from: url)
            let status: String
            let loaded: GLBEntityLoader.LoadedModel?
            switch state {
            case .ready(let model):
                status = "ready"
                loaded = model
            case .failed:
                status = "fail"
                loaded = nil
            case .loading:
                status = "timeout"
                loaded = nil
            }
            var shot = ""
            var shotSource = ""
            var shotBytes = 0
            var session: ViewerSession?
            if let model = loaded {
                let hasLights = !model.document.lights.isEmpty || entityHasPunctualLight(model.entity)
                session = ViewerSession(document: model.document, defaultExponent: hasLights ? -2 : 0)
                NSApp.windows.forEach { $0.makeKeyAndOrderFront(nil) }
                try? await Task.sleep(nanoseconds: settleNanoseconds)
                var data: Data?
                var source = "window"
                if let view = hostingView() {
                    data = await pngData(of: view)
                }
                if data == nil {
                    data = await stillPNG(entity: model.entity)
                    source = "still-renderer"
                }
                if let data {
                    let dest = out.appendingPathComponent("\(index + 1)-\(name).png")
                    try? data.write(to: dest)
                    shot = dest.lastPathComponent
                    shotSource = source
                    shotBytes = data.count
                    note("qa shot \(shot) bytes=\(data.count) source=\(source)")
                } else {
                    shotSource = "failed"
                    note("qa shot failed \(name) (empty window + still-renderer)")
                    failed = true
                }
            } else {
                note("qa \(status) \(name)")
                failed = true
            }
            QAShotDump.write(
                index: index + 1,
                url: url,
                status: status,
                model: loaded,
                session: session,
                loadError: GLBLoadFailure.lastMessage,
                logLines: GLBLoadFailure.lines,
                shotName: shot,
                shotSource: shotSource,
                shotBytes: shotBytes
            )
            rows.append([
                "file": name,
                "path": url.path,
                "status": status,
                "shot": shot,
                "shotSource": shotSource,
            ])
        }
        let manifest = out.appendingPathComponent("manifest.json")
        if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted]) {
            try? data.write(to: manifest)
        }
        note("qa done failed=\(failed)")
        NSApp.terminate(nil)
        if failed {
            exit(1)
        }
    }

    static func note(_ message: String) {
        GLBLog.info(GLBLog.host, message)
        guard let dir = outputDirectory else { return }
        let url = dir.appendingPathComponent("qa.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: Data((message + "\n").utf8))
    }

    static func pngData(of view: NSView) async -> Data? {
        if let data = await screenCapturePNG(of: view), !isEmptyCanvas(data) { return data }
        if let data = cacheDisplayPNG(of: view), !isEmptyCanvas(data) { return data }
        return nil
    }

    /// Offscreen RealityRenderer with Studio IBL — used when the window bitmap is still `#262626`.
    @MainActor
    static func stillPNG(entity: Entity) async -> Data? {
        await GLBPreviewLighting.prefetchStudioIBL()
        let clone = entity.clone(recursive: true)
        let assembled = GLBPreviewCamera.makeTurntable(for: clone)
        let root = Entity()
        root.addChild(assembled.pivot)
        if let ibl = GLBPreviewLighting.makeStudioIBLEntity(receiver: assembled.pivot) {
            root.addChild(ibl)
        }
        let backdrop = CGColor(srgbRed: 38 / 255, green: 38 / 255, blue: 38 / 255, alpha: 1)
        do {
            let renderer = try await GLBStillRenderer(
                root: root,
                bounds: assembled.bounds,
                width: 960,
                height: 640,
                background: backdrop,
                padding: GLBPreviewCamera.previewFitPadding
            )
            let image = try await renderer.capture()
            let dest = outputDirectory?.appendingPathComponent(".still-tmp.png")
            guard let dest else { return nil }
            try GLBStillRenderer.writePNG(image, to: dest)
            let data = try Data(contentsOf: dest)
            try? FileManager.default.removeItem(at: dest)
            return isEmptyCanvas(data) ? nil : data
        } catch {
            note("qa still-renderer failed \(error.localizedDescription)")
            return nil
        }
    }

    static func isEmptyCanvas(_ data: Data) -> Bool {
        guard let rep = NSBitmapImageRep(data: data), let image = rep.cgImage else { return true }
        let w = image.width
        let h = image.height
        guard w > 16, h > 16, let pixels = image.dataProvider?.data else { return true }
        let ptr = CFDataGetBytePtr(pixels)
        guard let ptr else { return true }
        let bytesPerRow = image.bytesPerRow
        let bpp = max(image.bitsPerPixel / 8, 3)
        // Title-bar traffic lights used to give the whole-window PNG enough
        // variance that a Metal-less `#262626` RealityView never fell through.
        let y0 = min(max(h / 8, 16), 56)
        let x0 = w / 20
        var sum = 0
        var sumSq = 0
        var n = 0
        var y = y0
        while y < h - 4 {
            var x = x0
            while x < w - x0 {
                let i = y * bytesPerRow + x * bpp
                let r = Int(ptr[i])
                let g = Int(ptr[i + 1])
                let b = Int(ptr[i + 2])
                sum += r + g + b
                sumSq += r * r + g * g + b * b
                n += 1
                x += max((w - 2 * x0) / 20, 1)
            }
            y += max((h - y0) / 16, 1)
        }
        guard n > 0 else { return true }
        let mean = Double(sum) / Double(n * 3)
        let variance = Double(sumSq) / Double(n * 3) - mean * mean
        return variance.squareRoot() < 2
    }

    private static func screenCapturePNG(of view: NSView) async -> Data? {
        guard let window = view.window else { return nil }
        let wanted = CGWindowID(window.windowNumber)
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let scWindow = content.windows.first(where: { $0.windowID == wanted })
        else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = SCStreamConfiguration()
        let scale = window.backingScaleFactor
        config.width = max(Int(view.bounds.width * scale), 1)
        config.height = max(Int(view.bounds.height * scale), 1)
        config.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        ) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private static func cacheDisplayPNG(of view: NSView) -> Data? {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds)
        else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    private static func entityHasPunctualLight(_ entity: Entity) -> Bool {
        if entity.components.has(PointLightComponent.self)
            || entity.components.has(SpotLightComponent.self)
            || entity.components.has(DirectionalLightComponent.self)
        {
            return true
        }
        return entity.children.contains { entityHasPunctualLight($0) }
    }

    static func hostingView() -> GLBPreviewHostingView? {
        for window in NSApp.windows {
            if let found = firstView(GLBPreviewHostingView.self, in: window.contentView) {
                return found
            }
        }
        return nil
    }

    private static func firstView<T: NSView>(_ type: T.Type, in root: NSView?) -> T? {
        guard let root else { return nil }
        if let match = root as? T { return match }
        for child in root.subviews {
            if let found = firstView(type, in: child) { return found }
        }
        return nil
    }
}
