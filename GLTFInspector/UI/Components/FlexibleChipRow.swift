import SwiftUI

/// Left-to-right wrap of chips. How many fit depends on the pane width.
struct FlexibleChipRow: View {
    var items: [String]

    var body: some View {
        DSFlowLayout {
            ForEach(items, id: \.self) { title in
                DSChip(title)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
