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
- `Sources/AUSNUT/` — the first regional source (ticket #13). It packages FSANZ AUSNUT 2023 as CSV exports of its
  workbooks and normalizes them to the same `DocumentedFood` (ADR 0005). `Resources/README.md` records where the
  files came from, and `docs/calibration/source-gaps.md` records the gap they answer.
- `Sources/NutritionCalibration/` — the accuracy calibration pilot (ADR 0002): consented reference meals, trials
  that run one through `MealEntryWorkflow` recording the pre-review and reviewed estimates, the accuracy report
  by cuisine and dish type, and pass criteria frozen before the validation set is scored. Scoring the held-out
  validation set decides the accuracy gate for broad launch and the accuracy claim the app may make
  (`EstimateReliability`, shown in the photo-analysis disclosure). `docs/calibration/launch-decision.md` records
  each decision.
  `Sources/NutritionCalibrationTool/` is its `nutrition-calibration` command; the app's debug-build
  **Calibration pilot** screen runs trials. See `docs/calibration/README.md`. Its tests
  (`Tests/NutritionCalibrationTests/`) fake only `MealAnalysisGateway`.
- `Backend/` — separate Swift package for the small backend that keeps the Gemini and FoodData Central API
  keys off the iPhone. See "Backend" below.
- `Tests/NutritionCoreTests/` — XCTest suite. Feature tests drive `MealEntryWorkflow` and fake only the
  external boundary (`MealAnalysisGateway`). Camera capture tests drive `MealPhotoCapture` with a camera test
  substitute for the on-device `MealPhotoCamera` adapter, since hardware capture is unavailable to them.
- `iOSApp/` — thin SwiftUI views over the core, built as the iOS 17+ `MealNutrition` app target described by
  the XcodeGen spec `iOSApp/project.yml`. Not part of the Swift package.

### iOS app

The Xcode project is generated, not committed. On a Mac with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
cd iOSApp
xcodegen generate
open MealNutrition.xcodeproj
```

`project.yml` also generates the Info.plist, including `NSCameraUsageDescription` (in-app camera capture
crashes without it) and `MealAnalysisBackendURL` (the backend, `http://127.0.0.1:8080`, which the iOS
Simulator reaches on this Mac). Change the plist through `project.yml`, never the generated file.

## Build and test

Requires a Swift 5.10+ toolchain (macOS, Linux or Windows).

```sh
swift build
swift test
```

On Windows, make sure the Swift toolchain and runtime are on `PATH` and `SDKROOT` points at the Windows SDK
before running these commands.

CI (`.github/workflows/ci.yml`) runs on macOS for every push and pull request: the core package tests, the
backend tests plus a build of its server, and a build of the iOS app for the Simulator.

## Backend

`Backend/` serves the app's two outside calls, both in `AnalysisContract`:

- `POST /v1/meal-photo-analyses` asks the Gemini API for structured meal photo suggestions.
- `POST /v1/food-searches` searches USDA FoodData Central (Foundation, SR Legacy and Survey (FNDDS) foods),
  fetches the full records of the hits for their portion weights, and answers with documented foods normalized
  by the shared `FoodDataCentral` adapter: source name, FDC ID, nutrients per 100 g and serving units. It also
  searches the packaged AUSNUT 2023 data (loaded once at start-up). Foods whose name has every word of the
  search come first, from either source. Within that group and the rest, the two sources' results alternate,
  FDC first, so overlapping foods appear side by side, each with its source name and record ID (ADR 0006).

Its `MealPhotoAnalysis` library holds every decision (request validation, provider request building, response
validation, failure mapping, credential handling); contract tests run it against hand-built Gemini and FDC
replies, never a live model or API, and need no key. One feature test, `ExpandNutritionSourceCoverageFeatureTests`,
covers the app and backend together. It drives `MealEntryWorkflow` through the real `HTTPMealAnalysisGateway` and
hands each request to `FoodSearchService` in-process. It searches the packaged AUSNUT data and fakes only FDC.

```sh
cd Backend
swift test                                                            # any platform, including Windows
GEMINI_API_KEY=... FDC_API_KEY=... swift run MealPhotoAnalysisServer  # macOS or Linux only
```

| Variable | Use |
| --- | --- |
| `GEMINI_API_KEY` | Required for photo analysis. Without it that endpoint answers `notConfigured` and nothing is uploaded. |
| `GEMINI_MODEL` | Optional, default `gemini-2.5-flash`. |
| `FDC_API_KEY` | Required for FoodData Central results (sign up at https://fdc.nal.usda.gov/api-key-signup). Without it, or while FDC is unavailable, food search returns only AUSNUT 2023 foods. If AUSNUT has no match either, it answers `notConfigured` (or `providerUnavailable`) and the app offers custom foods. |
| `PORT`, `HOST` | Optional, default 8080 and 127.0.0.1. |

- Both keys stay on the server: each is sent only in its outbound request header (`x-goog-api-key`,
  `X-Api-Key`), never in a URL, and never appears in replies.
- The `MealPhotoAnalysisServer` executable uses Hummingbird, which does not build on Windows, so
  `Backend/Package.swift` leaves it out there.
- **Re-verify before relying on it:** the model name, the live free-tier quota, and the Gemini API terms in the
  developer account, and the FoodData Central rate limits for your key. On the unpaid Gemini tier Google may use
  submitted content and responses to improve its products, possibly with human review, so the app discloses
  this before upload and the prototype uses only non-sensitive test photos.
