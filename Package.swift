// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MiniTools",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "MiniTools", targets: ["MiniTools"]),
        .executable(name: "MiniToolsPowerHelper", targets: ["MiniToolsPowerHelper"])
    ],
    targets: [
        .target(
            name: "MiniToolsPowerSupport",
            path: "Sources/MiniToolsPowerSupport",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "MiniTools",
            dependencies: ["MiniToolsPowerSupport"],
            path: "Sources/MiniTools",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreServices"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Vision")
            ]
        ),
        .executableTarget(
            name: "MiniToolsPowerHelper",
            dependencies: ["MiniToolsPowerSupport"],
            path: "Sources/MiniToolsPowerHelper"
        ),
        .testTarget(
            name: "MiniToolsTests",
            dependencies: ["MiniTools", "MiniToolsPowerSupport"],
            path: "Tests/MiniToolsTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
