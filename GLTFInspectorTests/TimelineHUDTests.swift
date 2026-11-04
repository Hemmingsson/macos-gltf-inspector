import AppKit
import Foundation
import GLTFCore
import Testing
@testable import GLTFInspector
@testable import Renderer
import SwiftUI

/// Hosted timeline HUD: visibility, transport wiring, and scrub pose without launching the app.
@MainActor
@Suite(.serialized)
struct TimelineHUDTests {
    private func clipTitles(for canvas: ModelCanvasController) -> [String] {
        canvas.animationClips.enumerated().map { index, clip in
            clip.name?.isEmpty == false ? clip.name! : "Clip \(index + 1)"
        }
    }

    private func accessibilityFrame<Content: View>(labeled label: String, in host: AccessibilityTestHost<Content>) -> NSRect? {
        for element in host.elements {
            guard let modern = element as? any NSAccessibilityProtocol, modern.accessibilityLabel() == label else { continue }
            let frame = modern.accessibilityFrame()
            guard frame.width > 0, frame.height > 0 else { continue }
            return frame
        }
        return nil
    }

    private func findSpaceKeyView(in view: NSView) -> SpaceKeyNSView? {
        if let match = view as? SpaceKeyNSView { return match }
        for subview in view.subviews {
            if let match = findSpaceKeyView(in: subview) { return match }
        }
        return nil
    }

    private func readyCanvas() async throws -> (ModelCanvasController, NSView) {
        let canvas = ModelCanvasController()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        canvas.mount(in: container, url: TestFixtures.boxAnimated, options: ViewOptions())
        #expect(try await waitUntil { canvas.phase == .ready })

        return (canvas, container)
    }

    @Test func zeroDurationClipsHideTimelineHUD() async throws {
        let canvas = ModelCanvasController()
        #expect(!canvas.showsAnimationTimeline)
        let host = await AccessibilityTestHost(AnimationTimelineHUD(canvas: canvas))
        defer { host.close() }
        #expect(!host.text.contains("Play"))
    }

    @Test func animatedFileShowsPlayControl() async throws {
        let (canvas, container) = try await readyCanvas()
        defer { canvas.view?.removeFromSuperview() }
        #expect(canvas.showsAnimationTimeline)
        let host = await AccessibilityTestHost(AnimationTimelineHUD(canvas: canvas))
        defer { host.close() }
        #expect(host.text.contains("Play"))
        _ = container
    }

    @Test func playPauseToggleUpdatesController() async throws {
        let (canvas, container) = try await readyCanvas()
        defer { canvas.view?.removeFromSuperview() }
        var isPlaying = false
        let host = await AccessibilityTestHost(
            DSTimeline(
                isPlaying: Binding(
                    get: { isPlaying },
                    set: { newValue in
                        isPlaying = newValue
                        if newValue { canvas.play() } else { canvas.pause() }
                    }
                ),
                time: .constant(0),
                loops: .constant(true),
                speed: .constant(1),
                duration: canvas.activePlaybackDuration,
                capsuleHeight: OverlayMetrics.timelineHeight,
                clipTitles: clipTitles(for: canvas),
                selectedClipIndices: canvas.selectedClipIndices,
                defaultClipIndices: canvas.defaultSelectedAnimationClipIndices,
                onSelectClip: { _ in }
            )
        )
        defer { host.close() }
        #expect(!canvas.isPlaying)
        isPlaying = true
        canvas.play()
        #expect(canvas.isPlaying)
        isPlaying = false
        canvas.pause()
        #expect(!canvas.isPlaying)
        _ = host
        _ = container
    }

    @Test func playButtonClickStartsAndPausesThroughTheHUD() async throws {
        let (canvas, container) = try await readyCanvas()
        defer { canvas.view?.removeFromSuperview() }
        let host = await AccessibilityTestHost(AnimationTimelineHUD(canvas: canvas))
        defer { host.close() }
        #expect(!canvas.isPlaying)
        #expect(host.performCustomAction(named: "Toggle playback"), "Play exposes a VoiceOver action")
        #expect(try await waitUntil { canvas.isPlaying }, "activating Play starts playback")
        #expect(try await waitUntil { host.text.contains("Pause") }, "the control relabels to Pause while playing")
        #expect(host.performCustomAction(named: "Toggle playback"))
        #expect(try await waitUntil { !canvas.isPlaying }, "activating Pause stops playback")
        _ = container
    }

    @Test func scrubberIncrementAdjustsTimeViaAccessibility() async throws {
        let (canvas, container) = try await readyCanvas()
        defer { canvas.view?.removeFromSuperview() }
        let host = await AccessibilityTestHost(AnimationTimelineHUD(canvas: canvas))
        defer { host.close() }
        let start = canvas.time
        #expect(host.performCustomAction(named: "Step timeline forward"), "the scrubber exposes a forward step action")
        #expect(canvas.time > start, "stepping the scrubber advances time")
        #expect(!canvas.isPlaying)
        _ = container
    }

    @Test func scrubberClickSeeksWithoutPlaying() async throws {
        let (canvas, container) = try await readyCanvas()
        defer { canvas.view?.removeFromSuperview() }
        let host = await AccessibilityTestHost(AnimationTimelineHUD(canvas: canvas))
        defer { host.close() }
        #expect(canvas.time == 0)
        let duration = canvas.activePlaybackDuration
        let target = duration * 0.5
        let frameStep: Float = 1 / 30
        let steps = max(1, Int((target / frameStep).rounded(.up)))
        for _ in 0 ..< steps {
            guard host.performCustomAction(named: "Step timeline forward") else { break }
        }
        #expect(canvas.time > 0, "adjusting the scrubber moves time")
        #expect(abs(canvas.time - target) < max(duration * 0.05, 0.02), "increment reaches about mid-track")
        #expect(!canvas.isPlaying)
        _ = container
    }

    @Test func spaceKeyTogglesPlaybackInTheHUD() async throws {
        let document = try await GLTFDocument.load(from: TestFixtures.boxAnimated)
        let suite = "gltf.timeline-space.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let state = ViewState(settings: AppSettings(defaults: defaults))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 512, height: 512))
        state.canvas.mount(in: container, url: TestFixtures.boxAnimated, options: state.options)
        #expect(try await waitUntil { state.canvas.phase == .ready && state.canvas.showsAnimationTimeline })
        defer { state.canvas.view?.removeFromSuperview() }
        let host = await AccessibilityTestHost(
            CanvasRegion(bounds: document.bounds, view: state) { Color.clear }
        )
        defer { host.close() }
        #expect(host.performCustomAction(named: "Toggle playback"))
        #expect(try await waitUntil { state.canvas.isPlaying })
        let space = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: host.window.windowNumber, context: nil,
            characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49
        ))
        host.window.makeKeyAndOrderFront(nil)
        defer { host.window.resignKey() }
        let spaceTarget = try #require(findSpaceKeyView(in: host.view))
        host.window.makeFirstResponder(spaceTarget)
        spaceTarget.keyDown(with: space)
        #expect(try await waitUntil { !state.canvas.isPlaying }, "Space pauses playback from the canvas focus section")
        _ = container
    }

    @Test func sidebarOffersAnimationsSection() async throws {
        let (canvas, container) = try await readyCanvas()
        defer { canvas.view?.removeFromSuperview() }
        let document = try await GLTFDocument.load(from: TestFixtures.boxAnimated)
        let host = await AccessibilityTestHost(
            OutlinerList(
                document: document,
                validation: ValidationResult(nil, document: document),
                selection: .constant(nil),
                selectedIDs: .constant([]),
                onActivate: { _ in },
                animatedSceneNodes: canvas.animatedSceneNodeIndicesInSelection()
            )
        )
        defer { host.close() }
        #expect(host.text.localizedCaseInsensitiveContains("Animations"), "the sidebar lists the file's animations")
        _ = container
    }

    @Test func animatedRowShowsAnimatedIndicatorOnlyWhenFlagged() async throws {
        let animated = await AccessibilityTestHost(
            NodeRow(item: OutlinerItem(id: NodeID(kind: .mesh, index: 0), name: "Box"), isSelected: false,
                    showsAnimatedIndicator: true)
        )
        defer { animated.close() }
        #expect(animated.text.contains("Animated"))

        let still = await AccessibilityTestHost(
            NodeRow(item: OutlinerItem(id: NodeID(kind: .mesh, index: 0), name: "Box"), isSelected: false)
        )
        defer { still.close() }
        #expect(!still.text.contains("Animated"))
    }

    @Test func animatedMorphSamplesLiveWeightsAtMidClip() async throws {
        let canvas = ModelCanvasController()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 512, height: 512))
        canvas.mount(in: container, url: TestFixtures.animatedMorphCube, options: ViewOptions())
        #expect(try await waitUntil { canvas.phase == .ready && canvas.showsAnimationTimeline })
        defer { canvas.view?.removeFromSuperview() }
        let duration = canvas.activePlaybackDuration
        canvas.scrub(to: duration * 0.5)
        let pose = try #require(canvas.currentAnimationPose())
        let nodeWeights = pose.nodeWeights[0]
        let meshWeights = pose.meshWeights[0]
        let weights = nodeWeights ?? meshWeights
        let sampled = try #require(weights)
        #expect(sampled.contains { $0 > 0.01 }, "AnimatedMorphCube morph weights change at mid-clip")
        _ = container
    }

    @Test func scrubberChangesTimeAndPose() async throws {
        let (canvas, container) = try await readyCanvas()
        defer { canvas.view?.removeFromSuperview() }
        #expect(canvas.currentAnimationPose() == nil)
        canvas.scrub(to: 0.5)
        let posed = try #require(canvas.currentAnimationPose())
        #expect(!posed.nodeOverrides.isEmpty)
        let host = await AccessibilityTestHost(
            DSTimeline(
                isPlaying: .constant(false),
                time: Binding(get: { canvas.time }, set: { canvas.scrub(to: $0) }),
                loops: .constant(true),
                speed: .constant(1),
                duration: canvas.activePlaybackDuration,
                capsuleHeight: OverlayMetrics.timelineHeight,
                clipTitles: clipTitles(for: canvas),
                selectedClipIndices: canvas.selectedClipIndices,
                defaultClipIndices: canvas.defaultSelectedAnimationClipIndices,
                onSelectClip: { canvas.selectAnimationClip(at: $0) }
            )
        )
        defer { host.close() }
        #expect(host.text.contains(PlaybackTimeFormat.string(0.5)))
        _ = container
    }

    @Test func singleSelectedClipShowsItsNameInThePicker() async throws {
        let host = await AccessibilityTestHost(
            DSTimeline(
                isPlaying: .constant(false),
                time: .constant(0),
                loops: .constant(true),
                speed: .constant(1),
                duration: 3,
                capsuleHeight: OverlayMetrics.timelineHeight,
                clipTitles: ["Alpha", "Beta", "Gamma"],
                selectedClipIndices: [0],
                defaultClipIndices: [0, 1, 2],
                onSelectClip: { _ in }
            )
        )
        defer { host.close() }
        #expect(host.text.contains("Alpha"))
        #expect(!host.text.contains("Default"))
    }

    @Test func timelineAndReadoutDoNotOverlapAt800x600() async throws {
        let canvasWidth: CGFloat = 800
        let readoutWidth: CGFloat = 220
        let timelineWidth: CGFloat = 400
        let inset = OverlayMetrics.inset
        let readoutBottom = inset + OverlayMetrics.timelineHeight + DS.Spacing.m
        let readoutRect = CGRect(x: canvasWidth - inset - readoutWidth, y: readoutBottom,
                                 width: readoutWidth, height: OverlayMetrics.dimensionsHeight)
        let timelineRect = CGRect(x: (canvasWidth - timelineWidth) / 2, y: inset,
                                  width: timelineWidth, height: OverlayMetrics.timelineHeight)
        #expect(!readoutRect.intersects(timelineRect))
    }

    @Test func inspectorShowsLiveMorphWeightsAtMidClip() async throws {
        let document = try await GLTFDocument.load(from: TestFixtures.animatedMorphCube)
        let canvas = ModelCanvasController()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 512, height: 512))
        canvas.mount(in: container, url: TestFixtures.animatedMorphCube, options: ViewOptions())
        #expect(try await waitUntil { canvas.phase == .ready && canvas.showsAnimationTimeline })
        defer { canvas.view?.removeFromSuperview() }
        canvas.scrub(to: canvas.activePlaybackDuration * 0.5)
        let pose = try #require(canvas.currentAnimationPose())
        #expect(pose.nodeWeights[0] != nil || pose.meshWeights[0] != nil)
        let morph = try #require(document.morphs.first)
        let weights = try #require(MorphLiveWeightRows.weights(for: morph, document: document, canvas: canvas))
        #expect(weights.contains { $0 > 0.01 })
        _ = container
    }

    @Test func scrubberAccessibilityIncrementStepsOneFrame() async throws {
        let (canvas, container) = try await readyCanvas()
        defer { canvas.view?.removeFromSuperview() }
        let host = await AccessibilityTestHost(AnimationTimelineHUD(canvas: canvas))
        defer { host.close() }
        let start = canvas.time
        #expect(host.incrementAccessibility(labeled: "Timeline"))
        #expect(abs(canvas.time - start - 1 / 30) < 0.002)
        _ = container
    }

    @Test func clipSpeedAndLoopControlsMutateController() async throws {
        let (canvas, container) = try await readyCanvas()
        defer { canvas.view?.removeFromSuperview() }
        canvas.loops = false
        canvas.speed = 2
        canvas.selectAnimationClip(at: 0)
        #expect(!canvas.loops)
        #expect(canvas.speed == 2)
        #expect(canvas.selectedClipIndices == [0])
        canvas.selectAnimationClip(at: nil)
        #expect(canvas.selectedClipIndices == canvas.defaultSelectedAnimationClipIndices)
        _ = container
    }
}
