import RealityKit
import SwiftUI


/// Reference box so RealityView `make` can stash unscaled bounds while zoom scales the pivot.
private final class PreviewFrame {
    var bounds = BoundingBox()
}

struct PreviewScene: View {
    let entity: Entity
    var stats: PreviewStats?
    @Bindable var interaction: PreviewInteraction
    var isDark: Bool
    var sidebar: (any PreviewOverlay)?

    @AppStorage(SettingsKeys.autoRotate) private var settingsAutoRotate = true
    @AppStorage(SettingsKeys.playOnOpen) private var playOnOpen = true
    @AppStorage(SettingsKeys.showStats) private var showStats = true
    @AppStorage(SettingsKeys.showToolbar) private var showToolbar = true
    @AppStorage(SettingsKeys.background) private var backgroundRaw = PreviewBackground.window.rawValue

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var backdropIndex: Int
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

    init(
        entity: Entity,
        stats: PreviewStats?,
        interaction: PreviewInteraction,
        isDark: Bool,
        sidebar: (any PreviewOverlay)? = nil
    ) {
        self.entity = entity
        self.stats = stats
        self.interaction = interaction
        self.isDark = isDark
        self.sidebar = sidebar
        let bounds = PreviewCamera.modelBounds(of: entity, relativeTo: entity)
        let extent = bounds.max - bounds.min
        let settingsOn = UserDefaults.standard.object(forKey: SettingsKeys.autoRotate) as? Bool ?? true
        if PreviewCamera.disablesAutoRotate(extent) {
            _autoRotate = State(initialValue: false)
            AppLog.info(AppLog.preview, "autoRotate disabled for standing plane")
        } else {
            _autoRotate = State(initialValue: settingsOn)
        }
        let storedBackground = UserDefaults.standard.string(forKey: SettingsKeys.background)
            ?? PreviewBackground.window.rawValue
        if let background = PreviewBackground(rawValue: storedBackground),
           let index = PreviewBackground.allCases.firstIndex(of: background) {
            _backdropIndex = State(initialValue: index)
        } else {
            _backdropIndex = State(initialValue: 0)
        }
    }

    private var isHost: Bool { sidebar != nil }

    private var backdropColor: Color {
        if isHost {
            return PreviewBackground(rawValue: backgroundRaw)?.color ?? PreviewBackground.window.color
        }
        return PreviewBackground.color(at: backdropIndex)
    }

    private var tickWhileActive: Bool {
        return autoRotate || (!isHost && chromeVisible && isPlaying && playback != nil)
    }

    var body: some View {
        let _ = sidebar?.overlayRevision
        ZStack {
            RealityView { content in
                content.camera = .virtual
                let assembled = PreviewCamera.makeTurntable(for: entity)
                frame.bounds = assembled.bounds

                content.add(assembled.pivot)
                content.add(
                    PreviewCamera.makeFrontThreeQuarter(
                        minBound: assembled.bounds.min,
                        maxBound: assembled.bounds.max,
                        padding: PreviewCamera.previewFitPadding,
                        aspect: aspect(of: viewport)
                    )
                )
                let exponent = PreviewEmissive.studioIBLExponent(
                    punctualLightCount: EntityLoader.punctualLightCount(in: entity)
                )
                PreviewLighting.applyLook(
                    to: &content,
                    pivot: assembled.pivot,
                    look: AppLook.current,
                    intensityExponent: exponent
                )
                sidebar?.applyIfNeeded(to: assembled.pivot)

                if playOnOpen, let animation = entity.availableAnimations.first,
                   let duration = EntityLoader.clipDuration(animation, on: entity)
                {
                    clipDuration = duration
                    playback = entity.playAnimation(animation.repeat())
                }
            } update: { content in
                for entity in content.entities where entity.name == "turntable" {
                    entity.orientation =
                        simd_quatf(angle: orbitYaw, axis: [0, 1, 0]) *
                        simd_quatf(angle: orbitPitch, axis: [1, 0, 0])
                    entity.scale = SIMD3<Float>(repeating: interaction.zoom)
                    sidebar?.applyIfNeeded(to: entity)
                }
                let viewAspect = aspect(of: viewport)
                if sidebar?.selectedCameraIndex != nil {
                    applyFileCamera(content)
                } else {
                    for entity in content.entities where entity.name == "previewCamera" {
                        PreviewCamera.restoreFitPerspective(on: entity)
                        let position = PreviewCamera.cameraPosition(
                            minBound: frame.bounds.min,
                            maxBound: frame.bounds.max,
                            padding: PreviewCamera.previewFitPadding,
                            aspect: viewAspect
                        )
                        entity.look(at: frame.bounds.center, from: position, relativeTo: nil)
                        if var camera = entity.components[PerspectiveCameraComponent.self] {
                            PreviewCamera.applyFitClip(
                                to: &camera,
                                eye: position,
                                target: frame.bounds.center
                            )
                            entity.components.set(camera)
                        }
                    }
                }
            }
            .backgroundStyle(backdropColor)
            .background {
                GeometryReader { proxy in
                    backdropColor
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
                    guard !isHost else { return }
                    chromeVisible.toggle()
                }

            if !isHost, chromeVisible, showToolbar {
                HStack(alignment: .bottom, spacing: 12) {
                    PreviewToolbar(
                        backdropIndex: $backdropIndex,
                        autoRotate: $autoRotate,
                        showPlayback: playback != nil,
                        isPlaying: $isPlaying,
                        currentTime: currentTime,
                        systemDark: isDark
                    )
                    Spacer(minLength: 8)
                        .allowsHitTesting(false)
                    if showStats, let lines = stats?.previewLines, !lines.isEmpty {
                        VStack(alignment: .trailing, spacing: 2) {
                            ForEach(lines, id: \.self) { line in
                                Text(line)
                                    .font(.system(size: 11, weight: .regular).monospacedDigit())
                                    .foregroundStyle(
                                        PreviewBackground.iconColor(
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
            applyAutoRotateSetting()
        }
        .onChange(of: settingsAutoRotate) { _, _ in
            applyAutoRotateSetting()
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

    private func applyFileCamera(_ content: RealityViewCameraContent) {
        guard let sidebar, let index = sidebar.selectedCameraIndex,
              sidebar.document.cameras.indices.contains(index)
        else { return }
        let node = sidebar.document.nodes.first(where: { $0.cameraIndex == index })
        guard let node,
              let cameraNode = findEntity(nodeIndex: node.index, in: entity),
              let preview = content.entities.first(where: { $0.name == "previewCamera" })
        else { return }
        PreviewCamera.applyFileView(
            to: preview,
            cameraNode: cameraNode,
            spec: sidebar.document.cameras[index]
        )
    }

    private func findEntity(nodeIndex: Int, in root: Entity) -> Entity? {
        if root.components[GLTFNodeIDComponent.self]?.nodeIndex == nodeIndex {
            return root
        }
        for child in root.children {
            if let found = findEntity(nodeIndex: nodeIndex, in: child) {
                return found
            }
        }
        return nil
    }

    private func applyAutoRotateSetting() {
        let bounds = PreviewCamera.modelBounds(of: entity, relativeTo: entity)
        let extent = bounds.max - bounds.min
        if PreviewCamera.disablesAutoRotate(extent) {
            autoRotate = false
            return
        }
        autoRotate = settingsAutoRotate && !reduceMotion
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

struct PreviewToolbar: View {
    @Binding var backdropIndex: Int
    @Binding var autoRotate: Bool
    var showPlayback: Bool
    @Binding var isPlaying: Bool
    var currentTime: TimeInterval
    var systemDark: Bool

    private func tint(active: Bool) -> Color {
        PreviewBackground.iconColor(at: backdropIndex, systemDark: systemDark, active: active)
    }

    var body: some View {
        HStack(spacing: 12) {
            iconButton("circle.lefthalf.filled", active: true, help: "Toggle background") {
                backdropIndex = (backdropIndex + 1) % PreviewBackground.allCases.count
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
