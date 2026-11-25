import GLTFCore
import Renderer
import SwiftUI
import Testing
@testable import GLTFInspector

struct ShortcutsTests {
    /// Standard macOS shortcuts the table must never claim
    /// (Edit / File / Window / app menus, plus the sidebar toggle).
    private static let commandKeys: [Character] = [
        "c", "x", "v", "a", "z", "f", "g", "w", "q", "n", "o", "s", "p", "h", "m", ","
    ]

    private static let reserved: [KeyboardShortcut] = commandKeys.map {
        KeyboardShortcut(KeyEquivalent($0), modifiers: .command)
    } + [
        KeyboardShortcut("z", modifiers: [.command, .shift]),
        KeyboardShortcut("h", modifiers: [.command, .option]),
        KeyboardShortcut("f", modifiers: [.command, .control]),
        KeyboardShortcut("s", modifiers: [.command, .control])
    ]

    private static func signature(_ shortcut: KeyboardShortcut) -> String {
        "\(shortcut.modifiers.rawValue)|\(String(shortcut.key.character).lowercased())"
    }

    @Test func allBound_hasNoDuplicates() {
        let signatures = Shortcuts.allBound.map { Self.signature($0.shortcut) }
        #expect(Set(signatures).count == signatures.count, "duplicate shortcut in \(Shortcuts.allBound.map(\.id))")
    }

    @Test func allBound_hasUniqueIDs() {
        let ids = Shortcuts.allBound.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func allBound_avoidsStandardShortcuts() {
        let reserved = Set(Self.reserved.map(Self.signature))
        for entry in Shortcuts.allBound {
            #expect(!reserved.contains(Self.signature(entry.shortcut)), "\(entry.id) collides with a standard shortcut")
        }
    }

    @Test func allBound_coversEveryCase() {
        let presetsWithShortcut = CameraPreset.allCases.filter { Shortcuts.cameraPreset($0) != nil }
        #expect(Shortcuts.allBound.count == 1 + RenderViewMode.displayModes.count + presetsWithShortcut.count
            + Shortcuts.Action.allCases.count)
        #expect(Shortcuts.cameraPreset(.isometric) == nil)
    }
}
