import SwiftUI

/// The document's identity card at the top of the sidebar: file icon in the accent colour, file
/// name, scene subtitle, and an accessory slot (the material-variant `DSMenuPicker`).
///
/// The window has no title band, so this card is where the file names itself. The icon uses the
/// accent — not a type tint — because it stands for the document, not an outliner row. The title
/// truncates in the middle so the extension stays visible. The accessory sits below the title row
/// at the card's full width, so a long variant name never squeezes the file name.
///
/// Opaque `DS.Color.controlBackground` ground with a `DS.Color.separator` hairline at
/// `DS.Radius.large`. The icon and texts are one accessibility element; the accessory stays its
/// own control.
public struct DSDocumentCard<Accessory: View>: View {
    private let title: String
    private let subtitle: String?
    private let systemImage: String
    private let accessory: Accessory

    /// - Parameters:
    ///   - title: File name.
    ///   - subtitle: Scene name; `nil` collapses the line rather than printing a placeholder.
    ///   - systemImage: Document glyph. Defaults to `cube`.
    ///   - accessory: Extra control under the title row.
    public init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String = "cube",
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accessory = accessory()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous)

        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack(spacing: DS.Spacing.m) {
                Image(systemName: systemImage)
                    .font(DS.Font.body)
                    .imageScale(.large)
                    .foregroundStyle(DS.Color.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title)
                        .font(DS.Font.bodyEmphasized)
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let subtitle {
                        Text(subtitle)
                            .font(DS.Font.subheadline)
                            .foregroundStyle(DS.Color.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            accessory
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.vertical, DS.Spacing.m)
        .background(DS.Color.controlBackground, in: shape)
        .overlay(shape.strokeBorder(DS.Color.separator, lineWidth: DS.Metrics.cellStrokeWidth))
    }
}

public extension DSDocumentCard where Accessory == EmptyView {
    /// Card without an accessory.
    init(_ title: String, subtitle: String? = nil, systemImage: String = "cube") {
        self.init(title, subtitle: subtitle, systemImage: systemImage) { EmptyView() }
    }
}

// MARK: - Previews

#Preview("Document card") {
    @Previewable @State var variant: Int? = 1
    let variants = ["Wood", "Metal", "Paint"]
    DSContentPreviewStage(width: DS.Metrics.sidebarWidth) {
        DSDocumentCard("cube.gltf")
        DSDocumentCard("cube.gltf", subtitle: "Scene1")
        DSDocumentCard("Variants.glb", subtitle: "Scene") {
            DSMenuPicker(
                "Material variant",
                selection: $variant,
                options: [nil] + variants.indices.map { Optional($0) },
                labelVisibility: .hidden
            ) { $0.map { variants[$0] } ?? "Default" }
                .controlSize(.small)
        }
    }
}

#Preview("Document card long text, dark") {
    DSContentPreviewStage(width: DS.Metrics.sidebarWidth) {
        DSDocumentCard(
            "SciFi_Helmet_with_a_really_long_export_name_v12_final.glb",
            subtitle: "A scene name that is also far too long for the sidebar"
        )
        DSDocumentCard("")
    }
    .preferredColorScheme(.dark)
}
