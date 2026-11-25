// shot-renderer — real frames from the one renderer, with no window.
//
// Every moving picture in the README is drawn by `Renderer.ModelView`, the same canvas the
// document window, Quick Look and the Finder thumbnail mount. The macOS chrome around it is
// mocked in HTML (demo/video); the model inside it never is.
//
// Usage:
//   shot-renderer --model FILE --out DIR [options]
//
// Options:
//   --out DIR          directory for the PNG sequence (created; 0000.png, 0001.png, …)
//   --frames N         turntable frames for one full 360° orbit (default 120). 1 = a still.
//   --size WxH         pixel size per frame (default 1600x1200)
//   --preset NAME      starting camera: front back left right top bottom isometric (default isometric)
//   --view NAME        shaded clay xray wireframe wireframeOnShaded, or a channel:
//                      baseColor metallic roughness normals tangents textureCoordinates
//                      ambientOcclusion emissive alpha                      (default shaded)
//   --floor            draw the contact-shadow floor
//   --gizmos           draw authored camera / light gizmos
//   --exposure EV      exposure compensation in stops (default 0)
//   --yaw DEG          environment rotation about +Y (default 0)
//   --background CSS   #rrggbb[aa] behind the model (default transparent)
//   --zoom F           dolly by F after framing (>1 pulls back, <1 pushes in; default 1)
//   --fov DEG          vertical field of view (default 45)
//
// Frames are transparent PNGs unless --background is given, so the HTML demo can composite
// them straight into a mocked window.
//
// Exit code 0 when every frame was written.

import AppKit
import GLTFCore
import Renderer

// MARK: - Arguments

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("shot-renderer: \(message)\n".utf8))
    exit(2)
}

var modelPath: String?
var outPath: String?
var frameCount = 120
var width = 1600, height = 1200
var preset = CameraPreset.isometric
var viewMode = RenderViewMode.shaded
var showsFloor = false, showsGizmos = false
var exposureEV = 0.0, yawDegrees = 0.0
var background = RenderLook.Color.clear
var zoomFactor = 1.0
var fieldOfView = 45.0

/// `#rgb`, `#rrggbb` or `#rrggbbaa`; anything else is a usage error.
func parseColor(_ text: String) -> RenderLook.Color {
    var hex = text.hasPrefix("#") ? String(text.dropFirst()) : text
    if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
    if hex.count == 6 { hex += "ff" }
    guard hex.count == 8, let value = UInt32(hex, radix: 16) else { die("bad --background \(text)") }
    func channel(_ shift: UInt32) -> Double { Double((value >> shift) & 0xff) / 255 }
    return RenderLook.Color(red: channel(24), green: channel(16), blue: channel(8), alpha: channel(0))
}

func parseViewMode(_ name: String) -> RenderViewMode {
    switch name {
    case "shaded": return .shaded
    case "clay": return .clay
    case "xray": return .xray
    case "wireframe": return .wireframe
    case "wireframeOnShaded": return .wireframeOnShaded
    default:
        guard let channel = RenderViewMode.Channel(rawValue: name) else { die("unknown --view \(name)") }
        return .channel(channel)
    }
}

var arguments = Array(CommandLine.arguments.dropFirst())
func next(_ flag: String) -> String {
    guard !arguments.isEmpty else { die("\(flag) needs a value") }
    return arguments.removeFirst()
}
while !arguments.isEmpty {
    let flag = arguments.removeFirst()
    switch flag {
    case "--model": modelPath = next(flag)
    case "--out": outPath = next(flag)
    case "--frames": frameCount = Int(next(flag)) ?? frameCount
    case "--size":
        let parts = next(flag).lowercased().split(separator: "x")
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) else { die("bad --size") }
        (width, height) = (w, h)
    case "--preset":
        let name = next(flag)
        guard let value = CameraPreset(rawValue: name) else { die("unknown --preset \(name)") }
        preset = value
    case "--view": viewMode = parseViewMode(next(flag))
    case "--floor": showsFloor = true
    case "--gizmos": showsGizmos = true
    case "--exposure": exposureEV = Double(next(flag)) ?? exposureEV
    case "--yaw": yawDegrees = Double(next(flag)) ?? yawDegrees
    case "--background": background = parseColor(next(flag))
    case "--zoom": zoomFactor = Double(next(flag)) ?? zoomFactor
    case "--fov": fieldOfView = Double(next(flag)) ?? fieldOfView
    default: die("unknown option \(flag)")
    }
}
guard let modelPath, let outPath else { die("usage: shot-renderer --model FILE --out DIR [options]") }
guard frameCount > 0 else { die("--frames must be positive") }
guard width > 0, height > 0, width <= 8192, height <= 8192 else { die("--size must be within 1…8192") }
guard zoomFactor.isFinite, zoomFactor > 0, fieldOfView.isFinite, fieldOfView > 0, fieldOfView < 180, exposureEV.isFinite, yawDegrees.isFinite else { die("invalid camera or lighting value") }

// MARK: - Render

/// Writes one frame, atomically, so a reader never picks up a half-written PNG.
func writePNG(_ image: CGImage, to url: URL) throws {
    let bitmap = NSBitmapImageRep(cgImage: image)
    bitmap.size = NSSize(width: image.width, height: image.height)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url, options: .atomic)
}

@MainActor
func run() async {
    let model = URL(fileURLWithPath: modelPath)
    let directory = URL(fileURLWithPath: outPath, isDirectory: true)
    let started = Date()
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var look = RenderLook.standard
        look.exposureEV = exposureEV
        look.environmentYawDegrees = yawDegrees
        look.background = background
        // No selection, hover or highlight: these frames stand in for an untouched canvas.
        let options = ViewOptions(look: look, viewMode: viewMode, fieldOfView: fieldOfView,
                                  showsFloor: showsFloor, showsSceneGizmos: showsGizmos)

        // Off-screen, exactly as `ThumbnailRenderer` drives it: a `ModelView` never added to a
        // window still lays out and draws, because the Metal layer owns its own drawable.
        let view = ModelView(renderer: try MetalRenderer())
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        try await view.load(model, options: options)
        view.show(preset)
        if zoomFactor != 1 { view.zoom(by: zoomFactor) }

        if frameCount == 1 {
            try writePNG(view.image(width: width, height: height), to: directory.appendingPathComponent("0000.png"))
        } else {
            try await view.turntable(count: frameCount, width: width, height: height) { index, image in
                try writePNG(image, to: directory.appendingPathComponent(String(format: "%04d.png", index)))
            }
        }
        let seconds = Date().timeIntervalSince(started)
        print("ok \(frameCount) frame\(frameCount == 1 ? "" : "s") \(width)x\(height) " +
              "in \(String(format: "%.1f", seconds))s → \(directory.path)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("shot-renderer: \(model.lastPathComponent): \(error)\n".utf8))
        exit(1)
    }
}

// A GPU renderer wants a run loop and an AppKit app; `.prohibited` keeps it off the Dock and
// out of the user's focus, so a render never steals the screen mid-session.
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
Task { await run() }
application.run()
