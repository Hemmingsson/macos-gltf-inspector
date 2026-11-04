import SwiftUI

/// One of a few mutually exclusive options, all visible: a system segmented `Picker`.
///
/// With `labelVisibility` `.visible` (the default) the title sits leading as a `LabeledContent`
/// label and the control hugs the trailing edge at its natural width — the popover row
/// ("Lights  [Studio | File]"). With `.hidden` only the control shows; the title stays its
/// accessibility label. Use for two to four short options (Lights, Environment); for longer or
/// more numerous choices use `DSMenuPicker`.
struct DSSegmentedPicker<SelectionValue: Hashable>: View {
    private let title: String
    @Binding private var selection: SelectionValue
    private let options: [SelectionValue]
    private let optionTitle: (SelectionValue) -> String
    private let labelVisibility: Visibility

    /// - Parameters:
    ///   - title: Leading label (and accessibility label).
    ///   - selection: The chosen option.
    ///   - options: Segments, in order.
    ///   - labelVisibility: `.hidden` drops the visible title; `.visible` / `.automatic` show it.
    ///   - optionTitle: The segment title for an option.
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
            style: .segmented
        )
    }
}
