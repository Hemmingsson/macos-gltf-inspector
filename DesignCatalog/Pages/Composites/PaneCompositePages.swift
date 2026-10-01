import DesignSystem
import PreviewUI
import SwiftUI

struct SidebarPage: View {
    var body: some View {
        CatalogPageView(page: .sidebar) {
            StateGroup(title: "Document states") {
                StateRow("Ready", alignment: .top, minHeight: 420) {
                    Live(MockSelectionModel()) { $selection in
                        Live(MockViewportController()) { $viewport in
                            CatalogComposites.sidebar(
                                model: FixtureSceneModel.cube,
                                selection: $selection.wrappedValue,
                                viewport: $viewport.wrappedValue,
                                documentState: .ready
                            )
                        }
                    }
                }
                StateRow("Empty", alignment: .top, minHeight: 280) {
                    Live(MockSelectionModel(selected: nil, details: [])) { $selection in
                        Live(MockViewportController()) { $viewport in
                            CatalogComposites.sidebar(
                                model: FixtureSceneModel.cube,
                                selection: $selection.wrappedValue,
                                viewport: $viewport.wrappedValue,
                                documentState: .empty
                            )
                        }
                    }
                }
                StateRow("Loading", alignment: .top, minHeight: 280) {
                    Live(MockSelectionModel(selected: nil, details: [])) { $selection in
                        Live(MockViewportController()) { $viewport in
                            CatalogComposites.sidebar(
                                model: FixtureSceneModel.cube,
                                selection: $selection.wrappedValue,
                                viewport: $viewport.wrappedValue,
                                documentState: .loading
                            )
                        }
                    }
                }
                StateRow("Failed", alignment: .top, minHeight: 280) {
                    Live(MockSelectionModel(selected: nil, details: [])) { $selection in
                        Live(MockViewportController()) { $viewport in
                            CatalogComposites.sidebar(
                                model: FixtureSceneModel.cube,
                                selection: $selection.wrappedValue,
                                viewport: $viewport.wrappedValue,
                                documentState: .failed("The file is not valid glTF 2.0.")
                            )
                        }
                    }
                }
            }
        }
    }
}

struct InspectorPage: View {
    var body: some View {
        CatalogPageView(page: .inspector) {
            StateGroup(title: "Selections") {
                StateRow("Mesh", alignment: .top, minHeight: 420) {
                    Live(MockSelectionModel()) { $selection in
                        CatalogComposites.inspector(
                            selection: $selection.wrappedValue,
                            documentState: .ready,
                            openInMenu: AnyView(PreviewOpenInItems())
                        )
                    }
                }
                StateRow("Material", alignment: .top, minHeight: 420) {
                    Live(
                        MockSelectionModel(
                            selected: NodeDetailFixtures.material.id,
                            details: [NodeDetailFixtures.material]
                        )
                    ) { $selection in
                        CatalogComposites.inspector(
                            selection: $selection.wrappedValue,
                            documentState: .ready,
                            openInMenu: AnyView(PreviewOpenInItems())
                        )
                    }
                }
                StateRow("Morph", alignment: .top, minHeight: 420) {
                    Live(
                        MockSelectionModel(
                            selected: NodeDetailFixtures.morph.id,
                            details: [NodeDetailFixtures.morph]
                        )
                    ) { $selection in
                        CatalogComposites.inspector(
                            selection: $selection.wrappedValue,
                            documentState: .ready,
                            openInMenu: AnyView(PreviewOpenInItems()),
                            morphTargets: MorphFixtures.faceControls
                        )
                    }
                }
            }

            StateGroup(title: "Document states") {
                StateRow("Empty", alignment: .top, minHeight: 280) {
                    Live(MockSelectionModel(selected: nil, details: [])) { $selection in
                        CatalogComposites.inspector(
                            selection: $selection.wrappedValue,
                            documentState: .empty,
                            openInMenu: AnyView(PreviewOpenInItems())
                        )
                    }
                }
                StateRow("Loading", alignment: .top, minHeight: 280) {
                    Live(MockSelectionModel(selected: nil, details: [])) { $selection in
                        CatalogComposites.inspector(
                            selection: $selection.wrappedValue,
                            documentState: .loading,
                            openInMenu: AnyView(PreviewOpenInItems())
                        )
                    }
                }
                StateRow("Failed", alignment: .top, minHeight: 280) {
                    Live(MockSelectionModel(selected: nil, details: [])) { $selection in
                        CatalogComposites.inspector(
                            selection: $selection.wrappedValue,
                            documentState: .failed("The file is not valid glTF 2.0."),
                            openInMenu: AnyView(PreviewOpenInItems())
                        )
                    }
                }
            }
        }
    }
}
