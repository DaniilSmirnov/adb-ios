# DeviceManager compatibility matrix

The protocol test suite runs against a deterministic fake-adbd transport. It
checks the direct CNXN/AUTH/OPEN/WRTE/CLSE flow and SYNC push semantics without
requiring a physical Android device in CI.

| Android family | Connection path | Automated coverage | Device validation |
| --- | --- | --- | --- |
| Android 11–12 | `_adb._tcp` / direct TCP | packet/session/SYNC tests | required on a physical device |
| Android 13–14 | `_adb-tls-connect._tcp` / TLS | packet/session tests | required on a physical device |
| Android 15–16 | Wi‑Fi debugging pairing + TLS | pairing integration test pending | required on a physical device |
| Android 17 / Wi‑Fi 2.0 | versioned pairing/discovery | compatibility gate pending | required on a physical device |

CI must keep the fake-adbd suite green. A release is not considered device
validated until the physical-device rows have been exercised and recorded.
