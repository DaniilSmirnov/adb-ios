# DeviceManager UI integration

The UI is owned by the separate `DaniilSmirnov/APKInstaller` repository. This repository intentionally does not vendor or submodule that project.

The iOS app expects a versioned static bundle at `DeviceManagerUI/index.html`.

APKInstaller CI should publish the bundle as a versioned release asset. The iOS
consumer downloads that asset and copies it into app resources; it never imports
the APKInstaller source tree.

## Fetch the pinned artifact

The repository includes a consumer-side installer. It requires both a versioned
archive URL and its checksum:

```sh
DEVICE_MANAGER_UI_URL="https://github.com/DaniilSmirnov/APKInstaller/releases/download/<version>/DeviceManagerUI.tar.gz" \
DEVICE_MANAGER_UI_SHA256="<sha256>" \
./scripts/fetch-device-manager-ui.sh
```

The script accepts archives containing either the files directly or a top-level
`DeviceManagerUI/` directory. Override `DEVICE_MANAGER_UI_DESTINATION` when the
app uses a different resources directory. The script verifies the checksum and
requires `index.html` and `device-manager.js` before replacing the destination.

## Xcode integration

1. Run the fetch script from the `adb-ios` checkout in CI or before opening Xcode.
2. Add the resulting `Resources/DeviceManagerUI` directory as a folder reference
   to the application target's Copy Bundle Resources phase.
3. Add `ADBKit` as the Swift package dependency and construct
   `DeviceManagerWebViewController(backend: ADBDeviceManagerBackendAdapter())`.
4. Present or push that controller from the app's UIKit navigation flow.

`DeviceManagerWebViewController` loads `DeviceManagerUI/index.html` from
`Bundle.main`, registers the `deviceManager` WKWebView message handler, and
uses `UIDocumentPickerViewController` for `file.select`. The native boundary is
the JSON request/response types in `DeviceManagerBridge.swift`.

The legacy Objective-C sample remains unchanged while the host app migrates its
navigation and Swift package dependency.
