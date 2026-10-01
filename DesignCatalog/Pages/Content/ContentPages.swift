import DesignSystem
import SwiftUI

struct ChipPage: View {
    var body: some View {
        CatalogPageView(page: .chip) {
            StateGroup(title: "States") {
                StateRow("Default") {
                    DSChip("12 tris")
                }
                StateRow("With icon") {
                    DSChip("Base", systemImage: "photo")
                }
                StateRow("Long text") {
                    DSChip("KHR_materials_clearcoat_extension_with_a_very_long_name")
                }
                StateRow("Empty") {
                    DSChip("")
                }
                StateRow("Row") {
                    DSFlowLayout {
                        DSChip("12 tris")
                        DSChip("24 verts")
                        DSChip("1 UV set")
                        DSChip("Tangents")
                        DSChip("Vertex colors")
                        DSChip("Base", systemImage: "photo")
                    }
                }
            }
        }
    }
}

struct FlowLayoutPage: View {
    var body: some View {
        CatalogPageView(page: .flowLayout) {
            StateGroup(title: "States") {
                StateRow("Default wrap") {
                    DSFlowLayout {
                        ForEach(
                            ["12 tris", "24 verts", "1 UV set", "Tangents", "Vertex colors", "Skinned", "2 morph targets"],
                            id: \.self
                        ) {
                            DSChip($0)
                        }
                    }
                }
                StateRow("Narrow · custom spacing") {
                    DSFlowLayout(horizontalSpacing: DS.Spacing.xs, verticalSpacing: DS.Spacing.m) {
                        DSChip("Base")
                        DSChip("Normal")
                        DSChip("Metallic-roughness")
                        DSChip("Occlusion")
                    }
                    .frame(maxWidth: 160)
                }
                StateRow("Empty") {
                    DSFlowLayout {}
                        .frame(minHeight: 24)
                }
            }
        }
    }
}

struct DisclosureCardPage: View {
    var body: some View {
        CatalogPageView(page: .disclosureCard) {
            StateGroup(title: "States") {
                StateRow("Warning · expanded", alignment: .top, minHeight: 180) {
                    Live(true) { $open in
                        DSDisclosureCard("2 warnings", isExpanded: $open, messages: CatalogIssues.preview)
                            .frame(maxWidth: DS.Metrics.sidebarWidth)
                    }
                }
                StateRow("Error · collapsed", alignment: .top) {
                    Live(false) { $open in
                        DSDisclosureCard(
                            "1 error",
                            status: .error,
                            isExpanded: $open,
                            messages: [CatalogIssues.preview[0]]
                        )
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                    }
                }
                StateRow("Long title · expanded", alignment: .top, minHeight: 200) {
                    Live(true) { $open in
                        DSDisclosureCard(
                            "3 textures dropped · 2 extensions ignored by the RealityKit pipeline",
                            isExpanded: $open,
                            messages: CatalogIssues.preview
                        )
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                    }
                }
                StateRow("Empty messages", alignment: .top) {
                    Live(true) { $open in
                        DSDisclosureCard("No issues", status: .valid, isExpanded: $open, messages: [])
                            .frame(maxWidth: DS.Metrics.sidebarWidth)
                    }
                }
            }
        }
    }
}

struct DocumentCardPage: View {
    var body: some View {
        CatalogPageView(page: .documentCard) {
            StateGroup(title: "States") {
                StateRow("Title only") {
                    DSDocumentCard("cube.gltf")
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
                StateRow("With subtitle") {
                    DSDocumentCard("cube.gltf", subtitle: "Scene1")
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
                StateRow("Accessory picker") {
                    Live(Optional(1)) { $variant in
                        DSDocumentCard("Variants.glb", subtitle: "Scene") {
                            DSMenuPicker(
                                "Material variant",
                                selection: $variant,
                                options: [nil, 0, 1, 2],
                                labelVisibility: .hidden
                            ) { $0.map { ["Wood", "Metal", "Paint"][$0] } ?? "Default" }
                            .controlSize(.small)
                        }
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                    }
                }
                StateRow("Long text") {
                    DSDocumentCard(
                        "SciFi_Helmet_with_a_really_long_export_name_v12_final.glb",
                        subtitle: "A scene name that is also far too long for the sidebar"
                    )
                    .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
                StateRow("Empty") {
                    DSDocumentCard("")
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
            }
        }
    }
}

struct FactRowPage: View {
    var body: some View {
        CatalogPageView(page: .factRow) {
            StateGroup(title: "States") {
                StateRow("Default") {
                    VStack(spacing: DS.Spacing.s) {
                        DSFactRow("Triangles", value: 12.formatted())
                        DSFactRow("Meshes · Materials", value: "1 · 1")
                        DSFactRow("File size", value: "2 KB")
                    }
                    .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
                StateRow("Long value") {
                    DSFactRow("Used by", value: "Cube, Sphere, Cylinder, Cone, Torus, Suzanne")
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
                StateRow("Long label") {
                    DSFactRow("A label long enough to squeeze its value", value: "1,234,567")
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
                StateRow("Empty") {
                    DSFactRow("Empty", value: "")
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
            }
        }
    }
}

struct ListRowPage: View {
    var body: some View {
        CatalogPageView(page: .listRow) {
            StateGroup(title: "Custom selection") {
                StateRow("Default") {
                    DSListRow("Cube", role: .mesh)
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
                StateRow("Selected") {
                    DSListRow("Cube", role: .mesh, isSelected: true)
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
                StateRow("Muted · accessory") {
                    DSListRow("Hidden light", role: .light, isMuted: true) {
                        Image(systemName: "eye.slash")
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
                StateRow("Subtitle") {
                    DSListRow("Faces", subtitle: "PBR metallic-roughness", role: .material)
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
                StateRow("Long text") {
                    DSListRow(
                        "SM_Building_Facade_Window_Frame_Left.001",
                        subtitle: "A long subtitle that should truncate at the tail",
                        role: .mesh
                    ) {
                        Text("12")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
                StateRow("Empty title") {
                    DSListRow("", role: .empty)
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
            }

            StateGroup(title: "Native list") {
                StateRow("Sidebar list", alignment: .top, minHeight: 220) {
                    Live(Optional("Cube")) { $selection in
                        List(selection: $selection) {
                            Section {
                                DSListRow("Cube", role: .mesh).tag("Cube")
                                DSListRow("Camera", role: .camera).tag("Camera")
                                DSListRow("Hidden light", role: .light, isMuted: true) {
                                    Image(systemName: "eye.slash")
                                        .foregroundStyle(DS.Color.textSecondary)
                                }
                                .tag("Light")
                            } header: {
                                DSSectionHeader("Scene")
                            }
                        }
                        .listStyle(.sidebar)
                        .frame(width: DS.Metrics.sidebarWidth, height: 200)
                    }
                }
            }
        }
    }
}

struct SectionHeaderPage: View {
    var body: some View {
        CatalogPageView(page: .sectionHeader) {
            StateGroup(
                title: "Tones",
                note: "API tones are .secondary (default) and .tertiary — there is no .primary."
            ) {
                StateRow("Secondary") {
                    DSSectionHeader("Scene")
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
                StateRow("Tertiary") {
                    DSSectionHeader("Materials", tone: .tertiary)
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
                StateRow("With middot") {
                    DSSectionHeader("Transform · authored")
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
                StateRow("Long text") {
                    DSSectionHeader("This model, our pipeline — extensions we ignored and textures we dropped")
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
            }
        }
    }
}

private enum CatalogIssues {
    static let preview = [
        DSDisclosureMessage(id: "accessor", text: "Accessor min length must be a multiple of component size"),
        DSDisclosureMessage(id: "extension", text: "Unused extension KHR_materials_unlit")
    ]
}
