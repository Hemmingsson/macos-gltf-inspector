import SwiftUI

public extension DS {
    /// Liquid Glass variants for custom floating chrome (SwiftUI `Glass`, macOS 26;
    /// HIG › Materials › "Liquid Glass"). Prefer system bars and `.buttonStyle(.glass)` where they
    /// fit; these are for the canvas clusters and HUDs. Never place glass on glass.
    enum Glass {
        /// A resting interactive control. `Glass.regular.interactive()`.
        public static var control: SwiftUI.Glass { .regular.interactive() }

        /// An interactive control in its "on" state, tinted so state reads without colour-only
        /// glyphs. `Glass.regular.tint(tint).interactive()`; defaults to the user's accent.
        public static func controlOn(tint: SwiftUI.Color = DS.Color.accent) -> SwiftUI.Glass {
            .regular.tint(tint).interactive()
        }

        /// Non-interactive readouts (dimensions, playback bar). `Glass.regular`.
        public static var hud: SwiftUI.Glass { .regular }

        /// `GlassEffectContainer(spacing:)` for a cluster: matches `DS.Metrics.clusterSpacing`, so
        /// islands sample together but stay visually separate at rest.
        public static let containerSpacing: CGFloat = DS.Metrics.clusterSpacing
    }
}
