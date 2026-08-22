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
    /// Ortho `scale` is fixed world height — recompute on viewport change.
    var needsOrthoScale = false
    /// Last session projection applied while `useSystemOrbit` (nil after file camera).
    var appliedSessionOrthographic: Bool?
    weak var pivot: Entity?
    weak var spin: Entity?
    weak var floor: Entity?
    weak var camera: Entity?
    weak var lookRoot: Entity?
    /// Last IBL intensity / yaw applied via `applyLook` (session lighting, not @State).
    var appliedIntensityExponent: Float?
    var appliedEnvironmentYaw: Float?
    /// Last skeleton overlay visibility applied to the turntable.
    var appliedShowSkeleton: Bool?
    /// Last session FOV applied to the preview camera (nil after file camera).
    var appliedFieldOfViewDegrees: Float?
    let debugStore = DebugMaterialStore()
    let debugApplied = DebugAppliedIndex()
}

struct PreviewScene: View {
    let entity: Entity
    /// Session document — clip names for `PreviewClip.usable` (RK often drops them).
    var document: GLTFSessionDocument = GLTFSessionDocument()
    var stats: PreviewStats?
    var debugModes: [PreviewDebugMode]
    var studioIBLExponent: Float
    @Bindable var interaction: PreviewInteraction
    var isDark: Bool
    var sidebar: (any PreviewOverlay)?
    /// Concrete Int from the host — reliable RealityView dependency for select/hide.
    var overlayRevision: Int
    /// Host passes window-owned bindings. Quick Look leaves this nil and uses local `@State`.
    var session: PreviewSessionBindings?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var localBackdropIndex: Int
    @State private var localAutoRotate: Bool
    @State private var localShowFloor: Bool
    /// Center on by default; ephemeral, never UserDefaults.
    @State private var localCenterModel: Bool
    /// Orthographic projection; ephemeral, never UserDefaults.
    @State private var localOrthographic: Bool
    /// Session lighting; ephemeral, never UserDefaults.
    @State private var localExposureEV: Float
    @State private var localDimStudioForFileLights: Bool
    @State private var localEnvironmentYaw: Float
    /// Force double-sided materials; ephemeral, never UserDefaults.
    @State private var localDoubleSided: Bool
    /// Skeleton overlay; ephemeral, never UserDefaults.
    @State private var localShowSkeleton: Bool
    /// Perspective FOV; ephemeral, never UserDefaults.
    @State private var localFieldOfViewDegrees: Float
    /// Huge/flat models veto auto-rotate. Computed once per entity in `init` (cheap to read
    /// in the 16ms tick, unlike re-deriving bounds each frame).
    private let geometryDisablesAutoRotate: Bool
    @State private var playback: RealityKit.AnimationPlaybackController?
    @State private var clips: [PreviewClip] = []
    @State private var clipIndex = 0
    @State private var clipDuration: TimeInterval = 0
    @State private var currentTime: TimeInterval = 0
    @State private var isPlaying = false
    @State private var isSeeking = false
    @State private var viewport = CGSize(width: 810, height: 600)
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
        document: GLTFSessionDocument = GLTFSessionDocument(),
        stats: PreviewStats?,
        debugModes: [PreviewDebugMode] = [.none],
        studioIBLExponent: Float = 0,
        interaction: PreviewInteraction,
        isDark: Bool,
        sidebar: (any PreviewOverlay)? = nil,
        overlayRevision: Int = 0,
        session: PreviewSessionBindings? = nil
    ) {
        self.entity = entity
        self.document = document
        self.stats = stats
        self.debugModes = debugModes.isEmpty ? [.none] : debugModes
        self.studioIBLExponent = studioIBLExponent
        self.interaction = interaction
        self.isDark = isDark
        self.sidebar = sidebar
        self.overlayRevision = overlayRevision
        self.session = session
        let bounds = PreviewCamera.modelBounds(of: entity, relativeTo: entity)
        let extent = bounds.max - bounds.min
        geometryDisablesAutoRotate = PreviewCamera.disablesAutoRotate(extent)
        // Seed local session from defaults when the host did not pass bindings (Quick Look).
        // Only `_State(initialValue:)` here — never touch `@Observable` / other `@State` (AGENTS.md).
        _localAutoRotate = State(
            initialValue: UserDefaults.standard.object(forKey: SettingsKeys.autoRotate) as? Bool ?? true
        )
        _localShowFloor = State(
            initialValue: UserDefaults.standard.object(forKey: SettingsKeys.showFloor) as? Bool ?? true
        )
        _localBackdropIndex = State(initialValue: PreviewBackground.storedIndex)
        _localCenterModel = State(initialValue: true)
        _localOrthographic = State(initialValue: false)
        _localExposureEV = State(initialValue: 0)
        // Match auto-dim when the file brought punctual lights (`studioIBLExponent == -2`).
        _localDimStudioForFileLights = State(initialValue: studioIBLExponent < 0)
        _localEnvironmentYaw = State(initialValue: 0)
        _localDoubleSided = State(initialValue: false)
        _localShowSkeleton = State(initialValue: false)
        _localFieldOfViewDegrees = State(initialValue: PreviewCamera.defaultFieldOfViewDegrees)
    }

    /// Host window supplies PreviewUI overlays; Quick Look (`sidebar == nil`) keeps inlined chrome.
    private var isHost: Bool { sidebar != nil }

    /// Quick Look (`sidebar == nil`) draws minimal canvas chrome; host uses PreviewUI.
    private var showsInlineChrome: Bool { !isHost }

    private var backdropIndex: Binding<Int> {
        session?.backdropIndex ?? $localBackdropIndex
    }

    private var autoRotateBinding: Binding<Bool> {
        session?.autoRotate ?? $localAutoRotate
    }

    private var showFloorBinding: Binding<Bool> {
        session?.showFloor ?? $localShowFloor
    }

    private var centerModelBinding: Binding<Bool> {
        session?.centerModel ?? $localCenterModel
    }

    private var orthographicBinding: Binding<Bool> {
        session?.orthographic ?? $localOrthographic
    }

    private var exposureEVBinding: Binding<Float> {
        session?.exposureEV ?? $localExposureEV
    }

    private var dimStudioForFileLightsBinding: Binding<Bool> {
        session?.dimStudioForFileLights ?? $localDimStudioForFileLights
    }

    private var environmentYawBinding: Binding<Float> {
        session?.environmentYaw ?? $localEnvironmentYaw
    }

    private var doubleSidedBinding: Binding<Bool> {
        session?.doubleSided ?? $localDoubleSided
    }

    private var showSkeletonBinding: Binding<Bool> {
        session?.showSkeleton ?? $localShowSkeleton
    }

    private var fieldOfViewBinding: Binding<Float> {
        session?.fieldOfViewDegrees ?? $localFieldOfViewDegrees
    }

    private var debugModeIndexBinding: Binding<Int> {
        session?.debugModeIndex ?? $debugModeIndex
    }

    private var debugModeIndexValue: Int {
        debugModeIndexBinding.wrappedValue
    }

    // Session auto-rotate / floor are ephemeral. `autoRotateActive` layers runtime vetoes
    // (Reduced Motion, geometry) without writing them back to Settings.
    private var showFloorValue: Bool { showFloorBinding.wrappedValue }
    private var centerModelValue: Bool { centerModelBinding.wrappedValue }
    private var orthographicValue: Bool { orthographicBinding.wrappedValue }
    private var exposureEVValue: Float { exposureEVBinding.wrappedValue }
    private var dimStudioForFileLightsValue: Bool { dimStudioForFileLightsBinding.wrappedValue }
    private var environmentYawValue: Float { environmentYawBinding.wrappedValue }
    private var doubleSidedValue: Bool { doubleSidedBinding.wrappedValue }
    private var showSkeletonValue: Bool { showSkeletonBinding.wrappedValue }
    private var fieldOfViewValue: Float {
        PreviewCamera.clampedFieldOfView(fieldOfViewBinding.wrappedValue)
    }
    private var documentSkins: [GLTFSessionDocument.Skin] {
        let fromSidebar = sidebar?.document.skins ?? []
        return fromSidebar.isEmpty ? document.skins : fromSidebar
    }
    private var effectiveIBLExponent: Float {
        PreviewEmissive.sessionIBLExponent(
            dimStudioForFileLights: dimStudioForFileLightsValue,
            exposureEV: exposureEVValue
        )
    }
    private var autoRotateIntent: Bool { autoRotateBinding.wrappedValue }
    private var autoRotateActive: Bool {
        autoRotateIntent && !reduceMotion && !geometryDisablesAutoRotate
    }

    private var useSystemOrbit: Bool {
        sidebar?.selectedCameraIndex == nil
    }

    private var backdropColor: Color {
        PreviewBackground.at(backdropIndex.wrappedValue).color
    }

    private var tickWhileActive: Bool {
        autoRotateActive || (isPlaying && playback != nil)
    }

    var body: some View {
        let _ = overlayRevision
        let _ = debugModeIndexValue
        let _ = lookStore.look
        ZStack {
            RealityView { content in
                content.camera = .virtual
                // Capture once for this make — do not write @State from make/update.
                let centerModel = centerModelValue
                let assembled = PreviewCamera.makeTurntable(for: entity, center: centerModel)
                frame.bounds = assembled.bounds
                frame.pivot = assembled.pivot
                frame.spin = assembled.spin
                frame.autoRotateYaw = 0
                frame.didLayoutFit = false
                frame.needsLayoutFit = true
                let floor = PreviewFloor.make(
                    bounds: assembled.bounds,
                    lineColor: PreviewBackground.at(backdropIndex.wrappedValue).gridLineNSColor(systemDark: isDark)
                )
                frame.floor = floor
                assembled.pivot.addChild(floor)
                PreviewFloor.enableCastingShadows(on: entity)

                let camera = PreviewCamera.makeFrontThreeQuarter(
                    minBound: assembled.bounds.min,
                    maxBound: assembled.bounds.max,
                    padding: PreviewCamera.previewFitPadding,
                    aspect: aspect(of: viewport),
                    fieldOfViewInDegrees: fieldOfViewValue
                )
                frame.camera = camera
                frame.appliedFieldOfViewDegrees = fieldOfViewValue
                // Pivot carries the model (real bounds) — system `.orbit` frames from it.
                // A separate empty focus entity was nose-diving the camera on open.
                content.cameraTarget = assembled.pivot

                let lookRoot = Entity()
                lookRoot.name = PreviewLighting.lookRootName
                frame.lookRoot = lookRoot

                content.add(assembled.pivot)
                content.add(camera)
                content.add(lookRoot)
                let intensity = effectiveIBLExponent
                let yaw = environmentYawValue
                PreviewLighting.applyLook(
                    lookRoot: lookRoot,
                    pivot: assembled.pivot,
                    look: lookStore.look,
                    intensityExponent: intensity,
                    environmentYaw: yaw
                )
                frame.appliedIntensityExponent = intensity
                frame.appliedEnvironmentYaw = yaw
                sidebar?.applyIfNeeded(to: assembled.pivot)
                let usable = PreviewClip.usable(on: entity, document: document)
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
                    if !usable.isEmpty {
                        let summary = usable
                            .map { "\($0.title) (\((($0.duration * 100).rounded() / 100))s)" }
                            .joined(separator: ", ")
                        AppLog.info(AppLog.load, "animation clips: \(summary)")
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
                        orbitFocus: pivot,
                        orthographic: useSystemOrbit && orthographicValue,
                        fieldOfViewInDegrees: fieldOfViewValue
                    )
                    frame.needsLayoutFit = false
                    frame.needsOrthoScale = false
                    frame.didLayoutFit = true
                    if useSystemOrbit {
                        frame.appliedSessionOrthographic = orthographicValue
                        frame.appliedFieldOfViewDegrees = fieldOfViewValue
                    }
                    Task { @MainActor in interaction.markFitted() }
                } else if frame.needsOrthoScale, useSystemOrbit, orthographicValue,
                          let camera = frame.camera
                {
                    PreviewCamera.updateOrthographicScale(
                        on: camera,
                        bounds: frame.bounds,
                        aspect: aspect(of: viewport)
                    )
                    frame.needsOrthoScale = false
                }
                var lookToMarkApplied: AppLook?
                if let lookRoot = frame.lookRoot, let pivot = frame.pivot {
                    let intensity = effectiveIBLExponent
                    let yaw = environmentYawValue
                    let lookChanged = pendingReady != nil && pendingReady != appliedLook
                    let lightingChanged =
                        frame.appliedIntensityExponent != intensity
                        || frame.appliedEnvironmentYaw != yaw
                    if lookChanged || lightingChanged {
                        let look = pendingReady ?? appliedLook ?? lookStore.look
                        PreviewLighting.applyLook(
                            lookRoot: lookRoot,
                            pivot: pivot,
                            look: look,
                            intensityExponent: intensity,
                            environmentYaw: yaw
                        )
                        frame.appliedIntensityExponent = intensity
                        frame.appliedEnvironmentYaw = yaw
                        if lookChanged {
                            lookToMarkApplied = pendingReady
                        }
                    }
                }
                var floorIndexToMarkApplied: Int?
                if let pivot = frame.pivot {
                    if let floor = frame.floor {
                        floor.isEnabled = showFloorValue
                        let index = backdropIndex.wrappedValue
                        if appliedFloorLineIndex != index {
                            PreviewFloor.applyLineColor(
                                PreviewBackground.at(index).gridLineNSColor(systemDark: isDark),
                                to: floor
                            )
                            floorIndexToMarkApplied = index
                        }
                    }
                    sidebar?.applyIfNeeded(to: pivot)
                    applyDebugIfNeeded(to: pivot)
                    applySkeletonOverlayIfNeeded(to: pivot)
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
                    frame.appliedSessionOrthographic = nil
                    frame.appliedFieldOfViewDegrees = nil
                    applyFileCamera()
                } else if useSystemOrbit {
                    syncSessionProjectionIfNeeded()
                    syncSessionFieldOfViewIfNeeded()
                }
            } placeholder: {
                // RealityView's default ProgressView is unframed and sits at the
                // AppKit origin — a sliver in the window's bottom-left corner.
                Color.clear
            }
            .realityViewCameraControls(useSystemOrbit ? .orbit : .none)
            // Remount when Center toggles so `make` rebuilds the turntable (no @State writes from make).
            .id(centerModelValue)
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

            if showsInlineChrome {
                PreviewQuickLookChrome(
                    backdropIndex: backdropIndex,
                    autoRotate: autoRotateBinding,
                    isDark: isDark
                )
            }

            if showsInlineChrome, let facts = stats?.overlayFacts, !facts.isEmpty {
                PreviewOverlayFacts(facts: facts, tint: chromeTint(active: true))
                    .allowsHitTesting(false)
                    .padding(.leading, 14)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .onAppear {
            // Lighting is never part of open — warm HDR after the model is on screen.
            prefetchLook(lookStore.look)
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
        .onChange(of: orthographicValue) { _, _ in
            // Toggle from View menu — apply when system orbit owns the camera.
            guard useSystemOrbit else { return }
            frame.appliedSessionOrthographic = nil
            syncSessionProjectionIfNeeded()
        }
        .onChange(of: interaction.openingFitResetID) { _, id in
            // Menu / Task MainActor only — not RealityView update (AGENTS.md pitfall 4).
            guard id > 0 else { return }
            resetOpeningFit()
        }
        .onChange(of: overlayRevision) { _, _ in
            // Host selection/hide: NSHostingView + `any PreviewOverlay` do not reliably
            // drive RealityView `update`; apply on the pivot from MainActor here.
            guard let pivot = frame.pivot else { return }
            sidebar?.applyIfNeeded(to: pivot)
        }
        .task(id: tickWhileActive) {
            guard tickWhileActive else { return }
            var lastTick = Date()
            while !Task.isCancelled {
                let now = Date()
                let dt = now.timeIntervalSince(lastTick)
                lastTick = now
                if autoRotateActive, useSystemOrbit {
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

    /// Undo Shift-pan, clear auto-rotate yaw, re-apply opening front-3/4 fit.
    private func resetOpeningFit() {
        frame.pivot?.setPosition(.zero, relativeTo: nil)
        frame.autoRotateYaw = 0
        frame.spin?.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        guard let camera = frame.camera else {
            interaction.markFitted()
            return
        }
        PreviewCamera.applyFit(
            to: camera,
            bounds: frame.bounds,
            aspect: aspect(of: viewport),
            orbitFocus: frame.pivot,
            orthographic: useSystemOrbit && orthographicValue,
            fieldOfViewInDegrees: fieldOfViewValue
        )
        if useSystemOrbit {
            frame.appliedSessionOrthographic = orthographicValue
            frame.appliedFieldOfViewDegrees = fieldOfViewValue
        }
        interaction.markFitted()
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

    /// Preview ortho toggle only while `useSystemOrbit` — file cameras own projection via
    /// `applyFileView`. Keeps pose; swaps projection components.
    private func syncSessionProjectionIfNeeded() {
        guard useSystemOrbit, let camera = frame.camera else { return }
        let want = orthographicValue
        guard frame.appliedSessionOrthographic != want else { return }
        if want {
            PreviewCamera.applyOrthographicProjection(
                to: camera,
                bounds: frame.bounds,
                aspect: aspect(of: viewport)
            )
        } else {
            PreviewCamera.restoreFitPerspective(on: camera, fieldOfViewInDegrees: fieldOfViewValue)
            frame.appliedFieldOfViewDegrees = fieldOfViewValue
        }
        frame.appliedSessionOrthographic = want
    }

    /// Live FOV while perspective; no-op while ortho / file camera.
    private func syncSessionFieldOfViewIfNeeded() {
        guard useSystemOrbit, !orthographicValue, let camera = frame.camera else { return }
        let want = fieldOfViewValue
        guard frame.appliedFieldOfViewDegrees != want else { return }
        PreviewCamera.applyFieldOfView(to: camera, degrees: want)
        frame.appliedFieldOfViewDegrees = want
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

    private func chromeTint(active: Bool) -> Color {
        PreviewBackground.iconColor(at: backdropIndex.wrappedValue, systemDark: isDark, active: active)
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

    private func applyDebugIfNeeded(to root: Entity) {
        let index = debugModes.indices.contains(debugModeIndexValue) ? debugModeIndexValue : 0
        let doubleSided = doubleSidedValue
        guard frame.debugApplied.index != index || frame.debugApplied.doubleSided != doubleSided
        else { return }
        PreviewDebugMode.apply(
            debugModes[index],
            doubleSided: doubleSided,
            to: root,
            store: frame.debugStore
        )
        frame.debugApplied.index = index
        frame.debugApplied.doubleSided = doubleSided
    }

    private func applySkeletonOverlayIfNeeded(to pivot: Entity) {
        let want = showSkeletonValue && !documentSkins.isEmpty
        if frame.appliedShowSkeleton != want {
            PreviewSkeletonOverlay.apply(
                show: want,
                skins: documentSkins,
                to: entity,
                relativeTo: pivot
            )
            frame.appliedShowSkeleton = want
        } else if want {
            PreviewSkeletonOverlay.updateBones(
                skins: documentSkins,
                root: entity,
                pivot: pivot
            )
        }
    }

    private func applyViewport(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let sizeChanged =
            abs(size.width - viewport.width) > 0.5 || abs(size.height - viewport.height) > 0.5
        if sizeChanged {
            viewport = size
            // Ortho scale is fixed world height — recompute when the pane aspect changes.
            if useSystemOrbit, orthographicValue, frame.didLayoutFit {
                frame.needsOrthoScale = true
            }
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
    var doubleSided: Bool?
}
