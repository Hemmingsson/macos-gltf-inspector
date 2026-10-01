import SwiftUI

/// An outliner / list row: leading icon, title (middle-truncated, so "Cube.001" keeps its suffix),
/// optional subtitle, and a trailing accessory (visibility eye, count).
///
/// Built for a native `List(selection:)`: the row draws **no** selection of its own — the list's
/// highlight and emphasised text styles apply because every colour is hierarchical. For a custom
/// row that cannot use native selection, pass `isSelected: true`: the row paints
/// `DS.Color.selectionFill` (outset behind it, so layout does not shift) and switches the title to
/// `DS.Color.selectionText`. `isMuted` renders a hidden node's title in `.tertiary` rather than
/// dimming the row with opacity.
public struct DSListRow<Icon: View, Accessory: View>: View {
    private let title: String
    private let subtitle: String?
    private let isSelected: Bool
    private let isMuted: Bool
    private let icon: Icon
    private let accessory: Accessory

    public init(
        _ title: String,
        subtitle: String? = nil,
        isSelected: Bool = false,
        isMuted: Bool = false,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.isMuted = isMuted
        self.icon = icon()
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: DS.Spacing.m) {
            icon
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .font(DS.Font.body)
                    .foregroundStyle(titleStyle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Font.subheadline)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: DS.Spacing.m)
            accessory
        }
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous)
                    .fill(DS.Color.selectionFill)
                    .padding(.horizontal, -DS.Spacing.s)
                    .padding(.vertical, -DS.Spacing.xs)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var titleStyle: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(DS.Color.selectionText) }
        if isMuted { return AnyShapeStyle(DS.Color.textTertiary) }
        return AnyShapeStyle(DS.Color.textPrimary)
    }
}

public extension DSListRow where Accessory == EmptyView {
    /// Row without a trailing accessory.
    init(
        _ title: String,
        subtitle: String? = nil,
        isSelected: Bool = false,
        isMuted: Bool = false,
        @ViewBuilder icon: () -> Icon
    ) {
        self.init(title, subtitle: subtitle, isSelected: isSelected, isMuted: isMuted, icon: icon) {
            EmptyView()
        }
    }
}

public extension DSListRow where Icon == DSTypeIcon {
    /// Row whose icon is the glTF type glyph; the glyph follows `isSelected`.
    init(
        _ title: String,
        subtitle: String? = nil,
        role: DSTypeRole,
        isSelected: Bool = false,
        isMuted: Bool = false,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.init(
            title,
            subtitle: subtitle,
            isSelected: isSelected,
            isMuted: isMuted,
            icon: { DSTypeIcon(role, isSelected: isSelected) },
            accessory: accessory
        )
    }
}

public extension DSListRow where Icon == DSTypeIcon, Accessory == EmptyView {
    /// Type-glyph row without an accessory.
    init(
        _ title: String,
        subtitle: String? = nil,
        role: DSTypeRole,
        isSelected: Bool = false,
        isMuted: Bool = false
    ) {
        self.init(title, subtitle: subtitle, role: role, isSelected: isSelected, isMuted: isMuted) {
            EmptyView()
        }
    }
}

// MARK: - Previews

#Preview("List row, native list") {
    @Previewable @State var selection: String? = "Cube"
    List(selection: $selection) {
        Section {
            DSListRow("Cube", role: .mesh).tag("Cube")
            DSListRow("Camera", role: .camera).tag("Camera")
            DSListRow("Hidden light", role: .light, isMuted: true) {
                Image(systemName: "eye.slash").foregroundStyle(DS.Color.textSecondary)
            }
            .tag("Light")
        } header: {
            DSSectionHeader("Scene")
        }
        Section {
            DSListRow("Faces", role: .material).tag("Faces")
        } header: {
            DSSectionHeader("Materials")
        }
    }
    .listStyle(.sidebar)
    .frame(width: DS.Metrics.sidebarWidth, height: 280)
}

#Preview("List row, custom selection") {
    DSContentPreviewStage(width: DS.Metrics.sidebarWidth) {
        DSListRow("Cube", role: .mesh, isSelected: true)
        DSListRow("Faces", subtitle: "PBR metallic-roughness", role: .material)
        DSListRow("Hidden", role: .mesh, isMuted: true)
    }
}

#Preview("List row long text, dark") {
    DSContentPreviewStage(width: DS.Metrics.sidebarWidth) {
        DSListRow(
            "SM_Building_Facade_Window_Frame_Left.001",
            subtitle: "A long subtitle that should truncate at the tail",
            role: .mesh
        ) {
            Text("12").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
        }
        DSListRow("SM_Building_Facade_Window_Frame_Left.001", role: .animation, isSelected: true)
        DSListRow("", role: .empty)
    }
    .preferredColorScheme(.dark)
}
