# Tidy ledger

Rejected, deferred or doubtful tidy ideas, so later research rounds do not re-propose them. One
line each: what, why.

## W1 core-webkit

- Kept `GLTFValidationReport.isClean`: only tests read it now that the badges are gone, but it is the report's one summary predicate; revisit with the validator surface.
- Deferred `JointNames.synthesized` / `GLTFInspectorError` to private or RealityKit, and `PNGWriter`'s `"StillRenderer"` error domain (chunk I extras): crosses into the realitykit lane / renames a domain; not dead code.
- Deferred chunk F live parts to wave 2 with the file split: `reset()` → `fit()`, the second load-copy re-show after `start`, and the stale "First step of the viewport migration" header on `WebPreviewCanvas`.
- Kept `WebPreviewCanvas.dismantleNSView(first, coordinator:)` in `WebCanvasControllerTests.remountAdoptsTheRunningPage`: it now calls the protocol's default no-op, which is what SwiftUI does on a remount; the test still proves adoption.
- `GLTFInspectorTests/RealityKit/CameraFramingTests.swift` gained `@testable import GLTFCore`: it builds `GLTFSessionDocument.Camera` values, whose memberwise init is now internal (D).

## W1 ui

- Deferred C2's `OutlinerList` perf tidy (`sections` rebuilt 3–4× per body, `treeIdentity` flatten per render): not a deletion; wave 2.
- Kept `MockSettingsStore`'s `defaults*` dictionaries: with `promoteToDefault` gone nothing writes them (`default(for:)` always returns the fallback), but C3 deletes the whole mock; simplify there if C3 keeps it.
- Kept `DSListRow` / `DSTypeIcon` `isSelected:`: NodeRow no longer passes it, but it is DesignSystem API the catalog shows (custom-row selection look).
- Kept the single-child `HStack` in `NodeRow.body`: it carries `.accessibilityElement(children: .contain)` and `.onHover`; removing it is not a pure deletion.
- Left the stale `PreviewUI.Theme` mentions in `DS+Color.swift:88, 126` for C9 (stale comments, wave 3).
- Crossed into GLTFCore for one line: `AppGroupSettings.Key.showToolbar` went with `SettingKey.showPills` (only `AppGroupSettingsTests` compared them; no other reader).
- Deleted the `promoteToDefault` tests (`environmentKeyPromoteWritesAppLook`, `canvasPromoteWritesUserDefaults`): the App Look / UserDefaults routing they covered is still covered through `EngineAppDefaultsBridgeTests.environmentKeysWriteAppLookNotUserDefaults`.
