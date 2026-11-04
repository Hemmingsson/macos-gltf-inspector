import SwiftUI

/// One of several options behind a system pop-up button: `Picker` with `.menu` style.
///
/// Same layout contract as `DSSegmentedPicker`: a leading `LabeledContent` title with the pop-up
/// trailing at its natural width ("Tone mapping  [ACES ▾]"), or the control alone with
/// `labelVisibility: .hidden` (the material-variant picker in `DSDocumentCard`). Optional
/// selections work by listing `nil` as an option ("Default").
struct DSMenuPicker<SelectionValue: Hashable>: View {
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
    init(
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

    var body: some View {
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
