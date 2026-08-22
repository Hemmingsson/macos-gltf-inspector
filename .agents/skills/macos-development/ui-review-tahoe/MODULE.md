# UI Review for macOS Tahoe

Review process for macOS 26 UI. Load files on demand. Do not tutor APIs owned elsewhere.

## Deferrals

- SwiftUI API, state, lists, animations → `swiftui-expert-skill`
- Liquid Glass **implementation** → `swiftui-expert-skill/references/liquid-glass.md`
- Menu-bar product / sandbox → `../macos-capabilities/`
- Bridge bugs → `../appkit-swiftui-bridge/`

## Review flow

1. Note framework (SwiftUI, AppKit, hybrid), min macOS, and product goals.
2. Audit against the matching file below.
3. For each issue: Issue → Guideline → Impact → Fix → Priority (critical / important / polish).
4. Prefer `List`/`Table`; profile before AppKit tables.

## Modules

| Review | File |
|--------|------|
| Glass vs materials (design only) | `liquid-glass-design.md` |
| Window, toolbar, menu HIG | `macos-tahoe-hig.md` |
| Mac SwiftUI footguns | `swiftui-macos.md` |
| AppKit modernization | `appkit-modern.md` |
| Mac VoiceOver / keyboard | `accessibility.md` |
