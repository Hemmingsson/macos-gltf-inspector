import AppKit
import Foundation
import Testing
@testable import GLTFInspector
@testable import Renderer
import SwiftUI

/// Hosted timeline HUD: visibility, transport wiring, and scrub pose without launching the app.
@MainActor
@Suite(.serialized)
struct TimelineHUDTests {
    private func readyCanvas() async throws -> (ModelCanvasController, NSView) {
        let canvas = ModelCanvasController()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        canvas.mount(in: container, url: TestFixtures.boxAnimated, options: ViewOptions())
        _ = try await waitUntil { canvas.phase == .ready }
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
                clips: canvas.animationClips,
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
                clips: canvas.animationClips,
                selectedClipIndices: canvas.selectedClipIndices,
                defaultClipIndices: canvas.defaultSelectedAnimationClipIndices,
                onSelectClip: { canvas.selectAnimationClip(at: $0) }
            )
        )
        defer { host.close() }
        #expect(host.text.contains(PlaybackTimeFormat.string(0.5)))
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
