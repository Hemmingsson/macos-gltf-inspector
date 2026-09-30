import DesignSystem
import SwiftUI
import Testing

struct DesignShortcutsTests {
    /// Standard macOS shortcuts the table must never claim
    /// (Edit / File / Window / app menus, plus the sidebar toggle).
    private static let commandKeys: [Character] = [
        "c", "x", "v", "a", "z", "f", "g", "w", "q", "n", "o", "s", "p", "h", "m", ","
    ]

    private static let reserved: [KeyboardShortcut] = commandKeys.map {
        KeyboardShortcut(KeyEquivalent($0), modifiers: .command)
    } + [
        KeyboardShortcut("z", modifiers: [.command, .shift]),   // Redo
        KeyboardShortcut("h", modifiers: [.command, .option]),  // Hide Others
        KeyboardShortcut("f", modifiers: [.command, .control]), // Enter Full Screen
        KeyboardShortcut("s", modifiers: [.command, .control])  // Show Sidebar
    ]

    private static func signature(_ shortcut: KeyboardShortcut) -> String {
        "\(shortcut.modifiers.rawValue)|\(String(shortcut.key.character).lowercased())"
    }

    @Test func all_hasNoDuplicateShortcuts() {
        let signatures = DS.Shortcuts.all.map { Self.signature($0.shortcut) }
        #expect(Set(signatures).count == signatures.count, "duplicate shortcut in \(DS.Shortcuts.all.map(\.id))")
    }

    @Test func all_hasUniqueIDs() {
        let ids = DS.Shortcuts.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func all_avoidsStandardShortcuts() {
        let reserved = Set(Self.reserved.map(Self.signature))
        for entry in DS.Shortcuts.all {
            #expect(!reserved.contains(Self.signature(entry.shortcut)), "\(entry.id) collides with a standard shortcut")
        }
    }

    @Test func all_coversEveryCase() {
        let presetsWithShortcut = DS.Shortcuts.CameraPreset.allCases.filter { DS.Shortcuts.cameraPreset($0) != nil }
        #expect(DS.Shortcuts.all.count
            == DS.Shortcuts.ViewMode.allCases.count + presetsWithShortcut.count + DS.Shortcuts.Action.allCases.count)
        #expect(DS.Shortcuts.cameraPreset(.isometric) == nil)
    }
}
