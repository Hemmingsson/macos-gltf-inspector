---
name: swiftui-expert-skill
description: >
  Use when implementing or reviewing SwiftUI on iOS/macOS: @Observable, ForEach
  identity, Liquid Glass modifiers, animation, localization, soft-deprecated
  APIs, Instruments .trace analysis, or refreshing latest-apis after a new
  OS/Xcode release. Not for sandbox, HIG-only review, AppKit bridge, or SwiftData.
last_verified: 2026-08-20
review_by: 2027-06-22
---

# SwiftUI Expert

SwiftUI implementation. Sandbox, HIG, AppKit bridge, architecture: `macos-development`. RealityKit: `metal-realitykit-visionos`.

## Operating rules

- Liquid Glass: `references/liquid-glass.md` only — do not restate elsewhere.
- Prefer `@Observable`. Large lists: `List`/`Table`; profile first → else `macos-development/appkit-swiftui-bridge`.
- Gate version APIs with `#available` + fallback.
- API/deprecation → `references/latest-apis.md`. Refresh → `references/updating-apis.md`.
- `@State`/`@FocusState` are `private`. Never `@State` passed values. `ForEach` ids stable (never `.indices`). `.animation` always has `value:`.

## vs macos-development

| Topic | This skill | macos-development |
|-------|------------|-------------------|
| State, lists, animation, charts, traces | Owns | — |
| Liquid Glass API | `liquid-glass.md` | Design review only |
| macOS scenes/windows/views | `macos-*.md` | menubar product; HIG |
| Sandbox, extensions, login items | — | `macos-capabilities/` |
| AppKit bridge / architecture | — | those modules |

## Topic router

| Topic | File under `references/` |
|-------|--------------------------|
| State | `state-management.md` |
| Views | `view-structure.md` |
| Performance | `performance-patterns.md` |
| Lists / Table | `list-patterns.md` |
| Layout | `layout-best-practices.md` |
| Sheets / nav | `sheet-navigation-patterns.md` |
| Scroll | `scroll-patterns.md` |
| Focus | `focus-patterns.md` |
| Animation | `animation.md` |
| Accessibility | `accessibility-patterns.md` |
| Images | `image-optimization.md` |
| Liquid Glass | `liquid-glass.md` |
| macOS scenes / windows / views | `macos-scenes.md` / `macos-window-styling.md` / `macos-views.md` |
| Localization | `localization.md` |
| Latest APIs / soft deprecation | `latest-apis.md` / `soft-deprecation.md` |
| Refresh latest-apis | `updating-apis.md` (+ `scan-manifest.md`) |
| Previews | `previews.md` |
