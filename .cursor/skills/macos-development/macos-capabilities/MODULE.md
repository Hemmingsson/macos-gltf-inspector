# macOS Capabilities

Sandbox, extensions (incl. Quick Look / thumbnails), menu-bar product architecture, background execution.

## Decision table

| Need | Module |
|------|--------|
| File access, bookmarks, entitlements XML | `sandboxing.md` |
| Share, Finder Sync, Quick Look, thumbnails, XPC | `extensions.md` |
| LSUIElement, activation policy, status-item product | `menubar.md` |
| Login items, agents, background work | `background.md` |

## Deferrals

- `MenuBarExtra` scene API → `swiftui-expert-skill/references/macos-scenes.md`
- SwiftUI / Liquid Glass API → `swiftui-expert-skill`
- AppKit ↔ SwiftUI wrapping → `../appkit-swiftui-bridge/`

## Workflow

1. Identify the capability and whether the app is sandboxed (Mac App Store requires it).
2. Read only the matching module. Name entitlements and Info.plist keys in the answer.
3. Call out App Store vs direct-distribution differences.

## Guardrails

- Do not re-teach `MenuBarExtra` styles or claim the app quits if the user removes the extra.
- Do not invent entitlements. Copy keys from `sandboxing.md`.
