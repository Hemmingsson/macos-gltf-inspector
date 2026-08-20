# App Planner

Clarify new vs existing. Cite sibling modules; do not re-teach their APIs.

## New app

- [ ] Features / MVP / audience
- [ ] Size → `../architecture-patterns/` (default small: views + `@Observable` + functions)
- [ ] Persistence: none, or prefs → `../coding-best-practices/data-persistence.md` (no SwiftData unless a real model store is required — then Apple docs)
- [ ] UI / lists → `swiftui-expert-skill`; HIG / glass design → `../ui-review-tahoe/`
- [ ] Sandbox, extensions, menu bar → `../macos-capabilities/`
- [ ] RealityKit / Metal → `metal-realitykit-visionos`
- [ ] One target unless a real share need → `../architecture-patterns/modular-design.md`
- [ ] Tests that match size
- [ ] Distribution: Store vs direct, signing, notarization

## Existing app

- [ ] Size vs architecture in the repo
- [ ] Isolation / Sendable → `../coding-best-practices/`
- [ ] Tahoe UI / a11y → `../ui-review-tahoe/`
- [ ] Prefs vs accidental over-architecture
- [ ] Measured perf (lists, launch) — not “use AppKit”
- [ ] Entitlements / sandbox → `../macos-capabilities/`
- [ ] Dependencies still needed?
- [ ] Test gaps that matter
- [ ] Modernize only what the product needs

## Output

Short plan or audit: decisions, cited modules, priorities. Not a copy of those modules.
