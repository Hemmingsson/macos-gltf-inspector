# macOS Tahoe Human Interface Guidelines

> Read this when: reviewing window chrome, toolbars, menus, navigation, or Spotlight/search presentation — not when writing SwiftUI scene APIs (owner: `swiftui-expert-skill`).

## Contents

- [Windows](#windows)
- [Toolbars](#toolbars)
- [Menus and shortcuts](#menus-and-shortcuts)
- [Navigation and controls](#navigation-and-controls)
- [Search and Continuity](#search-and-continuity)
- [Checklist](#checklist)

Platform conventions for macOS 26 review. Cite `swiftui-expert-skill` for scene/toolbar/form syntax.

## Windows

- Standard titled window + unified toolbar. Hidden title bar only when the toolbar still provides window controls and a drag region.
- Set a sensible `defaultSize` and resizability. Document windows are larger than settings panels.
- Multi-window apps need File → New Window (or equivalent) and a Settings scene. Do not trap the user in a single fixed frame.
- Touch Bar is gone on current hardware — do not require it.

## Toolbars

- Leading: sidebar toggle. Center: search/filter. Trailing: primary actions / share.
- Customizable toolbars (`toolbar(id:)`) when the window is an editor.
- Prefer system placements over a custom button row that duplicates the toolbar.

## Menus and shortcuts

- Keep the standard File / Edit / View / Window / Help structure. Add a custom menu only for a real Tools-like group.
- Honor ⌘N / ⌘S / ⌘W / ⌘Z / ⇧⌘Z. Do not steal ⌘Q, ⌘H, ⌘M, or ⌘Tab.
- List and table rows should offer a context menu for Open / Duplicate / Delete.

## Navigation and controls

- Sidebar shells: `NavigationSplitView`. Distinct peer sections: tabs. Settings: grouped form + `LabeledContent`.
- Primary / secondary / tertiary button styles. Destructive actions use `role: .destructive` and a confirmation.
- Alerts for destructive confirmations; confirmation dialogs for export-style choices; sheets for multi-field work.

## Search and Continuity

Index content with Core Spotlight using `UTType` / `.content` — not `kUTTypeContent as String`:

```swift
import CoreSpotlight
import UniformTypeIdentifiers

let attributes = CSSearchableItemAttributeSet(contentType: .content)
attributes.title = article.title
attributes.contentDescription = article.excerpt
```

`NSUserActivity` remains Handoff/search eligibility, not a new Tahoe-only API. `tel:` / `facetime:` links are fine when the product places calls.

## Checklist

- [ ] Standard window chrome and size constraints
- [ ] Multi-window / Settings if the product needs them
- [ ] Toolbar organization and customization where expected
- [ ] Standard menus and shortcuts; no system-shortcut theft
- [ ] Sidebar or tabs match the information architecture
- [ ] Context menus on list/table rows
- [ ] Spotlight uses `UTType` / `.content` when indexing
- [ ] No Touch Bar dependency

## Resources

- [macOS HIG](https://developer.apple.com/design/human-interface-guidelines/macos)
- [macOS design resources](https://developer.apple.com/design/resources/)
