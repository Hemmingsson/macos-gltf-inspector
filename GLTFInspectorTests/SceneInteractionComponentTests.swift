import AppKit
import Foundation
@testable import GLTFCore
@testable import GLTFInspector
@testable import Renderer
import simd
import SwiftUI
import Testing

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

    private func inspector(_ selection: NodeID?, onSelect: ((NodeID) -> Void)? = nil) -> Inspector {
        let document = document
        let suite = "gltf.interaction-inspector.\(UUID().uuidString)"
        let defaults = try! UserDefaults(suiteName: suite)!
        return Inspector(view: ViewState(settings: AppSettings(defaults: defaults)),
                         document: document, selection: selection, documentState: .ready,
                         validation: ValidationResult(nil, document: document), documentURL: nil,
                         onSelect: onSelect)
    }

    @Test func hostReadsTheExistingInspectorContent() async {
        let host = await AccessibilityTestHost(inspector(NodeID(kind: .mesh, index: 1)))
        defer { host.close() }
        #expect(host.text.contains("Inspector"))
        #expect(host.text.contains("Panel"))
        #expect(host.text.contains("Geometry"))
        #expect(host.text.contains("Copper"))
    }

    @Test func meshInspectorExposesEveryPrimitiveMaterial() async {
        let host = await AccessibilityTestHost(inspector(NodeID(kind: .mesh, index: 1)))
        defer { host.close() }
        #expect(host.text.contains("Copper"))
        #expect(host.text.contains("Rubber"))
        #expect(host.text.contains("Primitives"))
    }

    @Test func primitiveRowsOfferMaterialSelectActions() async {
        let host = await AccessibilityTestHost(inspector(NodeID(kind: .mesh, index: 1)))
        defer { host.close() }
        #expect(host.customActionNames.contains("Select Copper"))
        #expect(host.customActionNames.contains("Select Rubber"))
    }

    @Test func materialUsedBySelectsMeshNode() async {
        let host = await AccessibilityTestHost(inspector(NodeID(kind: .material, index: 1)))
        defer { host.close() }
        #expect(host.text.contains("Used by"))
        #expect(host.text.contains("Bracket"))
        #expect(host.customActionNames.contains("Select Bracket"))
    }

    @Test func navigationGizmoOffersAllSixAxisActions() async {
        let host = await AccessibilityTestHost(
            NavigationGizmo(viewRotation: matrix_identity_float3x3, activePreset: nil, onSelect: { _ in }, onOrbit: { _, _ in })
        )
        defer { host.close() }
        let actions = host.customActionNames
        for direction in ["top", "bottom", "front", "back", "left", "right"] {
            #expect(actions.contains("View from \(direction)"), "the navigation gizmo must expose the \(direction) action")
        }
    }

    @Test func dimensionsReadoutExposesItsRenderedValue() async {
        let host = await AccessibilityTestHost(DimensionsReadout(size: SIMD3(1, 2, 3)))
        defer { host.close() }
        #expect(host.text.contains("1.00 × 2.00 × 3.00 m"))
    }

    @Test func animatedFileOffersPlaybackControls() async throws {
        let document = try await GLTFDocument.load(from: TestFixtures.boxAnimated)
        let suite = "gltf.interaction-component-animated.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let state = ViewState(settings: AppSettings(defaults: defaults))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 512, height: 512))
        state.canvas.mount(in: container, url: TestFixtures.boxAnimated, options: state.options)
        try #require(try await waitUntil { state.canvas.phase == .ready && state.canvas.showsAnimationTimeline })
        defer { state.canvas.view?.removeFromSuperview() }
        let host = await AccessibilityTestHost(CanvasRegion(bounds: document.bounds, view: state) { Color.clear })
        defer { host.close() }
        #expect(host.text.contains("Play"))
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
        let host = await AccessibilityTestHost(CanvasRegion(bounds: document.bounds, view: state) { Color.clear })
        defer { host.close() }
        #expect(!host.text.contains("Play"))
    }
}
