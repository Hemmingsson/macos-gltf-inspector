import AppKit
import CoreGraphics
import Foundation

/// What a canvas, Quick Look and the thumbnail need from a renderer. Three implementations:
/// `KhronosMetalRendererHost` (the native Metal port of the Khronos Sample Renderer, the default
/// for every surface), `FilamentRendererHost` (`GLTF_RENDERER=filament`) and `WebRendererHost`
/// (the Khronos page in WebKit: `GLTF_RENDERER=webkit`, and the pixel-diff oracle).
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
    /// Short name shown on the live canvas, e.g. "Metal · Khronos 863b981".
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

/// The one renderer switch. Window, Quick Look and the Finder thumbnail all build their host
/// here, so the three surfaces always draw with the same backend. Dev-only: `GLTF_RENDERER` in
/// the process environment, never a user setting (AGENTS.md pitfall 7).
@MainActor
public enum CanvasRenderer {
    public enum Backend: String, CaseIterable, Sendable {
        /// Native Metal port of the Khronos Sample Renderer (`RendererMetal`). The default.
        case metal
        /// Google's Filament: `GLTF_RENDERER=filament`.
        case filament
        /// The Khronos page in a `WKWebView`: `GLTF_RENDERER=webkit`.
        case webkit
    }

    /// The backend `GLTF_RENDERER` names, else `.metal` (also for an unknown value).
    public nonisolated static func backend(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Backend {
        environment["GLTF_RENDERER"].flatMap { Backend(rawValue: $0.lowercased()) } ?? .metal
    }

    public static func makeHost(
        mode: WebRendererMode,
        size: Int = 512,
        backend: Backend = CanvasRenderer.backend()
    ) throws -> any CanvasRendererHost {
        switch backend {
        case .metal: KhronosMetalRendererHost(mode: mode, size: size)
        case .filament: FilamentRendererHost(mode: mode, size: size)
        case .webkit: try WebRendererHost(mode: mode, size: size)
        }
    }
}
