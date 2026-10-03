// swift-tools-version: 5.9
import Foundation
import PackageDescription

let boringSSLRoot = ProcessInfo.processInfo.environment["ADBKIT_BORINGSSL_ROOT"]
let pairingCxxSettings: [CXXSetting] = [.unsafeFlags(["-std=c++17"])] + (boringSSLRoot.map {
    [.define("ADBKit_BoringSSL_ENABLED"), .unsafeFlags(["-I\($0)/include"])]
} ?? [])
let pairingLinkerSettings: [LinkerSetting] = boringSSLRoot.map {
    [.unsafeFlags(["-L\($0)/build/crypto"]), .linkedLibrary("crypto")]
} ?? []

let package = Package(
    name: "ADBKit",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [.library(name: "ADBKit", targets: ["ADBKit"])],
    targets: [
        .target(
            name: "ADBPairingNative",
            path: "Sources/ADBPairingNative",
            publicHeadersPath: "include",
            cxxSettings: pairingCxxSettings,
            linkerSettings: pairingLinkerSettings
        ),
        .target(name: "ADBKit", dependencies: ["ADBPairingNative"]),
        .testTarget(name: "ADBKitTests", dependencies: ["ADBKit"])
    ]
)
