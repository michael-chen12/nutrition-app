// swift-tools-version:5.10
// The app's backend: keeps the Gemini and USDA FoodData Central credentials off the iPhone and answers photo
// analysis and food search in the shared `AnalysisContract` (root package).
//
// `MealPhotoAnalysis` holds every decision (request validation, Gemini request building, response validation,
// FoodData Central search and normalization through the shared `FoodDataCentral` adapter, failure mapping,
// credential handling) and tests on any platform without a network or a real key.
// `MealPhotoAnalysisServer` is a thin Hummingbird HTTP server around it. Hummingbird (and SwiftNIO's
// networking) does not build on Windows, so on Windows this package leaves the server out and `swift test`
// covers the library only; build and run the server on macOS or Linux.

import PackageDescription

var dependencies: [Package.Dependency] = [
    .package(name: "NutritionApp", path: ".."),
]

var products: [Product] = [
    .library(name: "MealPhotoAnalysis", targets: ["MealPhotoAnalysis"]),
]

var targets: [Target] = [
    .target(
        name: "MealPhotoAnalysis",
        dependencies: [
            .product(name: "AnalysisContract", package: "NutritionApp"),
            .product(name: "FoodDataCentral", package: "NutritionApp"),
        ]
    ),
    .testTarget(name: "MealPhotoAnalysisTests", dependencies: ["MealPhotoAnalysis"]),
]

#if !os(Windows)
dependencies += [
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
]
products += [
    .executable(name: "MealPhotoAnalysisServer", targets: ["MealPhotoAnalysisServer"]),
]
targets += [
    .executableTarget(
        name: "MealPhotoAnalysisServer",
        dependencies: [
            "MealPhotoAnalysis",
            .product(name: "AnalysisContract", package: "NutritionApp"),
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "NIOCore", package: "swift-nio"),
        ]
    ),
]
#endif

let package = Package(
    name: "NutritionBackend",
    platforms: [
        .macOS(.v14),
    ],
    products: products,
    dependencies: dependencies,
    targets: targets
)
