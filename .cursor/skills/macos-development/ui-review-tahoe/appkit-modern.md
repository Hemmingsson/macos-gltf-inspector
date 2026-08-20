# Modern AppKit review (macOS 26)

> Read this when: reviewing AppKit or hybrid windows for Tahoe chrome, materials vs glass, or whether a table should leave SwiftUI.

## Contents

- [When AppKit is justified](#when-appkit-is-justified)
- [Materials vs Liquid Glass](#materials-vs-liquid-glass)
- [Windows and toolbars](#windows-and-toolbars)
- [Review checklist](#review-checklist)

AppKit modernization **review**. Representable how-to: `../appkit-swiftui-bridge/`. Glass API: `swiftui-expert-skill/references/liquid-glass.md`. Menu-bar product: `../macos-capabilities/menubar.md`.

## When AppKit is justified

- Rich text (`NSTextView`), custom drawing, or a feature SwiftUI cannot express
- Legacy controllers you are migrating incrementally
- **Measured** list performance — profile SwiftUI `Table`/`List` first. Do not start from “complex table → AppKit.” Bridge `NSTableView` only after Instruments shows a need (`../appkit-swiftui-bridge/nsviewrepresentable.md`)

Prefer `@Observable` view models. Auto Layout over springs-and-struts. Validate menu items on the responder chain.

## Materials vs Liquid Glass

`NSVisualEffectView` = materials/vibrancy, **not** Liquid Glass. Custom glass → host SwiftUI (`.glassEffect` / glass button styles) via `NSHostingView`. API: `swiftui-expert-skill/references/liquid-glass.md`. Flag any “NSVisualEffectView for Liquid Glass” claim.

## Windows and toolbars

- `fullSizeContentView` + transparent title bar only when the toolbar still provides traffic lights and a drag region
- `NSToolbar` in icon-or-label mode; `NSSplitViewController` sidebar items with an autosave name
- Dark mode and accent color via semantic colors, not hard-coded fills

## Review checklist

- [ ] SwiftUI `Table`/`List` profiled before `NSTableView`
- [ ] `NSVisualEffectView` used only as material/vibrancy, never as “Liquid Glass”
- [ ] System chrome left intact on macOS 26+ unless a custom hosted glass surface is intentional
- [ ] Auto Layout; responder chain; menu validation
- [ ] Dark mode and accent color
- [ ] Hosted SwiftUI cleaned up (`dismantle`, first-click, scroll) — see the bridge skill

## Resources

- [AppKit](https://developer.apple.com/documentation/appkit)
- [NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview)
