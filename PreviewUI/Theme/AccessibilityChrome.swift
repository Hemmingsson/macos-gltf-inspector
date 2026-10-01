import SwiftUI

/// Kept as a no-op so existing call sites compile. Increase Contrast is already
/// carried by `DS.Color.separator`.
public struct ThemeContrastEnvironment: ViewModifier {
    public func body(content: Content) -> some View {
        content
    }
}

public extension View {
    func themeContrastEnvironment() -> some View {
        modifier(ThemeContrastEnvironment())
    }
}
