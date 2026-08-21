//  SnapshotHarness.swift — shell-only. Never ships in GLBPreview.
//
//  WHAT THESE SNAPSHOTS ARE NOT GOOD FOR
//  Rendering happens offscreen with no window server behind it, so Liquid Glass cannot be
//  reproduced: `glassEffect`, `.buttonStyle(.glass)` and `.glassProminent`, `GlassEffectContainer`,
//  `Material`, vibrancy, and backdrop blur all come out flat, ghosted, or missing entirely. The
//  same applies to anything that samples what is *behind* it (shadow-through-blur,
//  `.background(.ultraThinMaterial)`).
//
//  FLATTEN SWITCH (`\.previewFlattenGlass`)
//  Offscreen `.buttonStyle(.glassProminent)` is not merely "flat" — it paints an unbounded
//  opaque white sheet that blanks every snapshot row (sidebar + canvas included). The harness
//  therefore injects `.environment(\.previewFlattenGlass, true)` so `Theme/Glass.swift` and
//  `Pill` substitute flat card / accent stand-ins. Live `PreviewUIShell` windows leave the key
//  unset and keep real Liquid Glass. PNGs prove geometry and active vs default; Peekaboo proves
//  glass.
//
//  WHY NOT `ImageRenderer` (it was, until Slice 2)
//  `ImageRenderer` draws **nothing at all** inside a `ScrollView` on macOS — not clipped content,
//  not a partial first screen: an empty rectangle. Measured on macOS 26 with a plain
//  `ScrollView { VStack { Text… } }`: 1426 opaque pixels rendered flat, 0 inside a scroll view.
//  The whole sidebar and inspector scroll, so an `ImageRenderer` harness silently reports every
//  panel as empty and an agent reads that as "the adaptive rule hid everything".
//
//  `NSHostingView` + `cacheDisplay(in:to:)` rasterizes the *real* AppKit layer tree instead, so
//  scroll views, clipping and appearance all behave as they do in the running app. Do not go
//  back to `ImageRenderer` without re-running that measurement.
//
//  Trust a snapshot for: layout, column widths, insets and spacing, Theme tokens, typography,
//  dark/light correctness, and adaptive show/hide (does a section render at all).
//  Do NOT trust it for: pill translucency, blur radius, or anything that reads as "glass".
//  Glass fidelity needs one real screenshot of a running window at slice sign-off.
//
//  ADDING A SNAPSHOT (later slices)
//  Add one row to `SnapshotHarness.rows`. `SnapshotRow` is generic over the view, so no
//  `AnyView` and no new plumbing:
//
//      SnapshotRow("inspector-rigged") { ShellWindow { $0.apply(.riggedAnimated) } }
//
//  Every row is rendered in both appearances and written as
//  `<dir>/<name>-light.png` and `<dir>/<name>-dark.png`.

import AppKit
import SwiftUI

/// A parsed `--snapshot [dir]` invocation. Plain value type so the process entry point can
/// decide whether to render or to open a window before any actor is involved.
struct SnapshotRequest {
    static let flag = "--snapshot"
    static let defaultDirectory = "/tmp/uishots"

    var directory: URL

    /// Returns `nil` when `--snapshot` is absent, i.e. the app should launch normally.
    ///
    /// The directory is the argument after the flag, but only when it does not itself look like
    /// a flag — Xcode and `open` inject their own (`-NSDocumentRevisionsDebugMode YES`), and
    /// swallowing one of those would write the PNGs somewhere surprising.
    init?(arguments: [String]) {
        guard let flagIndex = arguments.firstIndex(of: Self.flag) else { return nil }
        let next = arguments.indices.contains(flagIndex + 1) ? arguments[flagIndex + 1] : nil
        let path = (next?.hasPrefix("-") == false ? next : nil) ?? Self.defaultDirectory
        directory = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }
}

/// One named view to render. Generic over the view so the table stays type-safe; erasure happens
/// at the *image* boundary (`render` returns pixels), never at the view boundary.
struct SnapshotRow {
    let name: String
    let render: @MainActor (ColorScheme) -> NSBitmapImageRep?

    init<Content: View>(_ name: String, @ViewBuilder view: @escaping () -> Content) {
        self.name = name
        self.render = { scheme in SnapshotHarness.image(of: view(), colorScheme: scheme) }
    }
}

@MainActor
enum SnapshotHarness {

    /// 1280 x 820 at 1x — the exact geometry of `UI-REBUILD/Main@2x.png` / `Inspect@2x.png`,
    /// so a snapshot can be laid straight over a wireframe.
    static let size = CGSize(width: 1280, height: 820)
    /// @2x to match the wireframe PNGs pixel for pixel (output is 2560 x 1640).
    static let scale: CGFloat = 2

    /// The snapshot table. Later slices add rows here; nothing else changes.
    static var rows: [SnapshotRow] {
        [
            // The wireframe's own file: every section populated, "Body" selected. This is the row
            // to lay over `Main@2x.png`. Note the eye is hover-only, so it is correctly absent
            // here where the wireframe draws it — `Main@2x.png` illustrates the hover state.
            SnapshotRow("sidebar-full") {
                ShellWindow(select: NodeID(kind: .mesh, index: 0)) {
                    $0.apply(.riggedAnimated)
                    // `riggedAnimated` is skin + morphs + animations *only*; it does not add
                    // cameras or lights, so it alone cannot show all six sections.
                    $0.hasCameras = true
                    $0.hasLights = true
                }
            },
            // The fixture exactly as `MockFixture` defines it, which is the adaptive rule in
            // action: no cameras and no lights in this file, so those two sections do not exist.
            SnapshotRow("sidebar-rigged") { ShellWindow { $0.apply(.riggedAnimated) } },
            // The floor: a static mesh with no animations either. Scene / Meshes / Materials and
            // nothing else — the calm, near-empty UI DESIGN.md asks for.
            SnapshotRow("sidebar-plain") { ShellWindow { $0.apply(.plainMesh) } },
            // Nested Meshes fold chrome: Body → Eyes → Pupil (+ Beak), default depth < 3 expanded.
            SnapshotRow("meshes-nested") {
                ShellWindow(select: NodeID(kind: .mesh, index: 0)) {
                    $0.apply(.plainMesh)
                }
            },

            // Slice 4. These rows exist for pill *placement* — leading / centre / trailing, the
            // 14 pt inset, the 44 pt height, and that three pills fit side by side without
            // colliding at 1280 pt. They cannot say anything about the glass itself (see the
            // header): read them for geometry and check the material on a live window.
            //
            // The resting state, matching `Main@2x.png`: white backdrop, floor off, auto-rotate
            // and center on, Shaded, perspective.
            SnapshotRow("pills-default") { ShellWindow() },
            // Every toggle in its other position, so the active treatment is visible on all of
            // them at once and the view-mode chip is holding a non-default mode
            // (`Inspect@2x.png`). Cameras and lights are on so the Look pill's lighting popover
            // has its file-vs-studio control and the Camera pill has a preset checked.
            SnapshotRow("pills-active") {
                ShellWindow {
                    $0.apply(.riggedAnimated)
                    $0.hasCameras = true
                    $0.hasLights = true
                } viewport: { viewport in
                    viewport.setBackdrop(.dark)
                    viewport.setFloor(true)
                    viewport.setAutoRotate(false)
                    viewport.setCenter(false)
                    viewport.setViewMode(.channel(.normals))
                    viewport.setProjection(.orthographic)
                    viewport.applyCameraPreset(.isometric)
                }
            },

            // Slice 5. Bottom overlays only — trust for placement and gating, not glass.
            // Resting Main wireframe: orientation BL, dimensions BR, playback BC (animations on).
            SnapshotRow("overlays-animated") { ShellWindow { $0.apply(.riggedAnimated) } },
            // Same frame with animations off → playback bar must be absent.
            SnapshotRow("overlays-plain") { ShellWindow { $0.apply(.plainMesh) } },
            // Center off → origin gizmo in the canvas (Inspect mock). Uncentered authored origin
            // so the tag has a non-zero offset to read.
            SnapshotRow("overlays-origin") {
                ShellWindow {
                    $0.apply(.riggedAnimated)
                    $0.isUncentered = true
                } viewport: { viewport in
                    viewport.setCenter(false)
                }
            },

            // Slice 3 — Body selected: transform / geometry / material chips (no Emissive),
            // green Valid badge. Lay the right column over `Main@2x.png`'s inspector.
            SnapshotRow("inspector-body") {
                ShellWindow(select: NodeID(kind: .mesh, index: 0)) {
                    $0.apply(.riggedAnimated)
                }
            },
            // Material selected: full dossier (swatch, workflow/alpha/faces, map sizes, used-by).
            SnapshotRow("inspector-material") {
                ShellWindow(select: NodeID(kind: .material, index: 0)) {
                    $0.apply(.riggedAnimated)
                }
            },
            // Nothing selected → file-level summary (File + Validation + Pipeline), never blank.
            SnapshotRow("inspector-none") {
                ShellWindow(select: nil) {
                    $0.apply(.riggedAnimated)
                }
            },

            // Unified top chrome — layout only (flatten glass); Peekaboo for live baseline.
            SnapshotRow("chrome-aligned") {
                ShellWindow(select: NodeID(kind: .mesh, index: 0)) {
                    $0.apply(.riggedAnimated)
                }
            },
            SnapshotRow("chrome-sidebar-collapsed") {
                ShellWindow(
                    select: NodeID(kind: .mesh, index: 0),
                    sidebarVisible: false
                ) {
                    $0.apply(.riggedAnimated)
                }
            },
            SnapshotRow("chrome-inspector-collapsed") {
                ShellWindow(
                    select: NodeID(kind: .mesh, index: 0),
                    inspectorVisible: false
                ) {
                    $0.apply(.riggedAnimated)
                }
            },

            // Slice 6 — Debug / §2 presets (layout + adaptive show/hide only; not glass).
            SnapshotRow("debug-plain") { ShellWindow { $0.apply(.plainMesh) } },
            SnapshotRow("debug-invalid") { ShellWindow { $0.apply(.invalidFile) } },
            SnapshotRow("debug-lights") { ShellWindow { $0.apply(.withLights) } },
            SnapshotRow("debug-cameras") { ShellWindow { $0.apply(.withCameras) } },

            // Slice 8 — empty / loading / failed (never a spinner for failed).
            SnapshotRow("shell-empty") {
                ShellWindow { scene in
                    scene.apply(.plainMesh)
                    scene.documentState = .empty
                }
            },
            SnapshotRow("shell-loading") {
                ShellWindow { scene in
                    scene.apply(.plainMesh)
                    scene.documentState = .loading
                }
            },
            SnapshotRow("shell-failed") {
                ShellWindow { scene in
                    scene.apply(.plainMesh)
                    scene.documentState = .failed(ShellStatusCopy.invalidFileDetail)
                }
            }
        ]
    }

    /// Renders every row in both appearances, writes the PNGs, and terminates the process.
    /// Never returns: in snapshot mode the app must not reach `App.main()` and open a window.
    ///
    /// AppKit bring-up is owned by `AppKitBootstrap.prepareHeadlessSnapshot()` in `main` — do
    /// not touch `NSApplication.shared` here first. Doing so without the UI-element transform
    /// aborts inside `HIServices.RegisterApplication` and pops "quit unexpectedly" (Reopen then
    /// re-runs `--snapshot` and loops).
    static func run(_ request: SnapshotRequest) -> Never {
        // Activation policy is already `.prohibited` from bootstrap; keep it that way.
        NSApplication.shared.setActivationPolicy(.prohibited)

        do {
            try FileManager.default.createDirectory(at: request.directory, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("snapshot: cannot create \(request.directory.path): \(error)\n".utf8))
            exit(1)
        }

        var failed = false
        for row in rows {
            for scheme in [ColorScheme.light, .dark] {
                let suffix = scheme == .dark ? "dark" : "light"
                let url = request.directory.appendingPathComponent("\(row.name)-\(suffix).png")
                guard
                    let bitmap = row.render(scheme),
                    let png = bitmap.representation(using: .png, properties: [:])
                else {
                    FileHandle.standardError.write(Data("snapshot: failed to render \(row.name) \(suffix)\n".utf8))
                    failed = true
                    continue
                }
                do {
                    try png.write(to: url)
                    print("snapshot: \(url.path) (\(bitmap.pixelsWide)x\(bitmap.pixelsHigh))")
                } catch {
                    FileHandle.standardError.write(Data("snapshot: cannot write \(url.path): \(error)\n".utf8))
                    failed = true
                }
            }
        }
        exit(failed ? 1 : 0)
    }

    /// Rasterizes one view in one appearance.
    ///
    /// The appearance is applied in **three** places, and all three are load-bearing:
    ///
    /// - `.environment(\.colorScheme, …)` drives SwiftUI's own semantic colours and any view that
    ///   reads `@Environment(\.colorScheme)`.
    /// - `NSHostingView.appearance` gives the AppKit layer tree the right `effectiveAppearance`,
    ///   which is what actually decides how the hosted SwiftUI content is drawn.
    /// - `NSApp.appearance` + `performAsCurrentDrawingAppearance` drive `NSAppearance.currentDrawing`,
    ///   which is what `Theme`'s `NSColor(name:dynamicProvider:)` tokens resolve against. Without
    ///   it every Theme colour stays in its light variant and the "dark" PNG is a light PNG with a
    ///   dark label.
    static func image<Content: View>(of content: Content, colorScheme: ColorScheme) -> NSBitmapImageRep? {
        // The bitmap is built at an explicit pixel size with `rep.size` left at the *logical*
        // size, which is what makes `cacheDisplay` draw at exactly `scale`. Asking the view for
        // `bitmapImageRepForCachingDisplay` instead would inherit whatever backing scale the
        // current display happens to have, so the same command would emit @1x PNGs on a
        // non-Retina screen and quietly stop lining up with the @2x wireframes.
        guard
            let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua),
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width * scale),
                pixelsHigh: Int(size.height * scale),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        else { return nil }
        bitmap.size = size

        NSApp?.appearance = appearance
        let host = NSHostingView(
            rootView: content
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, colorScheme)
                // See header: without this, `.glassProminent` blanks the bitmap offscreen.
                .environment(\.previewFlattenGlass, true)
        )
        host.appearance = appearance
        host.frame = CGRect(origin: .zero, size: size)
        // Detached from any window, so nothing else will ever ask it to lay out.
        host.layoutSubtreeIfNeeded()
        appearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        return bitmap
    }
}
