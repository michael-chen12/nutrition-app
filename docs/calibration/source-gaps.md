# Nutrition-source gaps

Gaps in documented food coverage, and the source added for each (ADR 0003, ticket #13). Candidate sources are
compared in [`docs/research/regional-nutrition-sources.md`](../research/regional-nutrition-sources.md).

## 2026-10-23: Asian mixed dishes, answered with FSANZ AUSNUT 2023

**Gap.** Asian mixed dishes: sushi, laksa and other noodle soups, savoury dumplings, and curries. USDA
FoodData Central's Survey foods reflect US dietary data and rarely document these as whole dishes with
household measures. Without them a photo suggestion falls back to a weaker match or a custom food.

**How it was recorded.** The calibration pilot had not run yet. The developer recorded this gap in advance from
the research note's shortlist so ticket #13 could proceed. It is an expected gap, not a measured one. Once the
pilot runs, compare its report's **Gaps** section (foods still missing after review; suggestions and custom foods
with no documented food) and cuisine error groups with this entry, and note here whether the gap was confirmed.

**Source.** [AUSNUT 2023](https://www.foodstandards.gov.au/science-data/food-nutrient-databases/ausnut) from
Food Standards Australia New Zealand: 3,741 foods with many mixed dishes (74 curries, 16 sushi, laksa,
dumplings) and 9,816 food measures with gram weights. It is packaged in the `AUSNUT` module and searched by the
backend beside FDC. In the app its foods show as **FSANZ AUSNUT 2023** with their Public Food Key (for example
`F009009`, "Sushi, salmon").

Why this source, from the research note: it has the most of these dishes among openly licensed tables, and
it is the only one that documents gram weights for servings (pieces, rolls, cups). CoFID 2021 has a clearer
licence and more South Asian dishes but no portions. MEXT 2023 has Japanese names only.

**Normalization** (see `Sources/AUSNUT/AUSNUTDataset.swift` and ADR 0005):

- Energy is in kJ only. Calories are "Energy with dietary fibre (kJ)" / 4.184.
- Carbohydrate is "Available carbohydrate, with sugar alcohols (g)" as published. It excludes fibre, so it
  reads lower than FDC's total by difference.
- All values are per 100 g of edible portion, liquids included.
- Measures become serving units of one unit with their gram amount. "density" rows (grams per mL) are not
  servings and are left out, so foods such as curries and laksa, which have only a density row, are added in
  grams.

**Overlap with FDC.** Both sources have plain foods such as cooked rice. Search results alternate between the
two sources, FDC first, and every result shows its source name and record ID, so the person picks the suitable
match or adds a custom food.

**Before shipping.** FSANZ's [copyright page](https://www.foodstandards.gov.au/copyright) licenses its website
material under CC BY 4.0, including commercial use, but does not name AUSNUT. Confirm with FSANZ that the
datasets are covered, and credit "Food Standards Australia New Zealand" wherever the data is used. The app's
source label does this for each food.
