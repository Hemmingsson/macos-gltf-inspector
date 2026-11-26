// Generate the demo's model footage with glTF Inspector's Metal renderer.
// Run from the repository root via demo-video/turntable.sh.
import AppKit
import GLTFCore
import Renderer

@main struct DemoTurntable {
    @MainActor static func main() async throws {
        let view = try ModelView(renderer: MetalRenderer())
        let width = 744, height = 668, frames = 900
        view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        var options = ViewOptions(fieldOfView: 35, showsFloor: true)
        options.look.background = .init(red: 0.92, green: 0.94, blue: 0.94, alpha: 1)
        try await view.load(URL(fileURLWithPath: CommandLine.arguments[1]), options: options)
        view.show(.isometric)
        view.zoom(by: 0.48)
        for index in 0..<frames {
            if index == 432 || index == 642 {
                options.viewMode = index == 432 ? .wireframe : .shaded
                try await view.apply(options)
            }
            let image = try view.image(width: width, height: height)
            try autoreleasepool {
                guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                else { throw CocoaError(.fileWriteUnknown) }
                try FileHandle.standardOutput.write(contentsOf: data)
            }
            view.orbit(dx: -360 * .pi / Double(frames), dy: 0)
        }
    }
}
