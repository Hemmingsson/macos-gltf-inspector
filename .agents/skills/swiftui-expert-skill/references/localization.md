> Read this when: writing user-facing SwiftUI text, String Catalogs, `Text(verbatim:)`, locale-aware formatting, RTL, or translator comments.

# Localization

**Contents**
- [Text & catalogs](#text--catalogs)
- [Bundles & types](#bundles--types)
- [Interpolation & casing](#interpolation--casing)
- [Formatting & layout](#formatting--layout)
- [Locale & comments](#locale--comments)

## Text & catalogs

`LocalizedStringKey` literals (`Text`, `Button`, `Label`, titles) are keys. Don't wrap in `String(localized:)` / `NSLocalizedString` — eager resolve ignores `\.locale`.

```
String variable? → Text(variable)          // no localization
Literal to localize? → Text("…")
Literal must not localize? → Text(verbatim: "…")
```

Catalogs (`.xcstrings`) must exist — Xcode won't create them. Route with `tableName:`. Existing `.strings`/`.stringsdict` projects: add there, don't migrate mid-edit.

## Bundles & types

Frameworks/packages need `bundle: #bundle` (or `Bundle.module`) — else silent key fallback from `Bundle.main`.

`String` vars skip localization. Expose `LocalizedStringResource` / `LocalizedStringKey` from models. Non-view carriers store `LocalizedStringResource` (resolve at display).

```swift
enum Category {
    case appetizers
    var name: LocalizedStringResource { "Appetizers" }
}
Text(category.name)
```

## Interpolation & casing

Interpolation keeps format keys (`"Welcome, %@"`). `+` → plain `String`, not localized. Never glue fragments — word order varies.

Bake case into the string; avoid `.textCase` / runtime transforms on localized copy.

## Formatting & layout

`Text(..., format:)` / `.formatted()` — not hard-coded `DateFormatter` patterns. Field components choose fields; locale chooses order. Lists: `Array.formatted()`.

`.leading`/`.trailing` (RTL). No fixed text frames; `ViewThatFits` for long translations. Text styles, not fixed points.

## Locale & comments

`@Environment(\.locale)` in views — not `Locale.current`. Outside views: `String(localized:comment:)`, not `NSLocalizedString`.

`comment:` = UI role + placeholder **positions** for interpolations.

```swift
Text("Completed \(count) of \(total)",
     comment: "Progress — first is finished, second is total.")
```
