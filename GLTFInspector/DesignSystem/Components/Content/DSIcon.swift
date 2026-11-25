import AppKit
import SwiftUI

/// A template glyph from the Inspector catalog, with a system symbol fallback.
struct DSIcon: View {
    enum Source: Equatable {
        /// Asset name in `InspectorIcons.xcassets`.
        case catalog(String)
        /// SF Symbol name.
        case system(String)
    }

    private let source: Source
    private let font: Font

    @ScaledMetric(relativeTo: .body) private var side = DS.Metrics.typeIcon

    /// - Parameters:
    ///   - name: Inspector asset name, or nil to use the fallback.
    ///   - fallback: SF Symbol used when the catalog has no such icon.
    ///   - font: Size of the fallback symbol.
    init(_ name: String?, fallback: String, font: Font = .body) {
        self.source = Self.source(name, fallback: fallback)
        self.font = font
    }

    static func source(_ name: String?, fallback: String) -> Source {
        guard let name, name.hasPrefix("inspector."), NSImage(named: name) != nil else {
            return .system(fallback)
        }
        return .catalog(name)
    }

    var body: some View {
        switch source {
        case .catalog(let asset):
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: side, height: side)
                .accessibilityHidden(true)
        case .system(let symbol):
            Image(systemName: symbol)
                .font(font)
                .accessibilityHidden(true)
        }
    }
}
