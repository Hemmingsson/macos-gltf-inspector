import Foundation
@testable import GLTFInspector
import PreviewUI
import RendererWebKit
import Testing

/// Which state the WebKit window's canvas region shows. Only the page's own failure fails it —
/// panels still loading from JSON, or failed, must not hide a page that draws.
@MainActor
struct WebCanvasRoutingTests {
    private let url = URL(fileURLWithPath: "/tmp/model.glb")

    @Test func panelFailureDoesNotHideTheWebCanvas() {
        #expect(
            WebDocumentWindow.canvasState(webCanvasURL: url, webPhase: .ready, panels: .failed("json"))
                == .ready
        )
        #expect(
            WebDocumentWindow.canvasState(webCanvasURL: url, webPhase: .loading, panels: .failed("json"))
                == .ready
        )
    }

    @Test func webCanvasMountsBeforeThePanelsLand() {
        #expect(WebDocumentWindow.canvasState(webCanvasURL: url, webPhase: .loading, panels: .loading) == .ready)
    }

    @Test func webFailureFailsTheCanvas() {
        #expect(
            WebDocumentWindow.canvasState(webCanvasURL: url, webPhase: .failed("bad glb"), panels: .loading)
                == .failed("bad glb")
        )
    }

    @Test func withoutAPageTheCanvasFollowsThePanels() {
        #expect(
            WebDocumentWindow.canvasState(webCanvasURL: nil, webPhase: .loading, panels: .failed("x")) == .failed("x")
        )
    }
}
