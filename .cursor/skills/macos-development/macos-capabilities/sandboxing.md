# Sandboxing and Entitlements

> Read this when: the app needs App Sandbox, entitlements XML, security-scoped bookmarks, or user-selected file/folder access.

## Contents

- [Fundamentals](#fundamentals)
- [Entitlements](#entitlements)
- [Security-scoped bookmarks](#security-scoped-bookmarks)
- [Related items](#related-items)
- [Exceptions and failures](#exceptions-and-failures)

## Fundamentals

Sandbox limits the app to its container; required for Mac App Store. Default: no network, no camera, container-only files. Enable each resource via entitlement (+ usage description where required).

Container paths resolve automatically:

```swift
FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
```

Request only what you use. MAS rejects unused or temporary-exception entitlements.

## Entitlements

```xml
<key>com.apple.security.files.user-selected.read-write</key><true/>
<key>com.apple.security.files.bookmarks.app-scope</key><true/>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.application-groups</key>
<array><string>$(TeamIdentifierPrefix)com.example.shared</string></array>
```

Also common: `network.server`, `device.camera` / `microphone`, `automation.apple-events`, `print`, personal-information keys.

## Security-scoped bookmarks

User-selected files (NSOpenPanel / NSSavePanel) get **session** access. Persist across launches with bookmarks:

```swift
let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
// store Data; restore:
var stale = false
let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope,
                  relativeTo: nil, bookmarkDataIsStale: &stale)
if stale { /* re-save bookmark */ }

guard url.startAccessingSecurityScopedResource() else { return }
defer { url.stopAccessingSecurityScopedResource() }
// read/write
```

Always pair start/stop (`defer`). Folder pick + bookmark grants contents under that folder. Need: `files.bookmarks.app-scope` (document-scope only if sharing bookmarks between apps).

## Related items

Sidecars (`.bin` next to `.gltf`, `.srt` next to video) are not granted automatically. On the **host**, declare a related document type with `NSIsRelatedItemType` + extensions. Test in the process that reads them (often a sandboxed QL extension). See `extensions.md`.

## Exceptions and failures

Temporary absolute-path exceptions are **not** MAS-safe (`temporary-exception.files.absolute-path.*`).

| Failure | Fix |
|---------|-----|
| File without consent | Panel or bookmark |
| Network deny | `network.client` / `server` |
| Write outside container | Powerbox or bookmark |
| Apple Events | entitlement + Info.plist targets |
| Hardcoded `~/Desktop` | `FileManager.urls(for:)` |

Verify: `codesign -dvvv --entitlements :- App.app`. Console filter: process + `sandbox` / `deny`.
