import SwiftUI

/// One of several options behind a system pop-up button: `Picker` with `.menu` style.
///
/// Same layout contract as `DSSegmentedPicker`: a leading `LabeledContent` title with the pop-up
/// trailing at its natural width ("Tone mapping  [ACES ▾]"), or the control alone with
/// `labelVisibility: .hidden` (the material-variant picker in `DSDocumentCard`). Optional
/// selections work by listing `nil` as an option ("Default").
public struct DSMenuPicker<SelectionValue: Hashable>: View {
    private let title: String
    @Binding private var selection: SelectionValue
    private let options: [SelectionValue]
    private let optionTitle: (SelectionValue) -> String
    private let labelVisibility: Visibility

    /// - Parameters:
    ///   - title: Leading label (and accessibility label).
    ///   - selection: The chosen option.
    ///   - options: Menu items, in order.
    ///   - labelVisibility: `.hidden` drops the visible title; `.visible` / `.automatic` show it.
    ///   - optionTitle: The menu item title for an option.
    public init(
        _ title: String,
        selection: Binding<SelectionValue>,
        options: [SelectionValue],
        labelVisibility: Visibility = .visible,
        optionTitle: @escaping (SelectionValue) -> String
    ) {
        self.title = title
        self._selection = selection
        self.options = options
        self.optionTitle = optionTitle
        self.labelVisibility = labelVisibility
    }

    public var body: some View {
        DSPickerRow(
            title: title,
            selection: $selection,
            options: options,
            optionTitle: optionTitle,
            labelVisibility: labelVisibility,
            style: .menu
        )
    }
}

// MARK: - Previews

#Preview("Menu") {
    @Previewable @State var toneMapping = "ACES"
    @Previewable @State var variant: Int? = nil
    let variants = ["Wood", "Metal", "Paint"]
    DSContentPreviewStage {
        DSMenuPicker(
            "Tone mapping",
            selection: $toneMapping,
            options: ["None", "ACES", "AgX", "Khronos PBR Neutral"]
        ) { $0 }
        DSMenuPicker(
            "Material variant",
            selection: $variant,
            options: [nil] + variants.indices.map { Optional($0) },
            labelVisibility: .hidden
        ) { $0.map { variants[$0] } ?? "Default" }
            .controlSize(.small)
    }
}

#Preview("Menu long text, dark") {
    @Previewable @State var option = "A very long material variant name that will not fit"
    DSContentPreviewStage {
        DSMenuPicker(
            "Variant",
            selection: $option,
            options: [option, "Short"]
        ) { $0 }
    }
    .preferredColorScheme(.dark)
}
