import AppKit
import Testing
@testable import Renderer

@Suite struct ModelViewPickTests {
    @Test func clickWhenWithinThreshold() {
        #expect(ModelViewPick.isClick(start: NSPoint(x: 0, y: 0), end: NSPoint(x: 2, y: 2)))
        #expect(ModelViewPick.isClick(start: NSPoint(x: 10, y: 10), end: NSPoint(x: 10, y: 12.9)))
    }

    @Test func dragWhenAtOrBeyondThreshold() {
        #expect(!ModelViewPick.isClick(start: NSPoint(x: 0, y: 0), end: NSPoint(x: 3, y: 0)))
        #expect(!ModelViewPick.isClick(start: NSPoint(x: 0, y: 0), end: NSPoint(x: 2, y: 2.5)))
    }
}
