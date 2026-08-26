// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EasyMacBord",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "EasyMacBord", targets: ["EasyMacBord"])
    ],
    targets: [
        .executableTarget(
            name: "EasyMacBord",
            path: "Sources/EasyMacBord",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("IOKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "EasyMacBordTests",
            dependencies: ["EasyMacBord"],
            path: "Tests/EasyMacBordTests"
        )
    ]
)
