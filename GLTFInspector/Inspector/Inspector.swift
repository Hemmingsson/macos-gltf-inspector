import GLTFCore
import SwiftUI

/// Right column: what the file says about the selected outliner row. Sections are omitted when
/// the row's type has no such data (DESIGN.md: hide, don't disable).
struct Inspector: View {
    @Bindable var view: ViewState
    var document: GLTFDocument
    var selection: NodeID?
    var documentState: DocumentState
    /// File-wide validator report; the inspector shows the issues about the selection.
    var validation: ValidationResult
    var documentURL: URL?
    var onSelect: ((NodeID) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if documentState.isReady, let selection {
                IdentityRow(
                    name: document.displayName(of: selection),
                    kind: selection.kind,
                    systemImage: document.systemImage(for: selection),
                    assetImage: document.assetImage(for: selection),
                    swatchColor: document.swatchColor(for: selection),
                    subtitle: document.displayKindTitle(of: selection)
                )
                if view.selectedIDs.count > 1 {
                    DSFactRow("Selection", value: "\(view.selectedIDs.count) selected")
                        .padding(.horizontal, DS.Spacing.l)
                        .padding(.bottom, DS.Spacing.s)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        IssuesSection(issues: validation.issues(for: selection))
                        sections(for: selection)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, DS.Spacing.xl)
                }
                .focusSection()
            } else if documentState.isReady, document.scenes.indices.contains(view.sceneIndex) {
                // No selection: what the whole scene adds up to.
                ScrollView {
                    TotalsSection(title: "Scene Totals", totals: document.totals(ofScene: view.sceneIndex),
                                  textureCount: document.boundTextureCount, fileBytes: fileBytes)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .focusSection()
            } else {
                DocumentStatusView(state: documentState, placement: .inspector)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.paneFill, ignoresSafeAreaEdges: .all)
        // Same spot as the canvas's floating Open-in while the inspector is closed: on the
        // traffic-light line with the toolbar clusters.
        .overlay(alignment: .topTrailing) {
            if documentState.isReady {
                OpenInButton(documentURL: documentURL, view: view,
                             exportName: documentURL?.deletingPathExtension().lastPathComponent ?? "export")
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector")
    }

    @ViewBuilder
    private func sections(for id: NodeID) -> some View {
        let index = id.index
        switch id.kind {
        case .mesh, .empty, .camera, .light:
            if document.nodes.indices.contains(index) {
                let node = document.nodes[index]
                if node.isHiddenInFile {
                    DSFactRow("Visibility", value: "Hidden in file")
                        .padding(.horizontal, DS.Spacing.l)
                        .padding(.vertical, DS.Spacing.m)
                }
                TransformSection(node: node)
                if !node.children.isEmpty {
                    TotalsSection(title: "Subtree", totals: document.totals(ofSubtree: index))
                }
                if node.kind == .mesh || node.kind == .empty || node.kind == .camera {
                    ShapeSection(view: view, selection: id)
                }
                if node.kind == .mesh {
                    GeometrySection(node: node)
                    if !node.meshPrimitives.isEmpty {
                        PrimitivesSection(document: document, node: node, onSelect: onSelect)
                    }
                }
                if !node.jointOfSkinIndices.isEmpty {
                    JointOfSection(document: document, skinIndices: node.jointOfSkinIndices)
                }
                if node.kind == .camera, let camera = node.cameraIndex, document.cameras.indices.contains(camera) {
                    CameraSection(camera: document.cameras[camera])
                }
                if node.kind == .light, let light = node.lightIndex, document.lights.indices.contains(light) {
                    LightSection(light: document.lights[light])
                }
                sectionEnd
            }
        case .material where document.materials.indices.contains(index):
            MaterialSection(document: document, index: index, density: .full, onSelect: onSelect)
            sectionEnd
        case .skin where document.skins.indices.contains(index):
            SkinSection(skin: document.skins[index])
            sectionEnd
        case .animation where document.animations.indices.contains(index):
            AnimationSection(animation: document.animations[index])
            sectionEnd
        case .morph where document.morphs.indices.contains(index):
            MorphSection(
                morph: document.morphs[index],
                meshName: document.displayName(of: id),
                liveWeights: view.canvas.currentAnimationPose()?.meshWeights[document.morphs[index].meshIndex]
            )
            sectionEnd
        case .scene where document.scenes.indices.contains(index):
            VStack(alignment: .leading, spacing: 0) {
                InspectorSectionHeader("Scene")
                DSFactRow("Roots", value: "\(document.scenes[index].rootNodeIndices.count)")
                    .padding(.horizontal, DS.Spacing.l)
                    .padding(.bottom, DS.Spacing.m)
            }
            TotalsSection(title: "Totals", totals: document.totals(ofScene: index),
                          textureCount: document.boundTextureCount, fileBytes: fileBytes)
            sectionEnd
        default:
            EmptyView()
        }
    }

    private var fileBytes: Int64? {
        (try? documentURL?.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    private var sectionEnd: some View {
        DS.Color.separator
            .frame(height: DS.Metrics.hairline)
            .padding(.horizontal, DS.Spacing.l)
            .padding(.vertical, DS.Spacing.m)
    }
}
