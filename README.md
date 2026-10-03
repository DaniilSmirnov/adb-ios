# adb-ios / ADBKit

`ADBKit` is a direct Android ADB host implementation for iOS and macOS. It
connects to the `adbd` process running on an Android device and does not need a
local `adb server` or port `5037`.

The repository also contains the native host for the external **DeviceManager**
UI. The UI source remains in the separate
[`APKInstaller`](https://github.com/DaniilSmirnov/APKInstaller) repository and
is consumed only as a versioned static artifact. There is no monorepo, copied UI
source, or Git submodule.

## Features

- direct ADB packet transport: `CNXN`, `AUTH`, `OPEN`, `OKAY`, `WRTE`, `CLSE`;
- Wi-Fi/TCP and TLS device connections;
- Bonjour discovery for ADB services;
- RSA host authentication with Keychain-backed key storage;
- shell commands;
- ADB SYNC push followed by APK installation;
- package uninstall;
- Swift concurrency-safe `DeviceBackend` API;
- `WKWebView` host and typed JSON bridge for DeviceManager;
- iOS document picker with opaque APK file tokens;
- AOSP pairing crypto boundary backed by BoringSSL when configured.

USB transport and the Android-side ADB daemon are outside the scope of this
package.

## Requirements

- Xcode 15 or later;
- Swift 5.9 or later;
- iOS 15 or later for iOS targets;
- macOS 13 or later for macOS targets;
- a Wi-Fi-connected Android device with ADB or Wi-Fi debugging enabled.

The iOS application must include a local-network usage description and the
Bonjour service declarations from `adb-ios/Info.plist` in its own target.

## Build and test the SDK

Clone the repository and run the Swift package tests:

```sh
git clone https://github.com/DaniilSmirnov/adb-ios.git
cd adb-ios
swift test
swift build
```

To build the legacy Xcode application target in Xcode, open
`adb-ios.xcworkspace`. New integrations should use the `ADBKit` Swift package;
the Objective-C sample target is retained only for migration compatibility.

### Optional AOSP/BoringSSL pairing support

The package deliberately does not contain replacement cryptography. To enable
the AOSP-compatible SPAKE2 → HKDF-SHA256 → AES-128-GCM adapter, build the
required BoringSSL revision for the current Apple platform and set:

```sh
ADBKIT_BORINGSSL_ROOT=/path/to/boringssl-build swift test
```

Without this variable the package still builds and tests the protocol layers,
but pairing fails closed with `ADBError.pairingUnavailable`. The complete TLS
1.3 pairing transport, certificate exchange, and peer persistence must be
provided by the host integration before production Wi-Fi pairing is enabled.

## Build the DeviceManager UI integration

`DeviceManagerUI` is built in `APKInstaller` and downloaded into `adb-ios` as a
verified artifact. Build and release the UI from the UI repository first:

```sh
cd /path/to/APKInstaller
npm ci
npm run build:device-manager-ui
tar -czf DeviceManagerUI.tar.gz -C dist DeviceManagerUI
shasum -a 256 DeviceManagerUI.tar.gz
```

Publish `DeviceManagerUI.tar.gz` as a versioned APKInstaller release asset.
Then install that exact asset in this repository:

```sh
cd /path/to/adb-ios
DEVICE_MANAGER_UI_URL="https://github.com/DaniilSmirnov/APKInstaller/releases/download/<version>/DeviceManagerUI.tar.gz" \
DEVICE_MANAGER_UI_SHA256="<sha256>" \
./scripts/fetch-device-manager-ui.sh
```

The script verifies the SHA-256 checksum and requires both `index.html` and
`device-manager.js` before replacing `Resources/DeviceManagerUI`. Do not commit
an unverified or manually copied UI bundle.

### Add the UI to an iOS target

In Xcode:

1. Add `Resources/DeviceManagerUI` as a folder reference.
2. Add the folder reference to **Copy Bundle Resources**.
3. Confirm that the final application bundle contains
   `DeviceManagerUI/index.html` and `DeviceManagerUI/device-manager.js`.
4. Link the `ADBKit` product to the application target.

`DeviceManagerWebViewController` loads the bundle from `Bundle.main`, exposes
the `deviceManager` message handler, and presents `UIDocumentPickerViewController`
for APK selection. The JavaScript side receives an opaque file token; a local
filesystem path is never sent to the UI.

## Integrate ADBKit as an SDK

### Swift Package Manager

For a local checkout during development, add the package in Xcode with **File →
Add Package Dependencies… → Add Local…** and select the `adb-ios` directory.

For a remote dependency, use a tagged commit or an exact revision:

```swift
dependencies: [
    .package(
        url: "https://github.com/DaniilSmirnov/adb-ios.git",
        revision: "<reviewed-commit-sha>"
    )
]
```

Then add the product to the target:

```swift
.target(
    name: "MyDeviceManagerApp",
    dependencies: [
        .product(name: "ADBKit", package: "adb-ios")
    ]
)
```

### Use the native backend directly

The UI-neutral backend can be used from UIKit, SwiftUI, or another native UI:

```swift
import ADBKit

let backend = ADBDeviceManagerBackendAdapter()
let devices = try await backend.listDevices()

guard let device = devices.first else { return }
let shellResult = try await backend.shell("getprop ro.build.version.release", on: device)
print(shellResult.output)
```

The backend exposes:

```swift
func listDevices() async throws -> [ADBDevice]
func shell(_ command: String, on device: ADBDevice) async throws -> ADBCommandResult
func install(apk: URL, on device: ADBDevice) async throws -> ADBCommandResult
func uninstall(package: String, on device: ADBDevice) async throws -> ADBCommandResult
```

`install` performs a real ADB SYNC push to a temporary path on the device and
then runs `pm install`; it does not pass a host path to Android. The temporary
remote APK is removed after installation when the device accepts cleanup.

### Present the bundled DeviceManager UI

The UIKit integration is a thin host around the same backend:

```swift
import ADBKit
import UIKit

final class DeviceManagerViewController: UIViewController {
    func showDeviceManager() {
        let backend = ADBDeviceManagerBackendAdapter()
        let controller = DeviceManagerWebViewController(backend: backend)
        navigationController?.pushViewController(controller, animated: true)
    }
}
```

The host application remains responsible for navigation, lifecycle, and adding
the downloaded `DeviceManagerUI` folder to its resources. SwiftUI applications
can present the controller through `UIViewControllerRepresentable`.

## Bridge contract

The `WKWebView` bridge is registered under `deviceManager`. Requests and
responses are JSON objects with an `id`, method name, and a base64-encoded
`Codable` payload. The current methods are:

| Method | Purpose |
| --- | --- |
| `devices.list` | Discover and return connected devices |
| `device.shell` | Execute a shell command |
| `device.install` | Resolve an opaque file token, push the APK, and install it |
| `device.uninstall` | Uninstall a package |
| `file.select` | Open the native document picker |

The TypeScript contract and UI runtime are owned by APKInstaller. Changes to
the bridge must be made as coordinated, versioned changes in both repositories.

## Authentication and key storage

ADB host keys are generated and stored in the Apple Keychain by
`KeychainADBAuthenticator`. They are not loaded from the application bundle.
Existing legacy bundle files under `android/` are kept only for the old
Objective-C sample and are not used by the new `ADBKit` backend.

## Local development checklist

```sh
# adb-ios
swift test
swift build

# APKInstaller, in its own checkout
npm ci
npm test -- --runInBand
npm run typecheck
npm run lint
npm run build:device-manager-ui
```

For real-device validation, use a physical Android device on the same local
network, verify the iOS local-network permission, and test discovery, shell,
SYNC installation, uninstall, and reconnect separately. The deterministic
fake-adbd tests do not replace physical-device validation.

## Related documentation

- [DeviceManager UI integration](docs/device-manager-ui.md)
- [Compatibility matrix](docs/compatibility-matrix.md)
- [Implementation plan](docs/implementation-plan.md)
