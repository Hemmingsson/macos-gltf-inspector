---
name: macos-development
description: >
  Use when doing macOS app work: code review, architecture sizing, sandboxing /
  Quick Look / thumbnail extensions, AppKit–SwiftUI bridging, UI/HIG review, or
  new-app planning. Not for SwiftUI view APIs (swiftui-expert-skill) or Metal /
  RealityKit (metal-realitykit-visionos).
last_verified: 2026-08-20
review_by: 2027-06-22
os_version: macOS 26
---

# macOS Development

Router for this repo’s macOS work. Read a module’s `MODULE.md`, then only the local file the task needs. One owner per concern — do not copy guidance between modules. Do not invent unreleased OS APIs.

## Ownership

| Need | Owner |
|------|--------|
| SwiftUI views, state, lists, animation, Liquid Glass **API** | `swiftui-expert-skill` |
| Metal / RealityKit / RealityView | `metal-realitykit-visionos` |
| Verify UI (AX, Peekaboo, glass — no headless UI snapshots) | `macos-app-testing` |
| Swift 6 isolation, Sendable, MainActor, actors | `coding-best-practices/` |
| UserDefaults / AppStorage / Core Data legacy | `coding-best-practices/data-persistence.md` |
| App size → architecture | `architecture-patterns/` |
| Sandbox, entitlements, QL/thumbnail/XPC, menu bar, login items | `macos-capabilities/` |
| NSViewRepresentable, hosting, bridge state | `appkit-swiftui-bridge/` |
| UI review, Tahoe HIG, AppKit modernization (design) | `ui-review-tahoe/` |

`MenuBarExtra` scene API → `swiftui-expert-skill`. Entitlements → `macos-capabilities/`.

**Out of scope for this pack:** SwiftData stacks, Continuity, Foundation Models, Control Center widgets. Prefer `@AppStorage` / UserDefaults. If a product truly needs those system APIs, use current Apple docs — do not invent wrappers here.

## Canons (one line each)

1. Liquid Glass API → `swiftui-expert-skill` `references/liquid-glass.md` (never re-teach).
2. Prefer `@Observable`. `ObservableObject` is legacy.
3. Lists: SwiftUI `List`/`Table` first; profile; `NSTableView` only after measurement.
4. Architecture matches size. Default small Mac viewer: SwiftUI + `@Observable` + functions — no MVVM/coordinators/SPM unless size demands.
