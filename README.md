# Meal nutrition app

An English-language iPhone app that turns meal photos into an editable, approximate nutrition estimate
(calories, protein, carbohydrates, fat) for all pictured food, kept in local meal history.
See `IMPLEMENTATION_PLAN.md`, `GLOSSARY.md` and `docs/adr/`.

## Layout

- `Package.swift`, `Sources/NutritionCore/` — platform-neutral core (Foundation only): domain model,
  deterministic nutrient calculation, meal history persistence, the external boundary protocol, and the
  `MealEntryWorkflow` feature seam the UI binds to. All behaviour lives here. Documented foods arrive from the
  backend's food search and become the shared per-100 g `Food`.
  Meal history is grouped by day: a meal entry belongs to the calendar day containing its date in the
  `Calendar` (and time zone) given to `MealEntryWorkflow`; the app passes `.current`, tests a fixed one.
- `Sources/AnalysisContract/` — the Codable wire contract between the app and the backend: photo analysis
  (request with meal photos; response with candidate foods, match confidence, portion suggestions,
  duplicate-group hints and specific unresolved details) and food search (query; documented foods with source
  name, record ID, nutrients per 100 g and serving units), plus error codes. Photo analysis never carries
  nutrient values: nutrients come only from documented foods or custom foods once the person accepts a
  suggestion. `NutritionCore` re-exports it.
- `Sources/FoodDataCentral/` — the USDA FoodData Central adapter, normalizing FDC records to the contract's
  `DocumentedFood`. Additional regional sources get their own adapter producing the same type. The backend
  uses it; its tests use hand-built FDC fixtures.
- `Backend/` — separate Swift package for the small backend that keeps the Gemini and FoodData Central API
  keys off the iPhone. See "Backend" below.
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

## Backend

`Backend/` serves the app's two outside calls, both in `AnalysisContract`:

- `POST /v1/meal-photo-analyses` asks the Gemini API for structured meal photo suggestions.
- `POST /v1/food-searches` searches USDA FoodData Central (Foundation, SR Legacy and Survey (FNDDS) foods),
  fetches the full records of the hits for their portion weights, and answers with documented foods normalized
  by the shared `FoodDataCentral` adapter: source name, FDC ID, nutrients per 100 g and serving units.

Its `MealPhotoAnalysis` library holds every decision (request validation, provider request building, response
validation, failure mapping, credential handling); contract tests run it against hand-built Gemini and FDC
replies, never a live model or API, and need no key.

```sh
cd Backend
swift test                                                            # any platform, including Windows
GEMINI_API_KEY=... FDC_API_KEY=... swift run MealPhotoAnalysisServer  # macOS or Linux only
```

| Variable | Use |
| --- | --- |
| `GEMINI_API_KEY` | Required for photo analysis. Without it that endpoint answers `notConfigured` and nothing is uploaded. |
| `GEMINI_MODEL` | Optional, default `gemini-2.5-flash`. |
| `FDC_API_KEY` | Required for food search (sign up at https://fdc.nal.usda.gov/api-key-signup). Without it food search answers `notConfigured` and the app offers custom foods. |
| `PORT`, `HOST` | Optional, default 8080 and 127.0.0.1. |

- Both keys stay on the server: each is sent only in its outbound request header (`x-goog-api-key`,
  `X-Api-Key`), never in a URL, and never appears in replies.
- The `MealPhotoAnalysisServer` executable uses Hummingbird, which does not build on Windows, so
  `Backend/Package.swift` leaves it out there.
- **Re-verify before relying on it:** the model name, the live free-tier quota, and the Gemini API terms in the
  developer account, and the FoodData Central rate limits for your key. On the unpaid Gemini tier Google may use
  submitted content and responses to improve its products, possibly with human review, so the app discloses
  this before upload and the prototype uses only non-sensitive test photos.
