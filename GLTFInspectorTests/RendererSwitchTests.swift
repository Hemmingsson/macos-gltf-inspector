import Foundation
@testable import GLTFCore
@testable import GLTFInspector
import PreviewUI
import Testing

/// The temporary developer switch (`settings.preview.renderer`), the router that reads it, and
/// the renderer-neutral pieces each renderer window builds on. Renderer-free on purpose: this file
/// must build with either renderer deleted.
@MainActor
struct RendererSwitchTests {
    private func withSuite(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "gltf.renderer-switch.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func switchRoundTripsThroughTheGroupSuite() throws {
        try withSuite { defaults in
            #expect(AppGroupSettings.Key.renderer == "settings.preview.renderer")
            #expect(RendererKind.stored(in: defaults) == .realityKit)

            RendererKind.store(.webKit, in: defaults)
            #expect(defaults.string(forKey: "settings.preview.renderer") == "webkit")
            #expect(RendererKind.stored(in: defaults) == .webKit)

            RendererKind.store(.realityKit, in: defaults)
            #expect(RendererKind.stored(in: defaults) == .realityKit)

            defaults.set("metal", forKey: AppGroupSettings.Key.renderer)
            #expect(RendererKind.stored(in: defaults) == .default)
        }
    }

    @Test func routerUsesTheStoredRendererWhenLinked() {
        for kind in RendererRouter.available {
            #expect(RendererRouter.resolve(kind) == kind)
        }
        #expect(RendererRouter.available.contains(RendererRouter.resolve(.webKit)))
        #expect(RendererRouter.available.contains(RendererRouter.resolve(.realityKit)))
    }

    /// The document window mounts the chosen renderer's window root (and so its canvas).
    @Test func routerMountsTheWindowForEachKind() {
        let url = TestFixtures.cube
        for kind in RendererRouter.available {
            // `_ConditionalContent` names both branches in its type; its storage holds the mounted one.
            let body = DocumentWindowRouter(documentURL: url, kind: kind).body
            let mounted = String(describing: Mirror(reflecting: body).descendant("storage") ?? body)
            switch kind {
            case .realityKit:
                #expect(mounted.contains("RealityDocumentWindow("))
                #expect(!mounted.contains("WebDocumentWindow("))
            case .webKit:
                #expect(mounted.contains("WebDocumentWindow("))
                #expect(!mounted.contains("RealityDocumentWindow("))
            }
        }
    }

    /// The WebKit window's panels come from the JSON summary: the only loader it calls. No convert
    /// runs (the WebKit adapter cannot even import `RendererRealityKit`).
    @Test func jsonOpenFillsThePanelsWithoutARenderer() async throws {
        let url = TestFixtures.cube
        let window = DocumentWindowModel(documentURL: url)
        guard case .started(let generation) = window.beginOpen(url) else {
            Issue.record("open did not start")
            return
        }
        var calls: [URL] = []
        await window.openSummary(url, generation: generation, renderer: .webKit) { url in
            calls.append(url)
            return try await GLTFDocumentSummary.load(from: url)
        }

        #expect(calls == [url])
        #expect(window.phase == .ready)
        #expect(window.hasLoadedDocument)
        let model = window.sceneModel
        #expect(model.fileName == "cube.gltf")
        #expect(!model.nodeTree.isEmpty)
        #expect(model.stats.triangleCount > 0)
        #expect(model.dimensions.width > 0)
        #expect(model.pipelineReport.entries.isEmpty)
        #expect(model.convertProblems.entries.isEmpty)
        #expect(window.previewSession.viewModes.first == .shaded)
        #expect(window.previewSession.viewModes.contains(.wireframe))
        #expect(window.sidebar?.document.nodes.count == model.nodeTree.count)
    }

    @Test func jsonOpenFailureFailsThePanels() async {
        let url = TestFixtures.cube
        let window = DocumentWindowModel(documentURL: url)
        guard case .started(let generation) = window.beginOpen(url) else { return }
        struct Boom: LocalizedError { var errorDescription: String? { "boom" } }
        await window.openSummary(url, generation: generation, renderer: .webKit) { _ in throw Boom() }
        #expect(window.phase == .failed("boom"))
        #expect(window.sidebar == nil)
    }

    @Test func availabilityHidesWhatTheRendererCannotDo() async throws {
        let summary = try await GLTFDocumentSummary.load(from: TestFixtures.boxAnimated)
        let model = EngineSceneModel(summary: summary, fileName: "BoxAnimated.glb")
        let modes: [RenderViewMode] = [.shaded, .wireframe, .channel(.baseColor), .channel(.normals)]

        let everything = RendererAvailability(model: model, viewModes: modes, features: Set(RendererFeature.allCases))
        #expect(everything.hasAnimations)
        #expect(everything.canHideNodes)
        #expect(everything.availableDebugChannels == [.shaded, .wireframe, .channel(.baseColor), .channel(.normals)])

        let pageOnly = RendererAvailability(
            model: model,
            viewModes: modes,
            features: [.debugChannels, .materialVariants, .nodeSelection]
        )
        #expect(!pageOnly.hasAnimations)
        #expect(!pageOnly.canHideNodes)
        #expect(pageOnly.availableDebugChannels == [.shaded, .channel(.baseColor), .channel(.normals)])

        let none = RendererAvailability(model: model, viewModes: modes, features: [])
        #expect(none.availableDebugChannels == [.shaded])
        #expect(!none.hasMorphs)
        #expect(!none.hasLights)
    }

    @Test func selectionHidesTheEyeWithoutNodeVisibility() {
        let sidebar = HostSidebarModel(document: GLTFSessionDocument())
        #expect(EngineSelectionModel(sidebar: sidebar).canHideNodes)
        #expect(!EngineSelectionModel(sidebar: sidebar, canHideNodes: false).canHideNodes)
    }
}
