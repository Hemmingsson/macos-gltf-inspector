# Renderer backends

Which renderer draws the window, Quick Look and the Finder thumbnail, how to switch it while
developing, and how the default one is packaged into the app and both extensions.

## The default and the overrides

All three surfaces build their host through one factory, `CanvasRenderer.makeHost`
(`RendererWebKit/CanvasRendererHost.swift`), so they always use the same backend:

| `GLTF_RENDERER` | Host | Renderer |
| --- | --- | --- |
| unset, or any unknown value | `KhronosMetalRendererHost` | The native Metal port of the Khronos glTF Sample Renderer (`RendererMetal/`). **Shipped default.** |
| `filament` | `FilamentRendererHost` | Google's Filament (`FilamentBridge/`). |
| `webkit` | `WebRendererHost` | The Khronos page in a `WKWebView` ([pipeline](pipeline-web-renderer.md)), which is also the pixel-diff oracle. |

The variable is a dev override, read from the process environment. For the window, run
`GLTF_RENDERER=webkit ./scripts/dev.sh run cube`: `dev.sh run` writes it to the `dev-env` file
beside the `.build` app, which a Debug build applies at launch (`DevLaunch`), and the next
`dev.sh run` rewrites that file. The extensions are launched by the system, so in practice they
always get the default. There is no user-facing renderer setting (AGENTS.md pitfall 7).

The test scheme sets `GLTF_RENDERER=webkit`, so a test that mounts a canvas without passing a
host drives the page. Suites that test a specific backend pass it explicitly:
`CanvasRenderer.makeHost(mode:backend:)` or `ThumbnailRenderer(backend:)`.

## Surfaces

| Surface | Code path | Mode |
| --- | --- | --- |
| Document window | `DocumentWindow` → `WebPreviewCanvas` → `WebCanvasController` → factory | `.live` |
| Quick Look | `PreviewViewController` prestarts a factory host, then hands it to `WebCanvasController` | `.live` |
| Finder thumbnail | `ThumbnailProvider` → `ThumbnailRenderer` (one warm host, serialized) → `QLThumbnailReply(imageFileURL:)` | `.still` |

`ThumbnailRenderer` lives in `RendererWebKit` so the tests can drive the thumbnail's real
render path in-process (`qlmanage` hangs headless).

## Packaging

Each framework is embedded once, in `glTF Inspector.app/Contents/Frameworks`. The appex binaries
link `GLTFCore` and `RendererWebKit`, and find everything else through their
`@executable_path/../../../../Frameworks` rpath:

| Framework | Brings | Notes |
| --- | --- | --- |
| `RendererMetal.framework` | `default.metallib` (`Bundle(for: MetalRenderer.self)`) | DracoSwift, mikktspace and meshoptimizer are linked in statically. |
| `GLTFKit2.framework` | the glTF loader | Dynamic. Embedded only by the host app's own package dependency, *without* `embed: true` (see `project.yml`). |
| `GLTFCore.framework` | `khronos/*.hdr` and the prefiltered `khronos/*.metalibl` bakes | `MetalEnvironment` finds a bake next to its HDR (`KhronosEnvironments.bundledURL`). |

Every resource the Metal renderer reads is inside the signed app bundle, so the sandboxed
extensions read nothing outside their container except the glTF file and its siblings (covered
by the existing read-only entitlements). Metal needs no extra entitlement. The extensions keep
`com.apple.security.network.client` because the WebKit override still ships in them.

To check a build: run `./scripts/dev.sh install`, then on `.build/glTF Inspector.app` run
`otool -L` on each appex and framework binary, list `Contents/Frameworks` (no appex has its own
`Frameworks`), and run `codesign --verify --deep --strict`.

## Tests

| Test | Covers |
| --- | --- |
| `CanvasRendererFactoryTests` | Metal is the default; `filament` / `webkit` overrides build their hosts. |
| `ThumbnailRenderPathTests` | The thumbnail path end to end on the default backend: PNG size and coverage, renderer mark, serialized requests, a rejected file, Draco. |
| `QuickLookCanvasPathTests` | A prestarted live Metal host through `WebCanvasController`: `.ready`, export at the canvas size, the failure copy. |
| `PixelDiffMetalTests` (with `TEST_RUNNER_GLTF_METAL_PARITY=1`) | The Metal port against the WebKit references. |
