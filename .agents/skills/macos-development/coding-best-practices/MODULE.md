# Coding Best Practices

Swift 6 isolation and simple persistence. Load only the file the issue needs.

## Owns

- Isolation, Sendable, MainActor, actors → `modern-concurrency.md`
- UserDefaults / AppStorage / Core Data legacy → `data-persistence.md`

## Does not own

- Architecture size → `../architecture-patterns/`
- SwiftUI APIs / Liquid Glass → `swiftui-expert-skill`
- AppKit bridging → `../appkit-swiftui-bridge/`
- RealityKit → `metal-realitykit-visionos`

## Checklist

- [ ] Isolation and Sendable correct; `@MainActor` on UI, not on services by default
- [ ] No new `ObservableObject` (prefer `@Observable`)
- [ ] Prefs are UserDefaults / `@AppStorage`; secrets are Keychain
- [ ] No SwiftData for prefs — this app does not ship a SwiftData stack
