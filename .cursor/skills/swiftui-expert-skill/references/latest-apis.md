# Latest SwiftUI APIs

> Read this when: choosing a modern API, migrating a deprecated or renamed call, or adopting iOS/macOS 26 APIs. For *when* to migrate vs leave soft-deprecated code alone, see `soft-deprecation.md`.

## Contents

- [Always use (iOS 15+)](#always-use-ios-15)
- [iOS 16+](#ios-16)
- [iOS 17+](#ios-17)
- [iOS 18+](#ios-18)
- [iOS 26+ / macOS 26+](#ios-26--macos-26)
- [Quick lookup](#quick-lookup)

Liquid Glass detail: `liquid-glass.md`. Refresh this list after an SDK drop: `updating-apis.md`.

## Always use (iOS 15+)

| Instead of | Use |
|------------|-----|
| `navigationBarTitle(_:)` | `navigationTitle(_:)` |
| `navigationBarItems(...)` | `toolbar { ToolbarItem(...) }` |
| `navigationBarHidden(_:)` | `toolbarVisibility(.hidden, for: .navigationBar)` |
| `statusBar(hidden:)` | `statusBarHidden(_:)` |
| `edgesIgnoringSafeArea(_:)` | `ignoresSafeArea(_:edges:)` |
| `colorScheme(_:)` | `preferredColorScheme(_:)` |
| `foregroundColor(_:)` | `foregroundStyle(_:)` |
| `cornerRadius(_:)` | `clipShape(.rect(cornerRadius:))` |
| `autocapitalization(_:)` | `textInputAutocapitalization(_:)` (`.never` replaces `.none`) |
| `animation(_:)` | `animation(_:value:)` (back-deploys to iOS 13+) |
| `actionSheet(...)` | `confirmationDialog(_:isPresented:actions:message:)` |
| `alert(isPresented:content:)` | `alert(_:isPresented:actions:message:)` |
| `TextField` `onCommit` / `onEditingChanged` | `onSubmit` + `focused` |
| `accessibility(label:)` and siblings | `accessibilityLabel()`, `accessibilityValue()`, `accessibilityHint()`, `accessibilityAddTraits()`, `accessibilityHidden()` |
| Manual `EnvironmentKey` | `@Entry` (Xcode 16; back-deploys) |

`Section("Title") { }` is current. Prefer trailing-closure `Section { } header: { } footer: { }` over positional `Section(header:footer:content:)`.

Prefer `Button` over `onTapGesture` unless you need tap location or count.

## iOS 16+

| Instead of | Use |
|------------|-----|
| `NavigationView` | `NavigationStack` or `NavigationSplitView` |
| Destination `NavigationLink` | `NavigationLink(value:)` + `navigationDestination(for:)` |
| `accentColor(_:)` | `tint(_:)` |
| `disableAutocorrection(_:)` | `autocorrectionDisabled(_:)` |
| Ad-hoc `UIPasteboard` for paste UI | `PasteButton` |

## iOS 17+

| Instead of | Use |
|------------|-----|
| `ObservableObject` / `@StateObject` / `@ObservedObject` | `@Observable` + `@State` / `@Bindable` |
| `onChange(of:perform:)` | `onChange(of:) { }` or `{ old, new in }` (`initial:` optional) |
| UIKit feedback generators in SwiftUI | `sensoryFeedback(_:trigger:)` |
| `MagnificationGesture` | `MagnifyGesture` (`value.magnification`) |
| `RotationGesture` | `RotateGesture` (`value.rotation`) |
| `coordinateSpace(name:)` | `coordinateSpace(.named(...))` |

`GeometryReader` is not deprecated. Prefer `containerRelativeFrame`, `visualEffect`, or `onGeometryChange(for:of:action:)` when they fit.

```swift
.onGeometryChange(for: CGFloat.self) { proxy in proxy.size.height } action: { height = $0 }
```

## iOS 18+

| Instead of | Use |
|------------|-----|
| `.tabItem { }` | `Tab("Title", systemImage:) { }` |
| Local `@State` in `#Preview` without `@Previewable` | `@Previewable @State` |

`Tab(role:)` cannot mix with `.tabItem()`.

## iOS 26+ / macOS 26+

Glass (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)` / `.glassProminent`): `liquid-glass.md`. Availability: `if #available(iOS 26, macOS 26, *)`.

### Scroll and backgrounds

```swift
ScrollView { content }
    .scrollEdgeEffectStyle(.soft, for: .top)

Image("hero")
    .backgroundExtensionEffect()
```

Remove custom toolbar-background hacks that fight the scroll-edge effect.

### Tabs

```swift
TabView {
    Tab("Home", systemImage: "house") { HomeView() }
    Tab("Profile", systemImage: "person") { ProfileView() }
    Tab(role: .search) { SearchResultsView() }
}
.tabBarMinimizeBehavior(.onScrollDown)
.tabViewBottomAccessory {
    NowPlayingBar()
}
```

Read `tabViewBottomAccessoryPlacement` from the environment when the accessory collapses into the tab bar.

### Toolbars

`ToolbarSpacer(.fixed)` groups items; `.flexible` pushes groups apart. `sharedBackgroundVisibility(.hidden)` removes the shared glass pill from one item. `badge(_:)` on item content shows a count.

### Search

```swift
.searchable(text: $query)
.searchToolbarBehavior(.minimize)
```

The type property is **`.minimize`**, not `.minimizable`. Some HTML samples show `.minimized` — that is not the SDK name. System may already minimize search; this modifier opts in.

### Zoom transition

```swift
.toolbar {
    ToolbarItem {
        Button("Add", systemImage: "plus") { showSheet = true }
    }
    .matchedTransitionSource(id: "add", in: namespace)
}
.sheet(isPresented: $showSheet) {
    AddItemView()
        .navigationTransition(.zoom(sourceID: "add", in: namespace))
}
```

Do not invent `navigationTransitionSource`, `navigationTransitionDestination`, or `navigationZoomTransition`.

### Animation

`@Animatable` synthesizes `animatableData`. Exclude fields with `@AnimatableIgnored`.

### Web

```swift
WebView(url: url)

@State private var page = WebPage()
WebView(page)
    .onAppear { page.load(URLRequest(url: url)) }
```

### Other 26 APIs worth knowing

- `controlSize(.extraLarge)`
- `clipShape(.rect(cornerRadius:style: .concentric))`
- `Slider` `ticks:` + `sliderNeutralValue(_:)`
- `TextEditor` bound to `AttributedString` for rich text
- UIKit / AppKit lifecycle apps can request SwiftUI scenes (`MenuBarExtra`, `ImmersiveSpace`) via `activateSceneSession`

### dragContainer (split availability)

`dragContainer` is **macOS 26+**. It is **not** a general iOS 26 API. WWDC26 introduced it on **iOS 27** (also iPadOS / visionOS 27). Do not write iOS 27 how-to here — gate Mac use with `#available(macOS 26, *)` and keep iOS on `draggable` / `dropDestination` until that OS is in scope.

```swift
#if os(macOS)
if #available(macOS 26, *) {
    PhotoGrid(photos: photos)
        .dragContainer(for: Photo.self) { selection in
            selection.map(\.transferable)
        }
}
#endif
```

## Quick lookup

| Deprecated | Recommended | Since |
|------------|-------------|-------|
| `navigationBarTitle(_:)` | `navigationTitle(_:)` | iOS 15+ |
| `navigationBarItems(...)` | `toolbar { ToolbarItem(...) }` | iOS 15+ |
| `navigationBarHidden(_:)` | `toolbarVisibility(.hidden, for: .navigationBar)` | iOS 15+ |
| `statusBar(hidden:)` | `statusBarHidden(_:)` | iOS 15+ |
| `edgesIgnoringSafeArea(_:)` | `ignoresSafeArea(_:edges:)` | iOS 15+ |
| `colorScheme(_:)` | `preferredColorScheme(_:)` | iOS 15+ |
| `foregroundColor(_:)` | `foregroundStyle(_:)` | iOS 15+ |
| `cornerRadius(_:)` | `clipShape(.rect(cornerRadius:))` | iOS 15+ |
| `actionSheet(...)` | `confirmationDialog(...)` | iOS 15+ |
| `alert(isPresented:content:)` | `alert(_:isPresented:actions:message:)` | iOS 15+ |
| `autocapitalization(_:)` | `textInputAutocapitalization(_:)` | iOS 15+ |
| `accessibility(label:)` etc. | `accessibilityLabel()` etc. | iOS 15+ |
| `TextField` `onCommit` / `onEditingChanged` | `onSubmit` + `focused` | iOS 15+ |
| `animation(_:)` (no value) | `animation(_:value:)` | Back-deploys |
| `Section(header:content:)` | `Section { } header: { }` | Future-deprecated |
| Manual `EnvironmentKey` | `@Entry` | Xcode 16+ |
| `NavigationView` | `NavigationStack` / `NavigationSplitView` | iOS 16+ |
| `accentColor(_:)` | `tint(_:)` | iOS 16+ |
| `disableAutocorrection(_:)` | `autocorrectionDisabled(_:)` | iOS 16+ |
| `onChange(of:perform:)` | `onChange(of:) { }` | iOS 17+ |
| UIKit feedback generators | `sensoryFeedback(_:trigger:)` | iOS 17+ |
| `MagnificationGesture` | `MagnifyGesture` | iOS 17+ |
| `RotationGesture` | `RotateGesture` | iOS 17+ |
| `coordinateSpace(name:)` | `coordinateSpace(.named(...))` | iOS 17+ |
| `ObservableObject` | `@Observable` | iOS 17+ |
| `tabItem(_:)` | `Tab` | iOS 18+ |
| Manual `animatableData` | `@Animatable` | iOS 26+ |
| Custom sheet `presentationBackground` | Default glass sheet | iOS 26+ |
| Custom toolbar background hacks | `scrollEdgeEffectStyle` + system glass | iOS 26+ |
| Invented zoom names | `matchedTransitionSource` + `navigationTransition(.zoom)` | iOS 18+/26+ |
| `searchToolbarBehavior(.minimizable)` | `.minimize` | iOS 26+ |
