---
name: verify
description: Build, launch, and observe Cove at its real surfaces (iOS Simulator and macOS app) to verify changes at runtime.
---

# Verifying Cove at runtime

Cove is a SwiftUI multiplatform app. Unit tests cover the pure logic; runtime
verification means launching the app and looking at it.

## Build

```sh
xcodebuild -project Cove.xcodeproj -scheme Cove -destination 'platform=macOS' -derivedDataPath DerivedData build
xcodebuild -project Cove.xcodeproj -scheme Cove -destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath DerivedData build
# UDID from: xcrun simctl list devices available
```

Products land in `DerivedData/Build/Products/Debug{,-iphonesimulator}/Cove.app`.

## iOS Simulator (the drivable surface)

`simctl` screenshots work headlessly; macOS GUI capture and AppleScript
require Accessibility/Screen Recording permissions the shell does not have,
so prefer the simulator for anything visual.

```sh
xcrun simctl boot <UDID> && xcrun simctl bootstatus <UDID> -b
xcrun simctl install booted DerivedData/Build/Products/Debug-iphonesimulator/Cove.app
xcrun simctl launch booted com.ankitbhade.Cove
xcrun simctl io booted screenshot out.png
```

There is no tap injection. Two workarounds:

- **Preseed state via UserDefaults**: `xcrun simctl spawn booted defaults
  write com.ankitbhade.Cove <key> ...`. Known keys: `appearanceSetting`
  (string: system/light/dark), `vaultBookmark` (data). A vault bookmark
  created on the host with a small Swift script (`url.bookmarkData(options:
  [])` for a folder inside the app's data container — `xcrun simctl
  get_app_container booted com.ankitbhade.Cove data`, use
  `Documents/DevVault`) resolves fine inside the simulator and survives
  reinstalls, so the app launches straight into the open-vault TabView.
  Write the data value as hex: `-data "$(base64 -d <<<"$B64" | xxd -p | tr -d '\n')"`.
- **Screens only reachable by tapping**: temporarily route `RootView`'s
  `.open` case to the view under test (`SomeView() // TEMP-VERIFY` plus
  `let _ = TabView {...}` keeps the builder valid), build, screenshot,
  revert. Grep for `TEMP-VERIFY` before committing.

Transient UI (launch screen): still screenshots race and lose. Record
instead — `xcrun simctl io booted recordVideo --force out.mov &`, launch,
`kill -INT` the recorder — then extract frames with a Swift
`AVAssetImageGenerator` one-off (swift CLI runs single files directly).

Seeding a note with a timed task (`- [ ] X @due(YYYY-MM-DD HH:MM)`) makes
the notification-permission prompt appear on first load — expected, and
evidence the scheduler rebuild ran. `simctl privacy` cannot grant
notifications; the alert can only be answered by a human.

## macOS

`open DerivedData/Build/Products/Debug/Cove.app` launches it; `pgrep -x
Cove` confirms it stays alive, and the merged Info.plist can be checked with
`plutil -p .../Cove.app/Contents/Info.plist`. Visual capture is blocked
without extra permissions.

## Cleanup

Reinstall the final (non-scaffolded) build on the simulator, `xcrun simctl
shutdown booted`, `pkill -x Cove`.
