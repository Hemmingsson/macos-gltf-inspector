import Renderer
import simd
import SwiftUI

/// One of the six axis ends on the navigation gizmo.
enum NavigationAxis: CaseIterable, Hashable, Sendable {
    case posX, negX, posY, negY, posZ, negZ

    var worldDirection: SIMD3<Float> {
        switch self {
        case .posX: SIMD3(1, 0, 0)
        case .negX: SIMD3(-1, 0, 0)
        case .posY: SIMD3(0, 1, 0)
        case .negY: SIMD3(0, -1, 0)
        case .posZ: SIMD3(0, 0, 1)
        case .negZ: SIMD3(0, 0, -1)
        }
    }

    var isPositive: Bool {
        switch self {
        case .posX, .posY, .posZ: true
        case .negX, .negY, .negZ: false
        }
    }

    var color: Color {
        switch self {
        case .posX: DS.Color.Axis.x
        case .negX: DS.Color.Axis.negative
        case .posY: DS.Color.Axis.y
        case .negY: DS.Color.Axis.negative
        case .posZ: DS.Color.Axis.z
        case .negZ: DS.Color.Axis.negative
        }
    }

    var cameraPreset: CameraPreset {
        switch self {
        case .posX: .right
        case .negX: .left
        case .posY: .top
        case .negY: .bottom
        case .posZ: .front
        case .negZ: .back
        }
    }

    var opposite: NavigationAxis {
        switch self {
        case .posX: .negX
        case .negX: .posX
        case .posY: .negY
        case .negY: .posY
        case .posZ: .negZ
        case .negZ: .posZ
        }
    }

    var viewDirectionName: String {
        switch self {
        case .posX: "right"
        case .negX: "left"
        case .posY: "top"
        case .negY: "bottom"
        case .posZ: "front"
        case .negZ: "back"
        }
    }
}

struct NavigationGizmoBallLayout: Identifiable, Equatable, Sendable {
    var id: NavigationAxis { axis }
    let axis: NavigationAxis
    let center: CGPoint
    let radius: CGFloat
    /// View-space depth; larger values draw on top.
    let viewDepth: Float
}

/// Pure layout for the navigation gizmo balls and axis lines.
enum NavigationGizmoLayout {
    static let axisLength: CGFloat = 24
    static let positiveRadius: CGFloat = 7
    static let negativeRadius: CGFloat = 5
    static let axisLineWidth: CGFloat = 1.25

    static func ballLayouts(viewRotation: simd_float3x3, panelSize: CGSize) -> [NavigationGizmoBallLayout] {
        let hub = CGPoint(x: panelSize.width / 2, y: panelSize.height / 2)
        return NavigationAxis.allCases.map { axis in
            let viewDir = viewRotation * axis.worldDirection
            let center = CGPoint(
                x: hub.x + CGFloat(viewDir.x) * axisLength,
                y: hub.y - CGFloat(viewDir.y) * axisLength
            )
            let radius = axis.isPositive ? positiveRadius : negativeRadius
            return NavigationGizmoBallLayout(axis: axis, center: center, radius: radius, viewDepth: viewDir.z)
        }
    }

    /// Back-to-front draw order (farther axis ends first).
    static func sortedForDrawing(_ layouts: [NavigationGizmoBallLayout]) -> [NavigationGizmoBallLayout] {
        layouts.sorted { $0.viewDepth < $1.viewDepth }
    }

    static func cameraPreset(for axis: NavigationAxis, activePreset: CameraPreset?) -> CameraPreset {
        let preset = axis.cameraPreset
        if activePreset == preset { return axis.opposite.cameraPreset }
        return preset
    }

    /// Drag delta for the gizmo; SwiftUI locations are y-down, matching a downward drag to positive `dy`
    /// like AppKit window coordinates in `ModelView.drag`.
    static func dragDelta(from start: CGPoint, to location: CGPoint) -> (dx: Double, dy: Double) {
        (Double(location.x - start.x), Double(location.y - start.y))
    }
}

/// Bottom-leading view-orientation control: ± axis balls, preset snaps and drag-to-orbit.
struct NavigationGizmo: View {
    var viewRotation: simd_float3x3
    var activePreset: CameraPreset?
    var onSelect: (CameraPreset) -> Void
    var onOrbit: (Double, Double) -> Void

    @State private var hovered: NavigationAxis?
    @State private var dragAnchor: CGPoint?

    var body: some View {
        DSGizmoPanel {
            GeometryReader { geo in
                let layouts = NavigationGizmoLayout.sortedForDrawing(
                    NavigationGizmoLayout.ballLayouts(viewRotation: viewRotation, panelSize: geo.size)
                )
                ZStack {
                    Canvas { context, size in
                        let hub = CGPoint(x: size.width / 2, y: size.height / 2)
                        for layout in layouts {
                            OverlayMetrics.strokeAxis(
                                context,
                                from: hub,
                                to: layout.center,
                                color: layout.axis.color.opacity(0.85),
                                lineWidth: NavigationGizmoLayout.axisLineWidth
                            )
                        }
                        for layout in layouts {
                            let rect = CGRect(
                                x: layout.center.x - layout.radius,
                                y: layout.center.y - layout.radius,
                                width: layout.radius * 2,
                                height: layout.radius * 2
                            )
                            let fill = layout.axis.color.opacity(hovered == layout.axis ? 1 : 0.92)
                            context.fill(Path(ellipseIn: rect), with: .color(fill))
                            if hovered == layout.axis {
                                context.stroke(Path(ellipseIn: rect), with: .color(.primary.opacity(0.35)),
                                               style: StrokeStyle(lineWidth: 1.5))
                            }
                        }
                    }

                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(dragGesture(in: geo.size))
                        .onTapGesture { location in
                            if let axis = hitTest(location, in: geo.size) {
                                onSelect(NavigationGizmoLayout.cameraPreset(for: axis, activePreset: activePreset))
                            }
                        }
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                hovered = hitTest(location, in: geo.size)
                            case .ended:
                                hovered = nil
                            }
                        }
                        .modifier(NavigationGizmoAccessibility(activePreset: activePreset, onSelect: onSelect))
                }
            }
        }
    }

    private func hitTest(_ location: CGPoint, in size: CGSize) -> NavigationAxis? {
        let layouts = NavigationGizmoLayout.ballLayouts(viewRotation: viewRotation, panelSize: size)
        return NavigationGizmoLayout.sortedForDrawing(layouts)
            .reversed()
            .first { layout in
                hypot(location.x - layout.center.x, location.y - layout.center.y) <= layout.radius + 2
            }?
            .axis
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragAnchor == nil { dragAnchor = value.startLocation }
                guard let start = dragAnchor else { return }
                let delta = NavigationGizmoLayout.dragDelta(from: start, to: value.location)
                dragAnchor = value.location
                onOrbit(delta.dx, delta.dy)
            }
            .onEnded { _ in dragAnchor = nil }
    }
}

private struct NavigationGizmoAccessibility: ViewModifier {
    var activePreset: CameraPreset?
    var onSelect: (CameraPreset) -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement()
            .accessibilityLabel("Navigation gizmo")
            .accessibilityAction(named: "View from top") { select(.posY) }
            .accessibilityAction(named: "View from bottom") { select(.negY) }
            .accessibilityAction(named: "View from front") { select(.posZ) }
            .accessibilityAction(named: "View from back") { select(.negZ) }
            .accessibilityAction(named: "View from left") { select(.negX) }
            .accessibilityAction(named: "View from right") { select(.posX) }
    }

    private func select(_ axis: NavigationAxis) {
        onSelect(NavigationGizmoLayout.cameraPreset(for: axis, activePreset: activePreset))
    }
}
