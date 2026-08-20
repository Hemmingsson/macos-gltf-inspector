import SwiftUI

/// Shared QL / host fact list: value then dimmed noun.
struct PreviewOverlayFacts: View {
    let facts: [PreviewStats.Row]
    var tint: Color
    /// Host sidebar spreads value left and noun right; Quick Look keeps them adjacent.
    var spread: Bool = false

    var body: some View {
        VStack(alignment: spread ? .center : .leading, spacing: 2) {
            ForEach(facts, id: \.label) { fact in
                HStack(spacing: spread ? 8 : 4) {
                    if !fact.value.isEmpty {
                        Text(fact.value)
                            .foregroundStyle(tint.opacity(0.85))
                    }
                    if spread {
                        Spacer(minLength: 8)
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
