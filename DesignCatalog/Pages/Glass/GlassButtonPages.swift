import DesignSystem
import SwiftUI

struct GlassToggleButtonPage: View {
    var body: some View {
        CatalogPageView(page: .glassToggleButton) {
            StateGroup(title: "States") {
                StateRow("Default") {
                    Live(false) { $on in
                        DSGlassToggleButton("Floor", systemImage: "circle.grid.cross", isOn: $on)
                    }
                }
                StateRow("On") {
                    Live(true) { $on in
                        DSGlassToggleButton("Floor", systemImage: "circle.grid.cross", isOn: $on)
                    }
                }
                StateRow("Disabled") {
                    Live(false) { $on in
                        DSGlassToggleButton("Unavailable", systemImage: "dot.scope", isOn: $on)
                            .disabled(true)
                    }
                }
                StateRow("Disabled · on") {
                    Live(true) { $on in
                        DSGlassToggleButton("Floor", systemImage: "circle.grid.cross", isOn: $on)
                            .disabled(true)
                    }
                }
                StateRow("Shortcut") {
                    Live(false) { $on in
                        DSGlassToggleButton(
                            "Auto-rotate",
                            systemImage: "arrow.trianglehead.counterclockwise.rotate.90",
                            isOn: $on,
                            shortcut: DS.Shortcuts.action(.autoRotate)
                        )
                    }
                }
            }

            StateGroup(
                title: "In an island",
                note: "Inside DSGlassIsland the toggle draws no glass of its own."
            ) {
                StateRow("Off and on") {
                    Live(IslandToggles()) { $toggles in
                        DSGlassIsland {
                            DSGlassToggleButton("Grid", systemImage: "grid", isOn: $toggles.off)
                            DSGlassToggleButton("Floor", systemImage: "circle.grid.cross", isOn: $toggles.on)
                        }
                    }
                }
            }
        }
    }
}

struct GlassIconButtonPage: View {
    var body: some View {
        CatalogPageView(page: .glassIconButton) {
            StateGroup(title: "States") {
                StateRow("Default") {
                    DSGlassIconButton(
                        "Frame Model",
                        systemImage: "viewfinder",
                        shortcut: DS.Shortcuts.action(.fit)
                    ) {}
                }
                StateRow("Engaged") {
                    DSGlassIconButton("Camera preset active", systemImage: "cube", isEngaged: true) {}
                }
                StateRow("Disabled") {
                    DSGlassIconButton("Share", systemImage: "square.and.arrow.up") {}
                        .disabled(true)
                }
                StateRow("Disabled · engaged") {
                    DSGlassIconButton("Camera preset active", systemImage: "cube", isEngaged: true) {}
                        .disabled(true)
                }
            }

            StateGroup(
                title: "In an island",
                note: "Inside DSGlassIsland the button draws no glass of its own."
            ) {
                StateRow("Rest and engaged") {
                    DSGlassIsland {
                        DSGlassIconButton("Play", systemImage: "play.fill") {}
                        DSGlassIconButton("Loop", systemImage: "repeat", isEngaged: true) {}
                    }
                }
            }
        }
    }
}

struct GlassMenuButtonPage: View {
    var body: some View {
        CatalogPageView(page: .glassMenuButton) {
            StateGroup(title: "Styles") {
                StateRow("Icon") {
                    DSGlassMenuButton("Camera presets", systemImage: "cube") {
                        presetMenu
                    }
                }
                StateRow("Icon · engaged") {
                    DSGlassMenuButton("Camera presets", systemImage: "cube", isEngaged: true) {
                        presetMenu
                    }
                }
                StateRow("Icon with chevron") {
                    DSGlassMenuButton("Open in", systemImage: "square.and.arrow.up", style: .iconWithChevron) {
                        Button("Finder") {}
                        Button("Blender") {}
                    }
                }
                StateRow("Titled") {
                    Live("Shaded") { $mode in
                        DSGlassMenuButton(
                            "View mode",
                            systemImage: "circle.lefthalf.filled",
                            style: .titled($mode.wrappedValue)
                        ) {
                            Picker("View mode", selection: $mode) {
                                Text("Shaded").tag("Shaded")
                                Text("Wireframe").tag("Wireframe")
                                Text("Ambient Occlusion").tag("Ambient Occlusion")
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        }
                    }
                }
                StateRow("Titled · engaged · long value") {
                    DSGlassMenuButton(
                        "View mode",
                        systemImage: "circle.lefthalf.filled",
                        style: .titled("Ambient Occlusion with a very long channel name"),
                        isEngaged: true
                    ) {
                        Button("Shaded") {}
                    }
                }
                StateRow("Disabled") {
                    DSGlassMenuButton("Camera presets", systemImage: "cube") {
                        presetMenu
                    }
                    .disabled(true)
                }
            }

            StateGroup(
                title: "In an island",
                note: "Inside DSGlassIsland the menu draws no glass of its own."
            ) {
                StateRow("Look-style island") {
                    DSGlassIsland {
                        DSGlassMenuButton(
                            "View mode",
                            systemImage: "cube",
                            style: .titled("Ambient Occlusion"),
                            isEngaged: true
                        ) {
                            Button("Shaded") {}
                        }
                        DSGlassIslandDivider()
                        DSGlassMenuButton("Lighting preset", systemImage: "sun.max", style: .iconWithChevron) {
                            Button("Studio") {}
                        }
                        DSGlassMenuButton("Presets", systemImage: "cube") {
                            presetMenu
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var presetMenu: some View {
        Button("Front") {}
        Button("Top") {}
        Button("Isometric") {}
    }
}

struct GlassPopoverButtonPage: View {
    var body: some View {
        CatalogPageView(page: .glassPopoverButton) {
            StateGroup(title: "States") {
                StateRow("Default") {
                    DSGlassPopoverButton("Field of View", systemImage: "camera.aperture", value: "35°") {
                        DSPopoverPanel {
                            Text("Field of view controls")
                                .font(DS.Font.body)
                                .foregroundStyle(DS.Color.textPrimary)
                        }
                    }
                }
                StateRow("Driven") {
                    Live(false) { $open in
                        HStack(spacing: DS.Spacing.m) {
                            DSGlassPopoverButton(
                                "Lighting",
                                systemImage: "sun.max",
                                isPresented: $open,
                                help: "Lighting — exposure, environment, lights"
                            ) {
                                DSPopoverPanel {
                                    Text("Lighting controls")
                                        .font(DS.Font.body)
                                        .foregroundStyle(DS.Color.textPrimary)
                                }
                            }
                            DSButton($open.wrappedValue ? "Close" : "Open", size: .small) {
                                $open.wrappedValue.toggle()
                            }
                        }
                    }
                }
                StateRow("Disabled") {
                    DSGlassPopoverButton("Lighting", systemImage: "sun.max") {
                        EmptyView()
                    }
                    .disabled(true)
                }
                StateRow("Body (stand-in)", note: "A real popover draws its own glass; open the live chip to compare.") {
                    PopoverStandIn {
                        DSPopoverPanel {
                            Text("Lighting controls")
                                .font(DS.Font.body)
                                .foregroundStyle(DS.Color.textPrimary)
                        }
                    }
                }
            }

            StateGroup(
                title: "In an island",
                note: "Inside DSGlassIsland the popover button draws no glass of its own."
            ) {
                StateRow("Look-style island") {
                    DSGlassIsland {
                        DSGlassMenuButton(
                            "View mode",
                            systemImage: "circle.lefthalf.filled",
                            style: .titled("Shaded")
                        ) {
                            Button("Shaded") {}
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
        }
    }
}

private struct IslandToggles {
    var off = false
    var on = true
}
