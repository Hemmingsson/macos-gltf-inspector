import SwiftUI

/// Fixed-width preview surface with theme background and contrast-aware borders.
///
/// Use in `#Preview` blocks with `traits: .fixedLayout(width:height:)` — sidebar (248) and
/// inspector (288) widths match `Theme.sidebarWidth` / `Theme.inspectorWidth`.
public struct PreviewCanvas<Content: View>: View {
  public enum Background {
    case chrome
    case canvas
  }

  public var width: CGFloat
  public var height: CGFloat?
  public var background: Background
  @ViewBuilder public var content: () -> Content

  public init(
    width: CGFloat = Theme.sidebarWidth,
    height: CGFloat? = nil,
    background: Background = .chrome,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.width = width
    self.height = height
    self.background = background
    self.content = content
  }

  public var body: some View {
    content()
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .frame(width: width)
      .frame(maxHeight: height == nil ? nil : .infinity, alignment: .top)
      .frame(height: height)
      .background(backgroundColor)
      .themeContrastEnvironment()
  }

  private var backgroundColor: Color {
    switch background {
    case .chrome: Theme.chrome
    case .canvas: Theme.canvas
    }
  }
}

public extension PreviewCanvas {
  /// Left sidebar column width (`Theme.sidebarWidth`).
  static var sidebarWidth: CGFloat { Theme.sidebarWidth }

  /// Right inspector column width (`Theme.inspectorWidth`).
  static var inspectorWidth: CGFloat { Theme.inspectorWidth }
}
