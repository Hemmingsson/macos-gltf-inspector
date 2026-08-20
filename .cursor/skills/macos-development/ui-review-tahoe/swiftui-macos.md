# SwiftUI on macOS — review notes (Tahoe)

> Read this when: reviewing Mac SwiftUI UX, focus/keyboard, hosting, or large lists — not when you need a SwiftUI API manual.

## Contents

- [Prefer native Mac patterns](#prefer-native-mac-patterns)
- [Focus and keyboard](#focus-and-keyboard)
- [Known Tahoe / hybrid footguns](#known-tahoe--hybrid-footguns)
- [Large lists](#large-lists)
- [Review checklist](#review-checklist)

Not a SwiftUI API manual. For scenes, windows, Table, focus, lists, state, and animations, use `swiftui-expert-skill` (`macos-scenes.md`, `macos-window-styling.md`, `macos-views.md`, `focus-patterns.md`).

## Prefer native Mac patterns

During review, expect:

- `NavigationSplitView` for sidebar shells
- `Table` for multi-column data
- `formStyle(.grouped)` + `LabeledContent` for Settings-like panes
- Scene-level window styling instead of fighting AppKit chrome

Flag iOS-only navigation idioms and hand-rolled window chrome.

## Focus and keyboard

- Sonoma+ `focusable()` grants click-to-focus by default — audit `focusable(interactions:)` when click must not steal activation.
- Test with System Settings → Keyboard → Keyboard navigation on and off.
- Full patterns: `swiftui-expert-skill/references/focus-patterns.md`.

## Known Tahoe / hybrid footguns

### Layout

Prefer explicit spacing and alignment under resize. Ambiguous `maxWidth: .infinity` stacks without anchors often break.

### NSHostingView animation

Frame changes inside `NSHostingView` may not animate. Prefer SwiftUI-owned animation or see `../appkit-swiftui-bridge/hosting-controllers.md`.

### Transparency

Test materials and glass on real Tahoe light/dark. Custom `Color.opacity` overlays often fail vibrancy. Design rules: `liquid-glass-design.md`. API: `swiftui-expert-skill` `references/liquid-glass.md`.

## Large lists

Prefer SwiftUI `List`/`Table` and **profile** before bridging to `NSTableView`. Canon: `../appkit-swiftui-bridge/MODULE.md`.

## Review checklist

- [ ] Mac scene/window APIs instead of iOS-only navigation
- [ ] Focus/keyboard audited on Mac
- [ ] Hybrid hosting cleaned up (`dismantle`, layout via SwiftUI)
- [ ] List/Table first; no default AppKit table
- [ ] No second API guide — point to `swiftui-expert-skill` for fixes
