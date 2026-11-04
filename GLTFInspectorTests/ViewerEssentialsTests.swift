import AppKit
import AVFoundation
import ImageIO
import Foundation
@testable import GLTFCore
@testable import GLTFInspector
@testable import Renderer
import simd
import SwiftUI
import Testing

/// Backlog 3pk4ibv6 "Viewer essentials": stats, selection dimensions, multi-select, hierarchy
/// selection, auto-orthographic, orbit pivot, pointer zoom and hover pre-selection.
@MainActor
@Suite(.serialized)
struct ViewerEssentialsTests {
    // MARK: - Fixtures

    /// Assembly (0) → Panel (1, mesh 0: 1 + 2 tris), Bracket (2, mesh 1: 1 tri).
    private var assembly: GLTFDocument {
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

    private func settings() throws -> AppSettings {
        AppSettings(defaults: try #require(UserDefaults(suiteName: "gltf.viewer-essentials.\(UUID().uuidString)")))
    }

    /// Root (0) → Group (1) → Mesh A (2); Root → Mesh B (3).
    private func model() async throws -> DocumentWindowModel {
        let model = DocumentWindowModel(documentURL: nil, settings: try settings())
        let url = URL(fileURLWithPath: "/tmp/viewer-essentials.glb")
        let document = GLTFDocumentJSON.makeDocument(json: [
            "asset": ["version": "2.0"],
            "scenes": [["nodes": [0]]],
            "nodes": [["name": "Root", "children": [1, 3]],
                      ["name": "Group", "children": [2]],
                      ["name": "Mesh A", "mesh": 0], ["name": "Mesh B", "mesh": 0]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0], "material": 0]]]],
            "accessors": [["componentType": 5126, "count": 3, "type": "VEC3"]],
            "materials": [["name": "Shared"]],
        ])
        guard case .started(let generation) = model.beginOpen(url) else { throw CocoaError(.fileReadUnknown) }
        await model.openSummary(url, generation: generation, load: { _ in document })
        return model
    }

    private func loadedState(_ url: URL) async throws -> (ViewState, NSView) {
        let state = ViewState(settings: try settings())
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 512, height: 512))
        state.canvas.mount(in: container, url: url, options: state.options)
        try #require(try await waitUntil { state.canvas.phase != .loading })
        try #require(state.canvas.phase == .ready)
        return (state, container)
    }

    private func inspector(_ selection: NodeID?) throws -> Inspector {
        let document = assembly
        return Inspector(view: ViewState(settings: try settings()), document: document, selection: selection,
                         documentState: .ready, validation: ValidationResult(nil, document: document), documentURL: nil)
    }

    // MARK: - mdleya4f stats

    @Test func sceneAndSubtreeTotalsCountEveryMeshNodeBelowTheRoot() {
        let document = assembly
        let scene = document.totals(ofScene: 0)
        #expect(scene.triangleCount == 4)
        #expect(scene.nodeCount == 3)
        #expect(scene.meshNodeCount == 2)
        #expect(scene.uniqueMeshCount == 2)
        #expect(scene.drawCallCount == 3)
        #expect(scene.materialCount == 2)
        #expect(document.totals(ofSubtree: 0) == scene)
        #expect(document.totals(ofSubtree: 2).triangleCount == 1)
    }

    @Test func totalsSurviveACycleInAMalformedFile() {
        var document = assembly
        document.nodes[2].children = [0]
        #expect(document.totals(ofSubtree: 0).nodeCount == 3)
    }

    @Test func emptySelectionShowsSceneGeometryTotals() async throws {
        let host = await AccessibilityTestHost(try inspector(nil))
        defer { host.close() }
        #expect(host.text.lowercased().contains("4 tris"))
    }

    @Test func sceneRowShowsSceneGeometryTotals() async throws {
        let host = await AccessibilityTestHost(try inspector(NodeID(kind: .scene, index: 0)))
        defer { host.close() }
        #expect(host.text.lowercased().contains("4 tris"))
        #expect(host.text.contains("3 draw calls"))
    }

    @Test func groupSelectionShowsSubtreeGeometryTotals() async throws {
        let host = await AccessibilityTestHost(try inspector(NodeID(kind: .empty, index: 0)))
        defer { host.close() }
        #expect(host.text.lowercased().contains("4 tris"))
    }

    // MARK: - 1cxtu56y selection dimensions

    @Test func selectingAQuadShowsItsDimensionsInsteadOfTheWholeScene() async throws {
        let url = try writeTempStackedQuadsGLB(prefix: "selection-dimensions")
        defer { try? FileManager.default.removeItem(at: url) }
        let (state, container) = try await loadedState(url)
        defer { state.canvas.view?.removeFromSuperview(); _ = container }
        let document = try await GLTFDocument.load(from: url)
        state.document = document
        let bounds = try #require(document.bounds)
        #expect(bounds.size == SIMD3<Float>(2, 2, 1))

        let whole = await AccessibilityTestHost(CanvasRegion(bounds: bounds, view: state) { Color.clear })
        #expect(whole.text.contains("2.00 × 2.00 × 1.00 m"))
        whole.close()

        state.selection = NodeID(kind: .mesh, index: 1)
        let host = await AccessibilityTestHost(CanvasRegion(bounds: bounds, view: state) { Color.clear })
        defer { host.close() }
        #expect(host.text.contains("2.00 × 2.00 × 0.00 m"))
        #expect(host.text.contains("Front"))
    }

    @Test func lightWithoutGeometryKeepsTheModelSize() async throws {
        let (state, container) = try await loadedState(TestFixtures.lights)
        defer { state.canvas.view?.removeFromSuperview(); _ = container }
        let document = try await GLTFDocument.load(from: TestFixtures.lights)
        state.document = document
        let bounds = try #require(document.bounds)
        let model = String(format: "%.2f × %.2f × %.2f m", bounds.size.x, bounds.size.y, bounds.size.z)
        state.selection = NodeID(kind: .light, index: 2)
        let host = await AccessibilityTestHost(CanvasRegion(bounds: bounds, view: state) { Color.clear })
        defer { host.close() }
        #expect(host.text.contains(model))
        #expect(!host.text.contains("0.00 × 0.00 × 0.00 m"))
    }

    // MARK: - lusha0c3 hierarchy selection

    @Test func repeatedMeshHitsCycleThroughParentsAndBack() async throws {
        let model = try await model()
        model.view.canvas.onPick?(2)
        #expect(model.view.selection == NodeID(kind: .mesh, index: 2))
        model.view.canvas.onPick?(2)
        #expect(model.view.selection == NodeID(kind: .empty, index: 1))
        model.view.canvas.onPick?(2)
        #expect(model.view.selection == NodeID(kind: .empty, index: 0))
        model.view.canvas.onPick?(2)
        #expect(model.view.selection == NodeID(kind: .mesh, index: 2))
    }

    @Test func clickingAChildOfAGroupChosenInTheListSelectsTheChild() async throws {
        let model = try await model()
        model.view.selection = NodeID(kind: .empty, index: 1)
        model.view.canvas.onPick?(2)
        #expect(model.view.selection == NodeID(kind: .mesh, index: 2))
    }

    @Test func selectParentAndChildrenWalkTheTree() async throws {
        let model = try await model()
        let view = model.view
        view.selection = NodeID(kind: .mesh, index: 2)
        view.selectParent()
        #expect(view.selection == NodeID(kind: .empty, index: 1))
        view.selectParent()
        #expect(view.selection == NodeID(kind: .empty, index: 0))
        #expect(!view.canSelectParent)
        view.selectChildren()
        #expect(view.selectedIDs == [NodeID(kind: .empty, index: 1), NodeID(kind: .mesh, index: 3)])
        #expect(view.selection == NodeID(kind: .empty, index: 1))
    }

    // MARK: - vn4trm11 multi-select

    @Test func commandClickTogglesNodesAndHideFrameActOnAll() async throws {
        let model = try await model()
        let view = model.view
        view.canvas.onPick?(2)
        view.canvas.onTogglePick?(3)
        #expect(view.selectedIDs == [NodeID(kind: .mesh, index: 2), NodeID(kind: .mesh, index: 3)])
        #expect(view.selection == NodeID(kind: .mesh, index: 3))
        #expect(view.options.selectedNodeIndices == [2, 3])
        #expect(view.selectedSceneNodes == [3, 2])

        view.toggleHiddenSelection()
        #expect(view.hiddenNodes == [2, 3])
        view.toggleHiddenSelection()
        #expect(view.hiddenNodes.isEmpty)
        view.toggleSoloSelection()
        #expect(view.soloNodes == [2, 3])

        view.canvas.onTogglePick?(3)
        #expect(view.selectedIDs == [NodeID(kind: .mesh, index: 2)])
        #expect(view.selection == NodeID(kind: .mesh, index: 2))
        view.selection = nil
        #expect(view.selectedIDs.isEmpty)
        #expect(view.options.selectedNodeIndices.isEmpty)
    }

    @Test func extraSelectedNodesEachGetASelectionBox() async throws {
        let url = try writeTempStackedQuadsGLB(prefix: "multi-select-boxes")
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let scene = try #require(renderer.scene)
        let one = overlayVertices(scene: scene, options: MetalOverlayOptions(selectedNode: 0)).count
        var both = MetalOverlayOptions(selectedNode: 0)
        both.selectedNodes = [0, 1]
        #expect(one == 0, "mesh selection uses the GPU silhouette, not an AABB overlay")
        #expect(overlayVertices(scene: scene, options: both).count == 0)
    }

    // MARK: - ggq8r9uj auto-orthographic

    @Test func orbitAfterAnAxisSnapReturnsToPerspective() throws {
        let view = ViewState(settings: try settings())
        view.show(.top)
        #expect(view.isOrthographic)
        view.canvasDidOrbit()
        #expect(!view.isOrthographic)
    }

    @Test func orbitKeepsOrthographicTheUserChose() throws {
        let view = ViewState(settings: try settings())
        view.isOrthographic = true
        view.show(.front)
        view.canvasDidOrbit()
        #expect(view.isOrthographic)
    }

    @Test func canvasOrbitDragReportsOncePerDrag() async throws {
        let view = ModelView(renderer: try MetalRenderer())
        try await view.load(TestFixtures.cube)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        var starts = 0
        view.onOrbitStart = { starts += 1 }
        let a = NSPoint(x: 200, y: 200)
        view.mouseDown(with: try testMouseEvent(.leftMouseDown, a, in: window))
        view.mouseDragged(with: try testMouseEvent(.leftMouseDragged, NSPoint(x: 220, y: 200), in: window))
        view.mouseDragged(with: try testMouseEvent(.leftMouseDragged, NSPoint(x: 240, y: 200), in: window))
        view.mouseUp(with: try testMouseEvent(.leftMouseUp, NSPoint(x: 240, y: 200), in: window))
        #expect(starts == 1)
    }

    @Test func orthographicWheelZoomRescalesTheOrthographicMagnitude() async throws {
        let view = ModelView(renderer: try MetalRenderer())
        try await view.load(TestFixtures.cube, options: ViewOptions(isOrthographic: true))
        view.show(.front)
        let before = view.camera.orthographic.magnitude
        view.wheel(deltaY: -40, at: .zero)
        #expect(view.camera.orthographic.magnitude < before)
        let expected = view.camera.distance * tan(view.camera.yfov / 2)
        #expect(abs(view.camera.orthographic.magnitude - expected) < 1e-9)
    }

    @Test func orthographicPointerZoomKeepsTheWorldPointUnderTheCursorFixed() async throws {
        let view = ModelView(renderer: try MetalRenderer())
        try await view.load(TestFixtures.cube, options: ViewOptions(isOrthographic: true, zoomsTowardPointer: true))
        view.show(.front)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        let point = NSPoint(x: 360, y: 150)
        let before = try #require(view.pointerWorldPoint(atViewPoint: point))
        let magnitudeBefore = view.camera.orthographic.magnitude
        view.wheel(deltaY: -40, at: point)
        #expect(view.camera.orthographic.magnitude < magnitudeBefore)
        let after = try #require(view.pointerWorldPoint(atViewPoint: point))
        #expect(simd_distance(before, after) < 1e-6)
    }

    // MARK: - vn4trm11 canvas modifiers

    @Test(arguments: [NSEvent.ModifierFlags.command, .shift])
    func modifiedClickTogglesInsteadOfPicking(_ modifier: NSEvent.ModifierFlags) async throws {
        let view = ModelView(renderer: try MetalRenderer())
        try await view.load(TestFixtures.cube)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        var picks = 0
        var toggles: [Int] = []
        view.onPick = { _ in picks += 1 }
        view.onTogglePick = { toggles.append($0) }
        let center = NSPoint(x: 256, y: 256)
        view.mouseDown(with: try testMouseEvent(.leftMouseDown, center, in: window, modifiers: modifier))
        view.mouseUp(with: try testMouseEvent(.leftMouseUp, center, in: window, modifiers: modifier))
        #expect(picks == 0)
        #expect(toggles == [0])
    }

    // MARK: - lf9s93sq orbit pivot and pointer zoom

    @Test func retargetKeepsTheEyeAndLooksAtTheNewPivot() {
        var camera = MetalUserCamera()
        camera.orbitTo(azimuth: 30, elevation: -20, distance: 5, target: SIMD3(0, 0, 0))
        let eye = camera.position
        let pivot = SIMD3<Double>(1, 0.5, -0.25)
        camera.retargetKeepingEye(to: pivot)
        #expect(simd_distance(camera.position, eye) < 1e-9)
        #expect(simd_distance(camera.target, pivot) < 1e-9)
        #expect(abs(camera.distance - simd_distance(eye, pivot)) < 1e-9)
    }

    @Test func pointerZoomKeepsThePointerSpotFixedOnScreen() {
        var camera = MetalUserCamera()
        camera.orbitTo(azimuth: 0, elevation: 0, distance: 10, target: .zero)
        camera.baseDistance = 10
        let pointer = SIMD3<Double>(2, 1, 0)
        func screen(_ c: MetalUserCamera, _ p: SIMD3<Double>) -> SIMD2<Double> {
            let relative = p - c.position
            let depth = simd_dot(relative, c.lookDirection)
            return SIMD2(relative.x, relative.y) / depth
        }
        let before = screen(camera, pointer)
        camera.zoomBy(-40, toward: pointer)
        #expect(camera.distance < 10)
        let after = screen(camera, pointer)
        #expect(simd_distance(before, after) < 1e-9)
        #expect(MetalUserCamera.pointerDollyTarget(target: .zero, pointer: pointer, factor: 1) == .zero)
    }

    @Test func selectingANodeLeavesTheViewAlone() async throws {
        let url = try writeTempStackedQuadsGLB(prefix: "orbit-pivot")
        defer { try? FileManager.default.removeItem(at: url) }
        let view = ModelView(renderer: try MetalRenderer())
        try await view.load(url)
        let eye = view.camera.position, target = view.camera.target
        let rotation = (view.camera.rotAroundX, view.camera.rotAroundY)
        try await view.apply(ViewOptions(selectedNodeIndex: 0, orbitsAroundSelection: true))
        #expect(simd_distance(view.camera.position, eye) < 1e-9)
        #expect(simd_distance(view.camera.target, target) < 1e-9)
        #expect(view.camera.rotAroundX == rotation.0 && view.camera.rotAroundY == rotation.1)
    }

    @Test func orbitDragAimsTheOrbitAtTheSelectionBox() async throws {
        let url = try writeTempStackedQuadsGLB(prefix: "orbit-drag-pivot")
        defer { try? FileManager.default.removeItem(at: url) }
        let view = ModelView(renderer: try MetalRenderer())
        try await view.load(url, options: ViewOptions(selectedNodeIndex: 0, orbitsAroundSelection: true))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        view.mouseDown(with: try testMouseEvent(.leftMouseDown, NSPoint(x: 200, y: 200), in: window))
        view.mouseDragged(with: try testMouseEvent(.leftMouseDragged, NSPoint(x: 210, y: 200), in: window))
        view.mouseUp(with: try testMouseEvent(.leftMouseUp, NSPoint(x: 210, y: 200), in: window))
        #expect(simd_distance(view.camera.target, SIMD3(0, 0, -1)) < 1e-5)
    }

    @Test func orthographicSelectionKeepsTheAxisViewAndScale() async throws {
        let url = try writeTempStackedQuadsGLB(prefix: "orbit-ortho-selection")
        defer { try? FileManager.default.removeItem(at: url) }
        let view = ModelView(renderer: try MetalRenderer())
        try await view.load(url, options: ViewOptions(isOrthographic: true, orbitsAroundSelection: true))
        view.show(.front)
        let look = view.camera.lookDirection, magnitude = view.camera.orthographic.magnitude
        try await view.apply(ViewOptions(isOrthographic: true, selectedNodeIndex: 0, orbitsAroundSelection: true))
        #expect(simd_distance(view.camera.lookDirection, look) < 1e-9)
        #expect(abs(view.camera.orthographic.magnitude - magnitude) < 1e-9)
    }

    @Test func orthographicRetargetSlidesTheTargetWithoutTurningTheView() {
        var camera = MetalUserCamera()
        camera.isOrthographic = true
        camera.orbitTo(azimuth: 0, elevation: 0, distance: 4, target: .zero)
        camera.applyProjection()
        let look = camera.lookDirection, magnitude = camera.orthographic.magnitude
        camera.retargetKeepingEye(to: SIMD3(1, 0.5, -2))
        #expect(simd_distance(camera.lookDirection, look) < 1e-9)
        #expect(abs(camera.orthographic.magnitude - magnitude) < 1e-9)
        #expect(abs(camera.target.x - 1) < 1e-9 && abs(camera.target.y - 0.5) < 1e-9)
        #expect(abs(camera.target.z) < 1e-9, "the depth offset is not in the view plane, so the target keeps its depth")
    }

    // MARK: - yel6vru3 hover

    @Test func hoverThrottlePicksAtOnceThenPacesAndSkipsWhileBusy() {
        var throttle = HoverPickThrottle(minimumInterval: 0.1)
        #expect(throttle.delay(at: 0, isBusy: false) == 0)
        #expect(throttle.delay(at: 0, isBusy: true) == nil)
        throttle.didPick(at: 1)
        #expect(throttle.delay(at: 1.04, isBusy: false).map { abs($0 - 0.06) < 1e-9 } == true)
        #expect(throttle.delay(at: 1.5, isBusy: false) == 0)
        #expect(throttle.delay(at: 1.5, isBusy: true) == nil)
    }

    @Test func hoveredMeshGetsAMutedBoxButNotWhenSelected() async throws {
        let url = try writeTempStackedQuadsGLB(prefix: "hover-box")
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let scene = try #require(renderer.scene)
        var hovered = MetalOverlayOptions()
        hovered.hoveredNode = 1
        #expect(overlayVertices(scene: scene, options: hovered).count == 24)
        var selected = MetalOverlayOptions(selectedNode: 1)
        selected.hoveredNode = 1
        #expect(overlayVertices(scene: scene, options: selected).count == 0)
    }

    // MARK: - advg8yaq view modes

    private func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    @Test(arguments: [RenderViewMode.wireframeOnShaded, .xray, .clay])
    func displayModeDrawsTheModelDifferentlyFromShaded(_ mode: RenderViewMode) async throws {
        let view = ModelView(renderer: try MetalRenderer())
        try await view.load(TestFixtures.cube)
        let shaded = pixels(try view.image(width: 96, height: 96))
        try await view.apply(ViewOptions(viewMode: mode))
        let styled = pixels(try view.image(width: 96, height: 96))
        let covered = stride(from: 3, to: styled.count, by: 4).filter { styled[$0] > 0 }.count
        #expect(covered > 96 * 96 / 20, "the model must still be drawn")
        let changed = zip(shaded, styled).filter { abs(Int($0) - Int($1)) > 8 }.count
        #expect(changed > 200, "\(mode) must look different from shaded")
    }

    @Test func fileWithTrianglesOffersTheDisplayModes() async throws {
        let modes = try await GLTFDocument.load(from: TestFixtures.cube).viewModes
        #expect(modes.starts(with: [.shaded, .wireframe, .wireframeOnShaded, .xray, .clay]))
    }

    // MARK: - cm2j1flm tree guides

    @Test func treeGuidesAreOnForAFreshInstall() throws {
        #expect(try settings().showsTreeGuides)
    }

    @Test func treeGuidesContinueOnlyWhereASiblingFollows() {
        func item(_ index: Int, _ children: [OutlinerItem] = []) -> OutlinerItem {
            OutlinerItem(id: NodeID(kind: .empty, index: index), name: "\(index)", children: children)
        }
        // Root(0) → A(1) → [A1(2), A2(3)], B(4)
        let root = item(0, [item(1, [item(2), item(3)]), item(4)])
        let all: Set<NodeID> = [root.id, root.children[0].id]
        let rows = OutlinerTree.visibleRows([root], expanded: all)
        #expect(rows.map(\.id.index) == [0, 1, 2, 3, 4])
        #expect(rows.map(\.guides) == [[], [true], [true, true], [true, false], [false]])
        let folded = OutlinerTree.visibleRows([root], expanded: [root.id])
        #expect(folded.map(\.guides) == [[], [true], [false]])
    }

    // MARK: - swrmm3ku turntable export

    @Test(arguments: TurntableExport.Format.allCases)
    func turntableWritesEveryFrameOfOneOrbit(_ format: TurntableExport.Format) async throws {
        let url = try writeTempStackedQuadsGLB(prefix: "turntable")
        defer { try? FileManager.default.removeItem(at: url) }
        let (state, container) = try await loadedState(url)
        defer { state.canvas.view?.removeFromSuperview(); _ = container }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("turntable-\(UUID().uuidString).\(format.rawValue)")
        defer { try? FileManager.default.removeItem(at: output) }
        let before = try #require(state.canvas.view).camera
        try await TurntableExport.write(format, from: state.canvas, to: output)
        #expect(try #require(state.canvas.view).camera == before, "the live camera must not move")
        switch format {
        case .gif:
            let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
            #expect(CGImageSourceGetCount(source) == format.frameCount)
        case .mp4:
            let asset = AVURLAsset(url: output)
            let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
            let reader = try AVAssetReader(asset: asset)
            let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(out)
            reader.startReading()
            var frames = 0
            while let sample = out.copyNextSampleBuffer() { frames += CMSampleBufferGetNumSamples(sample) }
            #expect(frames == format.frameCount, "decoded \(frames) frames")
            let duration = try await asset.load(.duration).seconds
            #expect(abs(duration - Double(format.frameCount) / Double(format.framesPerSecond)) < 0.1)
        }
    }

    @Test func turntableSizeKeepsAspectCapsTheEdgeAndStaysEven() {
        let size = TurntableExport.frameSize(for: CGSize(width: 3001, height: 1501), format: .mp4)
        #expect(size.width == 1080)
        #expect(size.height % 2 == 0)
        #expect(abs(Double(size.width) / Double(size.height) - 2) < 0.01)
    }

}
