import AppKit
import GLTFCore
import Observation
import Renderer

/// How this window shows its file: stage, look, camera, scene, variant and selection
/// (DESIGN.md "this window" job). The toolbar, the menu bar and the sidebar all edit this one
/// object; `options` is what the canvas draws with, and the camera commands go to `canvas`.
///
/// Backdrop, floor and auto-rotate follow Settings until this window changes them. Nothing here
/// writes Settings.
@MainActor
@Observable
final class ViewState {
    static let defaultFieldOfView = 35.0
    static let fieldOfViewRange = 15.0...90.0
    /// One Zoom In step; Zoom Out is its inverse.
    static let zoomStep = 0.8

    @ObservationIgnored let settings: AppSettings
    /// The renderer behind the canvas. Outlives SwiftUI remounts of the canvas view.
    let canvas = ModelCanvasController()

    private var overrides = StageOverrides()

    var backdrop: BackdropStyle {
        get { overrides.backdrop ?? settings.backdrop }
        set { overrides.backdrop = newValue }
    }
    var showsFloor: Bool {
        get { overrides.showsFloor ?? settings.showsFloor }
        set { overrides.showsFloor = newValue }
    }
    var autoRotates: Bool {
        get { overrides.autoRotates ?? settings.autoRotates }
        set { overrides.autoRotates = newValue }
    }
    /// False frames the authored origin too and shows the origin gizmo.
    var isCentered = true
    var isOrthographic = false
    /// Vertical field of view in degrees, kept within `fieldOfViewRange`.
    /// Stored separately so `@Observable` + `didSet` cannot re-enter on assign.
    var fieldOfView: Double {
        get { storedFieldOfView }
        set { storedFieldOfView = newValue.clamped(to: Self.fieldOfViewRange) }
    }
    private var storedFieldOfView = defaultFieldOfView
    var viewMode: RenderViewMode = .shaded
    /// The modes the open file has data for; `viewMode` is always one of them.
    var viewModes: [RenderViewMode] = [.shaded] {
        didSet { if !viewModes.contains(viewMode) { viewMode = .shaded } }
    }

    var exposure = 0.0
    /// Environment rotation in degrees; 0 is the Khronos Sample Viewer's view.
    var environmentYaw = 0.0
    var environment: LightingEnvironment
    var toneMapping: RenderLook.ToneMapping

    /// The scene drawn and listed. Changing it drops a node selection and the file camera, which
    /// belong to the previous scene.
    var sceneIndex = 0 {
        didSet {
            guard sceneIndex != oldValue else { return }
            if let selection, selection.kind.isSceneNode { self.selection = nil }
            fileCameraNodeIndex = nil
        }
    }
    /// `KHR_materials_variants` index, or nil for the file's default materials.
    var materialVariantIndex: Int?
    /// The node of the file camera the canvas looks through, or nil for the orbit camera.
    var fileCameraNodeIndex: Int? {
        didSet { if fileCameraNodeIndex != nil { activeCameraPreset = nil } }
    }
    /// The selected outliner row. A mesh or empty node is also outlined on the canvas.
    var selection: NodeID?
    /// The canned angle last chosen; cleared by Fit, zoom and file cameras.
    private(set) var activeCameraPreset: CameraPreset?

    init(settings: AppSettings) {
        self.settings = settings
        environment = settings.environment
        toneMapping = settings.toneMapping
    }

    /// What the canvas draws with.
    var options: ViewOptions {
        ViewOptions(
            look: RenderLook(exposureEV: exposure, environmentIntensity: 1, environmentYawDegrees: environmentYaw,
                             environment: environment, toneMapping: toneMapping, background: backdrop.color),
            viewMode: viewMode,
            autoRotates: autoRotates,
            isOrthographic: isOrthographic,
            fieldOfView: fieldOfView,
            fileCameraNodeIndex: fileCameraNodeIndex,
            materialVariantIndex: materialVariantIndex,
            sceneIndex: sceneIndex,
            showsFloor: showsFloor,
            isCentered: isCentered,
            selectedNodeIndex: selection.flatMap { $0.kind == .mesh || $0.kind == .empty ? $0.index : nil }
        )
    }

    /// A new document in this window: Settings' lighting and every other choice back to how a
    /// new window starts. The document's scene and view modes follow once its JSON is read.
    func reset() {
        restoreStageAndLook()
        viewModes = [.shaded]
        sceneIndex = 0
        materialVariantIndex = nil
        fileCameraNodeIndex = nil
        selection = nil
        activeCameraPreset = nil
    }

    // MARK: - Camera commands

    func fit() {
        fileCameraNodeIndex = nil
        activeCameraPreset = nil
        canvas.fit()
    }

    func zoom(by factor: Double) {
        activeCameraPreset = nil
        canvas.zoom(by: factor)
    }

    func show(_ preset: CameraPreset) {
        fileCameraNodeIndex = nil
        activeCameraPreset = preset
        canvas.show(preset)
    }

    /// Reset View: this window's stage, look and camera back to how it opened, then Fit.
    func resetView() {
        restoreStageAndLook()
        fit()
    }

    /// File ▸ Export PNG: the canvas at its pixel size, through a save panel.
    func exportPNG(suggestedName: String) {
        do {
            let image = try canvas.snapshot()
            Task { await PNGExport.save(image, suggestedName: suggestedName) }
        } catch {
            AppLog.error(AppLog.app, "PNG export failed: \(error.localizedDescription)")
        }
    }

    private func restoreStageAndLook() {
        overrides = StageOverrides()
        isCentered = true
        isOrthographic = false
        fieldOfView = Self.defaultFieldOfView
        viewMode = .shaded
        exposure = 0
        environmentYaw = 0
        environment = settings.environment
        toneMapping = settings.toneMapping
    }
}

/// Window overrides of Settings-seeded stage knobs. `nil` means “follow Settings”.
private struct StageOverrides {
    var backdrop: BackdropStyle?
    var showsFloor: Bool?
    var autoRotates: Bool?
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
