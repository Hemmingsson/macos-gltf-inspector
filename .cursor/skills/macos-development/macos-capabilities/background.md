# Background Operations

> Read this when: the app needs login items, launch agents, BGTaskScheduler, file watchers, or sleep assertions.

## Contents

- [Login Items (SMAppService)](#login-items-smappservice)
- [Helper agents](#helper-agents)
- [Background work](#background-work)
- [Watchers and sleep](#watchers-and-sleep)

## Login Items (SMAppService)

Use `SMAppService`, not deprecated `SMLoginItemSetEnabled`.

```swift
import ServiceManagement

try SMAppService.mainApp.register()
try SMAppService.mainApp.unregister()
SMAppService.mainApp.status == .enabled
```

Settings toggle: bind to status; on failure revert to `SMAppService.mainApp.status`. Handle `.requiresApproval` → System Settings → General → Login Items.

## Helper agents

Embed helper under `Contents/Library/LoginItems/`. Register:

```swift
let helper = SMAppService.agent(plistName: "com.example.myapp.helper.plist")
try helper.register()
```

Plist essentials: `Label`, `BundleProgram`, `RunAtLoad`, optional `KeepAlive`. Skip launchd essays — Apple’s Launch Agent docs own the rest.

## Background work

**BGTaskScheduler** (macOS 13+): register identifier in Info.plist (`BGTaskSchedulerPermittedIdentifiers`), submit `BGAppRefreshTaskRequest`, complete in handler, set `expirationHandler` to cancel. System-managed; do not poll.

**ProcessInfo.beginActivity** for critical exports (`.userInitiated`, `.idleSystemSleepDisabled`); always `endActivity` in `defer`.

**NSBackgroundActivityScheduler** for periodic utility work: set `interval` / `tolerance` / QoS, call `completion(.finished)` or `.deferred`.

## Watchers and sleep

**DispatchSource** file watch: `open(…, O_EVTONLY)` → `makeFileSystemObjectSource` → cancel closes fd.

**FSEvents** for directory trees — prefer when watching many paths; tear down stream in `stop`.

**IOPMAssertion** (`kIOPMAssertionTypeNoDisplaySleep`) during presentations/exports; release in `deinit`.
