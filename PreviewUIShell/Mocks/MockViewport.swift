import Foundation
import Observation

/// The shell's `ViewportController`: per-window view state with no renderer behind it.
///
/// Every mutator stores the value **and** appends to `callLog`, which is what turns "the pill
/// looks active" into "the pill called `setAutoRotate(false)`". Without it a control that only
/// flipped its own `@State` would be indistinguishable from one that is genuinely wired.
///
/// Settings-backed keys keep **one write path**: update the viewport property, then
/// `persistSession` mirrors that key into `MockSettings` (DESIGN.md This-window job). Pills
/// never write app defaults. Host adapters later can drop the mirror and own session themselves.
@MainActor
@Observable
final class MockViewport: ViewportController {
    /// `private(set)` satisfies the protocol's `{ get }` while forcing every write through a
    /// named mutator, so nothing can change view state without being logged.
    private(set) var backdrop: BackdropStyle = SettingKey<BackdropStyle>.backdrop.fallback
    private(set) var showsFloor: Bool = SettingKey<Bool>.showFloor.fallback
    private(set) var autoRotates: Bool = SettingKey<Bool>.autoRotate.fallback
    private(set) var isCentered: Bool = SettingKey<Bool>.center.fallback
    private(set) var viewMode: ViewMode = .shaded
    private(set) var projection: Projection = SettingKey<Projection>.projection.fallback
    private(set) var lighting: LightingSettings = .standard
    private(set) var activeCameraPreset: CameraPreset?
    private(set) var activeSceneID: NodeID?
    private(set) var selectedMaterialVariantIndex: Int?

    /// Newest last. Read it from a debug overlay, a test, or the launch log.
    private(set) var callLog: [String] = []

    /// Per-window settings; set from `ShellRootView` after both exist. Weak so the store can
    /// outlive a transient viewport during SwiftUI rebuilds without a cycle.
    weak var settings: MockSettings?

    init() {}

    /// Push the effective session values into the viewport without logging (open-path seed).
    func applySession(from settings: MockSettings, log: Bool = false) {
        self.settings = settings
        let backdrop = settings.sessionValue(for: .backdrop)
        let floor = settings.sessionValue(for: .showFloor)
        let autoRotate = settings.sessionValue(for: .autoRotate)
        let center = settings.sessionValue(for: .center)
        let projection = settings.sessionValue(for: .projection)
        if log {
            setBackdrop(backdrop)
            setFloor(floor)
            setAutoRotate(autoRotate)
            setCenter(center)
            setProjection(projection)
        } else {
            self.backdrop = backdrop
            showsFloor = floor
            autoRotates = autoRotate
            isCentered = center
            self.projection = projection
        }
    }

    /// After a Debug fixture pre-configures the viewport, mirror those values into session
    /// so menu and pills still share one This-window source of truth.
    func syncSessionFromViewport() {
        persistSession()
    }

    func setBackdrop(_ style: BackdropStyle) {
        backdrop = style
        persistSession(style, for: .backdrop)
        record("setBackdrop(.\(style.rawValue))")
    }

    func setFloor(_ isOn: Bool) {
        showsFloor = isOn
        persistSession(isOn, for: .showFloor)
        record("setFloor(\(isOn))")
    }

    func setAutoRotate(_ isOn: Bool) {
        autoRotates = isOn
        persistSession(isOn, for: .autoRotate)
        record("setAutoRotate(\(isOn))")
    }

    func setCenter(_ isOn: Bool) {
        isCentered = isOn
        persistSession(isOn, for: .center)
        record("setCenter(\(isOn))")
    }

    func setViewMode(_ mode: ViewMode) {
        viewMode = mode
        record("setViewMode(.\(mode.id))")
    }

    func setProjection(_ projection: Projection) {
        self.projection = projection
        persistSession(projection, for: .projection)
        record("setProjection(.\(projection.rawValue))")
    }

    func setLighting(_ lighting: LightingSettings) {
        self.lighting = lighting
        record(
            "setLighting(exposure: \(String(format: "%.2f", lighting.exposure)), "
                + "envRotation: \(String(format: "%.0f", lighting.environmentRotationDegrees)), "
                + "fileLights: \(lighting.usesFileLights))"
        )
    }

    func fit() {
        record("fit()")
    }

    /// Back to the opening pose *and* the opening view state — including the preset, which is why
    /// this clears it rather than leaving a checkmark on an angle the camera no longer holds.
    func reset() {
        backdrop = SettingKey<BackdropStyle>.backdrop.fallback
        showsFloor = SettingKey<Bool>.showFloor.fallback
        autoRotates = SettingKey<Bool>.autoRotate.fallback
        isCentered = SettingKey<Bool>.center.fallback
        viewMode = .shaded
        projection = SettingKey<Projection>.projection.fallback
        lighting = .standard
        activeCameraPreset = nil
        persistSession()
        record("reset()")
    }

    func applyCameraPreset(_ preset: CameraPreset) {
        activeCameraPreset = preset
        record("applyCameraPreset(.\(preset.rawValue))")
    }

    func screenshot() {
        record("screenshot()")
    }

    func setScene(_ id: NodeID) {
        activeSceneID = id
        record("setScene(\(id.kind.rawValue):\(id.index))")
    }

    func setMaterialVariant(_ index: Int?) {
        selectedMaterialVariantIndex = index
        record("setMaterialVariant(\(index.map(String.init) ?? "nil"))")
    }

    func setFileCamera(_ id: NodeID?) {
        if let id {
            guard id.kind == .camera else { return }
            record("setFileCamera(\(id.kind.rawValue):\(id.index))")
        } else {
            record("setFileCamera(nil)")
        }
        activeCameraPreset = nil
    }

    // MARK: - Session mirror

    /// Mirror every settings-backed key. Used by `reset` and harness `syncSessionFromViewport`.
    private func persistSession() {
        guard let settings else { return }
        settings.setSession(backdrop, for: .backdrop)
        settings.setSession(showsFloor, for: .showFloor)
        settings.setSession(autoRotates, for: .autoRotate)
        settings.setSession(isCentered, for: .center)
        settings.setSession(projection, for: .projection)
    }

    /// Single-key mirror after a live mutator — same dictionary as `persistSession()`.
    private func persistSession<Value>(_ value: Value, for key: SettingKey<Value>) {
        settings?.setSession(value, for: key)
    }

    /// Appends to the in-memory call log. Optional stdout + `/tmp` file when
    /// `PREVIEWUI_VIEWPORT_LOG=1` (Peekaboo / agent harness only).
    private func record(_ call: String) {
        callLog.append(call)
        guard ProcessInfo.processInfo.environment["PREVIEWUI_VIEWPORT_LOG"] == "1" else { return }
        let line = "viewport: \(call)\n"
        print(line, terminator: "")
        let url = URL(fileURLWithPath: "/tmp/previewuishell-viewport.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
