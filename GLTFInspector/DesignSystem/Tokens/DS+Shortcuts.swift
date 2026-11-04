import GLTFCore
import Renderer
import SwiftUI

extension DS {
    /// The single keyboard-shortcut table. Menu items and in-window controls read the same entry,
    /// so an action has one shortcut everywhere (DESIGN.md › "Menu bar = the full command set";
    /// HIG › Keyboards › "Custom keyboard shortcuts": prefer ⌘ alone for frequent commands, add ⌥
    /// for related variants, never reuse a standard system shortcut). SwiftUI `KeyboardShortcut`.
    enum Shortcuts {
        /// Viewport commands that are not view modes or presets.
        enum Action: String, CaseIterable, Sendable {
            case orthographic
            case center
            case fit
            case reset
            case autoRotate
            case zoomIn
            case zoomOut
        }

        /// One row of the table.
        struct Entry: Identifiable {
            /// Stable identifier, e.g. `viewMode.shaded`, `cameraPreset.front`, `action.fit`.
            let id: String
            let shortcut: KeyboardShortcut
        }

        /// Shaded ⌘1, Wireframe ⌘2. Per-file channels have none.
        static func viewMode(_ mode: RenderViewMode) -> KeyboardShortcut? {
            switch mode {
            case .shaded: KeyboardShortcut("1", modifiers: .command)
            case .wireframe: KeyboardShortcut("2", modifiers: .command)
            case .channel: nil
            }
        }

        /// Camera presets take ⌥⌘ + numpad-style digits (Blender convention on the top-row
        /// digits, so laptops without a keypad work): 1 Front, 3 Right, 7 Top, 9 Back, 4 Left,
        /// 2 Bottom. ⌥⌘5 is `Action.orthographic`, as numpad 5 toggles projection. Isometric has
        /// none.
        static func cameraPreset(_ preset: CameraPreset) -> KeyboardShortcut? {
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

        /// Orthographic ⌥⌘5, Center ⌥⌘C (⌘C is Copy), Fit ⌘9, Reset ⌘0, Auto-rotate ⌘R,
        /// Zoom In ⌘+, Zoom Out ⌘− (as in design tools).
        static func action(_ action: Action) -> KeyboardShortcut {
            switch action {
            case .orthographic: KeyboardShortcut("5", modifiers: [.command, .option])
            case .center: KeyboardShortcut("c", modifiers: [.command, .option])
            case .fit: KeyboardShortcut("9", modifiers: .command)
            case .reset: KeyboardShortcut("0", modifiers: .command)
            case .autoRotate: KeyboardShortcut("r", modifiers: .command)
            case .zoomIn: KeyboardShortcut("+", modifiers: .command)
            case .zoomOut: KeyboardShortcut("-", modifiers: .command)
            }
        }

        /// Every shortcut in the table, for duplicate / standard-shortcut checks.
        static var all: [Entry] {
            [RenderViewMode.shaded, .wireframe].compactMap { mode in
                viewMode(mode).map { Entry(id: "viewMode.\(mode.title)", shortcut: $0) }
            }
                + CameraPreset.allCases.compactMap { preset in
                    cameraPreset(preset).map { Entry(id: "cameraPreset.\(preset.rawValue)", shortcut: $0) }
                }
                + Action.allCases.map { Entry(id: "action.\($0.rawValue)", shortcut: action($0)) }
        }
    }
}

extension View {
    @ViewBuilder
    func keyboardShortcutIfAvailable(_ shortcut: KeyboardShortcut?) -> some View {
        if let shortcut {
            self.keyboardShortcut(shortcut)
        } else {
            self
        }
    }
}
