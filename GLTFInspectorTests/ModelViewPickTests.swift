import AppKit
import GLTFCore
import Testing
@testable import Renderer

@MainActor
@Suite(.serialized)
struct ModelViewPickTests {
    @Test func clickWhenWithinThreshold() {
        #expect(ModelViewPick.isClick(start: NSPoint(x: 0, y: 0), end: NSPoint(x: 2, y: 2)))
        #expect(ModelViewPick.isClick(start: NSPoint(x: 10, y: 10), end: NSPoint(x: 10, y: 12.9)))
    }

    @Test func dragWhenAtOrBeyondThreshold() {
        #expect(!ModelViewPick.isClick(start: NSPoint(x: 0, y: 0), end: NSPoint(x: 3, y: 0)))
        #expect(!ModelViewPick.isClick(start: NSPoint(x: 0, y: 0), end: NSPoint(x: 2, y: 2.5)))
    }

    private func pickNode(in view: ModelView, at windowPoint: NSPoint, window: NSWindow) throws -> Int? {
        var picked: Int??
        view.onPick = { picked = $0 }
        view.mouseDown(with: try testMouseEvent(.leftMouseDown, windowPoint, in: window))
        view.mouseUp(with: try testMouseEvent(.leftMouseUp, windowPoint, in: window))
        return picked ?? nil
    }

    @Test func occludedLightDoesNotWinOverTheMeshInFront() async throws {
        let light: [String: Any] = ["name": "Lamp", "translation": [0, 0, -1],
                                    "extensions": ["KHR_lights_punctual": ["light": 0]]]
        let url = try reviewQuadsGLB([(cx: 0, z: 1, h: 2)], extraNodes: [light],
                                     extensions: ["KHR_lights_punctual": ["lights": [["type": "point"]]]],
                                     prefix: "review2-r9")
        defer { try? FileManager.default.removeItem(at: url) }
        let view = ModelView(renderer: try MetalRenderer())
        view.frame = NSRect(x: 0, y: 0, width: 64, height: 64)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        try await view.load(url)
        try await view.apply(ViewOptions(showsSceneGizmos: true))
        let center = NSPoint(x: 32, y: 32)
        #expect(try pickNode(in: view, at: center, window: window) == 0)
    }

    @Test func hiddenQuadInFrontRevealsOccludedLight() async throws {
        let light: [String: Any] = ["name": "Lamp", "translation": [0, 0, -1],
                                    "extensions": ["KHR_lights_punctual": ["light": 0]]]
        let url = try reviewQuadsGLB([(cx: 0, z: 1, h: 2)], extraNodes: [light],
                                     extensions: ["KHR_lights_punctual": ["lights": [["type": "point"]]]],
                                     prefix: "review2-r9-hidden")
        defer { try? FileManager.default.removeItem(at: url) }
        let view = ModelView(renderer: try MetalRenderer())
        view.frame = NSRect(x: 0, y: 0, width: 64, height: 64)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        try await view.load(url)
        try await view.apply(ViewOptions(showsSceneGizmos: true, hiddenNodeIndices: [0]))
        let center = NSPoint(x: 32, y: 32)
        #expect(try pickNode(in: view, at: center, window: window) == 1)
    }

    @Test func hoverClearsWhenPointerIsInLeftContentInset() async throws {
        let view = ModelView(renderer: try MetalRenderer())
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        view.contentInsets = NSEdgeInsets(top: 0, left: 40, bottom: 0, right: 0)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        try await view.load(TestFixtures.cube)
        var reported: (Int?, CGPoint?)?
        view.onHover = { node, point in reported = (node, point) }
        view.mouseMoved(with: try testMouseEvent(.mouseMoved, NSPoint(x: 10, y: 100), in: window))
        let hover = try #require(reported, "a move in the side inset must call onHover")
        #expect(hover.0 == nil)
        #expect(hover.1 == nil)
    }

    @Test func hoverStillWorksInModelAreaWithSideInsets() async throws {
        let view = ModelView(renderer: try MetalRenderer())
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        view.contentInsets = NSEdgeInsets(top: 0, left: 40, bottom: 0, right: 0)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        try await view.load(TestFixtures.cube)
        var lastHover: Int?
        let modelMove = try testMouseEvent(.mouseMoved, NSPoint(x: 100, y: 100), in: window)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            view.onHover = { node, _ in
                lastHover = node
                if node == 0 { done.resume() }
            }
            view.mouseMoved(with: modelMove)
        }
        #expect(lastHover == 0)
        var followed: CGPoint?
        view.onHover = { _, point in followed = point }
        view.mouseMoved(with: try testMouseEvent(.mouseMoved, NSPoint(x: 120, y: 110), in: window))
        #expect(followed != nil, "once a node is hovered, the tag follows this move without waiting for the next pick")
    }

    @Test func lightInFrontOfQuadStillWins() async throws {
        // Default orbit eye is at z = +distance; the light sits closer on the view axis than the quad.
        let light: [String: Any] = ["name": "Lamp", "translation": [0, 0, 2],
                                    "extensions": ["KHR_lights_punctual": ["light": 0]]]
        let url = try reviewQuadsGLB([(cx: 0, z: 0, h: 2)], extraNodes: [light],
                                     extensions: ["KHR_lights_punctual": ["lights": [["type": "point"]]]],
                                     prefix: "review2-r9-front-light")
        defer { try? FileManager.default.removeItem(at: url) }
        let view = ModelView(renderer: try MetalRenderer())
        view.frame = NSRect(x: 0, y: 0, width: 64, height: 64)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        try await view.load(url)
        try await view.apply(ViewOptions(showsSceneGizmos: true))
        let center = NSPoint(x: 32, y: 32)
        #expect(try pickNode(in: view, at: center, window: window) == 1)
    }
}
