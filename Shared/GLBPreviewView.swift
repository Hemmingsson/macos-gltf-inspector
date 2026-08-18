import AppKit
import RealityKit
import SwiftUI

@Observable
final class GLBPreviewInteraction {
    var zoom: Float = 1

    func applyScroll(_ event: NSEvent) {
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        guard dy != 0 else { return }
        setZoom(zoom * exp(Float(-dy) * 0.004))
    }

    func applyMagnify(_ event: NSEvent) {
        guard event.magnification != 0 else { return }
        setZoom(zoom * Float(1 + event.magnification))
    }

    private func setZoom(_ value: Float) {
        let clamped = min(max(value, 0.12), 8)
        guard abs(clamped - zoom) > 0.0001 else { return }
        zoom = clamped
    }
}

/// Forwards trackpad scroll/magnify into `GLBPreviewInteraction` (SwiftUI misses these on macOS).
final class GLBPreviewHostingView: NSHostingView<GLBPreviewView> {
    var interaction: GLBPreviewInteraction?

    override var isOpaque: Bool { false }
    override func scrollWheel(with event: NSEvent) { interaction?.applyScroll(event) }
    override func magnify(with event: NSEvent) { interaction?.applyMagnify(event) }
    override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

/// Non-hosting root used by Quick Look so scroll events still hit before the hosting view.
final class GLBPreviewEventView: NSView {
    var interaction: GLBPreviewInteraction?

    override var isOpaque: Bool { false }
    override func scrollWheel(with event: NSEvent) { interaction?.applyScroll(event) }
    override func magnify(with event: NSEvent) { interaction?.applyMagnify(event) }
    override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

struct GLBPreviewView: View {
    enum State {
        case loading
        case ready(Entity, stats: GLBPreviewStats?)
        case failed

        /// File IO runs off the main actor (`GLBEntityLoader.load`).
        static func loaded(from url: URL) async -> State {
            do {
                let stats = try? GLBPreviewStats.from(url: url)
                let entity = try await GLBEntityLoader.load(from: url)
                return .ready(entity, stats: stats)
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
                GLBPreviewBackdrop.color(at: 0).ignoresSafeArea()
            case .ready(let entity, let stats):
                GLBPreviewScene(entity: entity, stats: stats, interaction: interaction, isDark: isDark)
            case .failed:
                ZStack {
                    GLBPreviewBackdrop.color(at: 0).ignoresSafeArea()
                    Text("Failed to load model")
                        .font(.system(size: 13))
                        .foregroundStyle(
                            GLBPreviewBackdrop.iconColor(at: 0, systemDark: isDark, active: true).opacity(0.5)
                        )
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
    }
}

enum GLBPreviewBackdrop {
    static let darkRGB = (r: 38.0 / 255, g: 38.0 / 255, b: 38.0 / 255)
    static let dark = Color(red: darkRGB.r, green: darkRGB.g, blue: darkRGB.b)
    /// Lets the host window / Quick Look panel show through.
    static let window = Color.clear
    static let all = [window, Color.white, dark]

    static func color(at index: Int) -> Color {
        all[index % all.count]
    }

    /// White icons on dark surfaces; charcoal on light. Clear backdrop: OS setting first (QL `isDark` is flaky).
    static func useLightIcons(at index: Int, systemDark: Bool) -> Bool {
        switch index % all.count {
        case 1: return false
        case 2: return true
        default:
            if UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" {
                return true
            }
            return systemDark
        }
    }

    static func iconColor(at index: Int, systemDark: Bool, active: Bool) -> Color {
        let base: Color = useLightIcons(at: index, systemDark: systemDark) ? .white : dark
        return active ? base : base.opacity(0.4)
    }
}

/// Reference box so RealityView `make` can stash unscaled bounds while zoom scales the pivot.
private final class PreviewFrame {
    var bounds = BoundingBox()
    var cameraAspect: Float = -1
}

private struct GLBPreviewScene: View {
    let entity: Entity
    var stats: GLBPreviewStats?
    @Bindable var interaction: GLBPreviewInteraction
    var isDark: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var backdropIndex = 0
    @State private var autoRotate: Bool
    @State private var orbitYaw: Float = 0
    @State private var orbitPitch: Float = 0
    @State private var dragOrigin: (yaw: Float, pitch: Float)?
    @State private var playback: AnimationPlaybackController?
    @State private var clipDuration: TimeInterval = 0
    @State private var currentTime: TimeInterval = 0
    @State private var isPlaying = true
    @State private var viewport = CGSize(width: 810, height: 600)
    @State private var chromeVisible = true
    private let frame = PreviewFrame()

    init(entity: Entity, stats: GLBPreviewStats?, interaction: GLBPreviewInteraction, isDark: Bool) {
        self.entity = entity
        self.stats = stats
        self.interaction = interaction
        self.isDark = isDark
        let bounds = GLBPreviewCamera.modelBounds(of: entity)
        let extent = bounds.max - bounds.min
        if let axis = GLBPreviewCamera.thinAxis(extent), axis == 0 || axis == 2 {
            _autoRotate = State(initialValue: false)
            GLBLog.info(GLBLog.preview, "autoRotate disabled for standing plane thinAxis=\(axis)")
        } else {
            _autoRotate = State(initialValue: true)
        }
    }

    private var tickWhileActive: Bool {
        autoRotate || (chromeVisible && isPlaying && playback != nil)
    }

    var body: some View {
        ZStack {
            RealityView { content in
                content.camera = .virtual
                let assembled = GLBPreviewCamera.makeTurntable(for: entity)
                frame.bounds = assembled.bounds

                content.add(assembled.pivot)
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
                    if clipDuration > 0 {
                        playback = entity.playAnimation(animation.repeat())
                    }
                }
            } update: { content in
                for entity in content.entities where entity.name == "turntable" {
                    entity.orientation =
                        simd_quatf(angle: orbitYaw, axis: [0, 1, 0]) *
                        simd_quatf(angle: orbitPitch, axis: [1, 0, 0])
                    entity.scale = SIMD3<Float>(repeating: interaction.zoom)
                }
                let viewAspect = aspect(of: viewport)
                guard abs(viewAspect - frame.cameraAspect) > 0.001 else { return }
                frame.cameraAspect = viewAspect
                for entity in content.entities where entity.name == "previewCamera" {
                    let position = GLBPreviewCamera.cameraPosition(
                        minBound: frame.bounds.min,
                        maxBound: frame.bounds.max,
                        padding: GLBPreviewCamera.previewFitPadding,
                        aspect: viewAspect
                    )
                    entity.look(at: frame.bounds.center, from: position, relativeTo: nil)
                }
            }
            .background {
                GeometryReader { proxy in
                    GLBPreviewBackdrop.color(at: backdropIndex)
                        .onAppear { applyViewport(proxy.size) }
                        .onChange(of: proxy.size) { _, size in
                            applyViewport(size)
                        }
                }
            }
            // RealityView often eats SwiftUI taps in QL; drive orbit + chrome toggle from this layer.
            Color.clear
                .contentShape(Rectangle())
                .gesture(orbitDragGesture)
                .onTapGesture {
                    chromeVisible.toggle()
                }

            if chromeVisible {
                HStack(alignment: .bottom, spacing: 12) {
                    GLBPreviewToolbar(
                        backdropIndex: $backdropIndex,
                        autoRotate: $autoRotate,
                        showPlayback: playback != nil,
                        isPlaying: $isPlaying,
                        currentTime: currentTime,
                        systemDark: isDark
                    )
                    Spacer(minLength: 8)
                        .allowsHitTesting(false)
                    if let lines = stats?.previewLines, !lines.isEmpty {
                        VStack(alignment: .trailing, spacing: 2) {
                            ForEach(lines, id: \.self) { line in
                                Text(line)
                                    .font(.system(size: 11, weight: .regular).monospacedDigit())
                                    .foregroundStyle(
                                        GLBPreviewBackdrop.iconColor(
                                            at: backdropIndex,
                                            systemDark: isDark,
                                            active: true
                                        ).opacity(0.55)
                                    )
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: chromeVisible)
        .onAppear {
            if reduceMotion {
                autoRotate = false
            }
        }
        .onChange(of: isPlaying) { _, playing in
            guard let playback else { return }
            if playing {
                playback.resume()
            } else {
                playback.pause()
            }
        }
        .task(id: tickWhileActive) {
            guard tickWhileActive else { return }
            var lastTick = Date()
            while !Task.isCancelled {
                let now = Date()
                let dt = now.timeIntervalSince(lastTick)
                lastTick = now
                if autoRotate, dragOrigin == nil {
                    orbitYaw += Float(dt) * 20 * .pi / 180
                }
                if chromeVisible, isPlaying, let playback, clipDuration > 0 {
                    currentTime = playback.time.truncatingRemainder(dividingBy: clipDuration)
                    if currentTime < 0 { currentTime += clipDuration }
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private var orbitDragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let origin = dragOrigin ?? (orbitYaw, orbitPitch)
                dragOrigin = origin
                orbitYaw = origin.yaw + Float(value.translation.width) * 0.008
                orbitPitch = origin.pitch + Float(value.translation.height) * 0.008
            }
            .onEnded { _ in
                dragOrigin = nil
            }
    }

    private func applyViewport(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        if abs(size.width - viewport.width) > 0.5 || abs(size.height - viewport.height) > 0.5 {
            viewport = size
        }
    }

    private func aspect(of size: CGSize) -> Float {
        Float(size.width / max(size.height, 1))
    }
}

private struct GLBPreviewToolbar: View {
    @Binding var backdropIndex: Int
    @Binding var autoRotate: Bool
    var showPlayback: Bool
    @Binding var isPlaying: Bool
    var currentTime: TimeInterval
    var systemDark: Bool

    private func tint(active: Bool) -> Color {
        GLBPreviewBackdrop.iconColor(at: backdropIndex, systemDark: systemDark, active: active)
    }

    var body: some View {
        HStack(spacing: 12) {
            iconButton("circle.lefthalf.filled", active: true, help: "Toggle background") {
                backdropIndex = (backdropIndex + 1) % GLBPreviewBackdrop.all.count
            }
            iconButton(
                "arrow.trianglehead.2.clockwise.rotate.90",
                active: autoRotate,
                help: "Auto-rotate"
            ) {
                autoRotate.toggle()
            }
            if showPlayback {
                iconButton(
                    isPlaying ? "pause.fill" : "play.fill",
                    active: isPlaying,
                    help: "Play/Pause"
                ) {
                    isPlaying.toggle()
                }
                Text(String(format: "%.2f", currentTime))
                    .font(.system(size: 11, weight: .regular).monospacedDigit())
                    .foregroundStyle(tint(active: isPlaying))
                    .frame(minWidth: 36, alignment: .leading)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    private func iconButton(
        _ systemName: String,
        active: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint(active: active))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
