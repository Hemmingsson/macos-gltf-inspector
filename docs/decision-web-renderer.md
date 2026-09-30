# Decision: render glTF in WebKit, not RealityKit

**Status:** **GO**, hybrid on `webkit-renderer`. Finder, Quick Look, and the document
window draw through one Khronos `viewer.html` in `WKWebView`. RealityKit convert remains
for host inspector data and the unused `PreviewScene` fallback — not for on-screen pixels.
**Spike date:** 2026-08-24 · **Branch then:** `spike/web-thumbnail` · Apple Silicon, macOS 26

---

## The question

glTF Inspector is a pre-flight tool for people working with glTF **for the web**: check what a
file contains and how it renders before opening it in Blender or wiring it into a project.
That makes renderer fidelity the product, not an implementation detail — an inspector that
shows you artifacts of its own conversion is worse than no inspector.

The current path converts glTF to RealityKit entities. It cannot reach 1:1, and it rewrites
files before rendering them.

A hard product constraint decides the shape of any answer:

> Thumbnail, Quick Look and the document window must all be the same renderer. A file cannot
> look one way in Finder and another when opened.

Quick Look and the document window can host a `WKWebView` — that is well-trodden. The Finder
thumbnail is the risk: `QLThumbnailProvider` is non-UI and sandboxed. **Can it render WebGL?**

---

## Answer

Yes, with a one-line entitlement change.

```yaml
com.apple.security.network.client: true
```

`WKWebView` spawns a Networking XPC service even when the page makes zero network requests.
Without that entitlement the extension is denied the mach sandbox extension WebContent needs:

```
Sandbox: ThumbnailExtension(37619) deny(1) mach-issue-extension
  target:com.apple.coreservices.launchservicesd
  extension-class:com.apple.webkit.extension.mach
```

WebContent dies on launch and every thumbnail fails with `QLThumbnailError 102`. With the
entitlement, all four test models render correctly and appear in Finder.

Verified through `QLThumbnailGenerator.generateBestRepresentation` — the generator path Finder
uses — against a real signed, installed, sandboxed extension, then confirmed visually in Finder
icon view. `qlmanage` was not used: it hangs headless on this machine, and `qlmanage -x`
exercises a different reply path than Finder.

---

## What was measured

### Fidelity — why this came up at all

Read from the working tree, not from documentation:

| glTF feature | RealityKit path today |
| --- | --- |
| `KHR_materials_transmission` | collapsed to opacity, logged as approximated |
| `KHR_materials_volume` | not rendered |
| `KHR_materials_iridescence` | not rendered |
| `KHR_materials_anisotropy` | not rendered |
| `KHR_materials_dispersion` | not rendered |
| `KHR_materials_diffuse_transmission` | not rendered |
| `KHR_materials_sheen` | colour only, no roughness |
| `KHR_materials_specular` | factor only, no colour |

Worse for an inspector, the pipeline **rewrites the file before rendering it**.
`MetalRoughPrepare` and `RealityPrepare` (~802 lines) re-bake spec-gloss textures, dequantize
meshes, transcode WebP to PNG, and expand GPU instancing into real nodes. Every one of those
is natively supported by both candidate web renderers. The app is honest about the rewrites —
`PreparePipelineReport` surfaces them — but they exist only because the renderer cannot read
the format.

These are not bugs awaiting a fix. They are absent from `PhysicallyBasedMaterial`, and
screen-space refraction needs a scene colour texture RealityKit does not expose. There is no
version of this codebase where RealityKit reaches 1:1.

### Speed

Both stacks, same machine, same files, back to back.

| Model | RealityKit convert | RealityKit → 512px PNG | three.js parse | Web, cold process → first frame |
| --- | --- | --- | --- | --- |
| tiny.glb (428 B) | 0.6–0.8 ms | 19–20 ms | 1.7 ms | 331–356 ms |
| BoomBox (10 MB) | 104–137 ms | 163–198 ms | 114–122 ms | 557–581 ms |
| Corset (13 MB) | 172–220 ms | 142–235 ms | 127–133 ms | 525–773 ms |
| BarramundiFish (12 MB) | 154–197 ms | — | — | — |

Parsing is a wash or better for three.js. One-time stack warm-up also favours WebKit: RealityKit
+ Metal cost ~510 ms on first use in a fresh process (184 ms first `EntityLoader.load`, ~410 ms
first `StillRenderer`) against ~324 ms for process launch + WebContent spawn + JS engine + IBL.

**Through the real sandboxed extension, though, WebKit is clearly slower:**

| File | Total | In page |
| --- | --- | --- |
| BoomBox 10 MB | 1807 ms | 773 ms |
| BarramundiFish 12 MB | 1833 ms | 1070 ms |
| Corset 13 MB | 1841 ms | 1081 ms |
| tiny.glb | 292 ms | 124 ms |

Three large files ran concurrently and share start-up; `tiny.glb` hit an already-warm process.
Against RealityKit's 163–235 ms for the same PNGs, that is roughly **4–8x slower on cold work**.
Thumbnails are async and cached, so this is not disqualifying — but it is the real cost.

Memory is the other cost: the WebKit process family measured **~430 MB RSS** showing BoomBox
(231 MB GPU, 115 MB WebContent, 14 MB Networking, 71 MB host). RSS double-counts shared pages
and the native footprint was not measured for comparison.

---

## What the migration costs

**The UI does not move.** `PreviewUI/` is 8,611 lines importing only SwiftUI, Foundation,
Observation and AppKit — no RealityKit, no `Shared/`. Everything reaches the renderer through
`ViewportController` and `SceneModel`, both already renderer-neutral. A WebKit viewport is a
second implementation of that seam.

| Area | Roughly | Fate |
| --- | --- | --- |
| `PreviewUI/` | 8,611 lines | unchanged |
| `Shared/Convert/` | 2,713 lines | deleted |
| `RealityPrepare` + `MetalRoughPrepare` | 802 lines | deleted |
| `PreviewCamera`, `PreviewLighting`, `PreviewFloor`, `PreviewScene` | ~1,740 lines | rewritten in JS |
| `GLBBox`, `PreviewStats`, `GLTFValidator` | ~900 lines | unchanged — already parse the file, not the conversion |
| `GLTFSessionDocument` builder | ~560 lines | reworked to build from glTF JSON |
| Convert unit tests | large share of 5,491 lines | **no Swift equivalent** |

**The real cost is the last row.** A large share of the test suite asserts on converted
RealityKit entities — materials bound, primitives not dropped, skins built, morphs sampled.
Move rendering into JavaScript and `xcodebuild` cannot run those assertions. The honest
replacement is pixel-diffing against the Khronos sample set: slower, flakier, and more
valuable. Standing it up is most of the switching cost.

One compensation: building `SceneModel` from the glTF JSON rather than from convert output is
*more* correct for an inspector. The sidebar would describe the file, not the subset that
survived conversion.

---

## Which web renderer

**Khronos glTF Sample Renderer**, not three.js — a separate decision from this spike, which
used three.js purely because it ships prebuilt ESM and needs no bundler.

- It is the reference implementation, which is what "1:1 with glTF" is measured against.
- Apache-2.0, pushed as recently as 2026-08.
- Keeps `KHR_materials_pbrSpecularGlossiness`, which three.js dropped, plus
  `KHR_materials_variants` and `KHR_animation_pointer`, which three.js needs add-ons for.
- Ships its own debug output modes — the one thing RealityKit gives free today via
  `ModelDebugOptionsComponent` (13 channels: normal, UV, base colour, metallic, roughness, AO,
  emissive, alpha, specular, tangent, clearcoat and its maps).

Vendor from git; the npm package has been stale since October 2024.

---

## Traps found, worth not rediscovering

**Two false positives reported success while RealityKit was actually rendering.** Neither was
caught by an assertion — only by looking at the image.

1. `UserDefaults(suiteName:)` is invisible to a sandboxed extension: it reads preferences from
   its own container, so `defaults write` on a shared suite never arrives. The flag read
   `false` and thumbnails looked fine.
2. `homeDirectoryForCurrentUser` — and `NSHomeDirectory()` — return the *container* home under
   the sandbox. The marker-file replacement was looked for in the wrong directory and also read
   `false`. `getpwuid(getuid())->pw_dir` gives the real home.

**Assertions that pass on a wrong image.** The "more than 100 distinct colours" check passes on
a near-black silhouette. It catches a blank buffer, not a bad render.

**`PMREMGenerator.fromScene` renders scene *geometry*.** A probe built from a scene containing
only a `HemisphereLight` comes out black, and the result looks exactly like broken WebGL. Use
`RoomEnvironment`.

**A skipped test reports as a passing suite.** `TestModels/Khronos samples/` is gitignored, so a
fresh worktree has none. A symlink is not enough — `FileManager.enumerator` does not descend a
symlinked root, so `TestModels.hasKhronosSamples` stayed false and the sample-gated tests
silently skipped.

**22 registered copies of the app.** `lsregister -dump` found `glTF Inspector.app` registered
from 22 locations, and `pluginkit` was resolving the active thumbnail extension to a stale
Xcode DerivedData build from 22 Aug — not `/Applications`. Any earlier thumbnail verification
on this machine was testing an arbitrary old build. The stale copies were unregistered and
`/Applications` restored as the active provider.

---

## What the spike did not prove (later work on this branch)

These were open after the thumbnail spike. On `webkit-renderer` the first two are done:

- Quick Look **preview** in the same `WKWebView` page (`PreviewViewController` + `webCanvasURL`).
- Khronos Sample Renderer vendored and driven from Swift (`RendererWebKit/web-renderer/`,
  `RendererWebKit/`). Pixel-diff goldens live in `TestModels/References/`.
- Behaviour under Developer ID + notarization — still not the proof this spike ran. The
  spike was Debug-signed. `com.apple.security.network.client` on a thumbnail extension that
  makes no network requests is defensible but has not been through notarization here.
- Thumbnail throughput on a folder of hundreds of files, where per-process WebKit start-up
  stops amortizing. The extension now reuses one warm host per process; folder-scale cost
  is still the real bill.

---

## Renderer choice: Khronos glTF Sample Renderer — confirmed

**Date:** 2026-08-24 · prototyped, not decided from documentation.

Built from `KhronosGroup/glTF-Sample-Renderer` at `main` (Apache-2.0), driven headless in an
off-screen `WKWebView` through the same scheme-handler harness used for the thumbnail spike.
BoomBox rendered correctly with the vendored `neutral.hdr`. Output is visibly better lit than
the three.js prototype: correct studio reflections, readable control labels.

### The five checks

| Check | Result |
| --- | --- |
| Build story | `npm install && rollup -c`. One-time vendoring step — commit `dist/`, no build at app-build time. |
| Headless still render | Works. `canvas.toDataURL()` returns a correct PNG. |
| Byte loading | `loadGltf(ArrayBuffer)` takes GLB bytes directly. Sandboxed file access stays in Swift. |
| Size / parse cost | 6.4 MB JS evaluates in **~30 ms**. Not the problem it looks like — engines parse lazily. |
| Debug channels | **More than RealityKit's 13**, including transmission strength, volume thickness, sheen roughness, specular colour and clearcoat normal. |

### Measured against three.js, same file, same machine

| Phase | Khronos | three.js r180 |
| --- | --- | --- |
| Renderer import + eval | ~30 ms | ~10–70 ms |
| Environment / IBL | ~50 ms | ~20–40 ms |
| **glTF parse** | **11–23 ms** | 114–122 ms |
| First render (shader compile) | 117–465 ms | 87–121 ms |
| **Cold process → first frame** | **490–535 ms** | 557–581 ms |

The reference renderer is **faster overall** and parses 5–10x quicker. Its cost sits in shader
compilation, which is a one-time hit per process, not per file — so it amortizes in the app
window and in a warm thumbnail process.

### Bundle composition

6.4 MB JS, 7.5 MB `libs/`, 896 KB `assets/` (BRDF LUTs). **5.3 MB of `libs/` is
`physx-js-webidl.wasm`**, loaded lazily and never fetched unless a file uses
`KHR_physics_rigid_bodies` — irrelevant to inspection. `libktx.wasm` (1.7 MB) *is* needed:
`KHR_texture_basisu` is common in web glTF. Trimming physics and `KHR_interactivity` from the
rollup config is possible later; it is not blocking.

### Two integration gotchas

1. **`libs/libktx.js` must be loaded as a classic `<script>` before the module.** It defines a
   global `createKtxModule` that `createResourceLoader` reads; without it construction throws
   `Can't find variable: createKtxModule`.
2. **The renderer rejects absolute URLs** for LUT and library paths — *"Absolute URLs are not
   allowed for security reasons"*. Paths must be **relative**, so the page has to be served
   from a directory root under the custom scheme rather than assembled from absolute URLs.

### Consequences

- `MetalRoughPrepare` can go: `KHR_materials_pbrSpecularGlossiness` is native here. Had three.js
  won, that pre-pass would have had to survive.
- `assets/ibl/khronos` already vendors `neutral.hdr`, `field.hdr` and `Colorful_Studio.hdr` with
  stems matching the Sample Viewer's own keys — the environment work is largely done.
- `.gltf` sidecars need `loadGltf(buffer, externalFiles)`; only `.glb` loads from a bare buffer.
  Simplest path is packing sidecars to GLB in Swift, which `GLBBox` already does.
