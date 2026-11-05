import AppKit
import Foundation
@testable import GLTFCore
@testable import GLTFInspector
@testable import Renderer
import simd
import SwiftUI
import Testing

/// Real component accessibility, hosted in a test-owned off-screen window (never key/front).
@MainActor
private final class InteractionComponentHost<Content: View> {
    let window: NSWindow
    let view: NSHostingView<Content>

    init(_ content: Content) async {
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        view = NSHostingView(rootView: content)
        window = NSWindow(contentRect: NSRect(x: -2000, y: -2000, width: 900, height: 900),
                          styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 900, height: 900)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        view.layoutSubtreeIfNeeded()
    }

    func close() { window.contentView = nil; window.close() }

    private func attribute(_ name: String, of element: NSObject) -> Any? {
        let selector = NSSelectorFromString(name)
        guard element.responds(to: selector) else { return nil }
        return element.perform(selector)?.takeUnretainedValue()
    }

    var elements: [NSObject] {
        var result: [NSObject] = []
        var seen = Set<ObjectIdentifier>()
        func walk(_ element: Any) {
            guard let node = element as? NSObject,
                  seen.insert(ObjectIdentifier(node)).inserted else { return }
            result.append(node)
            let children = (node as? any NSAccessibilityProtocol)?.accessibilityChildren()
                ?? attribute("accessibilityChildren", of: node) as? [Any]
                ?? node.accessibilityAttributeValue(.children) as? [Any] ?? []
            for child in children { walk(child) }
        }
        walk(view)
        return result
    }

    var text: String {
        elements.flatMap { element -> [String] in
            let modern = element as? any NSAccessibilityProtocol
            return [modern?.accessibilityLabel(), modern?.accessibilityValue() as? String,
                    attribute("accessibilityLabel", of: element) as? String,
                    attribute("accessibilityValue", of: element) as? String,
                    element.accessibilityAttributeValue(.title) as? String,
                    element.accessibilityAttributeValue(.description) as? String,
                    element.accessibilityAttributeValue(.value) as? String].compactMap { $0 }
        }.joined(separator: "\n")
    }

    var customActionNames: [String] {
        elements.flatMap { element -> [String] in
            if let actions = (element as? any NSAccessibilityProtocol)?.accessibilityCustomActions() {
                return actions.map(\.name)
            }
            if let actions = attribute("accessibilityCustomActions", of: element) as? [NSAccessibilityCustomAction] {
                return actions.map(\.name)
            }
            let customActions = NSAccessibility.Attribute(rawValue: "AXCustomActions")
            if let actions = element.accessibilityAttributeValue(customActions) as? [NSAccessibilityCustomAction] {
                return actions.map(\.name)
            }
            return []
        }
    }
}

@MainActor
@Suite(.serialized)
struct SceneInteractionComponentTests {
    private var document: GLTFDocument {
        GLTFDocumentJSON.makeDocument(json: [
            "asset": ["version": "2.0"],
            "scenes": [["nodes": [0]]],
            "nodes": [["name": "Assembly", "children": [1, 2]],
                      ["name": "Panel", "mesh": 0], ["name": "Bracket", "mesh": 1]],
            "accessors": [["componentType": 5126, "count": 3, "type": "VEC3"],
                          ["componentType": 5126, "count": 6, "type": "VEC3"]],
            "meshes": [
                ["primitives": [["attributes": ["POSITION": 0], "material": 0],
                                ["attributes": ["POSITION": 1], "material": 1]]],
                ["primitives": [["attributes": ["POSITION": 0], "material": 1]]],
            ],
            "materials": [["name": "Copper"], ["name": "Rubber"]],
        ])
    }

    private func inspector(_ selection: NodeID?) -> Inspector {
        let document = document
        return Inspector(document: document, selection: selection, documentState: .ready,
                         validation: ValidationResult(nil, document: document), documentURL: nil)
    }

    @Test func hostReadsTheExistingInspectorContent() async {
        let host = await InteractionComponentHost(inspector(NodeID(kind: .mesh, index: 1)))
        defer { host.close() }
        #expect(host.text.contains("Inspector"))
        #expect(host.text.contains("Panel"))
        #expect(host.text.contains("Geometry"))
        #expect(host.text.contains("Copper"))
    }

    @Test func navigationGizmoOffersAllSixAxisActions() async {
        let host = await InteractionComponentHost(
            NavigationGizmo(viewRotation: matrix_identity_float3x3, activePreset: nil, onSelect: { _ in }, onOrbit: { _, _ in })
        )
        defer { host.close() }
        let actions = host.customActionNames
        for direction in ["top", "bottom", "front", "back", "left", "right"] {
            #expect(actions.contains("View from \(direction)"), "the navigation gizmo must expose the \(direction) action")
        }
    }

    @Test func dimensionsReadoutExposesItsRenderedValue() async {
        let host = await InteractionComponentHost(DimensionsReadout(size: SIMD3(1, 2, 3)))
        defer { host.close() }
        #expect(host.text.contains("1.00 × 2.00 × 3.00 m"))
    }

    @Test func staticFileDoesNotOfferPlaybackControls() async throws {
        let document = try await GLTFDocument.load(from: TestFixtures.cube)
        let suite = "gltf.interaction-component.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let state = ViewState(settings: AppSettings(defaults: defaults))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 512, height: 512))
        state.canvas.mount(in: container, url: TestFixtures.cube, options: state.options)
        try #require(try await waitUntil { state.canvas.phase != .loading })
        defer { state.canvas.view?.removeFromSuperview() }
        let host = await InteractionComponentHost(CanvasRegion(bounds: document.bounds, view: state) { Color.clear })
        defer { host.close() }
        #expect(!host.text.contains("Play"))
    }

    // 9toe55f5
    @Test func meshInspectorExposesEveryPrimitiveMaterial() async {
        let host = await InteractionComponentHost(inspector(NodeID(kind: .mesh, index: 1)))
        defer { host.close() }
        #expect(host.text.contains("Copper"))
        #expect(host.text.contains("Rubber"), "the second primitive's material must appear")
    }

    // mdleya4f: the fixture contains 3 + 1 triangles.
    @Test func emptySelectionShowsSceneGeometryTotals() async {
        let host = await InteractionComponentHost(inspector(nil))
        defer { host.close() }
        #expect(host.text.lowercased().contains("4 tris"))
    }

    @Test func groupSelectionShowsSubtreeGeometryTotals() async {
        let host = await InteractionComponentHost(inspector(NodeID(kind: .empty, index: 0)))
        defer { host.close() }
        #expect(host.text.lowercased().contains("4 tris"))
    }

    // hw4fh7zp
    @Test func meshInspectorOffersShapePreview() async {
        let host = await InteractionComponentHost(inspector(NodeID(kind: .mesh, index: 1)))
        defer { host.close() }
        #expect(host.text.contains("Shape"))
    }

    private func loadedState(_ url: URL) async throws -> (ViewState, NSView) {
        let suite = "gltf.interaction-component.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let state = ViewState(settings: AppSettings(defaults: defaults))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 512, height: 512))
        state.canvas.mount(in: container, url: url, options: state.options)
        try #require(try await waitUntil { state.canvas.phase != .loading })
        try #require(state.canvas.phase == .ready)
        return (state, container)
    }

    // 1cxtu56y: either quad is flat while their union is one meter deep.
    @Test func selectingAQuadShowsItsDimensionsInsteadOfTheWholeScene() async throws {
        let url = try writeTempStackedQuadsGLB(prefix: "selection-dimensions")
        defer { try? FileManager.default.removeItem(at: url) }
        let (state, container) = try await loadedState(url)
        defer { state.canvas.view?.removeFromSuperview(); _ = container }
        let bounds = try #require(try await GLTFDocument.load(from: url).bounds)
        #expect(bounds.size == SIMD3<Float>(2, 2, 1))
        state.selection = NodeID(kind: .mesh, index: 1)
        let host = await InteractionComponentHost(CanvasRegion(bounds: bounds, view: state) { Color.clear })
        defer { host.close() }
        #expect(host.text.contains("2.00 × 2.00 × 0.00 m"))
    }

    // sygpfhz7: a playable file opens paused with a Play control.
    @Test func animatedFileOffersPlaybackControls() async throws {
        let document = try await GLTFDocument.load(from: TestFixtures.boxAnimated)
        try #require(document.animations.contains { $0.duration > 0 })
        let (state, container) = try await loadedState(TestFixtures.boxAnimated)
        defer { state.canvas.view?.removeFromSuperview(); _ = container }
        let host = await InteractionComponentHost(CanvasRegion(bounds: document.bounds, view: state) { Color.clear })
        defer { host.close() }
        #expect(host.text.contains("Play"))
    }
}
