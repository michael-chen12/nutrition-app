# Meal nutrition app

An English-language iPhone app that turns meal photos into an editable, approximate nutrition estimate
(calories, protein, carbohydrates, fat) for all pictured food, kept in local meal history.
See `IMPLEMENTATION_PLAN.md`, `GLOSSARY.md` and `docs/adr/`.

## Layout

- `Package.swift`, `Sources/NutritionCore/` — platform-neutral core (Foundation only): domain model,
  deterministic nutrient calculation, meal history persistence, the external boundary protocol, and the
  `MealEntryWorkflow` feature seam the UI binds to. All behaviour lives here. `FoodData/` holds nutrition
  source adapters (USDA FoodData Central first) that normalize source records to the shared per-100 g `Food`.
  Meal history is grouped by day: a meal entry belongs to the calendar day containing its date in the
  `Calendar` (and time zone) given to `MealEntryWorkflow`; the app passes `.current`, tests a fixed one.
- `Tests/NutritionCoreTests/` — XCTest suite. Feature tests drive `MealEntryWorkflow` and fake only the
  external boundary (`MealAnalysisGateway`). Camera capture tests drive `MealPhotoCapture` with a camera test
  substitute for the on-device `MealPhotoCamera` adapter, since hardware capture is unavailable to them.
- `iOSApp/` — thin SwiftUI views over the core. Not part of the Swift package; build it in Xcode by adding
  these files to an iOS 17+ app target that depends on the `NutritionCore` package product.

### Info.plist

There is no Xcode project in this repo yet. When creating the app target, add this key to its Info.plist
(or the target's "Info" tab), or in-app camera capture crashes on first use:

| Key | Value |
| --- | --- |
| `NSCameraUsageDescription` | `Take meal photos to add to a meal entry.` |

## Build and test

Requires a Swift 5.10+ toolchain (macOS, Linux or Windows).

```sh
swift build
swift test
```

On Windows, make sure the Swift toolchain and runtime are on `PATH` and `SDKROOT` points at the Windows SDK
before running these commands.
