# SwiftUI API Scan Manifest

Categorized scan targets: queries + doc paths. Shipping: iOS 26 / macOS 26 / Xcode 26. After WWDC26, scan current developer.apple.com. Don't invent iOS 27 UI APIs except footnotes already in `latest-apis.md`.

## Name traps

| Wrong | Use |
|-------|-----|
| `CopyButton` | `PasteButton` / `ShareLink` / pasteboard |
| `searchToolbarBehavior(.minimizable)` | `.minimize` (`SearchToolbarBehavior`) |
| `navigationTransitionSource` / `…Destination` | `matchedTransitionSource(id:in:)` + `navigationTransition(.zoom(sourceID:in:))` |

---

## Navigation
**Queries:** `SwiftUI NavigationStack` · `NavigationSplitView` · `navigationTitle` · `toolbar` · `NavigationLink deprecated` · `matchedTransitionSource` · `navigationTransition zoom`
**Docs:** `/documentation/swiftui/navigationstack` · `navigationsplitview` · `navigationlink` · `view/navigationtitle(_:)-avgj` · `view/toolbar(content:)-5w0tj` · `view/toolbarvisibility(_:for:)` · `view/matchedtransitionsource(id:in:)` · `view/navigationtransition(_:)`

## Appearance & Styling
**Queries:** `foregroundStyle` · `foregroundColor deprecated` · `tint modifier` · `preferredColorScheme` · `clipShape`
**Docs:** `view/foregroundstyle(_:)` · `view/foregroundcolor(_:)` · `view/tint(_:)-93mfq` · `view/preferredcolorscheme(_:)` · `view/clipshape(_:style:)`

## State Management
**Queries:** `Observable macro` · `ObservableObject deprecated` · `Bindable` · `State` · `Entry macro`
**Docs:** `/documentation/observation/observable()` · `swiftui/observableobject` · `bindable` · `state` · `entry()` · `environmentvalues`

## Presentation & Alerts
**Queries:** `alert modifier` · `confirmationDialog` · `actionSheet deprecated` · `sheet` · `fullScreenCover`
**Docs:** `view/alert(_:ispresented:actions:message:)-8dvt8` · `view/confirmationdialog(…)-43f72` · `view/sheet(ispresented:ondismiss:content:)`

## Text Input
**Queries:** `TextField onSubmit` · `textInputAutocapitalization` · `autocorrectionDisabled` · `focused`
**Docs:** `view/onsubmit(of:_:)` · `view/textinputautocapitalization(_:)` · `view/autocorrectiondisabled(_:)` · `focusstate`

## Layout
**Queries:** `ignoresSafeArea` · `containerRelativeFrame` · `visualEffect` · `GeometryReader` · `coordinateSpace`
**Docs:** `view/ignoressafearea(_:edges:)` · `view/containerrelativeframe(_:alignment:_:)` · `view/visualeffect(_:)` · `geometryreader` · `view/coordinatespace(_:)`

## Gestures
**Queries:** `MagnifyGesture` · `RotateGesture` · `MagnificationGesture deprecated` · `RotationGesture deprecated`
**Docs:** `magnifygesture` · `rotategesture` · `magnificationgesture` · `rotationgesture`

## Accessibility
**Queries:** `accessibilityLabel` · `accessibility deprecated` · `accessibilityRepresentation`
**Docs:** `view/accessibilitylabel(_:)-1d7jv` · `view/accessibilityvalue(_:)-7a2ql` · `view/accessibilityhint(_:)` · `view/accessibilityrepresentation(representation:)`

## Animations
**Queries:** `animation value deprecated` · `withAnimation` · `phaseAnimator` · `keyframeAnimator`
**Docs:** `view/animation(_:value:)` · `view/phaseanimator(_:content:animation:)` · `view/keyframeanimator(initialvalue:repeating:content:keyframes:)`

## Tabs
**Queries:** `Tab API` · `tabItem deprecated` · `TabView`
**Docs:** `tab` · `tabview` · `view/tabitem(_:)`

## Previews
**Queries:** `Previewable` · `Preview macro`
**Docs:** `previewable()` · `preview(_:body:)`

## Liquid Glass (iOS 26+)
**Queries:** `glassEffect` · `GlassEffectContainer` · `glassProminent` · `backgroundExtensionEffect`
**Docs:** `view/glasseffect(_:in:isenabled:)` · `glasseffectcontainer` · `view/backgroundextensioneffect()` · `view/scrolledgeeffectstyle(_:for:)` · `view/tabbarminimizebehavior(_:)`

## Search
**Queries:** `searchToolbarBehavior` · `SearchToolbarBehavior minimized` · `searchable`
**Docs:** `view/searchtoolbarbehavior(_:)` · `view/searchable(text:placement:prompt:)`

## Clipboard
**Queries:** `PasteButton` · `ShareLink` · `Transferable pasteboard`
**Docs:** `pastebutton` · `sharelink`

## Scroll & Lists
**Queries:** `ScrollViewReader` · `scrollPosition` · `scrollTargetBehavior` · `ForEach`
**Docs:** `scrollviewreader` · `view/scrollposition(id:)` · `view/scrolltargetbehavior(_:)` · `foreach`

## WWDC Sessions

- `/videos/play/wwdc2025/232` — What's new in SwiftUI (WWDC25)
- `/videos/play/wwdc2025/323` — Build a SwiftUI app with the new design
- `/videos/play/wwdc2024/10144` — What's new in SwiftUI (WWDC24)
- `/videos/play/wwdc2023/10148` — What's new in SwiftUI (WWDC23)

After WWDC26, add the latest "What's new" once it exists. Don't invent session IDs.
