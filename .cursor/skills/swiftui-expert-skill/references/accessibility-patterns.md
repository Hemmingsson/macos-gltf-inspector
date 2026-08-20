> Read this when: implementing SwiftUI VoiceOver, Dynamic Type, grouping, or custom-control a11y. Mac audit process: `macos-development/ui-review-tahoe/accessibility.md`.

# Accessibility Patterns

**Contents**
- [Core](#core)
- [macOS VoiceOver](#macos-voiceover)
- [Dynamic Type](#dynamic-type)
- [Traits & images](#traits--images)
- [Grouping](#grouping)
- [Custom controls](#custom-controls)

## Core

Prefer `Button` over `onTapGesture` — VoiceOver, focus, traits free.

## macOS VoiceOver

Mac VO navigates by **container**. Shallow trees; group with `.contain` / `.combine`. Fix order with `accessibilitySortPriority` when visual ≠ announcement. Audit process: `macos-development/ui-review-tahoe/accessibility.md`.

## Dynamic Type

Prefer system text styles. Custom: `Font.custom(_:size:relativeTo:)` (or size-only → scales with body). Non-text sizes: `@ScaledMetric` / `@ScaledMetric(relativeTo:)`.

```swift
@ScaledMetric(relativeTo: .body) private var iconSize = 18.0
Text("Article").font(.custom("SourceSerif4-Semibold", size: 28, relativeTo: .title2))
```

## Traits & images

```swift
Text(item.title)
    .accessibilityAddTraits(item.isSelected ? [.isSelected, .isButton] : .isButton)
```

`.disabled(true)` → VO says "Dimmed". Decorative assets: `Image(decorative:)`. SF Symbol decoration: `.accessibilityHidden(true)`. Meaningful images need `.accessibilityLabel`.

## Grouping

| Mode | Effect |
|------|--------|
| `.combine` | Child labels joined as one element |
| `.ignore` | Manual `.accessibilityLabel` on container |
| `.contain` | Named container; VO enters/exits as a group |

```swift
HStack { Text(item.name); Spacer(); Text(item.price) }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(item.name), \(item.price)")
```

## Custom controls

```swift
.accessibilityElement()
.accessibilityValue("Page \(selectedIndex + 1) of \(pageCount)")
.accessibilityAdjustableAction { direction in /* increment/decrement */ }

.accessibilityRepresentation { Toggle(label, isOn: $isOn) }

.accessibilityLabeledPair(role: .label, id: "volume", in: ns)
.accessibilityLabeledPair(role: .content, id: "volume", in: ns)
```
