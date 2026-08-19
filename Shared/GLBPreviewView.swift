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
        case ready(GLBEntityLoader.LoadedModel)
        case failed

        /// File IO runs off the main actor (`GLBEntityLoader.load`).
        static func loaded(from url: URL) async -> State {
            async let ibl: Void = GLBPreviewLighting.prefetchStudioIBL()
            do {
                let model = try await GLBEntityLoader.load(from: url)
                await ibl
                return .ready(model)
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
                ZStack {
                    GLBPreviewBackdrop.color(at: 0).ignoresSafeArea()
                    ProgressView()
                        .controlSize(.regular)
                        .progressViewStyle(.circular)
                }
            case .ready(let model):
                GLBPreviewScene(model: model, interaction: interaction, isDark: isDark)
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

private enum PreviewCameraSelection: Equatable {
    case fit
    case file(Int)
}

/// Reference box so RealityView `make` can stash unscaled bounds while zoom scales the pivot.
private final class PreviewFrame {
    var bounds = BoundingBox()
    var cameraAspect: Float = -1
    var appliedCamera: PreviewCameraSelection?
}

private struct ChromeFrameKey: PreferenceKey {
    static var defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct GLBPreviewScene: View {
    let model: GLBEntityLoader.LoadedModel
    @Bindable var interaction: GLBPreviewInteraction
    var isDark: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var backdropIndex = 0
    @State private var autoRotate: Bool
    @State private var orbitYaw: Float = 0
    @State private var orbitPitch: Float = 0
    @State private var dragOrigin: (yaw: Float, pitch: Float)?
    @State private var playback: AnimationPlaybackController?
    @State private var selectedClipIndex = 0
    @State private var clipDuration: TimeInterval = 0
    @State private var currentTime: TimeInterval = 0
    @State private var isPlaying = true
    @State private var isSeeking = false
    @State private var wasPlayingBeforeSeek = false
    @State private var selectedCamera: PreviewCameraSelection = .fit
    @State private var viewport = CGSize(width: 810, height: 600)
    @State private var chromeVisible = true
    @State private var chromeFrame = CGRect.zero
    private let frame = PreviewFrame()

    init(model: GLBEntityLoader.LoadedModel, interaction: GLBPreviewInteraction, isDark: Bool) {
        self.model = model
        self.interaction = interaction
        self.isDark = isDark
        let bounds = GLBPreviewCamera.modelBounds(of: model.entity)
        let extent = bounds.max - bounds.min
        if let axis = GLBPreviewCamera.thinAxis(extent), axis == 0 || axis == 2 {
            _autoRotate = State(initialValue: false)
            GLBLog.info(GLBLog.preview, "autoRotate disabled for standing plane thinAxis=\(axis)")
        } else {
            _autoRotate = State(initialValue: true)
        }
    }

    private var entity: Entity { model.entity }
    private var fileCameras: [GLBPreviewScenery.FileCamera] { model.fileCameras }
    private var usableAnimations: [AnimationResource] { model.usableAnimations }
    private var isFitCamera: Bool {
        if case .fit = selectedCamera { return true }
        return false
    }

    private var tickWhileActive: Bool {
        (autoRotate && isFitCamera) || (chromeVisible && isPlaying && playback != nil && !isSeeking)
    }

    var body: some View {
        ZStack {
            RealityView { content in
                content.camera = .virtual
                let assembled = GLBPreviewCamera.makeTurntable(for: entity)
                frame.bounds = assembled.bounds

                content.add(assembled.pivot)
                if let ibl = GLBPreviewLighting.makeStudioIBLEntity(
                    receiver: assembled.pivot,
                    intensityExponent: model.studioIBLExponent
                ) {
                    content.add(ibl)
                }
                content.add(
                    GLBPreviewCamera.makeFrontThreeQuarter(
                        minBound: assembled.bounds.min,
                        maxBound: assembled.bounds.max,
                        padding: GLBPreviewCamera.previewFitPadding,
                        aspect: aspect(of: viewport)
                    )
                )

                if let animation = usableAnimations.first {
                    selectedClipIndex = 0
                    clipDuration = animation.definition.duration
                    playback = entity.playAnimation(animation.repeat())
                    currentTime = 0
                }
            } update: { content in
                guard let turntable = content.entities.first(where: { $0.name == "turntable" }),
                      let previewCamera = content.entities.first(where: { $0.name == "previewCamera" })
                else { return }

                if isFitCamera {
                    turntable.orientation =
                        simd_quatf(angle: orbitYaw, axis: [0, 1, 0]) *
                        simd_quatf(angle: orbitPitch, axis: [1, 0, 0])
                    turntable.scale = SIMD3<Float>(repeating: interaction.zoom)
                } else {
                    turntable.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
                    turntable.scale = .one
                }

                if frame.appliedCamera != selectedCamera {
                    frame.appliedCamera = selectedCamera
                    switch selectedCamera {
                    case .fit:
                        GLBPreviewCamera.activateCamera(
                            previewCamera,
                            disablingOthersIn: [turntable, previewCamera]
                        )
                    case .file(let index):
                        if fileCameras.indices.contains(index) {
                            GLBPreviewCamera.activateCamera(
                                fileCameras[index].entity,
                                disablingOthersIn: [turntable, previewCamera]
                            )
                        }
                    }
                }

                let viewAspect = aspect(of: viewport)
                guard abs(viewAspect - frame.cameraAspect) > 0.001 else { return }
                frame.cameraAspect = viewAspect
                let position = GLBPreviewCamera.cameraPosition(
                    minBound: frame.bounds.min,
                    maxBound: frame.bounds.max,
                    padding: GLBPreviewCamera.previewFitPadding,
                    aspect: viewAspect
                )
                previewCamera.look(at: frame.bounds.center, from: position, relativeTo: nil)
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
            // Bottom chrome is excluded so the clip slider cannot start an orbit.
            Color.clear
                .contentShape(Rectangle())
                .padding(.bottom, chromeVisible ? max(chromeFrame.height, 36) + 14 : 0)
                .gesture(orbitDragGesture)
                .onTapGesture {
                    chromeVisible.toggle()
                }

            if chromeVisible {
                HStack(alignment: .bottom, spacing: 12) {
                    GLBPreviewToolbar(
                        backdropIndex: $backdropIndex,
                        autoRotate: $autoRotate,
                        selectedCamera: $selectedCamera,
                        fileCameras: fileCameras,
                        usableAnimations: usableAnimations,
                        selectedClipIndex: selectedClipIndex,
                        showPlayback: !usableAnimations.isEmpty,
                        isPlaying: $isPlaying,
                        currentTime: seekBinding,
                        clipDuration: clipDuration,
                        onSeekingChanged: handleSeekingChanged,
                        onSelectClip: playClip,
                        systemDark: isDark
                    )
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ChromeFrameKey.self,
                                value: proxy.frame(in: .named("preview"))
                            )
                        }
                    }
                    Spacer(minLength: 8)
                        .allowsHitTesting(false)
                    GLBPreviewStatsTable(
                        rows: model.stats.previewRows,
                        backdropIndex: backdropIndex,
                        systemDark: isDark
                    )
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.opacity)
            }
        }
        .coordinateSpace(name: "preview")
        .onPreferenceChange(ChromeFrameKey.self) { chromeFrame = $0 }
        .animation(.easeInOut(duration: 0.15), value: chromeVisible)
        .onAppear {
            if reduceMotion {
                autoRotate = false
            }
        }
        .onChange(of: selectedCamera) { _, camera in
            if case .file = camera {
                autoRotate = false
            }
        }
        .onChange(of: isPlaying) { _, playing in
            guard let playback, !isSeeking else { return }
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
                if autoRotate, isFitCamera, dragOrigin == nil {
                    orbitYaw += Float(dt) * 20 * .pi / 180
                }
                if chromeVisible, isPlaying, !isSeeking, let playback, clipDuration > 0 {
                    currentTime = playback.time.truncatingRemainder(dividingBy: clipDuration)
                    if currentTime < 0 { currentTime += clipDuration }
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private var seekBinding: Binding<TimeInterval> {
        Binding(
            get: { currentTime },
            set: { value in
                currentTime = value
                playback?.time = value
            }
        )
    }

    private var orbitDragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard isFitCamera else { return }
                if chromeVisible, chromeFrame.insetBy(dx: -8, dy: -8).contains(value.startLocation) {
                    return
                }
                let origin = dragOrigin ?? (orbitYaw, orbitPitch)
                dragOrigin = origin
                orbitYaw = origin.yaw + Float(value.translation.width) * 0.008
                orbitPitch = origin.pitch + Float(value.translation.height) * 0.008
            }
            .onEnded { _ in
                dragOrigin = nil
            }
    }

    private func handleSeekingChanged(_ editing: Bool) {
        if editing {
            wasPlayingBeforeSeek = isPlaying
            isSeeking = true
            playback?.pause()
        } else {
            isSeeking = false
            if wasPlayingBeforeSeek {
                playback?.resume()
                isPlaying = true
            }
        }
    }

    private func playClip(_ index: Int) {
        guard usableAnimations.indices.contains(index) else { return }
        playback?.stop()
        selectedClipIndex = index
        let animation = usableAnimations[index]
        let duration = animation.definition.duration
        clipDuration = duration.isFinite && duration > 0 ? duration : 0
        currentTime = 0
        guard clipDuration > 0 else {
            playback = nil
            return
        }
        let controller = entity.playAnimation(animation.repeat())
        playback = controller
        isPlaying = true
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

private struct GLBPreviewStatsTable: View {
    var rows: [GLBPreviewStats.Row]
    var backdropIndex: Int
    var systemDark: Bool

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(rows, id: \.label) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.label)
                            .foregroundStyle(tint.opacity(0.42))
                        Spacer(minLength: 16)
                        Text(row.value)
                            .font(.system(size: 11, weight: .regular).monospacedDigit())
                            .foregroundStyle(tint.opacity(0.62))
                    }
                }
            }
            .font(.system(size: 11, weight: .regular))
            .frame(minWidth: 188, maxWidth: 230)
            .allowsHitTesting(false)
        }
    }

    private var tint: Color {
        GLBPreviewBackdrop.iconColor(at: backdropIndex, systemDark: systemDark, active: true)
    }
}

private struct GLBPreviewToolbar: View {
    @Binding var backdropIndex: Int
    @Binding var autoRotate: Bool
    @Binding var selectedCamera: PreviewCameraSelection
    var fileCameras: [GLBPreviewScenery.FileCamera]
    var usableAnimations: [AnimationResource]
    var selectedClipIndex: Int
    var showPlayback: Bool
    @Binding var isPlaying: Bool
    @Binding var currentTime: TimeInterval
    var clipDuration: TimeInterval
    var onSeekingChanged: (Bool) -> Void
    var onSelectClip: (Int) -> Void
    var systemDark: Bool

    private func tint(active: Bool) -> Color {
        GLBPreviewBackdrop.iconColor(at: backdropIndex, systemDark: systemDark, active: active)
    }

    var body: some View {
        glassWrapped {
            HStack(spacing: 10) {
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
                if !fileCameras.isEmpty {
                    cameraMenu
                }
                if usableAnimations.count > 1 {
                    clipMenu
                }
                if showPlayback {
                    iconButton(
                        isPlaying ? "pause.fill" : "play.fill",
                        active: isPlaying,
                        help: "Play/Pause"
                    ) {
                        isPlaying.toggle()
                    }
                    Slider(
                        value: $currentTime,
                        in: 0...max(clipDuration, 0.001)
                    ) { editing in
                        onSeekingChanged(editing)
                    }
                    .controlSize(.small)
                    .frame(width: 72)
                    Text(timeLabel)
                        .font(.system(size: 11, weight: .regular).monospacedDigit())
                        .foregroundStyle(tint(active: isPlaying))
                        .lineLimit(1)
                }
            }
        }
    }

    private var timeLabel: String {
        let duration = max(clipDuration, 0)
        let shown = duration > 0 ? currentTime.truncatingRemainder(dividingBy: duration) : currentTime
        let wrapped = shown < 0 ? shown + duration : shown
        return String(format: "%.2f / %.2f", wrapped, duration)
    }

    private var cameraMenu: some View {
        Menu {
            Button("Fit") { selectedCamera = .fit }
            ForEach(Array(fileCameras.enumerated()), id: \.offset) { index, camera in
                Button(camera.displayName) { selectedCamera = .file(index) }
            }
        } label: {
            Image(systemName: "video")
                .font(.system(size: 14, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint(active: !isFitSelected))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Camera")
        .modifier(GlassButtonStyleModifier())
    }

    private var clipMenu: some View {
        Menu {
            ForEach(Array(usableAnimations.enumerated()), id: \.offset) { index, animation in
                Button(clipTitle(animation, index: index)) {
                    onSelectClip(index)
                }
            }
        } label: {
            Image(systemName: "film")
                .font(.system(size: 14, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint(active: true))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Clip")
        .modifier(GlassButtonStyleModifier())
    }

    private var isFitSelected: Bool {
        if case .fit = selectedCamera { return true }
        return false
    }

    private func clipTitle(_ animation: AnimationResource, index: Int) -> String {
        let trimmed = (animation.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Clip \(index + 1)" : trimmed
    }

    @ViewBuilder
    private func glassWrapped<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(macOS 26, *) {
            GlassEffectContainer {
                content()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content()
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
        }
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
        .modifier(GlassButtonStyleModifier())
        .help(help)
    }
}

private struct GlassButtonStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.plain)
        }
    }
}
