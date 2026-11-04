import AppKit
import Foundation
import Testing
@testable import GLTFInspector
@testable import Renderer

/// Canvas animation playback: time, scrub, loop, and reset without launching the app.
@MainActor
@Suite(.serialized)
struct AnimationPlaybackTests {
    private func mount(_ canvas: ModelCanvasController, url: URL, options: ViewOptions = ViewOptions()) -> NSView {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        canvas.mount(in: container, url: url, options: options)
        return container
    }

    private func ready(_ canvas: ModelCanvasController, url: URL) async throws {
        _ = mount(canvas, url: url)
        _ = try await waitUntil { canvas.phase == .ready }
    }

    @Test func loadedFileExposesClipsPausedAtRest() async throws {
        let canvas = ModelCanvasController()
        try await ready(canvas, url: TestFixtures.boxAnimated)
        #expect(!canvas.animationClips.isEmpty)
        #expect(!canvas.isPlaying)
        #expect(canvas.time == 0)
        #expect(canvas.currentAnimationPose() == nil, "opens at rest without an animation pose")
    }

    @Test func playAdvancesTimeAndPauseFreezes() async throws {
        let canvas = ModelCanvasController()
        try await ready(canvas, url: TestFixtures.boxAnimated)
        canvas.speed = 2
        canvas.play()
        canvas.advancePlayback(elapsed: 0.5)
        #expect(abs(canvas.time - 1) < 1e-4, "0.5 s elapsed × speed 2 → 1 s clip time")
        canvas.pause()
        let frozen = canvas.time
        canvas.advancePlayback(elapsed: 2)
        #expect(canvas.time == frozen)
    }

    @Test func injectedClockDrivesDisplayLinkTicks() async throws {
        let canvas = ModelCanvasController()
        try await ready(canvas, url: TestFixtures.boxAnimated)
        let anchor = ContinuousClock.now
        let offset = Box(value: Duration.zero)
        canvas.playbackClock = AnimationPlaybackClock { anchor + offset.value }
        canvas.play()
        canvas.seedPlaybackInstantForTesting(anchor)
        offset.value = .milliseconds(250)
        canvas.tickAnimationFromDisplayLink()
        #expect(abs(canvas.time - 0.25) < 1e-3)
    }

    @Test func scrubReposesWhilePaused() async throws {
        let canvas = ModelCanvasController()
        try await ready(canvas, url: TestFixtures.boxAnimated)
        #expect(canvas.currentAnimationPose() == nil)
        canvas.scrub(to: 0.5)
        let posed = try #require(canvas.currentAnimationPose())
        #expect(!posed.nodeOverrides.isEmpty, "scrub evaluates selected clips")
        let animatedY = posed.nodeOverrides.values.compactMap(\.translation?.y).max() ?? 0
        #expect(animatedY > 0.5)
    }

    @Test func speedIsClamped() async throws {
        let canvas = ModelCanvasController()
        canvas.speed = 0.1
        #expect(canvas.speed == 0.25)
        canvas.speed = 9
        #expect(canvas.speed == 2)
    }

    @Test func nonLoopingPlaybackStopsAtClipEnd() async throws {
        let canvas = ModelCanvasController()
        try await ready(canvas, url: TestFixtures.boxAnimated)
        canvas.loops = false
        canvas.play()
        let duration = try #require(canvas.animationClips.first?.duration)
        canvas.advancePlayback(elapsed: duration + 1)
        #expect(!canvas.isPlaying)
        #expect(canvas.time == duration)
    }

    @Test func loopingWrapsTime() async throws {
        let canvas = ModelCanvasController()
        try await ready(canvas, url: TestFixtures.boxAnimated)
        canvas.loops = true
        canvas.play()
        let duration = try #require(canvas.animationClips.first?.duration)
        canvas.advancePlayback(elapsed: duration + 0.25)
        #expect(canvas.isPlaying)
        #expect(abs(canvas.time - 0.25) < 1e-4)
    }

    @Test func noClipsAdvanceDoesNothing() async throws {
        let canvas = ModelCanvasController()
        try await ready(canvas, url: TestFixtures.cube)
        #expect(canvas.animationClips.isEmpty)
        canvas.play()
        #expect(!canvas.isPlaying)
        canvas.advancePlayback(elapsed: 1)
        #expect(canvas.time == 0)
    }

    @Test func reloadAndResetStopPlayback() async throws {
        let canvas = ModelCanvasController()
        try await ready(canvas, url: TestFixtures.boxAnimated)
        canvas.play()
        canvas.scrub(to: 0.4)
        canvas.stopPlayback()
        #expect(!canvas.isPlaying && canvas.time == 0)

        canvas.update(url: TestFixtures.cube, options: ViewOptions())
        _ = try await waitUntil { canvas.phase == .ready && canvas.animationClips.isEmpty }

        let settings = try settingsForReset()
        let state = ViewState(settings: settings)
        _ = mount(state.canvas, url: TestFixtures.boxAnimated)
        _ = try await waitUntil { state.canvas.phase == .ready && !state.canvas.animationClips.isEmpty }
        state.canvas.play()
        state.canvas.scrub(to: 0.3)
        state.reset()
        #expect(!state.canvas.isPlaying && state.canvas.time == 0)
    }

    @Test func displayLinkRunsOnlyWhilePlayingOrAutoRotating() async throws {
        let canvas = ModelCanvasController()
        let container = mount(canvas, url: TestFixtures.cube)
        _ = try await waitUntil { canvas.phase == .ready }
        let view = try #require(canvas.view)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = container
        defer { window.contentView = nil; window.close() }
        view.layoutSubtreeIfNeeded()
        #expect(!view.isDisplayLinkActive)

        var options = ViewOptions()
        options.autoRotates = true
        canvas.update(url: TestFixtures.cube, options: options)
        _ = try await waitUntil { view.isDisplayLinkActive }

        options.autoRotates = false
        canvas.update(url: TestFixtures.cube, options: options)
        _ = try await waitUntil { !view.isDisplayLinkActive }

        canvas.update(url: TestFixtures.boxAnimated, options: ViewOptions())
        _ = try await waitUntil { canvas.phase == .ready && !canvas.animationClips.isEmpty }
        canvas.play()
        _ = try await waitUntil { view.isDisplayLinkActive }
        canvas.pause()
        _ = try await waitUntil { !view.isDisplayLinkActive }
    }

    private final class Box<T>: @unchecked Sendable {
        var value: T
        init(value: T) { self.value = value }
    }

    private func settingsForReset() throws -> AppSettings {
        let suite = "gltf.playback.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return AppSettings(defaults: defaults)
    }
}
