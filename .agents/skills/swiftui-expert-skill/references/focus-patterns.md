> Read this when: implementing or reviewing SwiftUI focus, `@FocusState`, or keyboard / Mac / TV focus.

# Focus Patterns

**Contents**
- [@FocusState](#focusstate)
- [Focusable views](#focusable-views)
- [Focused values](#focused-values)
- [Default / scope](#default--scope)
- [Search & effects](#search--effects)
- [Pitfalls](#pitfalls)

## @FocusState

Always `private`. `Bool` for one field; optional `Hashable` enum for many. Set enum / `nil` to move / dismiss keyboard.

```swift
enum Field: Hashable { case name, email }
@FocusState private var focusedField: Field?

TextField("Name", text: $name).focused($focusedField, equals: .name)
TextField("Email", text: $email).focused($focusedField, equals: .email)
```

`.focused($bool)` is true when the view **or any focusable descendant** has focus. `.focused($enum, equals:)` is true only when that specific view has focus.

`@Environment(\.isFocused)` — nearest focusable ancestor; style non-focusable children.

## Focusable views

Non-text views need `.focusable()` before `.focused()` / `onKeyPress` / `onDeleteCommand`.

iOS 17+ `.focusable(interactions:)` — `.activate` (keyboard-nav buttons), `.edit` (keyboard/Crown), `.automatic`.

## Focused values

Publish selection for Commands/menus. Prefer `@Entry` on `FocusedValues`.

```swift
extension FocusedValues { @Entry var selectedDocument: Binding<Document>? }

.focusedValue(\.selectedDocument, $document)       // view-scoped
.focusedSceneValue(\.selectedDocument, $document)  // scene-scoped

@FocusedBinding(\.selectedDocument) var document   // in App commands
```

`@FocusedObject` / `.focusedObject` / `.focusedSceneObject` for `ObservableObject`.

## Default / scope

Prefer `.defaultFocus($focusedField, .email)` over `@FocusState` in `onAppear` (iOS 17+). Priority: `.automatic` vs `.userInitiated`.

macOS/tvOS/watchOS: `.focusScope(_:)`, `prefersDefaultFocus(_:in:)`, `@Environment(\.resetFocus)`.

`.focusSection()` (macOS 13+ / tvOS 15+) — guides directional focus across spatially separated groups.

## Search & effects

`.searchFocused` / `.searchFocused(_:equals:)` binds to nearest `.searchable` field.

`.focusEffectDisabled()` — suppress system ring when drawing custom focus chrome. Read `isFocusEffectEnabled`.

## Pitfalls

- **Redundant `@FocusState` write** — `.focusable()` + `.focused()` already focuses on click. Extra `onTapGesture { isFocused = true }` double-evaluates and **revokes** focus; key commands die.
- **Same enum case on two views** — ambiguous; runtime warning.
- **`onAppear` focus** — may race; prefer `.defaultFocus`. Last resort: `DispatchQueue.main.async`.
- **Missing `.focusable()`** on custom views — bindings and key handlers never fire (`TextField` is implicit).
