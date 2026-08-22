> Read this when: the repo has a real second product or a share need (host + Quick Look + thumbnail, app + CLI). Skip for a single-target Mac app.

Contents:

- [One target first](#one-target-first)
- [When SPM is justified](#when-spm-is-justified)
- [If you extract](#if-you-extract)

# One target first

Keep the app in one target. Group by feature folder when files pile up (`Host/`, `Settings/`, `Convert/`). Shared convert/render code can live in a folder the app target compiles — that is not a package.

Do not split Views / ViewModels / Models across top-level folders. Do not add SPM because a blog said “modular.”

# When SPM is justified

Add a local package only when two *products* must compile the same code:

- Host app + Quick Look / thumbnail extensions
- App + CLI / XPC that cannot just share the app target
- A second shipping app

“Clean API,” faster incremental builds, or “future reuse” is not enough.

# If you extract

- Thin app target; package owns the shared compile unit.
- Features depend on the shared package; packages do not import the app.
- `internal` by default. `public` only on the types the other product calls.
- Platforms in `Package.swift` match the documented target (macOS 26 / iOS 26). Do not invent 27.

```
GLTFInspector.xcodeproj
GLTFInspector/          # host UI
PreviewExtension/
ThumbnailExtension/
Shared/              # same sources in all three targets — or one local package if Xcode target membership becomes painful
```

Prefer Xcode target membership on a `Shared/` folder until membership itself is the problem. Then one local package, not a graph of feature packages.
