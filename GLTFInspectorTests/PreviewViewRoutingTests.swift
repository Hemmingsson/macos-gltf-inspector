import Foundation
@testable import GLTFInspector
import PreviewUI
import RendererWebKit
import Testing

/// Which state the document window's canvas region shows. With the web canvas mounted, only the
/// canvas's own failure fails it — a RealityKit convert that is still running, or failed, must
/// not hide a page that draws.
@MainActor
struct PreviewViewRoutingTests {
    private let url = URL(fileURLWithPath: "/tmp/model.glb")

    @Test func convertFailureDoesNotHideTheWebCanvas() {
        #expect(
            PreviewView.canvasState(webCanvasURL: url, webPhase: .ready, convert: .failed("convert"))
                == .ready
        )
        #expect(
            PreviewView.canvasState(webCanvasURL: url, webPhase: .loading, convert: .failed("convert"))
                == .ready
        )
    }

    @Test func webCanvasMountsBeforeConvertLands() {
        #expect(PreviewView.canvasState(webCanvasURL: url, webPhase: .loading, convert: .loading) == .ready)
    }

    @Test func webFailureFailsTheCanvas() {
        #expect(
            PreviewView.canvasState(webCanvasURL: url, webPhase: .failed("bad glb"), convert: .loading)
                == .failed("bad glb")
        )
    }

    @Test func realityKitFallbackFollowsConvert() {
        #expect(PreviewView.canvasState(webCanvasURL: nil, webPhase: nil, convert: .loading) == .loading)
        #expect(
            PreviewView.canvasState(webCanvasURL: nil, webPhase: nil, convert: .failed("x")) == .failed("x")
        )
    }
}
