import AppKit
import GLTFCore
import simd
import Testing
@testable import Renderer

@MainActor
@Suite(.serialized)
struct SceneInteractionGestureTests {
    @Test(arguments: [false, true])
    func shiftPanMovesTheModelWithThePointer(orthographic: Bool) async throws {
        try await withView(orthographic: orthographic) { view, window in
            // Pan must move content right/up when the pointer moves right/up,
            // regardless of projection or the camera's initial orbit angles.
            let before = view.camera
            let right = simd_normalize(simd_cross(before.lookDirection, SIMD3<Double>(0, 1, 0)))
            let up = simd_normalize(simd_cross(right, before.lookDirection))
            let point = before.target
            let start = NSPoint(x: 200, y: 200)
            let end = NSPoint(x: 230, y: 220)
            view.mouseDown(with: try testMouseEvent(.leftMouseDown, start, in: window, modifiers: .shift))
            view.mouseDragged(with: try testMouseEvent(.leftMouseDragged, end, in: window, modifiers: .shift))
            view.mouseUp(with: try testMouseEvent(.leftMouseUp, end, in: window, modifiers: .shift))
            let beforeRelative = point - before.position
            let afterRelative = point - view.camera.position
            #expect(simd_dot(afterRelative, right) > simd_dot(beforeRelative, right))
            #expect(simd_dot(afterRelative, up) > simd_dot(beforeRelative, up))
            #expect(view.camera.lookDirection == before.lookDirection)
            #expect(view.camera.distance == before.distance)
        }
    }

    private func withView(orthographic: Bool = false, _ body: (ModelView, NSWindow) throws -> Void) async throws {
        let view = ModelView(renderer: try MetalRenderer())
        try await view.load(TestFixtures.cube, options: ViewOptions(isOrthographic: orthographic))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        defer { window.contentView = nil; window.close() }
        try body(view, window)
    }

    // Backlog qtuda1nk: distance traveled during a gesture matters, not only its final point.
    @Test func outAndBackOrbitDoesNotBecomeAClick() async throws {
        try await withView { view, window in
            var picks = 0
            view.onPick = { _ in picks += 1 }
            let center = NSPoint(x: 256, y: 256)
            view.mouseDown(with: try testMouseEvent(.leftMouseDown, center, in: window))
            view.mouseDragged(with: try testMouseEvent(.leftMouseDragged, NSPoint(x: 280, y: 256), in: window))
            view.mouseDragged(with: try testMouseEvent(.leftMouseDragged, center, in: window))
            view.mouseUp(with: try testMouseEvent(.leftMouseUp, center, in: window))
            #expect(picks == 0, "an orbit that returns to its press point must not change selection")
        }
    }

    @Test(arguments: [NSEvent.ModifierFlags.shift, .option, .control, .command])
    func releasingAModifierBeforeMouseUpDoesNotProduceAnUnmodifiedPick(_ modifier: NSEvent.ModifierFlags) async throws {
        try await withView { view, window in
            var picks = 0
            view.onPick = { _ in picks += 1 }
            let center = NSPoint(x: 256, y: 256)
            view.mouseDown(with: try testMouseEvent(.leftMouseDown, center, in: window, modifiers: modifier))
            view.mouseUp(with: try testMouseEvent(.leftMouseUp, center, in: window))
            #expect(picks == 0, "a modified press must not turn into a plain click when its modifier is released")
        }
    }

    @Test func plainClickPicksExactlyOnce() async throws {
        try await withView { view, window in
            var hits: [Int?] = []
            view.onPick = { hits.append($0) }
            let center = NSPoint(x: 256, y: 256)
            view.mouseDown(with: try testMouseEvent(.leftMouseDown, center, in: window))
            view.mouseUp(with: try testMouseEvent(.leftMouseUp, center, in: window))
            #expect(hits == [0])
        }
    }
}
