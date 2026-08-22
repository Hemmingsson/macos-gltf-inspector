import SwiftUI

/// Quick Look overlay fact list: value then dimmed noun, adjacent.
struct PreviewOverlayFacts: View {
    let facts: [PreviewStats.Row]
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(facts, id: \.label) { fact in
                HStack(spacing: 4) {
                    if !fact.value.isEmpty {
                        Text(fact.value)
                            .foregroundStyle(tint.opacity(0.85))
                    }
                    if !fact.label.isEmpty {
                        Text(fact.label)
                            .foregroundStyle(tint.opacity(0.4))
                    }
                }
            }
        }
        .font(.system(size: 11, weight: .regular).monospacedDigit())
    }
}
