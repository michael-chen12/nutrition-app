# Calibration pilot

How a developer measures nutrition estimate accuracy before broad release (ADR 0002, ticket #12). The pilot
compares two estimates of each consented **reference meal** with what the meal actually contained:

- **Pre-review estimate**: the photo suggestions accepted as offered (first documented match, suggested
  portion), before the person changes anything. This measures photo analysis and food matching.
- **Reviewed estimate**: the saved meal entry after the person's review. This is the nutrition estimate the
  app shows, and measures what review adds.

Calibration meals set the numeric pass criteria. Validation meals are held out: they are scored only once,
against criteria frozen beforehand.

The code is `Sources/NutritionCalibration/` (`CalibrationPilot` holds the protocol), the debug-build
**Calibration pilot** screen in the iPhone app runs trials, and the `nutrition-calibration` command writes the
reports. None of this runs in CI on real meals; CI tests it with hand-built records.

## 1. Collect reference meals

For each meal (a checklist and a JSON template to fill in are in
[`collecting-a-reference-meal.md`](collecting-a-reference-meal.md)):

1. Get the participant's written consent, covering the meal photos being uploaded for photo analysis under the
   provider's retention terms (see `PhotoAnalysisDisclosure`). Record them only by a code such as `P01`.
   Photos must still be non-sensitive: no people, faces, documents or screens.
2. Establish reference nutrition independently of the app: weigh each food before taking the photos, or make
   the dish from a recipe with weighed ingredients and record the pictured share. Take per-100 g values from a
   documented source or the recipe calculation, and note where each came from.
3. Take the meal photos as a person would (several angles and every dish), including shared food and leftovers:
   the reference is all pictured food.
4. Assign the meal to the calibration or validation set **before** running it. Cover several cuisines and dish
   types in both sets; validation meals must be new meals, not re-photographed calibration meals.

## 2. The pilot folder

```
CalibrationPilot/
  reference-meals/<any name>.json   one reference meal each (format below)
  photos/<file name>                the photos the reference meals name
  evaluations/<meal ID>.json        written by the app, one per evaluated meal
  pass-criteria.json                written when the criteria are frozen
  calibration-report.md             written by `nutrition-calibration report`
  validation-report.md              written when the validation set is scored
  estimate-reliability.json         the accuracy claim the app may make, written with it
```

A reference meal (`ReferenceMeal`; dates are ISO 8601):

```json
{
  "id": "pilot-001",
  "split": "calibration",
  "cuisine": "South Asian",
  "dishType": "Rice plate",
  "referenceMethod": "weighedPortions",
  "consent": { "participantCode": "P01", "consentedOn": "2026-10-01T00:00:00Z", "coversPhotoAnalysisUpload": true },
  "photoFileNames": ["pilot-001-above.jpg", "pilot-001-side.jpg"],
  "referenceFoods": [
    {
      "id": "rice", "name": "White rice, cooked", "grams": 180,
      "nutrientsPer100g": { "calories": 130, "protein": 2.7, "carbohydrates": 28, "fat": 0.3 },
      "nutritionSource": "USDA FoodData Central 168878"
    }
  ]
}
```

`split` is `calibration` or `validation`; `referenceMethod` is `weighedPortions` or `knownRecipe`. A meal without
upload consent, a participant code, a cuisine and dish type, photos, or reference foods with positive grams is
refused. So are cuisines or dish types written two ways that differ only in case or spacing (`Japanese` and
`japanese`), which would count as two. Keep the pilot folder in version control (outside this repository if photos are private) so its history
shows when each record and the criteria were written.

## 3. Run trials in the app

1. Start the backend (see the main README) and run a **Debug** build of the app.
2. Copy the pilot folder into the app's files as `CalibrationPilot` (Finder for a device; the Files app; or
   `xcrun simctl get_app_container booted io.github.michael-chen12.MealNutrition data` for the Simulator, then
   `Documents/CalibrationPilot`).
3. In meal history, tap the scale icon (**Calibration pilot**) and pick a meal. Its photos are uploaded together
   for one analysis and the pre-review estimate is recorded.
4. The participant reviews the meal in the usual review screen and saves it. Correction time runs from the
   suggestions being shown to that save.
5. Label each reference food: whether a photo suggestion stood for it, and whether the saved meal entry includes
   it. These give the **missing-food rate** of each stage. Record the evaluation.

Trial meal entries are saved apart from the person's meal history. A meal is evaluated once; discard a trial to
run it again, for example after a backend outage. Two evaluation files for one meal (e.g. a Finder copy) are
refused rather than counted twice. Until the pass criteria are frozen only calibration meals can
be run; after, only validation meals, so no validation result exists before the criteria do. Every food starts
labelled as found: check each one rather than recording the defaults.

## 4. Inspect calibration and freeze the pass criteria

```sh
swift run nutrition-calibration report path/to/CalibrationPilot
```

The report shows calorie, protein, carbohydrate and fat errors for both stages, overall and by cuisine and dish
type, with the missing-food rate and median correction time. Its **Gaps** section lists thin coverage (few
cuisines, dish types or meals per group; unevaluated meals; meals whose photo analysis gave no suggestions,
with the message shown, so an outage is not mistaken for missed foods; foods still missing after review; suggestions and
custom foods with no documented food, i.e. candidates for another nutrition source, ADR 0003) and estimation
gaps (groups with calorie error well above the set's, or where review did not reduce it). Record each source gap,
and the source chosen for it, in `source-gaps.md`.

After inspecting it, write the criteria as a JSON array of `PassCriterion`, each with the reason for its limit:

```json
[
  { "stage": "reviewed", "metric": "caloriesPercentError", "scope": "eachCuisine", "atMost": 0,
    "rationale": "Why this limit, from the calibration report." }
]
```

Metrics: `caloriesPercentError`, `proteinPercentError`, `carbohydratesPercentError`, `fatPercentError`,
`missingFoodPercent` (percentages, 0–100), and `medianCorrectionTime` (seconds, reviewed stage only). Scopes:
`allMeals`, `eachCuisine`, `eachDishType`. The criteria must set a limit on calorie, protein, carbohydrate and
fat percent error for the pre-review and the reviewed stage separately, with any scope. Missing-food and
correction-time limits are optional, but both values appear in every report. Then freeze them:

```sh
swift run nutrition-calibration freeze-criteria path/to/CalibrationPilot criteria.json
```

Freezing is refused until every calibration meal is evaluated and the calibration set spans at least two
cuisines and two dish types. It happens once: afterwards calibration is closed, and validation is scored only
against those criteria and the calibration records they were set from. The calibration report never decides
broad launch, and says so.

## 5. Score validation

Validation meals are new meals collected for this set. They follow the rules in Section 1, and like the
calibration set they span at least two cuisines and two dish types. A validation meal whose photo is
byte-for-byte a calibration meal's photo is refused when its trial starts and again at scoring. That check
cannot spot a calibration meal that was photographed again, so collect new meals.

Run every validation meal in the app (Section 3), then:

```sh
swift run nutrition-calibration score-validation path/to/CalibrationPilot
```

It writes `validation-report.md`. The report states whether the **accuracy gate** passed (every criterion
passed) and gives each criterion's measured values. It then lists the **cuisine and dish-type failures**: every
criterion applied to each cuisine and dish type on its own, so a cuisine that misses an all-meals limit is named
even when the gate passes. The validation accuracy report follows. The command exits 0 only when the gate passed.

Scoring also writes `estimate-reliability.json`, the accuracy claim the app may make (`EstimateReliability`):

- `notValidated` unless the gate passed.
- After a pass, the meal count, cuisines and dish types tested, the mean calorie error before and after review,
  and the cuisines and dish types whose measured nutrient error went over a limit.

Scoring is refused before the criteria are frozen, while any validation meal is unevaluated, if the validation
set spans fewer than two cuisines or dish types or reuses a calibration photo, or if calibration records changed
since freezing. The validation set is scored once; afterwards neither scoring nor freezing runs again.

These checks guard the order of the study; they do not make files tamper-proof. The pilot folder's version
history is the record of what was written when.

## 6. Record the launch decision

Broad launch goes ahead only if the accuracy gate passed on the validation set. Calibration results alone never
decide it. After scoring:

1. Add an entry to [`launch-decision.md`](launch-decision.md) with the date, the pilot folder's commit, the gate
   result, the failed criteria and the cuisine and dish-type failures.
2. Set `EstimateReliability.published` (`Sources/NutritionCore/Domain/EstimateReliability.swift`) to the
   contents of `estimate-reliability.json`. The app shows its statement in the photo-analysis disclosure, so the
   app's public claim matches what was measured. If the gate did not pass it stays `notValidated`.
3. Where failures cluster in a cuisine or dish type, record the nutrition-source gap in `source-gaps.md`. A
   validation after any fix needs new meals and a new pilot, since this validation set has been seen.
