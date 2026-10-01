import DesignSystem
import PreviewUI
import SwiftUI

struct StageClusterPage: View {
    var body: some View {
        CatalogPageView(page: .stageCluster) {
            StateGroup(title: "States") {
                StateRow("Default") {
                    Live(MockViewportController()) { $viewport in
                        CatalogComposites.stageCluster(viewport: $viewport.wrappedValue)
                    }
                }
                StateRow("Floor off") {
                    Live(MockViewportController(showsFloor: false)) { $viewport in
                        CatalogComposites.stageCluster(viewport: $viewport.wrappedValue)
                    }
                }
            }
        }
    }
}

struct LookClusterPage: View {
    var body: some View {
        CatalogPageView(page: .lookCluster) {
            StateGroup(title: "States") {
                StateRow("Default") {
                    Live(MockViewportController()) { $viewport in
                        CatalogComposites.lookCluster(
                            availability: MockAvailability(),
                            viewport: $viewport.wrappedValue
                        )
                    }
                }
                StateRow("View mode · wireframe") {
                    Live(MockViewportController(viewMode: .wireframe)) { $viewport in
                        CatalogComposites.lookCluster(
                            availability: MockAvailability(),
                            viewport: $viewport.wrappedValue
                        )
                    }
                }
            }
        }
    }
}

struct CameraClusterPage: View {
    var body: some View {
        CatalogPageView(page: .cameraCluster) {
            StateGroup(title: "States") {
                StateRow("Default", minHeight: 72) {
                    Live(MockViewportController()) { $viewport in
                        CatalogComposites.cameraCluster(viewport: $viewport.wrappedValue)
                    }
                }
                StateRow("Orthographic", minHeight: 72) {
                    Live(MockViewportController(projection: .orthographic)) { $viewport in
                        CatalogComposites.cameraCluster(viewport: $viewport.wrappedValue)
                    }
                }
            }
        }
    }
}

struct LightingPopoverPage: View {
    var body: some View {
        CatalogPageView(page: .lightingPopover) {
            StateGroup(
                title: "States",
                note: "Live chip opens the real popover. The stand-in shows the body without a click."
            ) {
                StateRow("Default", alignment: .top, minHeight: 260) {
                    Live(MockViewportController()) { $viewport in
                        lightingPair(availability: MockAvailability(), viewport: $viewport.wrappedValue)
                    }
                }
                StateRow("File lights", alignment: .top, minHeight: 260) {
                    Live(
                        MockViewportController(
                            lighting: LightingSettings(
                                exposure: 0.5,
                                environmentRotationDegrees: 45,
                                usesFileLights: true,
                                usesStudioEnvironment: true
                            )
                        )
                    ) { $viewport in
                        lightingPair(
                            availability: MockAvailability(hasLights: true),
                            viewport: $viewport.wrappedValue
                        )
                    }
                }
            }
        }
    }

    private func lightingPair(
        availability: MockAvailability,
        viewport: MockViewportController
    ) -> some View {
        VStack(spacing: DS.Spacing.l) {
            CatalogComposites.lightingChip(availability: availability, viewport: viewport)
            PopoverStandIn {
                CatalogComposites.lightingControls(availability: availability, viewport: viewport)
            }
        }
    }
}

struct FieldOfViewPopoverPage: View {
    var body: some View {
        CatalogPageView(page: .fieldOfViewPopover) {
            StateGroup(
                title: "States",
                note: "In orthographic the slider is hidden. Live chip plus stand-in body."
            ) {
                StateRow("Perspective", alignment: .top, minHeight: 220) {
                    Live(MockViewportController()) { $viewport in
                        fovPair(viewport: $viewport.wrappedValue)
                    }
                }
                StateRow("Orthographic", alignment: .top, minHeight: 180) {
                    Live(MockViewportController(projection: .orthographic)) { $viewport in
                        fovPair(viewport: $viewport.wrappedValue)
                    }
                }
            }
        }
    }

    private func fovPair(viewport: MockViewportController) -> some View {
        VStack(spacing: DS.Spacing.l) {
            CatalogComposites.fieldOfViewChip(viewport: viewport)
            PopoverStandIn {
                CatalogComposites.fieldOfViewControls(viewport: viewport)
            }
        }
    }
}

struct PlaybackBarPage: View {
    var body: some View {
        CatalogPageView(page: .playbackBar) {
            StateGroup(title: "States") {
                StateRow("Paused") {
                    Live(MockPlaybackController(isPlaying: false, time: 0.8)) { $playback in
                        CatalogComposites.playbackBar(playback: $playback.wrappedValue)
                    }
                }
                StateRow("Playing") {
                    Live(MockPlaybackController(isPlaying: true, time: 0.8)) { $playback in
                        CatalogComposites.playbackBar(playback: $playback.wrappedValue)
                    }
                }
            }
        }
    }
}
