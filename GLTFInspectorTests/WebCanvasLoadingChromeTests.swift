import AppKit
import SwiftUI
import Testing
@testable import RendererWebKit

/// The Quick Look poster (cached Finder icon) sits under the loading chrome. An opaque
/// full-frame fill hides it for the whole page start — the bug EXP-008 poster never shows.
@MainActor
struct WebCanvasLoadingChromeTests {
    /// Composite the chrome over an sRGB-red poster the way `WebCanvasController` stacks
    /// placeholder + chrome, then sample the field. A `windowBackgroundColor` cover makes
    /// the poster vanish; a small non-opaque pill leaves the red field visible.
    @Test
    func loadingChromeDoesNotCoverThePoster() {
        let bounds = NSRect(x: 0, y: 0, width: 240, height: 180)
        let poster = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)

        let container = NSView(frame: bounds)
        container.wantsLayer = true
        container.layer?.backgroundColor = poster.cgColor

        let chrome = NSHostingView(
            rootView: WebCanvasLoadingChrome(title: WebRendererLoadCopy.starting, detail: nil)
        )
        chrome.wantsLayer = true
        chrome.layer?.isOpaque = false
        chrome.layer?.backgroundColor = NSColor.clear.cgColor
        chrome.frame = bounds
        container.addSubview(chrome)

        let window = NSWindow(
            contentRect: bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = poster
        window.isOpaque = false
        window.contentView = container
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        chrome.layoutSubtreeIfNeeded()
        container.layoutSubtreeIfNeeded()

        let bitmap = container.bitmapImageRepForCachingDisplay(in: bounds)
        guard let bitmap else {
            Issue.record("could not cache the chrome composite")
            window.close()
            return
        }
        container.cacheDisplay(in: bounds, to: bitmap)
        window.close()

        let samples = sampleField(bitmap)
        #expect(
            samples.posterVisible,
            "opaque loading chrome covered the poster (center RGBA \(samples.center))"
        )
        #expect(
            samples.chromePresent,
            "loading chrome vanished instead of becoming a small pill"
        )
    }

    private func sampleField(_ rep: NSBitmapImageRep) -> (
        posterVisible: Bool, chromePresent: Bool, center: String
    ) {
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        let center = color(rep, x: width / 2, y: height / 2)
        let midLeft = color(rep, x: max(0, width / 4), y: height / 2)
        let midRight = color(rep, x: min(width - 1, (width * 3) / 4), y: height / 2)
        let posterVisible = [center, midLeft, midRight].contains { isPosterRed($0) }

        var nonPoster = 0
        for y in stride(from: 0, to: height, by: 6) {
            for x in stride(from: 0, to: width, by: 6) {
                if !isPosterRed(color(rep, x: x, y: y)) { nonPoster += 1 }
            }
        }
        return (
            posterVisible: posterVisible,
            chromePresent: nonPoster > 0,
            center: String(
                format: "%.2f,%.2f,%.2f,%.2f",
                center.red, center.green, center.blue, center.alpha
            )
        )
    }

    private func color(_ rep: NSBitmapImageRep, x: Int, y: Int) -> (
        red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat
    ) {
        let c = rep.colorAt(x: x, y: y)
        return (
            c?.redComponent ?? 0,
            c?.greenComponent ?? 0,
            c?.blueComponent ?? 0,
            c?.alphaComponent ?? 0
        )
    }

    private func isPosterRed(_ c: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)) -> Bool {
        c.red > 0.8 && c.green < 0.25 && c.blue < 0.25 && c.alpha > 0.8
    }
}
