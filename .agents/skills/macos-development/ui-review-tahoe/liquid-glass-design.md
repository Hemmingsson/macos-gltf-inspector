# Liquid Glass design review (macOS 26)

> Read this when: reviewing whether chrome uses glass vs materials, or content is incorrectly glassed.

Design-language only. **API how-to:** `swiftui-expert-skill/references/liquid-glass.md` — do not re-teach modifiers here.

## What to flag

- Glass on list/table/media content
- Calling materials / `NSVisualEffectView` “Liquid Glass”
- Stacked translucent layers that muddy contrast
- Hard-coded light-only fills on translucent chrome
- Missing safe padding under transparent menu bar
- Decorative motion that fights Reduce Motion / Reduce Transparency
- Custom glass without `#available` fallback when deployment target < 26

## Checklist

- [ ] Chrome/controls prefer glass on macOS 26+ (gated); materials labeled as materials
- [ ] No glass on scroll content rows
- [ ] Contrast / Dynamic Type OK on translucent surfaces
- [ ] Menu bar / toolbar does not hide controls

Related: `macos-tahoe-hig.md`, `swiftui-macos.md`, `appkit-modern.md`.
