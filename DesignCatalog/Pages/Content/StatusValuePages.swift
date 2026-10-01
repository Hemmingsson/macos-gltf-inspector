import DesignSystem
import SwiftUI

struct StatusBadgePage: View {
    var body: some View {
        CatalogPageView(page: .statusBadge) {
            StateGroup(title: "Statuses") {
                StateRow("Valid") {
                    DSStatusBadge("Valid glTF 2.0", status: .valid)
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
                StateRow("Pending") {
                    DSStatusBadge("Checking validation…", status: .pending)
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
                StateRow("Warning") {
                    DSStatusBadge("2 warnings", status: .warning)
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
                StateRow("Error") {
                    DSStatusBadge("Invalid file", status: .error)
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
                StateRow("Long text") {
                    DSStatusBadge("3 errors · 12 warnings in the embedded validator report", status: .error)
                        .frame(maxWidth: DS.Metrics.sidebarWidth)
                }
            }
        }
    }
}

struct StatusViewPage: View {
    var body: some View {
        CatalogPageView(page: .statusView) {
            StateGroup(title: "Phases") {
                StateRow("Empty", alignment: .top, minHeight: 200) {
                    DSStatusView.empty(
                        "Open a glTF file",
                        systemImage: "cube",
                        message: "Drop a .glb or .gltf here."
                    )
                    .frame(width: 240, height: 180)
                }
                StateRow("Empty · no message", alignment: .top, minHeight: 200) {
                    DSStatusView.empty("Nothing to inspect", systemImage: "sidebar.right")
                        .frame(width: 240, height: 180)
                }
                StateRow("Loading", alignment: .top, minHeight: 200) {
                    DSStatusView.loading("Loading model…")
                        .frame(width: 240, height: 180)
                }
                StateRow("Failed", alignment: .top, minHeight: 200) {
                    DSStatusView.failed("Couldn't open file", message: "The file is not valid glTF 2.0.")
                        .frame(width: 240, height: 180)
                }
                StateRow("Failed · long message", alignment: .top, minHeight: 220) {
                    DSStatusView.failed(
                        "Couldn't open file",
                        message: "The buffer view at index 3 points past the end of the binary chunk, so the mesh data cannot be read."
                    )
                    .frame(width: DS.Metrics.sidebarWidth, height: 200)
                }
            }
        }
    }
}

struct TypeIconPage: View {
    var body: some View {
        CatalogPageView(page: .typeIcon) {
            StateGroup(title: "Roles") {
                StateRow("Default") {
                    roleColumn(isSelected: false)
                }
                StateRow("Selected") {
                    roleColumn(isSelected: true)
                }
            }
        }
    }

    private func roleColumn(isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            ForEach(DSTypeRole.allCases, id: \.self) { role in
                HStack(spacing: DS.Spacing.m) {
                    DSTypeIcon(role, isSelected: isSelected)
                    Text(role.rawValue.capitalized)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textPrimary)
                }
            }
        }
    }
}

struct ValueCellPage: View {
    var body: some View {
        CatalogPageView(page: .valueCell) {
            StateGroup(title: "States") {
                StateRow("Default") {
                    HStack(spacing: DS.Spacing.s) {
                        DSValueCell("0.00")
                        DSValueCell("0.50")
                        DSValueCell("0.00")
                    }
                    .frame(maxWidth: 240)
                }
                StateRow("Degrees") {
                    HStack(spacing: DS.Spacing.s) {
                        DSValueCell("90.00°")
                        DSValueCell("-0.00°")
                        DSValueCell("180.00°")
                    }
                    .frame(maxWidth: 240)
                }
                StateRow("Narrow · long value") {
                    DSValueCell("-12345.678°")
                        .frame(width: 60)
                }
                StateRow("Empty") {
                    DSValueCell("")
                        .frame(maxWidth: 80)
                }
            }
        }
    }
}

struct VectorRowPage: View {
    var body: some View {
        CatalogPageView(page: .vectorRow) {
            StateGroup(title: "States") {
                StateRow("Transform", alignment: .top) {
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        DSVectorRow("Position", shortTitle: "P", x: "0.00", y: "0.50", z: "0.00")
                        DSVectorRow("Rotation", shortTitle: "R", x: "0.00°", y: "90.00°", z: "0.00°")
                        DSVectorRow("Scale", shortTitle: "S", x: "1.00", y: "1.00", z: "1.00")
                    }
                    .frame(maxWidth: 320)
                }
                StateRow("Full titles · overflow") {
                    DSVectorRow("Position", x: "-12345.67", y: "0.50", z: "99999.99")
                        .frame(maxWidth: 320)
                }
                StateRow("Empty cells") {
                    DSVectorRow("Scale", shortTitle: "S", x: "", y: "", z: "")
                        .frame(maxWidth: 320)
                }
            }
        }
    }
}
