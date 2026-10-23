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
        // The wire contract shared by the app and the backend (Backend/): photo analysis and food search.
        .library(name: "AnalysisContract", targets: ["AnalysisContract"]),
        // USDA FoodData Central records normalized to the contract's documented foods; the backend's food search
        // uses it, so the FDC API key never ships with the app.
        .library(name: "FoodDataCentral", targets: ["FoodDataCentral"]),
    ],
    targets: [
        .target(name: "AnalysisContract"),
        .target(name: "FoodDataCentral", dependencies: ["AnalysisContract"]),
        .target(name: "NutritionCore", dependencies: ["AnalysisContract"]),
        .testTarget(name: "NutritionCoreTests", dependencies: ["NutritionCore"]),
        .testTarget(name: "FoodDataCentralTests", dependencies: ["FoodDataCentral"]),
    ]
)
