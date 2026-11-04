import AppKit
import CoreGraphics
import Foundation

/// What a canvas, Quick Look and the thumbnail need from a renderer. Two implementations:
/// `FilamentRendererHost` (Metal, the default on this branch) and `WebRendererHost` (the Khronos
/// page in WebKit, kept for `GLTF_RENDERER=webkit` and the pixel-diff tests).
@MainActor
public protocol CanvasRendererHost: AnyObject {
    var isBroken: Bool { get }
    /// Called when a renderer that was running dies. The owner decides whether to `start()` again.
    var onFailure: ((WebRendererError) -> Void)? { get set }
    /// Live mode: the camera's zoom against the last fit, as a whole percent, when it changes.
    var onZoom: ((Int) -> Void)? { get set }
    /// The live surface. Untouched in `.still`.
    var view: NSView { get }
    var logID: String { get }
    /// Short name shown on the live canvas, e.g. "Filament 1.80 · Metal".
    var rendererName: String { get }

    func start() async throws
    func apply(_ look: WebPreviewCanvas.Look) async throws
    @discardableResult func load(model url: URL) async throws -> WebRendererHost.LoadInfo
    @discardableResult func camera(_ command: CameraCommand) async throws -> RendererCameraState
    func renderStillPNG(size: Int?) async throws -> Data
    func renderStill(size: Int?) async throws -> CGImage
}

extension CanvasRendererHost {
    public func renderStillPNG() async throws -> Data { try await renderStillPNG(size: nil) }
    public func renderStill() async throws -> CGImage { try await renderStill(size: nil) }
}

extension WebRendererHost: CanvasRendererHost {
    public var rendererName: String { "WebKit · Khronos Sample Renderer" }
}

@MainActor
public enum CanvasRenderer {
    /// Filament, unless the process runs with `GLTF_RENDERER=webkit`.
    public static func makeHost(mode: WebRendererMode, size: Int = 512) throws -> any CanvasRendererHost {
        if ProcessInfo.processInfo.environment["GLTF_RENDERER"] == "metal" {
            return KhronosMetalRendererHost(mode: mode, size: size)
        }
        if ProcessInfo.processInfo.environment["GLTF_RENDERER"] == "webkit" {
            return try WebRendererHost(mode: mode, size: size)
        }
        return FilamentRendererHost(mode: mode, size: size)
    }
}
