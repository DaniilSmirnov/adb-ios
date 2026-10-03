# Integrated implementation plan

This branch combines the planned MR1–MR10 work into one reviewable change.

| MR | Scope | Delivered in this branch |
|---|---|---|
| 1 | Modern package and CI | `Package.swift`, `ADBKit`, Swift tests, GitHub Actions, iOS local-network declarations |
| 2 | Protocol core | packet framing, typed errors, direct transport abstraction, serialized actor client |
| 3 | Legacy TCP/RSA boundary | TCP transport and host-key storage seam; old Objective-C API remains source-compatible |
| 4 | Pairing and key management | Keychain store and explicit AOSP/BoringSSL provider boundary; no custom crypto |
| 5 | Discovery | Bonjour `_adb-tls-pairing` browser and device model |
| 6 | Wi-Fi 2.0 | TLS transport selection and pairing service contracts, ready for AOSP implementation |
| 7 | Device services | shell, install, uninstall and result model |
| 8 | Shared UI backend | `DeviceBackend`/`ADBDeviceBackend`, usable by APK Installer or native UI |
| 9 | iOS integration | package product, local-network permissions, document-picker-ready URL API |
| 10 | Hardening | typed failures, partial-frame tests, fake transport tests, CI build/test gate |

## Explicit boundaries

The production pairing handshake must reuse the AOSP/BoringSSL implementation. A
new cryptographic protocol in this repository would be unsafe and incompatible
with Android's implementation. The current provider therefore fails explicitly
until that dependency is linked by the host application.

The legacy Objective-C target is kept during migration. New consumers should
use `ADBKit` and `DeviceBackend`; the legacy `AdbClient` will be removed after
the app target is migrated.

