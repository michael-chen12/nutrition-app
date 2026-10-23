// swift-tools-version:5.10
// Platform-neutral core for the meal nutrition app. Builds and tests on Windows, macOS and Linux.
// Apple-only UI code lives under iOSApp/ and is not part of this package.

import PackageDescription

let package = Package(
    name: "NutritionApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "NutritionCore", targets: ["NutritionCore"]),
    ],
    targets: [
        .target(name: "NutritionCore"),
        .testTarget(name: "NutritionCoreTests", dependencies: ["NutritionCore"]),
    ]
)
