# Nutrition-source gaps

Gaps in documented food coverage, and the source added for each (ADR 0003, ticket #13). The research note
[`docs/research/regional-nutrition-sources.md`](../research/regional-nutrition-sources.md) compares the
candidate sources.

## 2026-10-23: Asian mixed dishes, answered with FSANZ AUSNUT 2023

**Gap.** The gap covers Asian mixed dishes such as sushi, laksa and other noodle soups, savoury dumplings, and
curries. USDA FoodData Central's Survey foods reflect US dietary data and rarely document these as whole dishes
with household measures. Without them a photo suggestion gets a weaker match, or the person adds a custom food.

**How it was recorded.** The calibration pilot had not run yet. The developer recorded this gap in advance from
the research note's shortlist so ticket #13 could proceed. It is an expected gap, not a measured one. Once the
pilot runs, compare this entry with the cuisine error groups and the Gaps section of its report, which lists
foods still missing after review and suggestions or custom foods with no documented food. Then note here
whether the pilot confirmed the gap.

**Source.** [AUSNUT 2023](https://www.foodstandards.gov.au/science-data/food-nutrient-databases/ausnut) is
published by Food Standards Australia New Zealand. It has 3,741 foods, including 74 curries, 16 sushi entries,
laksa and dumplings, and 9,816 food measures with gram weights. The `AUSNUT` module packages it, and the backend
searches it beside FDC. In the app its foods show the source "FSANZ AUSNUT 2023" and their Public Food Key, for
example `F009009` for "Sushi, salmon".

The research note gives the reasons for this choice. Among openly licensed tables, AUSNUT has the most of these
dishes, and it is the only one that documents gram weights for servings such as pieces, rolls and cups. CoFID
2021 has a clearer licence and more South Asian dishes, but no portions. MEXT 2023 has Japanese names only.

**Normalization.** `Sources/AUSNUT/AUSNUTDataset.swift` and ADR 0005 have the details.

- AUSNUT gives energy in kJ only. Calories are "Energy with dietary fibre (kJ)" divided by 4.184.
- Carbohydrate is "Available carbohydrate, with sugar alcohols (g)" as published. It excludes fibre, so it
  reads lower than FDC's total carbohydrate by difference.
- All values are per 100 g of edible portion, liquids included.
- Each measure with a gram amount becomes a serving unit for one unit, such as one piece or one cup.
- Density rows give grams per mL, not a serving, so the adapter leaves them out. Curries and laksa have only a
  density row, so the person enters them in grams.

**Overlap with FDC.** Both sources have plain foods such as cooked rice. Search puts foods whose name has every
word of the search first, from either source, because FDC returns something for almost any search (ADR 0006).
Within that group and the rest, results alternate between the two sources, FDC first, so plain foods both
sources match keep FDC first. Every result shows its source name and record ID. The person picks the suitable
match or adds a custom food. The backend packages AUSNUT, so search still returns AUSNUT foods when FDC has no
key or fails.

**Photo suggestion wording.** A photo suggestion may name a dish with a word AUSNUT's names lack, such as
"salmon sushi roll" for "Sushi, salmon". When no AUSNUT name has every word, AUSNUT search retries with one word
left out. A few dish names are searched in AUSNUT's words, such as "gyoza" as "fried dumpling". The test list of
gap-dish queries in `Tests/AUSNUTTests/AUSNUTDatasetTests.swift` checks that each finds its AUSNUT food.

**Before shipping.** FSANZ's [copyright page](https://www.foodstandards.gov.au/copyright) licenses its website
material under CC BY 4.0, including commercial use, but does not name AUSNUT. Confirm with FSANZ that the
licence covers the datasets, and credit "Food Standards Australia New Zealand" wherever the data appears. The
app's source label gives that credit on each food.
