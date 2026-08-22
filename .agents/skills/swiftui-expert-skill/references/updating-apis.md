> Read this when: refreshing `latest-apis.md` after a new iOS / macOS / Xcode release, or when asked to update / scan SwiftUI deprecations.

# Contents

- [Targets](#targets)
- [Workflow](#workflow)
- [Entry format](#entry-format)
- [Guardrails](#guardrails)

# Update latest-apis.md

## Targets

- List: `references/latest-apis.md`
- Scan plan: `references/scan-manifest.md`

Shipping: iOS 26 / macOS 26 / Xcode 26. Do not invent iOS 27 UI guidance except availability footnotes already in `latest-apis.md`.

## Workflow

1. Read `latest-apis.md` (coverage, version segments, Quick Lookup).
2. Read `scan-manifest.md`.
3. Scan each manifest category. Prefer Sosumi MCP (`searchAppleDocumentation`, `fetchAppleDocumentation`, optional `fetchAppleVideoTranscript`). If unavailable, use developer.apple.com / WebSearch. Do not guess replacements.
4. Compare: new deprecations, corrections, new version segments.
5. Update `latest-apis.md` in the established format. Keep the attribution line. Add Quick Lookup rows.
6. Leave edits in place (this tree lives in the repo).

## Entry format

Place under the correct segment (Always Use iOS 15+; When Targeting iOS 16+ / 17+ / 18+ / 26+).

```markdown
**Always use `modernAPI()` instead of `deprecatedAPI()`.**
```

```swift
// Modern
View().modernAPI()

// Deprecated
View().deprecatedAPI()
```

## Guardrails

- Confirm names on developer.apple.com. Do not write `CopyButton`, `searchToolbarBehavior(.minimizable)`, or `navigationTransitionSource`. Use `PasteButton`, `searchToolbarBehavior(.minimize)`, and `matchedTransitionSource` + `navigationTransition(.zoom(sourceID:in:))`.
- If deprecated with no replacement, say so.
