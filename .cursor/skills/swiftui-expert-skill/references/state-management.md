> Read this when: choosing SwiftUI property wrappers, owning or injecting `@Observable`, or writing `@Bindable` bindings.

# State Management

**Contents**
- [Decision table](#decision-table)
- [@Observable & granularity](#observable--granularity)
- [Bindable / Environment / legacy](#bindable--environment--legacy)

Prefer `@Observable` + `@State` / `@Bindable` / `@Environment(Type.self)`. Mark `@Observable` classes `@MainActor` unless default MainActor isolation.

## Decision table

| Wrapper | Use |
|---------|-----|
| `@State private` | View **owns** value or `@Observable` |
| `let` | Read-only from parent |
| `@Binding` | Child **writes** parent |
| `@Bindable` | Injected `@Observable`, need `$model.prop` |
| `@Environment(Type.self)` | Shared via `.environment(model)` |
| `@FocusState private` | Focus — `focus-patterns.md` |

Never `@State` a **passed** value (captures initial, ignores parent). Owned wrappers `private`; injected `let`/`@Binding`/`@Bindable` not. Owned `@Observable` **must** be `@State` — bare `let model = …` recreates on parent redraw. Owner `@State` already projects `$` (no `@Bindable`).

## @Observable & granularity

Property wrappers inside the class conflict — `@ObservationIgnored` (wrapper still notifies). Make hot props `Equatable` so setters skip no-ops.

Observation tracks **property** reads: computed over `users` → whole array; `session.user.name` → whole `user`; one element → whole collection. Cache derived as stored (`didSet`). Many rows watching element fields → one `@Observable` **per item** (`performance-patterns.md`).

## Bindable / Environment / legacy

`@Bindable` only on **injected** models needing `$`. Read-only → `let`. Reacting binding must be `@Binding var`, not `let x: Binding<T>` (misses `body`, often Release-only). Prefer KeyPath/subscript over `Binding(get:set:)`.

`@Entry` for custom env keys (also Transaction/ContainerValues/FocusedValues). No closures in keys (uncomparable). Stable defaults — not `Model()`/`UUID()` in `@Entry`. Unused `@Environment(\.key)` still subscribes; unused `@Environment(Model.self)` is cheap.

Legacy: owned `@StateObject private`; injected `@ObservedObject` (never create inline). Nested `ObservableObject` invisible. Migrate `@EnvironmentObject` → `@Observable` + `@Environment(Type.self)`.
