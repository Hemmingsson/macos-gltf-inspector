import Cocoa
import GLTFCore
import QuickLookUI

/// Quick Look principal class and the extension's one renderer router. It reads the renderer
/// switch when Quick Look builds the preview and embeds that renderer's controller
/// (`QuickLookRealityKit.swift` / `QuickLookWebKit.swift`). Each case is guarded by `canImport`,
/// so removing a renderer from this target needs no edit here.
class PreviewViewController: NSViewController, QLPreviewingController {
    /// The renderer's controller and its `preparePreviewOfFile` (held as a closure: calling the
    /// optional async protocol method through an existential crashes the Swift 6.4 compiler).
    private var renderer: (controller: NSViewController, prepare: (URL) async throws -> Void)!

    override func loadView() {
        renderer = Self.makeRenderer(RendererKind.stored())
        addChild(renderer.controller)
        let root = renderer.controller.view
        root.autoresizingMask = [.width, .height]
        view = root
    }

    func preparePreviewOfFile(at url: URL) async throws {
        try await renderer.prepare(url)
    }

    private static func makeRenderer(
        _ kind: RendererKind
    ) -> (controller: NSViewController, prepare: (URL) async throws -> Void) {
        AppLog.info(AppLog.preview, "ql renderer \(kind.rawValue)")
        #if canImport(RendererWebKit)
        if kind == .webKit {
            let web = WebQuickLookController()
            return (web, web.preparePreviewOfFile(at:))
        }
        #endif
        #if canImport(RendererRealityKit)
        let reality = RealityQuickLookController()
        return (reality, reality.preparePreviewOfFile(at:))
        #else
        let web = WebQuickLookController()
        return (web, web.preparePreviewOfFile(at:))
        #endif
    }

    static func systemIsDark() -> Bool {
        if UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" {
            return true
        }
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return true
        }
        return false
    }
}
