# Collecting a reference meal

A checklist for each meal of the calibration pilot or the validation set ([`README.md`](README.md) Section 1).
Start from [`reference-meal-template.json`](reference-meal-template.json). Save the filled copy in the pilot
folder's `reference-meals/`, not in this repository. The template as committed is refused by the pilot: its
consent is `false` and its food weighs 0 g. Every value you put in it must come from the meal itself.

## Before the meal

- [ ] The participant has given written consent that covers uploading the meal photos for photo analysis under
      the provider's retention terms (`PhotoAnalysisDisclosure`). Keep the signed form with the study records,
      outside the pilot folder.
- [ ] They have a pseudonymous code such as `P01`. No name or contact detail goes in the JSON.
- [ ] The meal is assigned to `calibration` or `validation` **now**, before any trial. A validation meal must be a
      new meal, not a calibration meal photographed again.

## Establish the reference nutrition

- [ ] `weighedPortions`: weigh each food on a kitchen scale before the photos, net of the plate.
- [ ] `knownRecipe`: weigh every ingredient, weigh the cooked dish, then weigh the share that is pictured.
- [ ] For each food, write down the per-100 g calories, protein, carbohydrates and fat. Take them from a
      documented source (e.g. a USDA FoodData Central or AUSNUT ID) or from the recipe calculation, and note
      which in `nutritionSource`.
- [ ] Include everything pictured: sides, sauces, drinks, shared dishes and leftovers.

## Photos

- [ ] Take the photos as a person would, from several angles and with every dish visible.
- [ ] No people, faces, documents or screens.
- [ ] Copy them into the pilot folder's `photos/` under the file names listed in `photoFileNames`.

## Fill in the JSON

| Field | What to write |
|---|---|
| `id` | Unique, usable as a file name, e.g. `val-007`. |
| `split` | `calibration` or `validation`. |
| `cuisine`, `dishType` | Spell each one exactly as in the other meals. Names that differ only in case or spacing are refused. |
| `referenceMethod` | `weighedPortions` or `knownRecipe`. |
| `consent` | The participant code, the consent date (ISO 8601), and `coversPhotoAnalysisUpload: true` only if the signed consent covers it. |
| `referenceFoods` | One entry per pictured food, each with a unique `id`, positive `grams`, per-100 g nutrients and their source. |

Then run `swift run nutrition-calibration report <pilot folder>`. It reads every reference meal and refuses
any that is incomplete, so a mistake shows up before a trial is run.
