import AppKit
import RealityKit
import SwiftUI


/// Reference box so RealityView `make` can stash unscaled bounds while zoom scales the pivot.
private final class PreviewFrame {
    var bounds = BoundingBox()
}

struct PreviewScene: View {
    let entity: Entity
    var stats: PreviewStats?
    var debugModes: [PreviewDebugMode]
    var studioIBLExponent: Float
    @Bindable var interaction: PreviewInteraction
    var isDark: Bool
    var sidebar: (any PreviewOverlay)?

    @AppStorage(SettingsKeys.autoRotate) private var settingsAutoRotate = true
    @AppStorage(SettingsKeys.showToolbar) private var showToolbar = true
    @AppStorage(SettingsKeys.background) private var backgroundRaw = PreviewBackground.window.rawValue

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var backdropIndex: Int
    @State private var autoRotate: Bool
    @State private var orbitYaw: Float = 0
    @State private var orbitPitch: Float = 0
    @State private var dragOrigin: (yaw: Float, pitch: Float)?
    @State private var playback: AnimationPlaybackController?
    @State private var clips: [PreviewClip] = []
    @State private var clipIndex = 0
    @State private var clipDuration: TimeInterval = 0
    @State private var currentTime: TimeInterval = 0
    @State private var isPlaying = false
    @State private var isSeeking = false
    @State private var viewport = CGSize(width: 810, height: 600)
    @State private var chromeVisible = true
    @State private var debugModeIndex = 0
    @State private var pendingReady: AppLook?
    @State private var appliedLook: AppLook?
    @State private var prefetchGeneration = 0
    private let lookStore = AppLookStore.shared
    private let frame = PreviewFrame()
    private let debugStore = DebugMaterialStore()
    private let debugApplied = DebugAppliedIndex()

    init(
        entity: Entity,
        stats: PreviewStats?,
        debugModes: [PreviewDebugMode] = [.none],
        studioIBLExponent: Float = 0,
        interaction: PreviewInteraction,
        isDark: Bool,
        sidebar: (any PreviewOverlay)? = nil
    ) {
        self.entity = entity
        self.stats = stats
        self.debugModes = debugModes.isEmpty ? [.none] : debugModes
        self.studioIBLExponent = studioIBLExponent
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
        autoRotate || (isPlaying && playback != nil && (isHost || chromeVisible))
    }

    var body: some View {
        let _ = sidebar?.overlayRevision
        let _ = lookStore.look
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
                PreviewLighting.applyLook(
                    to: &content,
                    pivot: assembled.pivot,
                    look: lookStore.look,
                    intensityExponent: studioIBLExponent
                )
                appliedLook = lookStore.look
                sidebar?.applyIfNeeded(to: assembled.pivot)

                let usable = Self.usableClips(on: entity)
                clips = usable
                if !usable.isEmpty {
                    clipIndex = 0
                    isPlaying = false
                    startClip(at: 0, playing: false)
                }
            } update: { content in
                if let pending = pendingReady, pending != appliedLook,
                   let pivot = content.entities.first(where: { $0.name == "turntable" })
                {
                    PreviewLighting.applyLook(
                        to: &content,
                        pivot: pivot,
                        look: pending,
                        intensityExponent: studioIBLExponent
                    )
                    appliedLook = pending
                }
                for entity in content.entities where entity.name == "turntable" {
                    entity.orientation =
                        simd_quatf(angle: orbitYaw, axis: [0, 1, 0]) *
                        simd_quatf(angle: orbitPitch, axis: [1, 0, 0])
                    entity.scale = SIMD3<Float>(repeating: interaction.zoom)
                    sidebar?.applyIfNeeded(to: entity)
                    applyDebugIfNeeded(to: entity)
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
            } placeholder: {
                // RealityView's default ProgressView is unframed and sits at the
                // AppKit origin — a sliver in the window's bottom-left corner.
                Color.clear
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

            if showToolbar, isHost || chromeVisible {
                VStack(alignment: .trailing, spacing: 10) {
                    PreviewCycleMenu(
                        options: PreviewBackground.allCases.map(\.shortTitle),
                        index: $backdropIndex,
                        tint: { active in
                            PreviewBackground.iconColor(
                                at: backdropIndex,
                                systemDark: isDark,
                                active: active
                            )
                        }
                    ) {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 14, weight: .regular))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(chromeTint(active: backdropIndex != 0))
                    }
                    PreviewCycleMenu(
                        options: debugModes.map(\.shortTitle),
                        index: $debugModeIndex,
                        tint: { active in
                            chromeTint(active: active)
                        }
                    ) {
                        Image(systemName: "square.3.layers.3d", variableValue: 1)
                            .font(.system(size: 14, weight: .regular))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(chromeTint(active: debugModeIndex != 0), .yellow)
                    }
                    Button {
                        autoRotate.toggle()
                        if isHost {
                            settingsAutoRotate = autoRotate
                        }
                    } label: {
                        Image(systemName: "arrow.trianglehead.counterclockwise.rotate.90")
                            .font(.system(size: 14, weight: .regular))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(chromeTint(active: autoRotate))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Auto-rotate")
                }
                .padding(.top, isHost ? 12 : 14)
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .transition(.opacity)
            }

            if !isHost, chromeVisible, let facts = stats?.overlayFacts, !facts.isEmpty {
                PreviewOverlayFacts(facts: facts, tint: chromeTint(active: true))
                    .allowsHitTesting(false)
                    .padding(.leading, 14)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .transition(.opacity)
            }

            if showToolbar, !clips.isEmpty, clipDuration > 0, isHost || chromeVisible {
                PreviewPlaybackBar(
                    isPlaying: $isPlaying,
                    isSeeking: $isSeeking,
                    currentTime: $currentTime,
                    clipIndex: $clipIndex,
                    clipTitles: clips.map(\.title),
                    clipDuration: clipDuration,
                    tint: chromeTint(active: true),
                    onSeek: seek(to:)
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .frame(maxWidth: clips.count > 1 ? 520 : 420)
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
        .onChange(of: backdropIndex) { _, index in
            guard isHost else { return }
            let backgrounds = PreviewBackground.allCases
            backgroundRaw = backgrounds[index % backgrounds.count].rawValue
        }
        .onChange(of: backgroundRaw) { _, raw in
            guard isHost,
                  let background = PreviewBackground(rawValue: raw),
                  let index = PreviewBackground.allCases.firstIndex(of: background)
            else { return }
            backdropIndex = index
        }
        .onChange(of: isPlaying) { _, playing in
            guard let playback else { return }
            if playing {
                playback.resume()
            } else {
                playback.pause()
            }
        }
        .onChange(of: isSeeking) { _, seeking in
            guard let playback else { return }
            if seeking {
                playback.pause()
            } else if isPlaying {
                playback.resume()
            }
        }
        .onChange(of: clipIndex) { _, index in
            startClip(at: index, playing: isPlaying)
        }
        .onChange(of: lookStore.look) { _, look in
            prefetchLook(look)
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
                if !isSeeking, isPlaying, let playback, clipDuration > 0 {
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

    private func prefetchLook(_ look: AppLook) {
        guard look.useEnvironmentMap else {
            pendingReady = look
            return
        }
        prefetchGeneration += 1
        let generation = prefetchGeneration
        Task {
            await PreviewLighting.prefetchLook(look)
            guard generation == prefetchGeneration else { return }
            pendingReady = look
        }
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

    private func chromeTint(active: Bool) -> Color {
        PreviewBackground.iconColor(at: backdropIndex, systemDark: isDark, active: active)
    }

    private func seek(to time: TimeInterval) {
        let duration = max(clipDuration, 0.001)
        let clamped = min(max(time, 0), duration)
        currentTime = clamped
        playback?.time = clamped
    }

    private func startClip(at index: Int, playing: Bool) {
        guard clips.indices.contains(index) else { return }
        let clip = clips[index]
        playback?.stop()
        clipDuration = clip.duration
        currentTime = 0
        playback = entity.playAnimation(clip.resource.repeat())
        if playing {
            playback?.resume()
        } else {
            playback?.pause()
        }
    }

    private static func usableClips(on entity: Entity) -> [PreviewClip] {
        var result: [PreviewClip] = []
        for (offset, resource) in entity.availableAnimations.enumerated() {
            guard let duration = EntityLoader.clipDuration(resource, on: entity) else { continue }
            let name = resource.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = name.isEmpty ? "Clip \(result.count + 1)" : name
            result.append(PreviewClip(id: offset, resource: resource, title: title, duration: duration))
        }
        return result
    }

    private func applyDebugIfNeeded(to root: Entity) {
        let index = debugModes.indices.contains(debugModeIndex) ? debugModeIndex : 0
        guard debugApplied.index != index else { return }
        PreviewDebugMode.apply(debugModes[index], to: root, store: debugStore)
        debugApplied.index = index
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

private final class DebugAppliedIndex {
    var index: Int?
}

private struct PreviewClip {
    let id: Int
    let resource: AnimationResource
    let title: String
    let duration: TimeInterval
}

private struct PreviewPlaybackBar: View {
    @Binding var isPlaying: Bool
    @Binding var isSeeking: Bool
    @Binding var currentTime: TimeInterval
    @Binding var clipIndex: Int
    var clipTitles: [String]
    var clipDuration: TimeInterval
    var tint: Color
    var onSeek: (TimeInterval) -> Void

    var body: some View {
        HStack(spacing: 10) {
            if clipTitles.count > 1 {
                ClipMenu(
                    titles: clipTitles,
                    selection: $clipIndex,
                    tint: tint
                )
                .help("Animation clip")
            }

            Button {
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Pause" : "Play")

            Slider(
                value: Binding(
                    get: { currentTime },
                    set: { onSeek($0) }
                ),
                in: 0...max(clipDuration, 0.001)
            ) { editing in
                isSeeking = editing
            }
            .controlSize(.small)
            .tint(tint)

            Text(String(format: "%.2f", currentTime))
                .font(.system(size: 11, weight: .regular).monospacedDigit())
                .foregroundStyle(tint)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .previewLiquidGlass(in: Capsule(style: .continuous))
    }
}

private struct ClipMenu: NSViewRepresentable {
    var titles: [String]
    @Binding var selection: Int
    var tint: Color

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        button.isBordered = false
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        context.coordinator.button = button
        rebuild(button)
        applyTint(button)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        if button.itemTitles != titles {
            rebuild(button)
        }
        if button.indexOfSelectedItem != selection,
           titles.indices.contains(selection)
        {
            button.selectItem(at: selection)
        }
        applyTint(button)
        button.sizeToFit()
        button.invalidateIntrinsicContentSize()
    }

    private func rebuild(_ button: NSPopUpButton) {
        button.removeAllItems()
        button.addItems(withTitles: titles)
        if titles.indices.contains(selection) {
            button.selectItem(at: selection)
        }
    }

    private func applyTint(_ button: NSPopUpButton) {
        button.contentTintColor = NSColor(tint)
    }

    final class Coordinator: NSObject {
        var selection: Binding<Int>
        weak var button: NSPopUpButton?

        init(selection: Binding<Int>) {
            self.selection = selection
        }

        @objc func changed(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard index >= 0, index != selection.wrappedValue else { return }
            selection.wrappedValue = index
        }
    }
}

private extension View {
    @ViewBuilder
    func previewLiquidGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}
