> Read this when: reviewing SwiftUI view composition, body cost, `ForEach` child count, `Equatable` views, or `AnyView`.

# View Structure

**Contents**
- [Cheap body / extract types](#cheap-body--extract-types)
- [Identity](#identity)
- [ForEach / Equatable / AnyView](#foreach--equatable--anyview)
- [Containers](#containers)

A view **type** is the invalidation unit. Computed props / `@ViewBuilder` helpers are inlined — no boundary.

## Cheap body / extract types

`body`/`init` run often (lists, animation). No filter/sort/map, formatters, JSON, or filesystem there. Prepare in the model; format with `Text(..., format:)`. One-shot work → `@Observable` / `.task`.

Extract `struct` types, not `private var header: some View` — helpers share parent invalidation. Stateful / env pieces always own a type. Store `@ViewBuilder let content: Content`, not `() -> Content` (closures incomparable → always re-render).

## Identity

Same view, two states → modifier/ternary. Different views → `if`/`else`. Never ship `View.if` extensions — destroy identity.

```swift
Text("Hello").opacity(highlighted ? 1 : 0.5)
```

## ForEach / Equatable / AnyView

Each `ForEach` element → **constant** top-level child count. `List` rows must be **unary**. Top-level `if`/`switch`/`AnyView` forces every-row `body` for ids. Filter before `ForEach`. Debug: `-LogForEachSlowPath YES`. Full rules: `list-patterns.md`.

`Equatable` views: targeted only (small inputs, expensive `body`); call `.equatable()`. Update `==` when fields change. Distinct from `Equatable` model props (`state-management.md`).

`AnyView` erases identity — only when an API must type-erase. Never in rows. Representables: `macos-development/appkit-swiftui-bridge/`.

## Containers

Drop useless `Group { OneView() }`. Large collections: `List` first, else lazy stacks in `ScrollView`. `overlay`/`background` decorate; `ZStack` for peer layers. Layered clip: `.compositingGroup()` before `.clipShape()`. Type-check timeout → extract types. Update-cycle debug: `performance-patterns.md`.
