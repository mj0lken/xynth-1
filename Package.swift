// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "xynth-1",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "XynthCore", targets: ["XynthCore"]),
        .executable(name: "XYNTH-1", targets: ["XynthApp"])
    ],
    targets: [
        .target(
            name: "XynthCore",
            path: "Sources/XynthCore",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .executableTarget(
            name: "XynthApp",
            dependencies: ["XynthCore"],
            path: "Sources/XynthApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .testTarget(
            name: "XynthCoreTests",
            dependencies: ["XynthCore"],
            path: "Tests/XynthCoreTests"
        )
    ]
)
