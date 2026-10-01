import DesignSystem
import PreviewUI
import SwiftUI

struct SidebarPage: View {
    var body: some View {
        CatalogPageView(page: .sidebar) {
            StateGroup(title: "Document states") {
                ForEach(CatalogDocumentState.all, id: \.title) { row in
                    StateRow(row.title, alignment: .top, minHeight: row.minHeight) {
                        Live(row.selection) { $selection in
                            Live(MockViewportController()) { $viewport in
                                CatalogComposites.sidebar(
                                    model: FixtureSceneModel.cube,
                                    selection: $selection.wrappedValue,
                                    viewport: $viewport.wrappedValue,
                                    documentState: row.state
                                )
                            }
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
                ForEach(CatalogDocumentState.notReady, id: \.title) { row in
                    StateRow(row.title, alignment: .top, minHeight: row.minHeight) {
                        Live(row.selection) { $selection in
                            CatalogComposites.inspector(
                                selection: $selection.wrappedValue,
                                documentState: row.state,
                                openInMenu: AnyView(PreviewOpenInItems())
                            )
                        }
                    }
                }
            }
        }
    }
}

/// One document-state row: ready shows the cube mesh selection, the others select nothing.
private struct CatalogDocumentState {
    let title: String
    let state: ShellDocumentState

    static let notReady = [
        CatalogDocumentState(title: "Empty", state: .empty),
        CatalogDocumentState(title: "Loading", state: .loading),
        CatalogDocumentState(title: "Failed", state: .failed(ShellStatusCopy.invalidFileDetail))
    ]
    static let all = [CatalogDocumentState(title: "Ready", state: .ready)] + notReady

    var minHeight: CGFloat { state.isReady ? 420 : 280 }

    @MainActor
    var selection: MockSelectionModel {
        state.isReady ? MockSelectionModel() : MockSelectionModel(selected: nil, details: [])
    }
}
