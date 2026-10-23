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
- `Sources/AnalysisContract/` — the Codable wire contract between the app and the photo analysis backend
  (request with meal photos; response with candidate foods, portion suggestions, duplicate-group hints and
  specific unresolved details; error codes). It never carries nutrient values: nutrients come only from
  documented sources or custom foods once the person accepts a suggestion. `NutritionCore` re-exports it.
- `Backend/` — separate Swift package for the small analysis backend that keeps the Gemini API key off the
  iPhone. See "Photo analysis backend" below.
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
| `MealAnalysisBackendURL` | Optional. The photo analysis backend, default `http://127.0.0.1:8080`. |

## Build and test

Requires a Swift 5.10+ toolchain (macOS, Linux or Windows).

```sh
swift build
swift test
```

On Windows, make sure the Swift toolchain and runtime are on `PATH` and `SDKROOT` points at the Windows SDK
before running these commands.

## Photo analysis backend

`Backend/` asks the Gemini API for structured meal photo suggestions and answers in `AnalysisContract` at
`POST /v1/meal-photo-analyses`. Its `MealPhotoAnalysis` library holds every decision (request validation,
Gemini request building, response validation, failure mapping, credential handling); contract tests run it
against fixture provider replies, never a live model, and need no key.

```sh
cd Backend
swift test                                        # any platform, including Windows
GEMINI_API_KEY=... swift run MealPhotoAnalysisServer   # macOS or Linux only
```

- `GEMINI_API_KEY` stays on the server: it is sent only in the provider request header and never appears in
  replies. Without it the endpoint answers `notConfigured` and nothing is uploaded.
- `GEMINI_MODEL` defaults to `gemini-2.5-flash`; `PORT` defaults to 8080 and `HOST` to 127.0.0.1.
- The `MealPhotoAnalysisServer` executable uses Hummingbird, which does not build on Windows, so
  `Backend/Package.swift` leaves it out there.
- **Re-verify before relying on it:** the model name, the live free-tier quota, and the Gemini API terms in the
  developer account. On the unpaid tier Google may use submitted content and responses to improve its products,
  possibly with human review, so the app discloses this before upload and the prototype uses only
  non-sensitive test photos.
