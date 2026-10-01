import DesignSystem
import SwiftUI

struct GlassIslandPage: View {
    var body: some View {
        CatalogPageView(page: .glassIsland) {
            StateGroup(
                title: "States",
                note: "The island is the only glass layer. Controls inside must not draw their own."
            ) {
                StateRow("Toggles, divider, action") {
                    Live(IslandToggles()) { $toggles in
                        DSGlassIsland {
                            DSGlassToggleButton("Floor", systemImage: "circle.grid.cross", isOn: $toggles.on)
                            DSGlassToggleButton("Grid", systemImage: "grid", isOn: $toggles.off)
                            DSGlassIslandDivider()
                            DSGlassIconButton("Frame Model", systemImage: "viewfinder") {}
                        }
                    }
                }
                StateRow("Plain button inside") {
                    DSGlassIsland {
                        Button("Plain button") {}
                            .font(DS.Font.body)
                            .padding(.horizontal, DS.Spacing.s)
                    }
                }
                StateRow("Long titled menu") {
                    DSGlassIsland {
                        DSGlassMenuButton(
                            "View mode",
                            systemImage: "circle.lefthalf.filled",
                            style: .titled("Ambient Occlusion")
                        ) {
                            Button("Shaded") {}
                        }
                    }
                }
            }

            StateGroup(
                title: "Placement",
                note: "Standalone glass controls draw their own glass; the same controls inside an island do not."
            ) {
                StateRow("Standalone (own glass)") {
                    Live(false) { $on in
                        HStack(spacing: DS.Metrics.clusterSpacing) {
                            DSGlassToggleButton("Floor", systemImage: "circle.grid.cross", isOn: $on)
                            DSGlassIconButton("Frame Model", systemImage: "viewfinder") {}
                        }
                    }
                }
                StateRow("In island (no nested glass)") {
                    Live(false) { $on in
                        DSGlassIsland {
                            DSGlassToggleButton("Floor", systemImage: "circle.grid.cross", isOn: $on)
                            DSGlassIconButton("Frame Model", systemImage: "viewfinder") {}
                        }
                    }
                }
            }
        }
    }
}

struct GlassClusterPage: View {
    var body: some View {
        CatalogPageView(page: .glassCluster) {
            StateGroup(
                title: "Clusters",
                note: "One GlassEffectContainer per cluster. Mix islands and standalone glass controls."
            ) {
                StateRow("Stage-style", minHeight: 72) {
                    Live(true) { $floor in
                        Live(0) { $backdrop in
                            DSGlassCluster {
                                DSSwatchPicker(
                                    "Backdrop",
                                    selection: $backdrop,
                                    swatches: CatalogSwatches.all
                                )
                                DSGlassToggleButton("Floor", systemImage: "circle.grid.cross", isOn: $floor)
                            }
                        }
                    }
                }
                StateRow("Look-style", minHeight: 72) {
                    DSGlassCluster {
                        DSGlassIsland {
                            DSGlassMenuButton(
                                "View mode",
                                systemImage: "circle.lefthalf.filled",
                                style: .titled("Shaded")
                            ) {
                                Button("Shaded") {}
                                Button("Wireframe") {}
                            }
                            DSGlassIslandDivider()
                            DSGlassPopoverButton("Lighting", systemImage: "sun.max") {
                                DSPopoverPanel {
                                    Text("Lighting controls")
                                        .font(DS.Font.body)
                                        .foregroundStyle(DS.Color.textPrimary)
                                }
                            }
                        }
                    }
                }
                StateRow("Camera-style", minHeight: 72) {
                    Live(CameraToggles()) { $camera in
                        DSGlassCluster {
                            DSGlassToggleButton(
                                "Auto-rotate",
                                systemImage: "arrow.trianglehead.counterclockwise.rotate.90",
                                isOn: $camera.autoRotate
                            )
                            DSGlassToggleButton("Center Model", systemImage: "dot.scope", isOn: $camera.centered)
                            DSGlassToggleButton("Orthographic", systemImage: "perspective", isOn: $camera.orthographic)
                            DSGlassPopoverButton("Field of View", systemImage: "camera.aperture", value: "35°") {
                                DSPopoverPanel {
                                    Text("Field of view controls")
                                        .font(DS.Font.body)
                                        .foregroundStyle(DS.Color.textPrimary)
                                }
                            }
                            DSGlassIconButton("Frame Model", systemImage: "viewfinder") {}
                            DSGlassMenuButton("Camera presets", systemImage: "cube") {
                                Button("Front") {}
                                Button("Top") {}
                            }
                        }
                    }
                }
            }
        }
    }
}

struct HUDCapsulePage: View {
    var body: some View {
        CatalogPageView(page: .hudCapsule) {
            StateGroup(
                title: "States",
                note: "HUD glass is non-interactive. Controls inside are borderless — no glass on glass."
            ) {
                StateRow("Dimensions") {
                    DSHUDCapsule(height: 30) {
                        Image(systemName: "cube")
                            .foregroundStyle(DS.Color.textSecondary)
                        Text("1.00 × 1.00 × 1.00 m")
                            .font(DS.Font.value)
                            .foregroundStyle(DS.Color.textPrimary)
                    }
                }
                StateRow("Playback", minHeight: 72) {
                    Live(PlaybackHUD()) { $hud in
                        DSHUDCapsule(height: 36, horizontalPadding: DS.Spacing.s) {
                            DSGlassIconButton(
                                $hud.wrappedValue.isPlaying ? "Pause" : "Play",
                                systemImage: $hud.wrappedValue.isPlaying ? "pause.fill" : "play.fill"
                            ) {
                                $hud.isPlaying.wrappedValue.toggle()
                            }
                            Slider(value: $hud.playhead)
                                .controlSize(.small)
                                .frame(width: 140)
                                .accessibilityLabel("Playhead")
                            Text("0:01.2 / 0:03.7")
                                .font(DS.Font.value)
                                .foregroundStyle(DS.Color.textSecondary)
                            DSGlassIslandDivider()
                            DSGlassMenuButton(
                                "Animation clip",
                                systemImage: "film",
                                style: .titled("Idle")
                            ) {
                                Button("Idle") {}
                                Button("Walk") {}
                            }
                        }
                    }
                }
                StateRow("Long readout") {
                    DSHUDCapsule {
                        Text("124.50 × 88.25 × 1,024.00 m")
                            .font(DS.Font.value)
                            .foregroundStyle(DS.Color.textPrimary)
                            .lineLimit(1)
                    }
                }
                StateRow("Empty") {
                    DSHUDCapsule {
                        Text("—")
                            .font(DS.Font.value)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }
            }
        }
    }
}

struct SwatchPickerPage: View {
    var body: some View {
        CatalogPageView(page: .swatchPicker) {
            StateGroup(title: "Selection") {
                StateRow("Checkerboard") {
                    Live(0) { $selection in
                        DSSwatchPicker("Backdrop", selection: $selection, swatches: CatalogSwatches.all)
                    }
                }
                StateRow("White") {
                    Live(1) { $selection in
                        DSSwatchPicker("Backdrop", selection: $selection, swatches: CatalogSwatches.all)
                    }
                }
                StateRow("Dark") {
                    Live(2) { $selection in
                        DSSwatchPicker("Backdrop", selection: $selection, swatches: CatalogSwatches.all)
                    }
                }
                StateRow("Disabled") {
                    Live(1) { $selection in
                        DSSwatchPicker("Backdrop", selection: $selection, swatches: CatalogSwatches.all)
                            .disabled(true)
                    }
                }
            }
        }
    }
}

struct CheckerboardPage: View {
    var body: some View {
        CatalogPageView(page: .checkerboard) {
            StateGroup(
                title: "States",
                note: "Fixed light grey on white in either appearance — it means transparent."
            ) {
                StateRow("Default cell") {
                    DSCheckerboard()
                        .frame(width: 120, height: 72)
                }
                StateRow("Large cell") {
                    DSCheckerboard(cell: 12)
                        .frame(width: 120, height: 72)
                }
                StateRow("Swatch clip") {
                    DSCheckerboard()
                        .frame(width: DS.Metrics.swatch, height: DS.Metrics.swatch)
                        .clipShape(.circle)
                }
            }
        }
    }
}

private struct IslandToggles {
    var off = false
    var on = true
}

private struct CameraToggles {
    var autoRotate = true
    var centered = true
    var orthographic = false
}

private struct PlaybackHUD {
    var isPlaying = false
    var playhead = 0.32
}

private enum CatalogSwatches {
    static let all: [DSSwatchPicker<Int>.Swatch] = [
        .init(id: 0, title: "Checkerboard", fill: .checkerboard),
        .init(id: 1, title: "White", fill: .color(DS.Color.Backdrop.white)),
        .init(id: 2, title: "Dark", fill: .color(DS.Color.Backdrop.dark))
    ]
}
