# Architecture Patterns

Decide size first. Load references only when size demands them.

## Decision

| Size | Shape |
|------|--------|
| Small (default) | Views + `@Observable` + functions. One target. Example: Mac document / Quick Look viewer. No ViewModel layer, coordinators, SwiftData, or SPM. |
| Medium | Several features or windows. Feature folders. `@Observable` + service functions. Still one app target. No coordinators. |
| Large | Second product, shared host/extension code, or navigation *is* the product → read files below. |

Default to small unless the repo already has a second product, a real share need, or measured pain.

## Load next

- Mac navigation / multi-window → `design-patterns.md`
- Real second product or share need → `modular-design.md`

## Do not

- Invent repositories, coordinators, or SOLID reviews for small apps
- Push SPM for “clean architecture”
- Restate SwiftUI (`swiftui-expert-skill`) or isolation (`../coding-best-practices/`)
