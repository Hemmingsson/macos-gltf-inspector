import AppKit
import RealityKit
import SwiftUI

@Observable
final class GLBPreviewInteraction {
    var zoom: Float = 1

    func applyScroll(_ event: NSEvent) {
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        GLBLog.event(GLBLog.preview, "scroll dy=\(dy) precise=\(event.hasPreciseScrollingDeltas) zoom=\(zoom)")
        setZoom(zoom * exp(Float(-dy) * 0.004))
    }

    func applyMagnify(_ event: NSEvent) {
        GLBLog.event(GLBLog.preview, "magnify=\(event.magnification) zoom=\(zoom)")
        setZoom(zoom * Float(1 + event.magnification))
    }

    private func setZoom(_ value: Float) {
        let clamped = min(max(value, 0.12), 8)
        if abs(clamped - zoom) > 0.0001 {
            GLBLog.event(GLBLog.preview, "zoom \(zoom) → \(clamped)")
        }
        zoom = clamped
    }
}

/// Forwards trackpad scroll/magnify into `GLBPreviewInteraction` (SwiftUI misses these on macOS).
final class GLBPreviewHostingView: NSHostingView<GLBPreviewView> {
    var interaction: GLBPreviewInteraction?

    override func scrollWheel(with event: NSEvent) { interaction?.applyScroll(event) }
    override func magnify(with event: NSEvent) { interaction?.applyMagnify(event) }
    override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

/// Non-hosting root used by Quick Look so scroll events still hit before the hosting view.
final class GLBPreviewEventView: NSView {
    var interaction: GLBPreviewInteraction?

    override func scrollWheel(with event: NSEvent) { interaction?.applyScroll(event) }
    override func magnify(with event: NSEvent) { interaction?.applyMagnify(event) }
    override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

struct GLBPreviewView: View {
    enum State {
        case loading
        case ready(Entity)
        case failed

        @MainActor
        static func loaded(from url: URL) async -> State {
            GLBLog.event(GLBLog.preview, "State.loaded \(GLBLog.describeURL(url))")
            do {
                let entity = try await GLBEntityLoader.load(from: url)
                GLBLog.event(GLBLog.preview, "State.ready \(GLBLog.describe(entity))")
                return .ready(entity)
            } catch {
                GLBLog.error(GLBLog.preview, "State.failed \(url.path) \(error)")
                return .failed
            }
        }
    }

    let state: State
    var interaction: GLBPreviewInteraction
    var isDark: Bool

    var body: some View {
        Group {
            switch state {
            case .loading:
                GLBPreviewBackdrop.color(at: 0, dark: isDark).ignoresSafeArea()
            case .ready(let entity):
                GLBPreviewScene(entity: entity, interaction: interaction, isDark: isDark)
            case .failed:
                ZStack {
                    GLBPreviewBackdrop.color(at: 0, dark: isDark).ignoresSafeArea()
                    Text("Failed to load model")
                        .font(.system(size: 13))
                        .foregroundStyle(isDark ? .white.opacity(0.5) : .black.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
        .onAppear {
            switch state {
            case .loading:
                GLBLog.event(GLBLog.preview, "view appear loading dark=\(isDark)")
            case .ready(let entity):
                GLBLog.event(GLBLog.preview, "view appear ready dark=\(isDark) \(GLBLog.describe(entity))")
            case .failed:
                GLBLog.error(GLBLog.preview, "view appear failed dark=\(isDark)")
            }
        }
    }
}

enum GLBPreviewBackdrop {
    static let darkRGB = (r: 38.0 / 255, g: 38.0 / 255, b: 38.0 / 255)
    static let dark = Color(red: darkRGB.r, green: darkRGB.g, blue: darkRGB.b)
    static let mid = Color(red: 128 / 255, green: 128 / 255, blue: 128 / 255)
    static let light = Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255)

    static func colors(dark: Bool) -> [Color] {
        dark ? [Self.dark, mid, light, .white] : [.white, light, mid, Self.dark]
    }

    static func color(at index: Int, dark: Bool) -> Color {
        let palette = colors(dark: dark)
        return palette[index % palette.count]
    }

    static func cgColor(dark: Bool) -> CGColor {
        if dark {
            return CGColor(srgbRed: darkRGB.r, green: darkRGB.g, blue: darkRGB.b, alpha: 1)
        }
        return CGColor(gray: 1, alpha: 1)
    }
}

/// Reference box so RealityView `make` can stash unscaled bounds while zoom scales the pivot.
private final class PreviewFrame {
    var bounds = BoundingBox()
}

private struct GLBPreviewScene: View {
    let entity: Entity
    @Bindable var interaction: GLBPreviewInteraction
    var isDark: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var backdropIndex = 0
    @State private var autoRotate = true
    @State private var lightingEnabled = true
    @State private var orbitYaw: Float = 0
    @State private var orbitPitch: Float = 0
    @State private var dragOrigin: (yaw: Float, pitch: Float)?
    @State private var playback: AnimationPlaybackController?
    @State private var clipDuration: TimeInterval = 0
    @State private var currentTime: TimeInterval = 0
    @State private var isPlaying = true
    @State private var isScrubbing = false
    @State private var viewport = CGSize(width: 810, height: 600)
    private let frame = PreviewFrame()

    private var tickWhileActive: Bool {
        autoRotate || (isPlaying && playback != nil)
    }

    var body: some View {
        RealityView { content in
            GLBLog.event(GLBLog.preview, "RealityView.make dark=\(isDark) viewport=\(viewport.width)x\(viewport.height)")
            content.camera = .virtual
            let assembled = GLBPreviewCamera.makeTurntable(for: entity)
            frame.bounds = assembled.bounds

            content.add(assembled.pivot)
            Self.syncStudioLights(in: &content, enabled: lightingEnabled)
            content.add(
                GLBPreviewCamera.makeFrontThreeQuarter(
                    minBound: assembled.bounds.min,
                    maxBound: assembled.bounds.max,
                    padding: GLBPreviewCamera.previewFitPadding,
                    aspect: aspect(of: viewport)
                )
            )

            if let animation = entity.availableAnimations.first {
                let probe = entity.playAnimation(animation, startsPaused: true)
                let duration = probe.duration
                probe.stop()
                clipDuration = duration.isFinite && duration > 0 ? duration : 0
                GLBLog.event(
                    GLBLog.preview,
                    "animation probe name=\(animation.name) duration=\(duration) clipDuration=\(clipDuration)"
                )
                if clipDuration > 0 {
                    playback = entity.playAnimation(animation.repeat())
                    GLBLog.event(GLBLog.preview, "animation looping")
                }
            } else {
                GLBLog.event(GLBLog.preview, "no animations on entity")
            }
            GLBLog.event(GLBLog.preview, "RealityView.make done entities=\(content.entities.count)")
        } update: { content in
            Self.syncStudioLights(in: &content, enabled: lightingEnabled)
            for entity in content.entities where entity.name == "turntable" {
                entity.orientation =
                    simd_quatf(angle: orbitYaw, axis: [0, 1, 0]) *
                    simd_quatf(angle: orbitPitch, axis: [1, 0, 0])
                entity.scale = SIMD3<Float>(repeating: interaction.zoom)
            }
            for entity in content.entities where entity.name == "previewCamera" {
                let position = GLBPreviewCamera.cameraPosition(
                    minBound: frame.bounds.min,
                    maxBound: frame.bounds.max,
                    padding: GLBPreviewCamera.previewFitPadding,
                    aspect: aspect(of: viewport)
                )
                entity.look(at: frame.bounds.center, from: position, relativeTo: nil)
            }
        }
        .gesture(orbitDragGesture)
        .background {
            GeometryReader { proxy in
                GLBPreviewBackdrop.color(at: backdropIndex, dark: isDark)
                    .onAppear { viewport = proxy.size }
                    .onChange(of: proxy.size) { _, size in
                        GLBLog.event(GLBLog.window, "preview viewport \(viewport.width)x\(viewport.height) → \(size.width)x\(size.height)")
                        viewport = size
                    }
            }
        }
        .overlay(alignment: .bottomLeading) {
            GLBPreviewToolbar(
                backdropIndex: $backdropIndex,
                autoRotate: $autoRotate,
                lightingEnabled: $lightingEnabled,
                isDark: isDark
            )
            .padding(10)
        }
        .overlay(alignment: .bottom) {
            if playback != nil, clipDuration > 0 {
                GLBPreviewPlayback(
                    isPlaying: $isPlaying,
                    isScrubbing: $isScrubbing,
                    currentTime: $currentTime,
                    duration: clipDuration,
                    onScrub: seek(to:)
                )
                .padding(.bottom, 10)
                .padding(.leading, 84)
            }
        }
        .onAppear {
            GLBLog.event(
                GLBLog.preview,
                "scene appear reduceMotion=\(reduceMotion) autoRotate=\(autoRotate) lighting=\(lightingEnabled) anims=\(entity.availableAnimations.count)"
            )
            if reduceMotion {
                autoRotate = false
                GLBLog.event(GLBLog.preview, "autoRotate disabled for Reduce Motion")
            }
        }
        .onChange(of: isPlaying) { _, playing in
            guard let playback else { return }
            GLBLog.event(GLBLog.preview, "playback \(playing ? "resume" : "pause") time=\(playback.time)")
            if playing {
                playback.resume()
            } else {
                playback.pause()
            }
        }
        .task(id: tickWhileActive) {
            guard tickWhileActive else { return }
            GLBLog.event(GLBLog.preview, "tick loop start autoRotate=\(autoRotate) playing=\(isPlaying)")
            var lastTick = Date()
            while !Task.isCancelled {
                let now = Date()
                let dt = now.timeIntervalSince(lastTick)
                lastTick = now
                // Pause spin while the user is dragging; keep `autoRotate` preference.
                if autoRotate, dragOrigin == nil {
                    orbitYaw += Float(dt) * 20 * .pi / 180
                }
                if isPlaying, !isScrubbing, let playback, clipDuration > 0 {
                    currentTime = playback.time.truncatingRemainder(dividingBy: clipDuration)
                    if currentTime < 0 { currentTime += clipDuration }
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
            GLBLog.event(GLBLog.preview, "tick loop end")
        }
    }

    private var orbitDragGesture: some Gesture {
        // minimumDistance 0 so mouse-down immediately pauses auto-rotate.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = (orbitYaw, orbitPitch)
                    GLBLog.event(GLBLog.preview, "orbit drag begin yaw=\(orbitYaw) pitch=\(orbitPitch)")
                }
                guard let dragOrigin else { return }
                orbitYaw = dragOrigin.yaw + Float(value.translation.width) * 0.008
                orbitPitch = min(
                    max(dragOrigin.pitch + Float(value.translation.height) * 0.008, -1.2),
                    1.2
                )
            }
            .onEnded { _ in
                GLBLog.event(GLBLog.preview, "orbit drag end yaw=\(orbitYaw) pitch=\(orbitPitch)")
                dragOrigin = nil
            }
    }

    private func aspect(of size: CGSize) -> Float {
        Float(size.width / max(size.height, 1))
    }

    private func seek(to time: TimeInterval) {
        playback?.time = time
        currentTime = time
    }

    @MainActor
    private static func syncStudioLights(in content: inout RealityViewCameraContent, enabled: Bool) {
        let existing = content.entities.filter { GLBPreviewLighting.studioLightNames.contains($0.name) }
        if enabled {
            if existing.isEmpty {
                GLBLog.event(GLBLog.lighting, "adding studio lights")
                for light in GLBPreviewLighting.makeStudioLights() {
                    content.add(light)
                }
            }
        } else {
            if !existing.isEmpty {
                GLBLog.event(GLBLog.lighting, "removing studio lights count=\(existing.count)")
            }
            for light in existing {
                content.remove(light)
            }
        }
    }
}

private struct GLBPreviewToolbar: View {
    @Binding var backdropIndex: Int
    @Binding var autoRotate: Bool
    @Binding var lightingEnabled: Bool
    let isDark: Bool

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 6) {
                toolbarButtons
            }
        } else {
            toolbarButtons
        }
    }

    private var toolbarButtons: some View {
        HStack(spacing: 6) {
            overlayButton("circle.lefthalf.filled", selected: false, help: "Toggle background") {
                let count = GLBPreviewBackdrop.colors(dark: isDark).count
                backdropIndex = (backdropIndex + 1) % count
                GLBLog.event(GLBLog.preview, "backdrop → \(backdropIndex)")
            }
            overlayButton(
                lightingEnabled ? "lightbulb.fill" : "lightbulb",
                selected: lightingEnabled,
                help: "Studio lighting"
            ) {
                lightingEnabled.toggle()
                GLBLog.event(GLBLog.preview, "lightingEnabled=\(lightingEnabled)")
            }
            overlayButton("arrow.trianglehead.2.clockwise.rotate.90", selected: autoRotate, help: "Auto-rotate") {
                autoRotate.toggle()
                GLBLog.event(GLBLog.preview, "autoRotate=\(autoRotate)")
            }
        }
    }

    private func overlayButton(_ systemName: String, selected: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .overlayChrome(selected: selected, cornerRadius: 6)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct GLBPreviewPlayback: View {
    @Binding var isPlaying: Bool
    @Binding var isScrubbing: Bool
    @Binding var currentTime: TimeInterval
    let duration: TimeInterval
    let onScrub: (TimeInterval) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isPlaying.toggle()
                GLBLog.event(GLBLog.preview, "play/pause tapped isPlaying=\(isPlaying)")
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Play/Pause")

            Slider(
                value: Binding(
                    get: { duration > 0 ? currentTime : 0 },
                    set: { onScrub($0) }
                ),
                in: 0...max(duration, 0.001),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    GLBLog.event(GLBLog.preview, "scrub editing=\(editing) time=\(currentTime)")
                }
            )

            Text("\(currentTime, specifier: "%.1f")s")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 32, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minWidth: 200, maxWidth: 360)
        .overlayChrome(selected: false, cornerRadius: 8)
    }
}

private extension View {
    @ViewBuilder
    func overlayChrome(selected: Bool, cornerRadius: CGFloat) -> some View {
        if #available(macOS 26, *) {
            glassEffect(
                selected ? .regular.tint(Color.primary.opacity(0.12)).interactive() : .regular.interactive(),
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            background(.black.opacity(selected ? 0.55 : 0.4), in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(.white.opacity(0.12))
                }
        }
    }
}
