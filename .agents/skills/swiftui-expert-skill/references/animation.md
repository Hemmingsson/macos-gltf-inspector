> Read this when: implementing or reviewing SwiftUI animations, transitions, `PhaseAnimator`, `matchedGeometryEffect`, or zoom / `matchedTransitionSource`.

# Animation

**Contents**
- [Implicit vs explicit](#implicit--explicit)
- [Placement / timing / perf](#placement--timing--perf)
- [Transactions & transitions](#transactions--transitions)
- [matchedGeometry & zoom](#matchedgeometry--zoom)
- [Phase / keyframe / Animatable](#phase--keyframe--animatable)

## Implicit vs explicit

| Trigger | API |
|---------|-----|
| Value change | `.animation(_:value:)` — **always** `value:` |
| Event | `withAnimation` |

Later implicit animations override earlier explicit. Disable: `.transaction { $0.animation = nil }` / `disablesAnimations = true` — no zero-duration hacks.

```swift
.animation(.spring) { $0.frame(width: expanded ? 200 : 100) }  // iOS 17+ scoped
```

## Placement / timing / perf

Put `.animation` **after** properties it should interpolate. Curves: `.spring` (UI), `.easeInOut` (appear), `.bouncy` (playful), `.linear` (progress). Prefer GPU transforms over animating `frame`/`padding`. Never `.animation` on a root `VStack`. Gate scroll prefs: animate only on threshold **cross**.

## Transactions & transitions

`withAnimation` = `withTransaction(Transaction(animation:))`. Custom `TransactionKey` (iOS 17+). `.transaction { }` without `value:` fires like deprecated bare `.animation`.

**Property animation** = same identity. **Transition** = insert/remove. Animation context must live **outside** the `if`.

```swift
.animation(.spring, value: show)
if show { DetailView().transition(.scale.combined(with: .opacity)) }
```

Built-ins: `.opacity`, `.scale`, `.slide`, `.move(edge:)`, `.offset`; `.asymmetric`. Identity change (`if`/`else`, `.id`) → transition. Custom: `Transition` (iOS 17+) or `AnyTransition.modifier`. Inline blur/opacity on conditional ≠ transition.

Completion: `withAnimation { } completion:` or `.transaction(value:) { $0.addAnimationCompletion { } }` — without `value:` completion fires once.

## matchedGeometry & zoom

Same hierarchy: shared `@Namespace` + `id`; one `isSource: true`. Prefer for in-place expand. Navigation/sheets → zoom (iOS 18+ / macOS 15+). **Correct names**:

| Role | API |
|------|-----|
| Source | `.matchedTransitionSource(id:in:)` |
| Destination | `.navigationTransition(.zoom(sourceID:in:))` |

Not `navigationTransitionSource` / `navigationTransitionDestination`. Destination modifier on the **presented** view.

## Phase / keyframe / Animatable

`phaseAnimator` (iOS 17+): discrete steps; `trigger:` one-shot; omit to loop. No `asyncAfter` sequencing. `keyframeAnimator`: parallel tracks (`Cubic`/`Linear`/`Spring`/`Move`).

Prefer `@Animatable` (iOS 26+ / macOS 26+); `@AnimatableIgnored` for non-interpolated props. Manual `animatableData` only for custom clamp/wrap. Missing → `EmptyAnimatableData` → **jump**.
