import AppKit
import SwiftUI

/// Hosted Meshes section: collapse/expand via the same `expanded` Binding the rows toggle,
/// then re-rasterize. Proves the live view tree changes (not only pure helpers).
///
/// `SnapshotHarness.image` always paints into a fixed 1280×820 canvas, so fold is proven by
/// bitmap *content* differing (not canvas height).
enum OutlinerLiveProof {
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

        final class Box: @unchecked Sendable {
            var expanded: Set<NodeID> = []
        }
        let box = Box()
        box.expanded = OutlinerTree.defaultExpandedIDs(roots: section.items)

        func render() -> NSBitmapImageRep? {
            let binding = Binding(
                get: { box.expanded },
                set: { box.expanded = $0 }
            )
            let view = OutlinerSectionView(
                section: section,
                selection: selection,
                expanded: binding
            )
            .frame(width: 280, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
            .background(Theme.chrome)
            return SnapshotHarness.image(of: view, colorScheme: .light)
        }

        func png(_ rep: NSBitmapImageRep) -> Data? {
            rep.representation(using: .png, properties: [:])
        }

        guard let open = render(), let openPNG = png(open) else { return "render open failed" }
        let openVisible = OutlinerTree.visibleItems(roots: section.items, expanded: box.expanded)
            .map(\.name)
        guard openVisible.contains("Pupil") else {
            return "open model missing Pupil: \(openVisible)"
        }

        OutlinerTree.toggle(body, recursive: false, expanded: &box.expanded)
        guard let closed = render(), let closedPNG = png(closed) else { return "render closed failed" }
        let closedVisible = OutlinerTree.visibleItems(roots: section.items, expanded: box.expanded)
            .map(\.name)
        guard closedVisible == ["Body"] else {
            return "closed model \(closedVisible)"
        }
        guard openPNG != closedPNG else {
            return "collapse did not change rasterized Meshes section"
        }

        OutlinerTree.toggle(body, recursive: false, expanded: &box.expanded)
        guard let reopened = render(), let reopenPNG = png(reopened) else {
            return "render reopen failed"
        }
        let reopenVisible = OutlinerTree.visibleItems(roots: section.items, expanded: box.expanded)
            .map(\.name)
        guard reopenVisible.contains("Pupil") else {
            return "reopen model missing Pupil: \(reopenVisible)"
        }
        guard reopenPNG == openPNG else {
            return "re-expand raster does not match original open state"
        }

        return nil
    }
}
