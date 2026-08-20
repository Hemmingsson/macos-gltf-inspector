import RealityKit
import SwiftUI


/// Persisted across SwiftUI `PreviewScene` re-inits (must be `@State`, not `let`).
/// RealityView `make` runs once; update must keep using the same entity refs.
private final class PreviewFrame {
    var bounds = BoundingBox()
    var autoRotateYaw: Float = 0
    /// Set when the real pane size is known so `update` can refit once.
    var needsLayoutFit = false
    var didLayoutFit = false
    weak var pivot: Entity?
    weak var spin: Entity?
    weak var floor: Entity?
    weak var camera: Entity?
    weak var lookRoot: Entity?
    let debugStore = DebugMaterialStore()
    let debugApplied = DebugAppliedIndex()
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
    @AppStorage(SettingsKeys.showFloor) private var settingsShowFloor = true
    @AppStorage(SettingsKeys.background) private var backgroundRaw = PreviewBackground.window.rawValue

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var backdropIndex: Int
    @State private var autoRotate: Bool
    @State private var showFloor: Bool
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
    @State private var appliedFloorLineIndex = -1
    @State private var prefetchGeneration = 0
    /// Must be `@State` — parent `updateNSView` recreates the view struct.
    @State private var frame = PreviewFrame()
    private let lookStore = AppLookStore.shared

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
        _autoRotate = State(
            initialValue: PreviewCamera.disablesAutoRotate(extent) ? false : settingsOn
        )
        let floorOn = UserDefaults.standard.object(forKey: SettingsKeys.showFloor) as? Bool ?? true
        _showFloor = State(initialValue: floorOn)
        _backdropIndex = State(initialValue: PreviewBackground.storedIndex)
    }

    private var isHost: Bool { sidebar != nil }

    private var useSystemOrbit: Bool {
        sidebar?.selectedCameraIndex == nil
    }

    private var backdropColor: Color {
        PreviewBackground.at(backdropIndex).color
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
                frame.pivot = assembled.pivot
                frame.spin = assembled.spin
                let floor = PreviewFloor.make(
                    bounds: assembled.bounds,
                    lineColor: PreviewBackground.at(backdropIndex).gridLineNSColor(systemDark: isDark)
                )
                frame.floor = floor
                assembled.pivot.addChild(floor)
                PreviewFloor.enableCastingShadows(on: entity)

                let camera = PreviewCamera.makeFrontThreeQuarter(
                    minBound: assembled.bounds.min,
                    maxBound: assembled.bounds.max,
                    padding: PreviewCamera.previewFitPadding,
                    aspect: aspect(of: viewport)
                )
                frame.camera = camera
                // Pivot carries the model (real bounds) — system `.orbit` frames from it.
                // A separate empty focus entity was nose-diving the camera on open.
                content.cameraTarget = assembled.pivot

                let lookRoot = Entity()
                lookRoot.name = PreviewLighting.lookRootName
                frame.lookRoot = lookRoot

                content.add(assembled.pivot)
                content.add(camera)
                content.add(lookRoot)
                PreviewLighting.applyLook(
                    lookRoot: lookRoot,
                    pivot: assembled.pivot,
                    look: lookStore.look,
                    intensityExponent: studioIBLExponent
                )
                sidebar?.applyIfNeeded(to: assembled.pivot)
                frame.needsLayoutFit = true
                let usable = Self.usableClips(on: entity)
                let look = lookStore.look
                Task { @MainActor in
                    interaction.bind(camera: camera, orbitFocus: assembled.pivot)
                    appliedLook = look
                    clips = usable
                    if !usable.isEmpty {
                        clipIndex = 0
                        isPlaying = false
                        startClip(at: 0, playing: false)
                    }
                }
            } update: { content in
                if content.cameraTarget == nil, let pivot = frame.pivot {
                    content.cameraTarget = pivot
                }
                if frame.needsLayoutFit, let camera = frame.camera, let pivot = frame.pivot {
                    // Undo any Shift-pan offset so Fit framing is around the model center.
                    pivot.setPosition(.zero, relativeTo: nil)
                    PreviewCamera.applyFit(
                        to: camera,
                        bounds: frame.bounds,
                        aspect: aspect(of: viewport),
                        orbitFocus: pivot
                    )
                    frame.needsLayoutFit = false
                    frame.didLayoutFit = true
                    Task { @MainActor in interaction.markFitted() }
                }
                var lookToMarkApplied: AppLook?
                if let pending = pendingReady, pending != appliedLook,
                   let lookRoot = frame.lookRoot, let pivot = frame.pivot
                {
                    PreviewLighting.applyLook(
                        lookRoot: lookRoot,
                        pivot: pivot,
                        look: pending,
                        intensityExponent: studioIBLExponent
                    )
                    lookToMarkApplied = pending
                }
                var floorIndexToMarkApplied: Int?
                if let pivot = frame.pivot {
                    if let floor = frame.floor {
                        floor.isEnabled = showFloor
                        if appliedFloorLineIndex != backdropIndex {
                            PreviewFloor.applyLineColor(
                                PreviewBackground.at(backdropIndex).gridLineNSColor(systemDark: isDark),
                                to: floor
                            )
                            floorIndexToMarkApplied = backdropIndex
                        }
                    }
                    sidebar?.applyIfNeeded(to: pivot)
                    applyDebugIfNeeded(to: pivot)
                }
                if lookToMarkApplied != nil || floorIndexToMarkApplied != nil {
                    let look = lookToMarkApplied
                    let floorIndex = floorIndexToMarkApplied
                    Task { @MainActor in
                        if let look { appliedLook = look }
                        if let floorIndex { appliedFloorLineIndex = floorIndex }
                    }
                }
                if sidebar?.selectedCameraIndex != nil {
                    applyFileCamera()
                }
            } placeholder: {
                // RealityView's default ProgressView is unframed and sits at the
                // AppKit origin — a sliver in the window's bottom-left corner.
                Color.clear
            }
            .realityViewCameraControls(useSystemOrbit ? .orbit : .none)
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
            .ignoresSafeArea()
            .onTapGesture {
                guard !isHost else { return }
                chromeVisible.toggle()
            }

            if showToolbar, isHost || chromeVisible {
                PreviewChromeBar(
                    backdropIndex: $backdropIndex,
                    debugModeIndex: $debugModeIndex,
                    autoRotate: $autoRotate,
                    showFloor: $showFloor,
                    debugModes: debugModes,
                    isDark: isDark,
                    isHost: isHost,
                    onAutoRotateChanged: { enabled in
                        if isHost {
                            settingsAutoRotate = enabled
                        }
                    }
                )
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
            // Lighting is never part of open — warm HDR after the model is on screen.
            prefetchLook(lookStore.look)
        }
        .onChange(of: settingsAutoRotate) { _, _ in
            applyAutoRotateSetting()
        }
        .onChange(of: settingsShowFloor) { _, value in
            guard isHost else { return }
            showFloor = value
        }
        .onChange(of: showFloor) { _, value in
            guard isHost else { return }
            settingsShowFloor = value
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
        .onChange(of: isDark) { _, _ in
            appliedFloorLineIndex = -1
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
                if autoRotate, useSystemOrbit {
                    interaction.refreshPointerTimeout()
                    if !interaction.suppressesAutoRotate {
                        // Keep yaw on `frame` (not `@State`) so the tick does not
                        // invalidate SwiftUI every 16ms — only the entity updates.
                        frame.autoRotateYaw += Float(dt) * 20 * .pi / 180
                        frame.spin?.orientation = simd_quatf(
                            angle: frame.autoRotateYaw,
                            axis: [0, 1, 0]
                        )
                    }
                }
                if !isSeeking, isPlaying, let playback, clipDuration > 0 {
                    currentTime = playback.time.truncatingRemainder(dividingBy: clipDuration)
                    if currentTime < 0 { currentTime += clipDuration }
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func applyFileCamera() {
        guard let sidebar, let index = sidebar.selectedCameraIndex,
              sidebar.document.cameras.indices.contains(index),
              let preview = frame.camera
        else { return }
        let node = sidebar.document.nodes.first(where: { $0.cameraIndex == index })
        guard let node,
              let cameraNode = GLTFNodeLookup.entity(nodeIndex: node.index, in: entity)
        else { return }
        PreviewCamera.applyFileView(
            to: preview,
            cameraNode: cameraNode,
            spec: sidebar.document.cameras[index]
        )
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
        guard frame.debugApplied.index != index else { return }
        PreviewDebugMode.apply(debugModes[index], to: root, store: frame.debugStore)
        frame.debugApplied.index = index
    }

    private func applyViewport(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let sizeChanged =
            abs(size.width - viewport.width) > 0.5 || abs(size.height - viewport.height) > 0.5
        if sizeChanged {
            viewport = size
        }
        // Refit once after the real pane size is known (make used a placeholder aspect).
        if frame.camera != nil, !frame.didLayoutFit {
            frame.needsLayoutFit = true
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
