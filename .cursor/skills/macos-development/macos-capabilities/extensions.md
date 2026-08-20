# System Extensions

> Read this when: adding Share, Finder Sync, Quick Look preview/thumbnail, XPC, or App Groups.

## Contents

- [Extension types](#extension-types)
- [Quick Look Preview and Thumbnail](#quick-look-preview-and-thumbnail)
- [Share / Finder Sync (pointers)](#share--finder-sync-pointers)
- [XPC and App Groups](#xpc-and-app-groups)

## Extension types

| Type | Role |
|------|------|
| Quick Look Preview / Thumbnail | File preview stills (this project’s main case) |
| Share / Action | Ingest or transform content from other apps |
| Finder Sync | Badges / context menu in Finder |
| Widget / App Intents | Desktop widgets, Shortcuts |
| XPC Service | Separate process / privilege domain |

Extensions are memory-limited and can die anytime. Declare capabilities in Info.plist; test with a dedicated scheme.

## Quick Look Preview and Thumbnail

Hosts (Finder, Mail, …) run preview in a **separate extension process** — not the host app. Not a renderer tutorial.

| Target | Type | Job |
|--------|------|-----|
| Preview | `NSViewController` + `QLPreviewingController` | Interactive/static preview of one file |
| Thumbnail | `QLThumbnailProvider` | Still for Finder / `QLThumbnailGenerator` |

Declare `QLSupportedContentTypes`. Preview: `preparePreviewOfFile(at:)`. Thumbnail: `provideThumbnail(for:_:)` → `QLThumbnailReply` (often `imageFileURL`).

```swift
class PreviewViewController: NSViewController, QLPreviewingController {
    func preparePreviewOfFile(at url: URL) async throws {
        // `url` scoped for this request. Keep work cancellable.
        let data = try Data(contentsOf: url)
    }
}

class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        // Draw at request.maximumSize * request.scale
        // handler(QLThumbnailReply(imageFileURL: pngURL), nil)
    }
}
```

**Sandbox:** Extension is typically sandboxed even if the host is not. Request URL is scoped for that call only. Persistent access → security-scoped bookmarks (`sandboxing.md`). Share caches via App Group both targets declare.

**Sidecars:** Same-basename extras (textures next to `.gltf`) are not auto-granted. Host declares related types with `NSIsRelatedItemType` (`sandboxing.md`). Test sidecar reads in the extension process. Keep the extension small.

## Share / Finder Sync (pointers)

- **Share:** New Share Extension target; read `NSExtensionItem` attachments; complete or cancel via `extensionContext`. Persist via App Group — no full tutorial here.
- **Finder Sync:** Subclass `FIFinderSync`; set `directoryURLs`; implement badges / `menu(for:)`. Prefer only when Finder chrome is the product.

## XPC and App Groups

**XPC:** Shared `@objc` protocol; service exports object on `NSXPCListener.service()`; app connects with `NSXPCConnection(serviceName:)`. Use to isolate crash-prone or privileged work.

**App Groups:** Same group entitlement on app + extension → `UserDefaults(suiteName:)`, `containerURL(forSecurityApplicationGroupIdentifier:)`, or SwiftData `ModelConfiguration(groupContainer:)`.
