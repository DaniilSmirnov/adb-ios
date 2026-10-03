# DeviceManager UI integration

The UI is owned by the separate `DaniilSmirnov/APKInstaller` repository. This repository intentionally does not vendor or submodule that project.

The iOS app expects a versioned static bundle at `DeviceManagerUI/index.html`.

APKInstaller CI should publish the bundle as a release artifact. The iOS integration pipeline can download the selected artifact and copy it into the app resources. The native boundary is the `deviceManager` WKWebView message handler and the JSON request/response types in `DeviceManagerBridge.swift`.
