# Menu Bar Product Architecture

> Read this when: building a menu-bar utility, choosing LSUIElement / activation policy, or deciding MenuBarExtra vs NSStatusItem as a product.

## Contents

- [Scene API lives elsewhere](#scene-api-lives-elsewhere)
- [Product shapes](#product-shapes)
- [LSUIElement and activation](#lsuielement-and-activation)
- [Sandbox and AppKit status item](#sandbox-and-appkit-status-item)

Activation policy, accessory apps, sandbox, status-item product choices. Not a SwiftUI scene tutorial.

## Scene API lives elsewhere

`MenuBarExtra` styles, Settings coexistence, `isInserted:` → `swiftui-expert-skill/references/macos-scenes.md`. This file owns Dock visibility, activation, sandbox, and when AppKit `NSStatusItem` is the architecture.

Removing the extra does **not** reliably quit the process — provide explicit Quit.

## Product shapes

| Shape | Dock | Policy |
|-------|------|--------|
| Full app + optional extra | Visible | `LSUIElement` false, `.regular` |
| Menu-bar utility | Hidden | `LSUIElement` true, `.accessory` |
| Hybrid | User toggle | Runtime `setActivationPolicy` |

Prefer `MenuBarExtra` unless you need AppKit click/badge drawing the scene cannot do.

## LSUIElement and activation

```xml
<key>LSUIElement</key><true/>
```

Hides Dock + Cmd-Tab; does not create the status item. Pair with a status extra or the user has no way back. Handle `applicationShouldHandleReopen` when Dock is visible.

```swift
NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
```

`.accessory` — activate explicitly before windows (`NSApp.activate(ignoringOtherApps: true)`). Persist hybrid choice. Never leave accessory + undismissible window + no status item.

## Sandbox and AppKit status item

MAS menu-bar apps are still sandboxed. Status items grant no extra I/O. Login-at-launch = `SMAppService` (`background.md`). Folder/file watch → Open panel + bookmarks (`sandboxing.md`).

Use `NSStatusItem` for left/right click split, custom drawing, or transient `NSPopover` the scene cannot express. Retain the item; tear down on quit. Host SwiftUI with `NSHostingController` (`../appkit-swiftui-bridge/hosting-controllers.md`).

Checklist: explicit Quit · Dock policy matches product · activate before windows · entitlements match I/O · no assumed quit on hide.
