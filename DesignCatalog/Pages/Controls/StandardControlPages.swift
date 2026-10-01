import DesignSystem
import SwiftUI

struct ButtonPage: View {
    var body: some View {
        CatalogPageView(page: .button) {
            StateGroup(title: "Variants") {
                StateRow("Bordered") {
                    DSButton("Reset") {}
                }
                StateRow("Prominent") {
                    DSButton("Use Perspective", variant: .prominent) {}
                }
                StateRow("Borderless") {
                    DSButton("Show", systemImage: "eye", variant: .borderless) {}
                }
                StateRow("Borderless · icon only") {
                    DSButton("Show", systemImage: "eye", variant: .borderless) {}
                        .labelStyle(.iconOnly)
                }
                StateRow("Destructive") {
                    DSButton("Remove", role: .destructive) {}
                }
            }

            StateGroup(title: "Size") {
                StateRow("Regular and small") {
                    HStack(spacing: DS.Spacing.m) {
                        DSButton("Reset") {}
                        DSButton("Reset", size: .small) {}
                        DSButton("Use Perspective", variant: .prominent, size: .small) {}
                    }
                }
            }

            StateGroup(title: "Edge states") {
                StateRow("Disabled") {
                    DSButton("Disabled") {}
                        .disabled(true)
                }
                StateRow("Long text") {
                    DSButton("Reset field of view to the default 35°", size: .small) {}
                }
            }
        }
    }
}

struct SegmentedPickerPage: View {
    var body: some View {
        CatalogPageView(page: .segmentedPicker) {
            StateGroup(title: "States") {
                StateRow("Default") {
                    Live(false) { $usesFileLights in
                        DSSegmentedPicker("Lights", selection: $usesFileLights, options: [false, true]) {
                            $0 ? "File" : "Studio"
                        }
                    }
                }
                StateRow("Three options") {
                    Live("Studio") { $environment in
                        DSSegmentedPicker(
                            "Environment",
                            selection: $environment,
                            options: ["Studio", "Neutral", "Outdoor"]
                        ) { $0 }
                    }
                }
                StateRow("Hidden label") {
                    Live(false) { $usesFileLights in
                        DSSegmentedPicker(
                            "Lights",
                            selection: $usesFileLights,
                            options: [false, true],
                            labelVisibility: .hidden
                        ) { $0 ? "File" : "Studio" }
                    }
                }
                StateRow("Long text") {
                    Live(0) { $choice in
                        DSSegmentedPicker(
                            "Environment lighting source",
                            selection: $choice,
                            options: [0, 1]
                        ) { $0 == 0 ? "Studio" : "Embedded in file" }
                        .controlSize(.small)
                    }
                }
                StateRow("Disabled") {
                    Live(false) { $usesFileLights in
                        DSSegmentedPicker("Lights", selection: $usesFileLights, options: [false, true]) {
                            $0 ? "File" : "Studio"
                        }
                        .disabled(true)
                    }
                }
            }
        }
    }
}

struct MenuPickerPage: View {
    var body: some View {
        CatalogPageView(page: .menuPicker) {
            StateGroup(title: "States") {
                StateRow("Default") {
                    Live("ACES") { $toneMapping in
                        DSMenuPicker(
                            "Tone mapping",
                            selection: $toneMapping,
                            options: ["None", "ACES", "AgX", "Khronos PBR Neutral"]
                        ) { $0 }
                    }
                }
                StateRow("Optional · hidden label") {
                    Live(Optional<Int>.none) { $variant in
                        DSMenuPicker(
                            "Material variant",
                            selection: $variant,
                            options: [nil, 0, 1, 2],
                            labelVisibility: .hidden
                        ) { $0.map { ["Wood", "Metal", "Paint"][$0] } ?? "Default" }
                        .controlSize(.small)
                    }
                }
                StateRow("Long text") {
                    Live("A very long material variant name that will not fit") { $option in
                        DSMenuPicker(
                            "Variant",
                            selection: $option,
                            options: [
                                "A very long material variant name that will not fit",
                                "Short"
                            ]
                        ) { $0 }
                    }
                }
                StateRow("Disabled") {
                    Live("ACES") { $toneMapping in
                        DSMenuPicker(
                            "Tone mapping",
                            selection: $toneMapping,
                            options: ["None", "ACES"]
                        ) { $0 }
                        .disabled(true)
                    }
                }
            }
        }
    }
}

struct SliderPage: View {
    var body: some View {
        CatalogPageView(page: .slider) {
            StateGroup(title: "States") {
                StateRow("Neutral rest (exposure)", minHeight: 120) {
                    Live(0.5) { $exposure in
                        DSSlider("Exposure", value: $exposure, in: -3...3, step: 0.1, neutralValue: 0) {
                            $0.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + " EV"
                        }
                    }
                }
                StateRow("No neutral (environment)", minHeight: 120) {
                    Live(120.0) { $rotation in
                        DSSlider("Environment", value: $rotation, in: 0...360, step: 1) {
                            $0.formatted(.number.precision(.fractionLength(0))) + "°"
                        }
                    }
                }
                StateRow("Fixed reading · small", minHeight: 120) {
                    Live(35.0) { $fov in
                        DSSlider("Field of View", value: $fov, in: 15...90, step: 1, reading: "35°")
                            .controlSize(.small)
                    }
                }
                StateRow("Long title", minHeight: 120) {
                    Live(35.0) { $fov in
                        DSSlider(
                            "Vertical field of view for the perspective camera",
                            value: $fov,
                            in: 15...90,
                            step: 1
                        ) { $0.formatted(.number.precision(.fractionLength(0))) + "°" }
                    }
                }
                StateRow("Disabled", minHeight: 120) {
                    Live(0.0) { $exposure in
                        DSSlider("Exposure", value: $exposure, in: -3...3, step: 0.1, neutralValue: 0) {
                            $0.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + " EV"
                        }
                        .disabled(true)
                    }
                }
            }
        }
    }
}

struct PopoverPanelPage: View {
    var body: some View {
        CatalogPageView(page: .popoverPanel) {
            StateGroup(
                title: "Inline body",
                note: "The panel is plain. A real popover draws the glass; the stand-in is for judging the body."
            ) {
                StateRow("Lighting body", minHeight: 240) {
                    Live(LightingPanel()) { $panel in
                        PopoverStandIn {
                            DSPopoverPanel {
                                DSSlider(
                                    "Exposure",
                                    value: $panel.exposure,
                                    in: -3...3,
                                    step: 0.1,
                                    neutralValue: 0
                                ) {
                                    $0.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + " EV"
                                }
                                DSSlider("Environment", value: $panel.rotation, in: 0...360, step: 1) {
                                    $0.formatted(.number.precision(.fractionLength(0))) + "°"
                                }
                                DSSegmentedPicker(
                                    "Lights",
                                    selection: $panel.usesFileLights,
                                    options: [false, true]
                                ) { $0 ? "File" : "Studio" }
                            }
                        }
                    }
                }
                StateRow("FoV body", minHeight: 180) {
                    Live(35.0) { $fov in
                        PopoverStandIn {
                            DSPopoverPanel {
                                DSSlider("Field of View", value: $fov, in: 15...90, step: 1) {
                                    $0.formatted(.number.precision(.fractionLength(0))) + "°"
                                }
                                HStack {
                                    Spacer()
                                    DSButton("Reset", size: .small) { $fov.wrappedValue = 35 }
                                }
                            }
                        }
                    }
                }
                StateRow("Empty", minHeight: 88) {
                    PopoverStandIn {
                        DSPopoverPanel {
                            EmptyView()
                        }
                    }
                }
                StateRow("Live chip") {
                    Live(false) { $open in
                        DSButton("Lighting", size: .small) { $open.wrappedValue.toggle() }
                            .popover(isPresented: $open, arrowEdge: .bottom) {
                                Live(0.5) { $exposure in
                                    DSPopoverPanel {
                                        DSSlider(
                                            "Exposure",
                                            value: $exposure,
                                            in: -3...3,
                                            step: 0.1,
                                            neutralValue: 0
                                        ) {
                                            $0.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))
                                                + " EV"
                                        }
                                    }
                                }
                            }
                    }
                }
            }
        }
    }
}

private struct LightingPanel {
    var exposure = 0.5
    var rotation = 120.0
    var usesFileLights = false
}
