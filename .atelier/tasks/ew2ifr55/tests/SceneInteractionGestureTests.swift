import AppKit
import Testing
@testable import Renderer

@MainActor
@Suite(.serialized)
struct SceneInteractionGestureTests {
    private func withView(_ body: (ModelView, NSWindow) throws -> Void) async throws {
        let view = ModelView(renderer: try MetalRenderer())
        try await view.load(TestFixtures.cube)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        defer { window.contentView = nil; window.close() }
        try body(view, window)
    }

    private func event(_ type: NSEvent.EventType, _ point: NSPoint, in window: NSWindow,
                       modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1
        ))
    }

    // Backlog qtuda1nk: distance traveled during a gesture matters, not only its final point.
    @Test func outAndBackOrbitDoesNotBecomeAClick() async throws {
        try await withView { view, window in
            var picks = 0
            view.onPick = { _ in picks += 1 }
            let center = NSPoint(x: 256, y: 256)
            view.mouseDown(with: try event(.leftMouseDown, center, in: window))
            view.mouseDragged(with: try event(.leftMouseDragged, NSPoint(x: 280, y: 256), in: window))
            view.mouseDragged(with: try event(.leftMouseDragged, center, in: window))
            view.mouseUp(with: try event(.leftMouseUp, center, in: window))
            #expect(picks == 0, "an orbit that returns to its press point must not change selection")
        }
    }

    @Test(arguments: [NSEvent.ModifierFlags.shift, .option, .control, .command])
    func releasingAModifierBeforeMouseUpDoesNotProduceAnUnmodifiedPick(_ modifier: NSEvent.ModifierFlags) async throws {
        try await withView { view, window in
            var picks = 0
            view.onPick = { _ in picks += 1 }
            let center = NSPoint(x: 256, y: 256)
            view.mouseDown(with: try event(.leftMouseDown, center, in: window, modifiers: modifier))
            view.mouseUp(with: try event(.leftMouseUp, center, in: window))
            #expect(picks == 0, "a modified press must not turn into a plain click when its modifier is released")
        }
    }

    @Test func plainClickPicksExactlyOnce() async throws {
        try await withView { view, window in
            var hits: [Int?] = []
            view.onPick = { hits.append($0) }
            let center = NSPoint(x: 256, y: 256)
            view.mouseDown(with: try event(.leftMouseDown, center, in: window))
            view.mouseUp(with: try event(.leftMouseUp, center, in: window))
            #expect(hits == [0])
        }
    }
}
