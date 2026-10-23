# Packaged AUSNUT 2023 data

Source: Food Standards Australia New Zealand, AUSNUT 2023. Credit: "Food Standards Australia New Zealand",
under the CC BY 4.0 licence on the [FSANZ copyright page](https://www.foodstandards.gov.au/copyright). Confirm
the licence covers AUSNUT before shipping (`docs/calibration/source-gaps.md`).

Each CSV is the data sheet of one FSANZ workbook, exported cell by cell (raw values, title row included) and
otherwise unchanged. The workbooks were downloaded on 2026-10-23:

| File | Workbook and sheet | SHA-256 of the downloaded workbook |
| --- | --- | --- |
| `AUSNUT 2023 - Food nutrient profiles.csv` | [AUSNUT 2023 - Food nutrient profiles.xlsx](https://www.foodstandards.gov.au/sites/default/files/2025-09/AUSNUT%202023%20-%20Food%20nutrient%20profiles.xlsx?v=20250903), sheet "Food nutrient profiles" | `374650afc59951009d5ddf48fe35f712467458eb07eef513ea9f54c8f110f317` |
| `AUSNUT 2023 - Food measures.csv` | [AUSNUT 2023 - Food measures.xlsx](https://www.foodstandards.gov.au/sites/default/files/2025-08/AUSNUT%202023%20-%20Food%20measures.xlsx?v=20250903), sheet "AUSNUT 2023" | `58bee1204610efb72bb831dc7fb65acc23db540b51d056f83c6ac0ce84590475` |

To update for a new release, export the same sheets as CSV (UTF-8) under these names. The adapter finds the
header row and columns by name, so a spreadsheet application's "Save as CSV" also works. Then update the
edition in `AUSNUTDataset.sourceName` and the food count in `AUSNUTDatasetTests`. Column meanings are in FSANZ's
"About the foods and nutrients" and "About the food measures" PDFs.
