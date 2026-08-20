> Read this when: adopting or reviewing Liquid Glass on iOS 26+ / macOS 26+ — chrome, controls, custom `.glassEffect`, morphing, or material fallbacks.

# Liquid Glass

**Contents**
- [When / availability](#when--availability)
- [glassEffect & variants](#glasseffect--variants)
- [System chrome & container](#system-chrome--container)
- [Morph / union / buttons](#morph--union--buttons)
- [Extension, zoom, order, fallbacks](#extension-zoom-order-fallbacks)
- [Pitfalls](#pitfalls)

## When / availability

Glass = **nav/control layer** (toolbars, tab bars, buttons, floating chrome). Not lists, tables, media, dense content. Prefer glass on 26+ chrome; materials only as `#available` fallback or content surfaces. Custom `.glassEffect` is the exception — prefer system bars + `.buttonStyle(.glass)` / `.glassProminent`.

```swift
if #available(iOS 26, macOS 26, *) { /* glass */ } else { /* material */ }
```

## glassEffect & variants

```swift
nonisolated func glassEffect(
    _ glass: Glass = .regular,
    in shape: some Shape = DefaultGlassEffectShape()  // Capsule — not .rect
) -> some View
```

No `isEnabled` on this overload. Apply **after** layout/visual modifiers (anchors to bounds including padding).

`Glass`: `.regular`, `.clear`, `.identity` — **no** `Glass.prominent`. Prominence = `.buttonStyle(.glassProminent)`. Tint/interact: `.regular.tint(.blue).interactive()` — `.interactive()` only on real controls (mainly iOS feel).

## System chrome & container

Rebuild with matching SDK → system bars glass. Remove conflicting `.toolbarBackground` / custom bar materials. Partial sheets glass by default — drop custom `.presentationBackground` unless content-surface reason. Scroll-edge blur fades under bars — don't add extra darkening behind bar items.

Glass cannot sample other glass. Group custom glass in `GlassEffectContainer(spacing:)` matching layout spacing (larger spacing → blend at rest; animate gap → morph). Don't wrap every isolated system button.

## Morph / union / buttons

Morph needs container + `@Namespace` + matching `glassEffectID` + real insert/remove (not opacity alone) + animation.

```swift
.glassEffect().glassEffectID("pencil", in: namespace)
.glassEffectTransition(.matchedGeometry)  // or .materialize / .identity
.glassEffectUnion(id: "1", namespace: namespace)  // merge same shape+Glass+id
```

Prefer `.buttonStyle(.glass)` / `.glassProminent`. Custom glass: matching `contentShape`. Mac over-tint: optional `.tint(.clear)` workaround — not a required rule.

## Extension, zoom, order, fallbacks

`.backgroundExtensionEffect()` on hero/media behind glass nav — keep text legible; no body copy inside glass.

Zoom: `.matchedTransitionSource(id:in:)` + `.navigationTransition(.zoom(sourceID:in:))` — not invented source/destination names.

Order: font/style → padding → `.glassEffect()` last.

Fallback: `.ultraThinMaterial` (then thin/regular/thick/ultraThick) in `Capsule()`. Mac content fills: `WindowBackgroundShapeStyle.windowBackground` — don't fake chrome with materials on 26+.

## Pitfalls

- Custom glass without container → inconsistent sampling / cost
- Glass on every scroll row → jank; float chrome
- Hits only on glyph → `contentShape`
- `rotationEffect` on SwiftUI glass morphs oddly → UIKit `UIGlassEffect` bridge if needed
- Custom `.presentationBackground` fights sheet glass
- Morph needs container + ID + namespace + animation + conditional insert
- Conflicting `.toolbarBackground` blocks system glass
- Test Reduce Transparency / Increase Contrast / Reduce Motion
