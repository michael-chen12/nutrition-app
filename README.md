# Meal nutrition app

An English-language iPhone app that turns meal photos into an editable, approximate nutrition estimate
(calories, protein, carbohydrates, fat) for all pictured food, kept in local meal history.
See `IMPLEMENTATION_PLAN.md`, `GLOSSARY.md` and `docs/adr/`.

## Layout

- `Package.swift`, `Sources/NutritionCore/` — platform-neutral core (Foundation only): domain model,
  deterministic nutrient calculation, meal history persistence, the external boundary protocol, and the
  `MealEntryWorkflow` feature seam the UI binds to. All behaviour lives here.
- `Tests/NutritionCoreTests/` — XCTest suite. Feature tests drive `MealEntryWorkflow` and fake only the
  external boundary (`MealAnalysisGateway`).
- `iOSApp/` — thin SwiftUI views over the core. Not part of the Swift package; build it in Xcode by adding
  these files to an iOS 17+ app target that depends on the `NutritionCore` package product.

## Build and test

Requires a Swift 5.10+ toolchain (macOS, Linux or Windows).

```sh
swift build
swift test
```

On Windows, make sure the Swift toolchain and runtime are on `PATH` and `SDKROOT` points at the Windows SDK
before running these commands.
