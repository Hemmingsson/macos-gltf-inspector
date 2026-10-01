# Tidy ledger

Rejected, deferred or doubtful tidy ideas, so later research rounds do not re-propose them. One
line each: what, why.

## W1 core-webkit

- Kept `GLTFValidationReport.isClean`: only tests read it now that the badges are gone, but it is the report's one summary predicate; revisit with the validator surface.
- Deferred `JointNames.synthesized` / `GLTFInspectorError` to private or RealityKit, and `PNGWriter`'s `"StillRenderer"` error domain (chunk I extras): crosses into the realitykit lane / renames a domain; not dead code.
- Deferred chunk F live parts to wave 2 with the file split: `reset()` → `fit()`, the second load-copy re-show after `start`, and the stale "First step of the viewport migration" header on `WebPreviewCanvas`.
- Kept `WebPreviewCanvas.dismantleNSView(first, coordinator:)` in `WebCanvasControllerTests.remountAdoptsTheRunningPage`: it now calls the protocol's default no-op, which is what SwiftUI does on a remount; the test still proves adoption.
- `GLTFInspectorTests/RealityKit/CameraFramingTests.swift` gained `@testable import GLTFCore`: it builds `GLTFSessionDocument.Camera` values, whose memberwise init is now internal (D).

## W1 host

- F2.3 publish `canvasState.isReady ? viewport.commands : nil` (`DocumentShell`) — deferred: a behaviour change (menus disabled while loading), not a deletion; belongs with chunk C/F or a ticket. Today commands of the last ready canvas stay registered while the next document loads.
- `RendererAvailability.canHideNodes`, `\.shellPanelChrome`, `Availability.hasSkin` — out of W1 scope by plan (chunks C / E).
- Optional JSON-only transform/euler assertion on `EngineSelectionModel.detail` (to replace deleted `SelectionDetailTests`) — not added: tests-only addition, not a delete; camera/light/mesh detail stays covered by `EngineViewportRealityKitTests`. Candidate for the tests lane.
- `@State private var playbackController = EngineAnimationPlaybackController()` still allocates an empty controller + `RealityClipPlayer` per `RealityDocumentWindow` init (SwiftUI discards it after the first) — accepted: per parent re-init instead of per body; a lazy optional would bring back the `??` branch.
- Lane overlap: chunk A/B touched `GLTFInspector/RealityKit/{EngineSceneModel+RealityKit,PreviewView,HostPreviewContainer,RealityDocumentWindow}.swift` (assigned in the host note); watch for merge conflicts with the realitykit lane.

### Bugs seen

- None in product code. Harness note: `log stream --predicate 'process == "glTF Inspector"'` also captures other worktrees' test-host apps (same process name, e.g. "open failed cube.gltf: boom"); filter the real-window check by the launched pid.

## W0b uitest

- Ready signal: host-only `canvasReadyMarker` (`GLTFInspector/CanvasReadyMarker.swift`) — a 1×1 clear AX element `canvas-ready`, label = renderer raw value, present only while the canvas has content (RK: convert landed and canvas mounted; WebKit: `WebCanvasController.phase == .ready`). No PreviewUI edit. Rejected: putting it on `CanvasStatusView` (PreviewUI, and its `.ready` case is the canvas region state, which for WebKit is `.ready` before the page draws).
- RK "ready" is convert + mount, not a proven first Metal frame; good enough for open-to-content trend, not a first-pixel number.
- `waitForExistence` re-polls about once a second, so open-to-content polls `exists` in a tight loop instead (no sleep); otherwise numbers round up by ~1 s.
- Open-to-content includes process launch (XCTClockMetric from `launch()`), BoxAnimated.glb, 3 iterations. First run: RK ≈ 1.15 s, WebKit ≈ 1.9 s (first iteration 2.9 s — cold page; RSD 38 %). Launch (first frame responsive) ≈ 0.40 s.
- Settings flow can only restore the App Group renderer through the UI (the test runner cannot write the host's group suite); `tearDown` re-selects the original if the test stopped midway. Stored value read from the picker, so it works whatever the user has set.
- Doubt: the WebKit open screenshot shows the box very close (fills the canvas) vs RK's fitted framing — looks like the page's initial camera, not a test issue; not investigated here.
- View-mode flow ~20–27 s per renderer, mostly XCUITest menu idling; acceptable for an opt-in suite.
- Rejected: a test plan for opt-in (a separate scheme is simpler with xcodegen and keeps `dev.sh test` untouched).
