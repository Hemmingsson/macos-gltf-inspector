import Foundation

/// A sidebar group.
enum CatalogSection: String, CaseIterable, Identifiable {
    case tokens = "Tokens"
    case glass = "Controls · Glass"
    case controls = "Controls · Standard"
    case content = "Controls · Content"
    case composites = "Composites"

    var id: Self { self }

    var pages: [CatalogPage] {
        CatalogPage.allCases.filter { $0.section == self }
    }
}

/// Every page in the catalog. The raw value is the `-page` launch argument
/// (`./scripts/dev.sh catalog -page colors`).
enum CatalogPage: String, CaseIterable, Identifiable, Hashable {
    // Tokens
    case colors, typography, spacing, radii, glass, motion, shortcuts
    // Glass components
    case glassToggleButton, glassIconButton, glassMenuButton, glassPopoverButton
    case glassIsland, glassCluster, hudCapsule, swatchPicker, checkerboard
    // Standard controls
    case button, segmentedPicker, menuPicker, slider, popoverPanel
    // Content
    case chip, flowLayout, disclosureCard, documentCard, factRow, listRow
    case sectionHeader, statusBadge, statusView, typeIcon, valueCell, vectorRow
    // Composites
    case stageCluster, lookCluster, cameraCluster, lightingPopover, fieldOfViewPopover
    case playbackBar, sidebar, inspector

    var id: Self { self }

    var section: CatalogSection {
        switch self {
        case .colors, .typography, .spacing, .radii, .glass, .motion, .shortcuts:
            .tokens
        case .glassToggleButton, .glassIconButton, .glassMenuButton, .glassPopoverButton,
             .glassIsland, .glassCluster, .hudCapsule, .swatchPicker, .checkerboard:
            .glass
        case .button, .segmentedPicker, .menuPicker, .slider, .popoverPanel:
            .controls
        case .chip, .flowLayout, .disclosureCard, .documentCard, .factRow, .listRow,
             .sectionHeader, .statusBadge, .statusView, .typeIcon, .valueCell, .vectorRow:
            .content
        case .stageCluster, .lookCluster, .cameraCluster, .lightingPopover, .fieldOfViewPopover,
             .playbackBar, .sidebar, .inspector:
            .composites
        }
    }

    /// Sidebar and page title.
    var title: String {
        switch self {
        case .colors: "Colors"
        case .typography: "Typography"
        case .spacing: "Spacing & Metrics"
        case .radii: "Radii"
        case .glass: "Glass & Materials"
        case .motion: "Motion"
        case .shortcuts: "Shortcuts"
        case .glassToggleButton: "Glass Toggle Button"
        case .glassIconButton: "Glass Icon Button"
        case .glassMenuButton: "Glass Menu Button"
        case .glassPopoverButton: "Glass Popover Button"
        case .glassIsland: "Glass Island"
        case .glassCluster: "Glass Cluster"
        case .hudCapsule: "HUD Capsule"
        case .swatchPicker: "Swatch Picker"
        case .checkerboard: "Checkerboard"
        case .button: "Button"
        case .segmentedPicker: "Segmented Picker"
        case .menuPicker: "Menu Picker"
        case .slider: "Slider"
        case .popoverPanel: "Popover Panel"
        case .chip: "Chip"
        case .flowLayout: "Flow Layout"
        case .disclosureCard: "Disclosure Card"
        case .documentCard: "Document Card"
        case .factRow: "Fact Row"
        case .listRow: "List Row"
        case .sectionHeader: "Section Header"
        case .statusBadge: "Status Badge"
        case .statusView: "Status View"
        case .typeIcon: "Type Icon"
        case .valueCell: "Value Cell"
        case .vectorRow: "Vector Row"
        case .stageCluster: "Stage Cluster"
        case .lookCluster: "Look Cluster"
        case .cameraCluster: "Camera Cluster"
        case .lightingPopover: "Lighting Popover"
        case .fieldOfViewPopover: "Field of View Popover"
        case .playbackBar: "Playback Bar"
        case .sidebar: "Sidebar"
        case .inspector: "Inspector"
        }
    }

    /// The Swift symbol the page documents.
    var symbol: String {
        switch self {
        case .colors: "DS.Color"
        case .typography: "DS.Font"
        case .spacing: "DS.Spacing · DS.Metrics"
        case .radii: "DS.Radius"
        case .glass: "DS.Glass"
        case .motion: "DS.Motion"
        case .shortcuts: "DS.Shortcuts"
        case .glassToggleButton: "DSGlassToggleButton"
        case .glassIconButton: "DSGlassIconButton"
        case .glassMenuButton: "DSGlassMenuButton"
        case .glassPopoverButton: "DSGlassPopoverButton"
        case .glassIsland: "DSGlassIsland · DSGlassIslandDivider"
        case .glassCluster: "DSGlassCluster"
        case .hudCapsule: "DSHUDCapsule"
        case .swatchPicker: "DSSwatchPicker"
        case .checkerboard: "DSCheckerboard"
        case .button: "DSButton"
        case .segmentedPicker: "DSSegmentedPicker"
        case .menuPicker: "DSMenuPicker"
        case .slider: "DSSlider"
        case .popoverPanel: "DSPopoverPanel"
        case .chip: "DSChip"
        case .flowLayout: "DSFlowLayout"
        case .disclosureCard: "DSDisclosureCard"
        case .documentCard: "DSDocumentCard"
        case .factRow: "DSFactRow"
        case .listRow: "DSListRow"
        case .sectionHeader: "DSSectionHeader"
        case .statusBadge: "DSStatusBadge"
        case .statusView: "DSStatusView"
        case .typeIcon: "DSTypeIcon"
        case .valueCell: "DSValueCell"
        case .vectorRow: "DSVectorRow"
        case .stageCluster: "PreviewUI.StageCluster"
        case .lookCluster: "PreviewUI.LookCluster"
        case .cameraCluster: "PreviewUI.CameraCluster"
        case .lightingPopover: "PreviewUI.LightingPopover"
        case .fieldOfViewPopover: "PreviewUI.FieldOfViewPopover"
        case .playbackBar: "PreviewUI.PlaybackBar"
        case .sidebar: "PreviewUI.LeftSidebar"
        case .inspector: "PreviewUI.RightInspector"
        }
    }

    /// One line: what the item is for.
    var purpose: String {
        switch self {
        case .colors: "Colour roles: hierarchical text and fills, semantic surfaces, status, and the fixed meaning-colours."
        case .typography: "The type ramp. Every token is a system text style, so it follows the user's text size."
        case .spacing: "The 4-pt spacing scale and the fixed metrics of custom chrome."
        case .radii: "Corner radii for cells, rows, cards and floating panes."
        case .glass: "Liquid Glass variants for floating canvas chrome. Never place glass on glass."
        case .motion: "Chrome animation curves; every curve collapses to none under Reduce Motion."
        case .shortcuts: "The single keyboard-shortcut table shared by menus and in-window controls."
        case .glassToggleButton: "Icon-only on/off glass control (Floor, Auto-rotate, Center, Orthographic)."
        case .glassIconButton: "Icon-only glass action (Fit, Play, Open in…)."
        case .glassMenuButton: "Glass control that opens a menu: presets circle, view-mode chip, clip picker."
        case .glassPopoverButton: "Glass control that owns a popover (Lighting ▾, Field of View ▾)."
        case .glassIsland: "One capsule of glass holding several related controls; the only glass layer."
        case .glassCluster: "One floating group of islands sharing a GlassEffectContainer (Stage, Look, Camera)."
        case .hudCapsule: "Non-interactive glass readout: dimensions, playback bar."
        case .swatchPicker: "Radio group of backdrop swatches in one glass island."
        case .checkerboard: "The \"no backdrop\" pattern: fixed light grey on white in either appearance."
        case .button: "Standard push button in three emphases, backed by system button styles."
        case .segmentedPicker: "Two to four short mutually exclusive options, all visible."
        case .menuPicker: "One of several options behind a system pop-up button."
        case .slider: "Titled continuous value with a monospaced reading above a system slider."
        case .popoverPanel: "Plain content column of a control popover; the system draws the glass."
        case .chip: "Compact, non-interactive fact tag."
        case .flowLayout: "Left-to-right wrapping layout for chip rows."
        case .disclosureCard: "Expandable status card that opens onto a list of issues."
        case .documentCard: "The document's identity card at the top of the sidebar."
        case .factRow: "Read-only label · value fact with selectable value."
        case .listRow: "Outliner / list row: icon, title, subtitle, trailing accessory."
        case .sectionHeader: "Quiet uppercase section label with the header accessibility trait."
        case .statusBadge: "One-line status pill: valid, warning, error, pending."
        case .statusView: "Pane-filling empty / loading / failed state."
        case .typeIcon: "glTF role glyph tinted with its meaning-colour in a fixed box."
        case .valueCell: "Boxed, read-only, selectable numeric value."
        case .vectorRow: "Axis label and three value cells, read as one accessibility element."
        case .stageCluster: "How the scene is dressed: backdrop swatches and floor. Current PreviewUI vs DS target."
        case .lookCluster: "How the surface is shaded and lit: view mode │ lighting. Current PreviewUI vs DS target."
        case .cameraCluster: "Where you stand and how you move. Current PreviewUI vs DS target."
        case .lightingPopover: "Exposure, environment rotation and file-vs-studio lights."
        case .fieldOfViewPopover: "Vertical field of view; perspective only."
        case .playbackBar: "Bottom-centre animation transport, shown only when the file has animations."
        case .sidebar: "Left column: document card, outliner, file facts and honesty sections."
        case .inspector: "Right column: the selected node's sections."
        }
    }

    var systemImage: String {
        switch section {
        case .tokens:
            switch self {
            case .colors: "paintpalette"
            case .typography: "textformat"
            case .spacing: "ruler"
            case .radii: "square.on.circle"
            case .glass: "drop"
            case .motion: "wind"
            default: "command"
            }
        case .glass: "capsule"
        case .controls: "slider.horizontal.3"
        case .content: "text.alignleft"
        case .composites: "square.stack.3d.up"
        }
    }
}
