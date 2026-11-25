// Native-window PNGs in, transparent composition out. Coordinates are top-left pixels.
import AppKit

struct Layer: Decodable { let source: String; let rect: [Double] }
struct Layout: Decodable { let size: [Int]; let layers: [Layer] }
let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 4 else {
    fatalError("usage: compose-mockup LAYOUTS.json KIND INPUT_DIRECTORY OUTPUT.png")
}
let layouts = try JSONDecoder().decode([String: Layout].self, from: Data(contentsOf: URL(fileURLWithPath: args[0])))
guard let layout = layouts[args[1]], layout.size.count == 2 else { fatalError("Unknown layout") }
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: layout.size[0], pixelsHigh: layout.size[1],
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: layout.size[0], height: layout.size[1]).fill(using: .copy)
for layer in layout.layers {
    guard layer.rect.count == 4,
          let image = NSImage(contentsOfFile: "\(args[2])/\(layer.source).png") else {
        fatalError("Missing source PNG or invalid rectangle: \(layer.source)")
    }
    let r = layer.rect
    let scale = min(r[2] / image.size.width, r[3] / image.size.height)
    let w = image.size.width * scale, h = image.size.height * scale
    image.draw(in: NSRect(x: r[0] + (r[2] - w) / 2,
        y: Double(layout.size[1]) - r[1] - r[3] + (r[3] - h) / 2, width: w, height: h))
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]), options: .atomic)
