import AppKit
import Foundation
import Testing
@testable import GLTFInspector
@testable import RendererWebKit

@MainActor
struct CachedQuickLookThumbnailTests {
    @Test
    func matchingIconsAreNotTreatedAsCachedThumbnails() {
        let icon = NSWorkspace.shared.icon(for: .json)
        #expect(!CachedQuickLookThumbnail.differsFromTypeIcon(icon, typeIcon: icon))
    }

    @Test
    func differentRendersCountAsCachedThumbnails() {
        let red = solidImage(.red)
        let blue = solidImage(.blue)
        #expect(CachedQuickLookThumbnail.differsFromTypeIcon(red, typeIcon: blue))
    }

    @Test
    func neverThumbnailedFileSkipsPlaceholder() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("exp008-\(UUID().uuidString).glb")
        try Data([0x67, 0x6C, 0x54, 0x46]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(CachedQuickLookThumbnail.existingIcon(for: url) == nil)
    }

    private func solidImage(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
    }
}
