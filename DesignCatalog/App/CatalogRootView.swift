import DesignSystem
import SwiftUI

/// Sidebar of pages, detail per page, and the catalog toolbar (backdrop filter, appearance, text
/// size). The toolbar settings apply to the detail only.
struct CatalogRootView: View {
    @State private var selection: CatalogPage? = CatalogLaunchOptions.page ?? .colors
    @State private var appearance: CatalogAppearance = CatalogLaunchOptions.appearance
    @State private var backdrop: CatalogBackdrop = CatalogLaunchOptions.backdrop
    @State private var typeSize: DynamicTypeSize = .large

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(CatalogSection.allCases) { section in
                    Section(section.rawValue) {
                        ForEach(section.pages) { page in
                            Label(page.title, systemImage: page.systemImage)
                                .tag(page)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            detail
                .environment(\.catalogBackdrop, backdrop)
                .dynamicTypeSize(typeSize)
                .preferredColorScheme(appearance.colorScheme)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Backdrop", selection: $backdrop) {
                    ForEach(CatalogBackdrop.allCases) { Text($0.title).tag($0) }
                }
                .help("Backdrop")

                Picker("Appearance", selection: $appearance) {
                    ForEach(CatalogAppearance.allCases) { Text($0.title).tag($0) }
                }
                .help("Appearance")

                Picker("Text Size", selection: $typeSize) {
                    ForEach(DynamicTypeSize.allCases, id: \.self) { Text($0.catalogTitle).tag($0) }
                }
                .help("Text size (dynamicTypeSize)")
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selection {
            CatalogDetail(page: selection)
                .navigationTitle(selection.title)
                .navigationSubtitle(selection.symbol)
        } else {
            DSStatusView.empty("Pick a page", systemImage: "sidebar.left")
        }
    }
}

/// Routes a page to its view.
private struct CatalogDetail: View {
    let page: CatalogPage

    var body: some View {
        switch page {
        case .colors: ColorsPage()
        case .typography: TypographyPage()
        case .spacing: SpacingPage()
        case .radii: RadiiPage()
        case .glass: GlassTokensPage()
        case .motion: MotionPage()
        case .shortcuts: ShortcutsPage()
        case .glassToggleButton: GlassToggleButtonPage()
        case .glassIconButton: GlassIconButtonPage()
        case .glassMenuButton: GlassMenuButtonPage()
        case .glassPopoverButton: GlassPopoverButtonPage()
        case .glassIsland: GlassIslandPage()
        case .glassCluster: GlassClusterPage()
        case .hudCapsule: HUDCapsulePage()
        case .swatchPicker: SwatchPickerPage()
        case .checkerboard: CheckerboardPage()
        case .button: ButtonPage()
        case .segmentedPicker: SegmentedPickerPage()
        case .menuPicker: MenuPickerPage()
        case .slider: SliderPage()
        case .popoverPanel: PopoverPanelPage()
        case .chip: ChipPage()
        case .flowLayout: FlowLayoutPage()
        case .disclosureCard: DisclosureCardPage()
        case .documentCard: DocumentCardPage()
        case .factRow: FactRowPage()
        case .listRow: ListRowPage()
        case .sectionHeader: SectionHeaderPage()
        case .statusBadge: StatusBadgePage()
        case .statusView: StatusViewPage()
        case .typeIcon: TypeIconPage()
        case .valueCell: ValueCellPage()
        case .vectorRow: VectorRowPage()
        case .stageCluster: StageClusterPage()
        case .lookCluster: LookClusterPage()
        case .cameraCluster: CameraClusterPage()
        case .lightingPopover: LightingPopoverPage()
        case .fieldOfViewPopover: FieldOfViewPopoverPage()
        case .playbackBar: PlaybackBarPage()
        case .sidebar: SidebarPage()
        case .inspector: InspectorPage()
        }
    }
}
