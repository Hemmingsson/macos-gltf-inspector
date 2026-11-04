import Foundation
@testable import GLTFInspector
import Renderer
import Testing

/// Which state the document window's canvas region shows. Only the renderer's own failure fails
/// it: panels still loading from JSON, or failed, must not hide a model that draws.
@MainActor
struct CanvasRoutingTests {
    private let url = URL(fileURLWithPath: "/tmp/model.glb")

    @Test func panelFailureDoesNotHideTheCanvas() {
        #expect(
            DocumentWindow.canvasState(canvasURL: url, canvasPhase: .ready, panels: .failed("json"))
                == .ready
        )
        #expect(
            DocumentWindow.canvasState(canvasURL: url, canvasPhase: .loading, panels: .failed("json"))
                == .ready
        )
    }

    @Test func canvasMountsBeforeThePanelsLand() {
        #expect(DocumentWindow.canvasState(canvasURL: url, canvasPhase: .loading, panels: .loading) == .ready)
    }

    @Test func rendererFailureFailsTheCanvas() {
        #expect(
            DocumentWindow.canvasState(canvasURL: url, canvasPhase: .failed("bad glb"), panels: .loading)
                == .failed("bad glb")
        )
    }

    @Test func withoutAFileTheCanvasFollowsThePanels() {
        #expect(
            DocumentWindow.canvasState(canvasURL: nil, canvasPhase: .loading, panels: .failed("x")) == .failed("x")
        )
    }
}
