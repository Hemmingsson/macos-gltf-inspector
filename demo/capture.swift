// Native window lookup and wallpaper composition. No Accessibility permission needed.
import AppKit
import CoreGraphics

func fail(_ message: String) -> Never {
    fputs(message + "\n", stderr)
    exit(1)
}
let args = Array(CommandLine.arguments.dropFirst())
if args.first == "window" {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { fail("Cannot list windows") }
    let expectedPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
    let pid = NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == expectedPath }?.processIdentifier
    if !expectedPath.isEmpty && pid == nil { fail("Requested app is not running: " + expectedPath) }
    let matches = list.filter {
        ($0[kCGWindowOwnerName as String] as? String) == "glTF Inspector" &&
        (pid == nil || ($0[kCGWindowOwnerPID as String] as? Int32) == pid) &&
        ($0[kCGWindowLayer as String] as? Int) == 0 &&
        (($0[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double ?? 0) > 400
    }
    guard let window = matches.first, let id = window[kCGWindowNumber as String] as? Int else { fail("No visible glTF Inspector window") }
    print(id)
} else if args.first == "compose", args.count == 4 {
    guard let capture = NSImage(contentsOfFile: args[1]) else { fail("Cannot load window PNG") }
    let wallpaper = args[2] == "-" ? nil : NSImage(contentsOfFile: args[2])
    if args[2] != "-" && wallpaper == nil { fail("Cannot load wallpaper") }
    let size = NSSize(width: 1920, height: 1080)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1920, pixelsHigh: 1080,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fail("Cannot create bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let rect = NSRect(origin: .zero, size: size)
    NSBezierPath(roundedRect: rect, xRadius: 48, yRadius: 48).addClip()
    if let wallpaper {
        let factor = max(size.width / wallpaper.size.width, size.height / wallpaper.size.height)
        let width = wallpaper.size.width * factor, height = wallpaper.size.height * factor
        wallpaper.draw(in: NSRect(x: (size.width-width)/2, y: (size.height-height)/2, width: width, height: height))
    } else {
        NSGradient(starting: NSColor(calibratedRed: 0.39, green: 0.47, blue: 0.64, alpha: 1), ending: NSColor(calibratedRed: 0.92, green: 0.72, blue: 0.68, alpha: 1))!.draw(in: rect, angle: 35)
    }
    let factor = min(1640 / capture.size.width, 860 / capture.size.height)
    let width = capture.size.width * factor, height = capture.size.height * factor
    let windowRect = NSRect(x: (size.width-width)/2, y: (size.height-height)/2, width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: windowRect, xRadius: 16, yRadius: 16).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSBezierPath(roundedRect: windowRect, xRadius: 16, yRadius: 16).addClip()
    capture.draw(in: windowRect)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fail("Cannot encode PNG") }
    try png.write(to: URL(fileURLWithPath: args[3]), options: .atomic)
} else { fail("usage: capture window | capture compose WINDOW.png WALLPAPER|- OUTPUT.png") }
