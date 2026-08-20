# Accessibility review (macOS)

> Read this when: auditing Mac VoiceOver container navigation or keyboard-only use. SwiftUI a11y **APIs** live in `swiftui-expert-skill/references/accessibility-patterns.md`.

## Contents

- [Mac VoiceOver](#mac-voiceover)
- [Keyboard](#keyboard)
- [AppKit notes](#appkit-notes)
- [How to test](#how-to-test)
- [Review checklist](#review-checklist)

Mac VoiceOver is keyboard-driven (VO + arrows) and **container-first**: it moves across groups and enters a container only when asked. Dense Mac UIs nest accessibility elements; extra levels slow every user. Shape the tree; do not re-teach SwiftUI modifiers here.

## Mac VoiceOver

Flag during review:

- Related controls not grouped (title + Apply, inspector clusters). Users should skip a group in one keystroke.
- Excessive nesting (every stack is a container). Flatten decorative wrappers.
- Hover-only buttons (bookmark, overflow). VoiceOver never moves the pointer — mirror the action as an accessibility action.
- Wrong reading order vs visual order. Fix at the owner API (`accessibilitySortPriority` in `swiftui-expert-skill`).
- Long lists with no rotor for the content that matters (bookmarks, unread, selected).

Do not dump trait/label/hint tutorials here. If labels, combine/ignore, or rotors are wrong, cite `swiftui-expert-skill/references/accessibility-patterns.md` and describe the Mac impact.

## Keyboard

Test with System Settings → Keyboard → Keyboard navigation **on and off**.

- Full keyboard loop: tab order, Return/Escape, list arrows, type-select where tables expect it.
- Shortcuts are an accessibility feature. Cover common tasks (New, Save, Find), not only power-user chords. Do not steal ⌘Q / ⌘H / ⌘M.
- `focusable()` on Sonoma+ can steal click-to-focus — see `swiftui-macos.md`.

## AppKit notes

- `setAccessibilityLabel` / `setAccessibilityRole` / `setAccessibilityHelp` on custom views.
- Table cells announce title + useful value, role `.cell`.
- `nextKeyView` loop is closed. `NSMenuItemValidation` disables impossible actions instead of beeping.

## How to test

1. VoiceOver: Cmd+F5. VO+Right through the window. Confirm container hops, then VO+Shift+Down into a group.
2. Keyboard only: Keyboard navigation on. Reach every control. Complete a form.
3. Accessibility Inspector on the Mac target (not an iPhone audit).

## Review checklist

- [ ] Container tree is shallow and matches visual groups
- [ ] Hover-only controls have accessibility actions
- [ ] Keyboard loop works with Keyboard navigation on and off
- [ ] Common shortcuts exist; system shortcuts untouched
- [ ] AppKit custom views expose label/role
- [ ] Cited SwiftUI a11y API fixes point at `swiftui-expert-skill` — not duplicated here
