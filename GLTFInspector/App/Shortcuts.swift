import GLTFCore
import Renderer
import SwiftUI

/// The single keyboard-shortcut table. Menu items and in-window controls read the same entry
/// (DESIGN.md › menu bar = full command set).
enum Shortcuts {
    enum Action: String, CaseIterable, Sendable {
        case orthographic, center, fit, reset, autoRotate, zoomIn, zoomOut
    }

    static func viewMode(_ mode: RenderViewMode) -> KeyboardShortcut? {
        switch mode {
        case .shaded: KeyboardShortcut("1", modifiers: .command)
        case .wireframe: KeyboardShortcut("2", modifiers: .command)
        case .channel: nil
        }
    }

    /// ⌥⌘ + top-row digits (Blender numpad layout). Isometric has none; ⌥⌘5 is orthographic.
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

    /// Every bound shortcut, for duplicate / reserved-key checks in tests.
    static var allBound: [(id: String, shortcut: KeyboardShortcut)] {
        [RenderViewMode.shaded, .wireframe].compactMap { mode in
            viewMode(mode).map { ("viewMode.\(mode)", $0) }
        }
            + CameraPreset.allCases.compactMap { preset in
                cameraPreset(preset).map { ("cameraPreset.\(preset.rawValue)", $0) }
            }
            + Action.allCases.map { ("action.\($0.rawValue)", action($0)) }
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
