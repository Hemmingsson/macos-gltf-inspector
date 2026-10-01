import SwiftUI

public extension DS {
    /// The single keyboard-shortcut table. Menu items and in-window controls read the same entry,
    /// so an action has one shortcut everywhere (DESIGN.md › "Menu bar = the full command set";
    /// HIG › Keyboards › "Custom keyboard shortcuts": prefer ⌘ alone for frequent commands, add ⌥
    /// for related variants, never reuse a standard system shortcut). SwiftUI `KeyboardShortcut`.
    ///
    /// `DesignSystem` cannot see PreviewUI's `ViewMode` / `CameraPreset`, so it mirrors them with
    /// enums whose raw values match (`ViewMode.id`, `CameraPreset.rawValue`); the seam maps with
    /// `init(rawValue:)`.
    enum Shortcuts {

        /// Mirrors the always-available PreviewUI view modes (`ViewMode.id`). Per-file debug
        /// channels have no shortcut.
        public enum ViewMode: String, CaseIterable, Sendable {
            case shaded
            case wireframe
        }

        /// Mirrors PreviewUI's `CameraPreset` (same raw values).
        public enum CameraPreset: String, CaseIterable, Sendable {
            case front
            case back
            case left
            case right
            case top
            case bottom
            case isometric
        }

        /// Viewport commands that are not view modes or presets.
        public enum Action: String, CaseIterable, Sendable {
            case orthographic
            case center
            case fit
            case reset
            case autoRotate
        }

        /// One row of the table.
        public struct Entry: Identifiable {
            /// Stable identifier, e.g. `viewMode.shaded`, `cameraPreset.front`, `action.fit`.
            public let id: String
            public let shortcut: KeyboardShortcut
        }

        /// View modes take ⌘ + their position: Shaded ⌘1, Wireframe ⌘2.
        public static func viewMode(_ mode: ViewMode) -> KeyboardShortcut {
            switch mode {
            case .shaded: KeyboardShortcut("1", modifiers: .command)
            case .wireframe: KeyboardShortcut("2", modifiers: .command)
            }
        }

        /// Camera presets take ⌥⌘ + numpad-style digits (Blender convention on the top-row
        /// digits, so laptops without a keypad work): 1 Front, 3 Right, 7 Top, 9 Back, 4 Left,
        /// 2 Bottom. ⌥⌘5 is `Action.orthographic`, as numpad 5 toggles projection. Isometric has
        /// none.
        public static func cameraPreset(_ preset: CameraPreset) -> KeyboardShortcut? {
            let modifiers: EventModifiers = [.command, .option]
            return switch preset {
            case .front: KeyboardShortcut("1", modifiers: modifiers)
            case .right: KeyboardShortcut("3", modifiers: modifiers)
            case .top: KeyboardShortcut("7", modifiers: modifiers)
            case .back: KeyboardShortcut("9", modifiers: modifiers)
            case .left: KeyboardShortcut("4", modifiers: modifiers)
            case .bottom: KeyboardShortcut("2", modifiers: modifiers)
            case .isometric: nil
            }
        }

        /// Orthographic ⌥⌘5, Center ⌥⌘C (⌘C is Copy), Fit ⌘9, Reset ⌘0, Auto-rotate ⌘R.
        public static func action(_ action: Action) -> KeyboardShortcut {
            switch action {
            case .orthographic: KeyboardShortcut("5", modifiers: [.command, .option])
            case .center: KeyboardShortcut("c", modifiers: [.command, .option])
            case .fit: KeyboardShortcut("9", modifiers: .command)
            case .reset: KeyboardShortcut("0", modifiers: .command)
            case .autoRotate: KeyboardShortcut("r", modifiers: .command)
            }
        }

        /// Every shortcut in the table, for duplicate / standard-shortcut checks and a
        /// shortcuts reference.
        public static var all: [Entry] {
            ViewMode.allCases.map { Entry(id: "viewMode.\($0.rawValue)", shortcut: viewMode($0)) }
                + CameraPreset.allCases.compactMap { preset in
                    cameraPreset(preset).map { Entry(id: "cameraPreset.\(preset.rawValue)", shortcut: $0) }
                }
                + Action.allCases.map { Entry(id: "action.\($0.rawValue)", shortcut: action($0)) }
        }
    }
}
