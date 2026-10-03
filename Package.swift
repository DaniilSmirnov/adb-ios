// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ADBKit",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [.library(name: "ADBKit", targets: ["ADBKit"])],
    targets: [
        .target(name: "ADBKit"),
        .testTarget(name: "ADBKitTests", dependencies: ["ADBKit"])
    ]
)

