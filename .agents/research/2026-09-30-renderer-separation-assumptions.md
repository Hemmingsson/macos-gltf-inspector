# Renderer separation: assumption check

Checks `.agents/plans/2026-09-30-renderer-separation.md` against `main` @ `a4a4a2f` (repo root), `webkit-renderer` @ `fa7dd64` plus its uncommitted worktree, the installed `/Applications/glTF Inspector.app`, Xcode 27.0 (27A266a), and Apple primary sources. Nothing in the repo was modified. The merge simulation used `git merge-tree` and `git stash create`, which write only dangling objects.

Verdicts: **CONFIRMED**, **WRONG** (or partly wrong), **UNVERIFIABLE** (needs a build or run).

## Answer first: corrections that change the plan

1. **"1.1 has shipped" is WRONG.** `gh release list -R Hemmingsson/macos-gltf-inspector` returns nothing. The repo has no tags. The appcast URL from `SUFeedURL` returns HTTP 404. `SUPublicEDKey` in `project.yml` is the placeholder `AAAA…=`. `MARKETING_VERSION: "1.1"` is only a build setting. On this machine the prefs plist contains no `settings.*` keys and `~/Library/Application Support/glTF Inspector/look.json` does not exist. The migration step in seam 2 can be dropped, or reduced to a best-effort copy for the developer's own machine.
2. **`./scripts/dev.sh test` does not exist** on either branch. `scripts/dev.sh` has only build, install, run, logs, fixtures and fixture-path (`scripts/dev.sh:100-125`). AGENTS.md:40 has the same bug. Every seam's check says "`dev.sh test` green", so it needs a real command: the `xcodebuild … test` from AGENTS.md:35-37, or a new `test` subcommand added to `dev.sh`.
3. **PreviewUI is not app-extension-safe.** The appexes build with `APPLICATION_EXTENSION_API_ONLY = YES`. PreviewUI builds with `= NO` and calls `NSApp` in `PreviewUI/Settings/PreviewSettingsRoot.swift:29,298` and `PreviewUI/Components/NodeRow.swift:172`. The Approach option "GLTFCore / renderers may `import PreviewUI`" would make both appexes link a framework that is not extension-safe. Expect the linker warning "linking against a dylib which is not safe for use in application extensions", and extension-safe frameworks cannot import it cleanly. This strongly favours the other option: keep the value types in core, or split a tiny extension-safe PreviewUI "Seam models" module.
4. **New frameworks need `APPLICATION_EXTENSION_API_ONLY: YES`.** "Copy the PreviewUI settings block" would copy `NO`. Setting it to `YES` will surface `Shared/StillRenderer.swift:244-253` (NSSavePanel + `NSApp.keyWindow`). The save-panel code has to leave `StillRenderer` *before* it can live in `RendererRealityKit`.
5. **"New code needed: material-variant names from JSON" is WRONG for the target branch.** `webkit-renderer` already has `GLTFDocumentJSON.materialVariantNames(json:)` (`Shared/GLTFDocumentJSON.swift:72`, used at `Shared/EntityLoader.swift:71`), and it builds the session document from JSON (`EntityLoader.swift:67`). Only JSON dimensions are new. A partial source exists: the page's fit already returns bounds (`Shared/WebRenderer/WebRendererBridge.swift:307`).
6. **"GLBTry is called only from RK prepare paths (`GLBBox.serialize`, `EntityLoader`)" is partly wrong.** `GLBBox.packSidecar` also calls `serialize` (`Shared/GLBBox.swift:120`). About 20 test fixture helpers call `GLBBox.serialize` / `writePrepared` to build GLBs, including core-side tests such as `PreviewStatsTests.swift:49` and `SessionDocumentTests.swift:525`. On the web branch, core code uses the *rest* of `GLBBox`: `GLTFBinaryStore` calls `parse`, `intValue` and `decodeDataURI`, and `WebRendererLoadCopy` calls `peekDocumentJSON`. So `GLBBox` itself has to split (parse/peek/int helpers → core; serialize/pack/writePrepared → RK), and test fixtures need a GLB writer that doesn't use GLBTry. `GLTFInspectorError` is defined in `Shared/GLBTry.swift:3` and is used by EntityLoader and Convert, so it moves as well.
7. **App Group entitlement.** The team-ID-prefixed group needs no profile or registration, but **the host app has no entitlements file today**. It is not sandboxed: the installed binary carries only `get-task-allow`, and the `GLTFInspector` target in `project.yml` has no `entitlements:` block. Seam 2 has to add one; otherwise `UserDefaults(suiteName:)` in the host will not resolve to the group container.

## Per-claim verdicts

### Context claims

| Claim | Verdict | Evidence |
|---|---|---|
| `PreviewUI/` is renderer-free | CONFIRMED | `grep -rl '^import RealityKit\|^import WebKit' PreviewUI` is empty on both branches |
| `Shared/` compiled by source into 3 targets with `excludes:` | CONFIRMED | `project.yml` main: app sources, PreviewExtension excludes 5 files, ThumbnailExtension excludes 15 |
| Bridging header imports only `GLBTry.h` | CONFIRMED | `Shared/GLTFInspector-Bridging-Header.h` is one line; set project-wide in `project.yml` `settings.base` |
| Draco found by class name | CONFIRMED | `Shared/EntityLoader.swift:163` `GLTFAsset.dracoDecompressorClassName = "GLBDracoDecompressor"`; no Swift reference to the class |
| GLBTry only from RK prepare paths | PARTLY WRONG | see correction 6 |
| RK in 8 host files | CONFIRMED | EngineAnimationPlaybackController, EngineSceneModel, EngineViewportController, ScreenshotCameraPose, HostPreviewContainer, HostShellRootView, HostSidebarModel, PreviewSelectionVisuals (same 8 on both branches) |
| 23 RK test files on main, 24 on webkit | CONFIRMED | `grep -rl '^import RealityKit' GLTFInspectorTests \| wc -l` gives 23 / 24 |
| main `ThumbnailProvider` imports RK | CONFIRMED | `ThumbnailExtension/ThumbnailProvider.swift:2`; on webkit it doesn't import RK but calls `StillRenderer.writePNG` (`:70`) |
| web-renderer 9.1 MB HEAD / 6.2 MB tree | CONFIRMED | `git ls-tree -l` sum 9.04 MiB; `du -sh` 6.2M |
| HDRs 4.4 MB | CONFIRMED | `du -sh assets/ibl/khronos` 4.4M (3 × .hdr: 1636 + 1560 + 1340 KB) |
| copied into all 3 bundles; test bundle copies HDRs too | CONFIRMED | installed app: `viewer.html` ×3, each `web-renderer/` 6.2M, `khronos/*.hdr` ×3; `project.yml` test target lists `assets/ibl/khronos`. Duplicates cost about 21 MB of 63 MB |
| GLTFKit2 dynamic in Contents/Frameworks, appexes load via `@executable_path/../../../../Frameworks` | CONFIRMED | `otool -L` appex: `@rpath/GLTFKit2.framework/Versions/A/GLTFKit2`; `otool -l` LC_RPATH `@executable_path/../Frameworks` and `@executable_path/../../../../Frameworks`; appexes have no own `Frameworks/` |
| DracoSwift static `libdraco.a` | CONFIRMED | `DracoSwift/Package.swift` is a binaryTarget `Libs/Draco.xcframework`; `file …/libdraco.a` gives an ar archive. GLTFKit2 is a binaryTarget xcframework (dynamic) |
| main WIP moved state into `@Observable PreviewSession` | CONFIRMED | `git show --stat a4a4a2f`: +48 `Shared/PreviewSession.swift`. The same commit also has a +501/−? rewrite of `RealityKitConvert+Mesh.swift` and `.vscode` changes, so "decide what is real" is warranted |
| webkit uses `stored*` + `WebPreviewCanvas.Look` | CONFIRMED | `EngineViewportController.swift:107 storedEnvironment`; `HostShellRootView.swift:133` |
| conflicts in EVC, HostShellRootView, EntityLoader | CONFIRMED | `git merge-tree --write-tree main webkit-renderer`: exactly those 3; `project.yml` auto-merges. Same result with the uncommitted tree (`git stash create` → merge-tree). Merge-base `3d2b374`; main is 1 commit ahead, webkit 15 |
| `PreviewSession` "imports" `PreviewCamera` (RK) and stores `[PreviewDebugMode]` | CONFIRMED (wording) | Not an import but a same-module reference: `fieldOfViewDegrees = PreviewCamera.defaultFieldOfViewDegrees`, `debugModes: [PreviewDebugMode]` (PreviewDebugMode.swift imports RK and wraps `ModelDebugOptionsComponent.VisualizationMode`). Also references `PreviewBackground` (`AppSettings.swift`, RK-free) |
| look stored in two places (`look.json` vs UserDefaults) | CONFIRMED | `AppLook.supportDirectory()` = Application Support/glTF Inspector; `EngineAppLookRouting` routes useEnvironmentMap / environmentCatalog / customEnvironmentFile to `AppLookStore`. It is actually **three** key vocabularies; see New risks |
| `RendererLookDefaults` → web extensions always get `neutral` | CONFIRMED (code + disk) | `.worktrees/webkit-renderer/Shared/WebRenderer/RendererLookDefaults.swift:17,51-53` reads `settings.preview.environmentCatalog` from `~/Library/Preferences/lol.mattias.gltf-inspector.plist`. The app writes that key only through `EngineAppLookRouting.write` → `look.json` (`EngineAppDefaultsBridge.swift:31-32`, `EngineSettingsStore.swift:55-56`), so the plist never gets it. `defaults read lol.mattias.gltf-inspector` shows no `settings.*` keys. `toneMapping` does reach the plist when it is changed from its default, so only the environment is always `neutral` |
| LoadedModel carries Entity + stats/document/variant names | CONFIRMED, incomplete | `Shared/EntityLoader.swift:7-19` also carries `debugModes` (RK), `studioIBLExponent`, `pipelineReport`, `convertProblems` (RK-prepare facts) |
| Host dims from `ModelDimensions` / `PreviewCamera.modelBounds` | CONFIRMED | `EngineSceneModel.swift:387-388`, `HostShellRootView.swift:320` |
| `FocusedPreviewCommands` uses `PreviewCamera.CameraPreset` | CONFIRMED | `Shared/PreviewFocus.swift:11`; PreviewUI has its own `public enum CameraPreset` (`Models.swift:782`) |
| WebKit appexes need `network.client` | CONFIRMED (repo evidence) | webkit `project.yml:227-229,301-302` comment + installed appex entitlements; not re-derived from Apple docs |
| ~650 uncommitted lines + 6 untracked (~750) | PARTLY WRONG | `git diff --shortstat HEAD -- '*.swift'`: 636+/118−; docs 157+/65−; `viewer.html` + `project.yml` 334+/9−. **8** untracked files, **906** lines. `gltf-viewer.module.js` +1153/−91233 and 12 PNG goldens confirmed |

### Approach / Risks assumptions

| Assumption | Verdict | Evidence |
|---|---|---|
| Framework targets can't use bridging headers | CONFIRMED | Xcode 27 `swift-frontend` contains "using bridging headers with framework targets is unsupported". The fix is to put `GLBTry.h` in the framework's umbrella/public headers (or a module map). Keep `GLBDracoDecompressor.h` out of public headers; it is found by name |
| Team-ID-prefixed group works without a profile | CONFIRMED (docs) / UNVERIFIABLE (notarized run) | Apple entitlement doc: the `<team id>.<name>` macOS format needs no registration on the Developer website. Quinn ([forum 721701](https://developer.apple.com/forums/thread/721701)): App Groups is unrestricted on macOS; macOS 15 container protection is satisfied when "the app group ID starts with your app's Team ID". Caveat: a claim without a profile clears the *entitlements-validated* flag (only matters for the data-protection keychain; the code has no `SecItem`/keychain use) |
| macOS 15+/27 "access data from other apps" prompt | NOT TRIGGERED for this setup | The prompt is for non-prefixed/unauthorised groups ([forum 767604](https://developer.apple.com/forums/thread/767604), [mjtsai](https://mjtsai.com/blog/2024/09/11/group-container-names-in-sequoia/)). In macOS 27, cross-*team* access is denied with no prompt ([summary](https://blakecrosley.com/blog/macos-27-cross-team-container-access)); same-team app + appex is unaffected. Ad-hoc signed builds (`CODE_SIGN_IDENTITY=-`) *would* prompt |
| Automatic signing needs `-allowProvisioningUpdates` | LIKELY WRONG / UNVERIFIABLE | `REGISTER_APP_GROUPS` defaults to `NO` (Xcode 27 `macOSNativeBuildSystem.xcspec`), and the project doesn't set it, so Xcode won't try to register the group in a profile. The current automatic build already embeds no `embedded.provisionprofile`. Confirm on the first build. Do **not** enable Register App Groups; it switches to the `group.`-style flow |
| Appex can read resources via `Bundle(for:)` from a framework in the app's Contents/Frameworks | UNVERIFIABLE (spike justified) | Code loading is proven (otool above). The resources are in the same bundle directory dyld already maps. No Apple doc states resource reads explicitly (the [Extension guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html) covers code only). The webkit path serves files via `WKURLSchemeHandler` in the appex process (`WebRendererHost.swift:73`, `WebRendererResourceHandler.swift:42-45`), so only the appex needs read access, not WebContent. Keep the spike, but make it cheap |
| App still needs `- package: GLTFKit2` to embed it | UNVERIFIABLE | xcodegen: `embed` "defaults to true for application target and false for non application targets", and apps embed transitive deps. Whether that covers a package dependency of a framework needs a build. Keeping the app dependency is the safe choice |
| `.id(shellMountID)` re-creates WKWebView | CONFIRMED (code) / UNVERIFIABLE (timing) | See below |
| Extensions on main read their own container (item 4) | CONFIRMED | `Shared/PreviewLighting.swift:18` `AppLook.current` → `FileManager.urls(.applicationSupportDirectory)` resolves to the appex container in a sandbox. `PreviewScene.swift:84` `AppLookStore.shared` does the same. `PreviewScene.swift:114,117` reads autoRotate/showFloor from the appex's own `UserDefaults.standard`. So RK thumbnails and QL ignore the Settings look and these toggles |
| Finder thumbnail cache doesn't invalidate on switch | Reasonable, unverified | — |

### `.id(shellMountID)` double load (item 7)

- `HostShellRootView.swift:141` puts `.id(shellMountID)` on the whole `ShellRootView`. `shellMountID` switches from `"loading-N"` to `"ready-N"` (`:144-153`).
- `PreviewView.swift:55` mounts `WebPreviewCanvas` during `.loading` when `webCanvasURL != nil`.
- The id change discards the subtree. `HostPreviewContainer.makeNSView` runs again, then `WebPreviewCanvas.makeNSView` → `attach(... existing: nil)` → `WebRendererHost(mode: .live)`, which creates a **new `WKWebView`** (`WebRendererHost.swift:76`). `dismantleNSView` only `cancel()`s the first one.
- So the first page start is thrown away and restarted, rather than completing twice. `.build/logs/debug.log` in the worktree (3 restored windows) shows one "viewport ready" per window, 4–5 s after "open ready". That is consistent with this, but the log has one-second resolution and no "page start" line, so the wasted time can't be measured from it. Add a log line in `WebRendererHost.init` before measuring.
- `PreviewView.swift:55` `!state.isFailed` also confirms that an RK convert failure hides a working web canvas.

## New assumptions and risks the plan misses

1. **Extension safety** (corrections 3 and 4): PreviewUI, StillRenderer's save panel, and `CachedQuickLookThumbnail` (NSWorkspace, probably fine) all need auditing under `APPLICATION_EXTENSION_API_ONLY=YES`.
2. **Three settings vocabularies, not two.** Besides PreviewUI `SettingKey` and `RendererLookDefaults`, `Shared/AppSettings.swift:7-13` `SettingsKeys` duplicates `settings.preview.autoRotate/background/showFloor` and `settings.general.appearance`. It is used by `GLTFInspectorApp.swift:17,57-60` (`register(defaults:)`) and `PreviewScene.swift:114-117`. All of them must move to the group suite. `register(defaults:)` is per-process, so each appex has to register its own fallbacks.
3. **HDR lookup crosses frameworks.** `WebRendererHost.swift:60` looks for `khronos` in the *same* bundle as `web-renderer`. If the HDRs move to GLTFCore and the page to RendererWebKit, that lookup must point at the GLTFCore bundle. `PreviewLighting.swift:161` defaults to `bundle: .main`.
4. **"No file imports RealityKit" is a weak silo check.** Same-module code uses RK types without an import; `PreviewFocus.swift` and `PreviewSession.swift` have no RK import. After extraction, the real check is `grep -rl 'import RendererRealityKit'` outside the allowed places, plus the delete-target build.
5. **Release pipeline never exercised.** No release exists. `archive.sh` uses `signingStyle automatic` export with no `-allowProvisioningUpdates`, so its first real run happens after the group change. Budget a notarization dry run in seam 2, not "before the release that ships it".
6. **Untracked `GLTFInspectorTests/RendererTimingBenchTests.swift` on main** (61 lines) differs from the worktree's (217 lines). A later webkit → main merge at the repo root would be blocked by the untracked file. Seam 1 should resolve it; `.agentree/` and `.atelier/` are untracked too.
7. **The installed `/Applications` app is the WebKit build** (`CFBundleDisplayName` "glTF Inspector (WebKit)", same bundle id, Debug `.debug.dylib`), but `dev.sh install` copies to `/Applications` only on main. Verification steps that read `/Applications` depend on which branch installed last.
8. **The group container is not covered by the plist workaround.** The appexes' `home-relative-path.read-only: /` exception would let them read the group plist directly, but `UserDefaults(suiteName:)` goes through cfprefsd and needs the entitlement claim. Keep one mechanism (the suite) and delete the file read.
9. **Test fixtures and `GLTFInspectorError`** (correction 6).

## Recommendation (smallest supported path)

- Seam 2: add an entitlements file for the **host** plus the group on both appexes. Set no `REGISTER_APP_GROUPS`. Skip migration, or make it best-effort. Run the notarization dry run now.
- Seam 4: choose "value types in core" (or an extension-safe Seam-models module), not `import PreviewUI`. Set `APPLICATION_EXTENSION_API_ONLY: YES` on every new framework and move the save panel out of `StillRenderer` first.
- Split `GLBBox` explicitly. Give tests a GLTFCore-side GLB writer.
- Replace `dev.sh test` in the plan with the actual xcodebuild test command, or add the subcommand.
- Keep seam 3 as a 30-minute spike.

## Unresolved (need a build or run)

- Whether `-allowProvisioningUpdates` is needed with the group entitlement (expected: no).
- Whether GLTFKit2 is embedded when only a framework depends on it.
- Appex `Bundle(for:)` resource read under `QLThumbnailGenerator`.
- Wasted-WKWebView time from the remount (add a start log line first).
