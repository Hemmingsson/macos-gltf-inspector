import DesignSystem
import SwiftUI

/// Fixed-width preview surface on the chrome or canvas background.
///
/// Use in `#Preview` blocks with `traits: .fixedLayout(width:height:)` — sidebar (248) and
/// inspector (288) widths match `DS.Metrics.sidebarWidth` / `DS.Metrics.inspectorWidth`.
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
    width: CGFloat = DS.Metrics.sidebarWidth,
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
  }

  private var backgroundColor: Color {
    switch background {
    case .chrome: DS.Color.windowBackground
    case .canvas: DS.Color.Canvas.ground
    }
  }
}

public extension PreviewCanvas {
  /// Left sidebar column width (`DS.Metrics.sidebarWidth`).
  static var sidebarWidth: CGFloat { DS.Metrics.sidebarWidth }

  /// Right inspector column width (`DS.Metrics.inspectorWidth`).
  static var inspectorWidth: CGFloat { DS.Metrics.inspectorWidth }
}
