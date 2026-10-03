# adb-ios / ADBKit
Android ADB on iOS. The repository now contains `ADBKit`, a direct device-side ADB host library for iOS and macOS.

NOTE that this is **not** the ADB **daemon** program that is running inside the android device. 

# Porting Details
- Direct `adbd` connections are used; the app does not require an `adb server` or port 5037.

- No USB supported

- `ADBClient` exposes async `connect`, `shell`, `install`, and `uninstall` operations.
- `ADBDiscovery` provides Bonjour discovery for Wi‑Fi pairing services.
- `KeychainADBKeyStore` keeps host keys outside the application bundle.
- `DeviceBackend` is the UI-neutral adapter that can be consumed by UIKit, SwiftUI, or a shared APK Installer UI.

- Application should include private/public key files in the application bundle (.ipa). The location and file name must be as this: 
 - [app-bundle-path]/android/adbkey 
 - [app-bundle-path]/android/adbkey.pub

# Code Snippet

<pre><code>

// initialize the AdbClient
_adb = [[AdbClient alloc] init];

...

// connect to a device
[_adb connect:@"10.0.1.223" didResponse:^(bool succ, NSString *result) {
  NSLog("%d : %@", succ, result); 
}];

//install apk
NSString *apkPath = [[NSBundle mainBundle] pathForResource:@"Term" ofType:@"apk"];
[_adb installApk:apkPath flags:ADBInstallFlag_Replace didResponse:^(bool succ, NSString *result) {
    NSLog("%d : %@", succ, result);       
}];

// some shell commands
[_adb shell:@"pm list packages" didResponse:^(bool succ, NSString *result) {
  //...
}];

</code></pre>

## Build and test

```sh
swift test
```

The legacy Objective-C sample remains for compatibility, while new integrations should use `Sources/ADBKit`.
The production Wi‑Fi pairing implementation must link the AOSP/BoringSSL pairing code; this project intentionally does not implement custom cryptography.

To enable the real AOSP pairing crypto adapter, build BoringSSL for the current
Apple platform and point SwiftPM at that build:

```sh
ADBKIT_BORINGSSL_ROOT=/path/to/boringssl-build swift test
```

The adapter calls BoringSSL's `SPAKE2_*` API and applies the AOSP pairing key
schedule (`HKDF-SHA256` followed by `AES-128-GCM`). Without the variable, the
package remains buildable for protocol work but pairing fails closed.

