import AppKit
import SwiftUI

/// Hosted Meshes section: collapse/expand via the same `expanded` Binding the rows toggle,
/// then re-rasterize. Proves the live view tree changes (not only pure helpers).
///
/// Fold is proven by bitmap *content* differing (fixed canvas size), not by canvas height.
enum OutlinerLiveProof {
    private static let canvasSize = CGSize(width: 280, height: 400)

    @MainActor
    static func failure() -> String? {
        let scene = MockScene()
        scene.apply(.plainMesh)
        guard let section = OutlinerSection.sections(of: scene.model).first(where: \.folds),
              let body = section.items.first
        else {
            return "no Meshes tree"
        }
        let selection = MockSelection(scene: scene, selected: body.id)

        @MainActor
        final class ExpandedState {
            var ids: Set<NodeID> = []
        }
        let state = ExpandedState()
        state.ids = OutlinerTree.defaultExpandedIDs(roots: section.items)

        func render() -> NSBitmapImageRep? {
            let binding = Binding(
                get: { state.ids },
                set: { state.ids = $0 }
            )
            let view = OutlinerSectionView(
                section: section,
                selection: selection,
                expanded: binding
            )
            .frame(width: canvasSize.width, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
            .background(Theme.chrome)
            return rasterize(view)
        }

        func png(_ rep: NSBitmapImageRep) -> Data? {
            rep.representation(using: .png, properties: [:])
        }

        guard let open = render(), let openPNG = png(open) else { return "render open failed" }
        let openVisible = OutlinerTree.visibleItems(roots: section.items, expanded: state.ids)
            .map(\.name)
        guard openVisible.contains("Pupil") else {
            return "open model missing Pupil: \(openVisible)"
        }

        OutlinerTree.toggle(body, recursive: false, expanded: &state.ids)
        guard let closed = render(), let closedPNG = png(closed) else { return "render closed failed" }
        let closedVisible = OutlinerTree.visibleItems(roots: section.items, expanded: state.ids)
            .map(\.name)
        guard closedVisible == ["Body"] else {
            return "closed model \(closedVisible)"
        }
        guard openPNG != closedPNG else {
            return "collapse did not change rasterized Meshes section"
        }

        OutlinerTree.toggle(body, recursive: false, expanded: &state.ids)
        guard let reopened = render(), let reopenPNG = png(reopened) else {
            return "render reopen failed"
        }
        let reopenVisible = OutlinerTree.visibleItems(roots: section.items, expanded: state.ids)
            .map(\.name)
        guard reopenVisible.contains("Pupil") else {
            return "reopen model missing Pupil: \(reopenVisible)"
        }
        guard reopenPNG == openPNG else {
            return "re-expand raster does not match original open state"
        }

        return nil
    }

    /// Tiny offscreen raster for the outliner fold proof only — not a UI snapshot harness.
    @MainActor
    private static func rasterize<Content: View>(_ content: Content) -> NSBitmapImageRep? {
        guard
            let appearance = NSAppearance(named: .aqua),
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(canvasSize.width),
                pixelsHigh: Int(canvasSize.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        else { return nil }
        bitmap.size = canvasSize

        NSApp?.appearance = appearance
        let host = NSHostingView(
            rootView: content
                .frame(width: canvasSize.width, height: canvasSize.height)
                .environment(\.colorScheme, .light)
        )
        host.appearance = appearance
        host.frame = CGRect(origin: .zero, size: canvasSize)
        host.layoutSubtreeIfNeeded()
        appearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        return bitmap
    }
}
