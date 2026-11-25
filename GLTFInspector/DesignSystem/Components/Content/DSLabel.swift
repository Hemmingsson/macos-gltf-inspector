import SwiftUI

/// A title and its glyph, for menus, buttons and pickers.
///
/// The counterpart of `Label(_:systemImage:)` for the drawn inspector set: it takes a `DSGlyph`,
/// so a call site names the thing ("Zoom In"), never an image. Catalog art is drawn as a template
/// at the system label size; when the catalog has not got it, the SF Symbol draws instead and
/// AppKit lays it out exactly as a plain `Label` would.
struct DSLabel: View {
    private let title: String
    private let glyph: DSGlyph

    @ScaledMetric(relativeTo: .body) private var side = DS.Metrics.typeIcon

    init(_ title: String, _ glyph: DSGlyph) {
        self.title = title
        self.glyph = glyph
    }

    var body: some View {
        if let asset = glyph.assetImage {
            Label {
                Text(title)
            } icon: {
                Image(asset)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side, height: side)
            }
        } else {
            Label(title, systemImage: glyph.symbol)
        }
    }
}
