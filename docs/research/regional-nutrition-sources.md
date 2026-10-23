# Regional nutrition sources

Date: 2026-10-23

This note supports issue #13 ("Expand nutrition-source coverage") and [ADR 0003](../adr/0003-combine-traceable-nutrition-sources.md). Issue #13 adds one documented regional source beside USDA FoodData Central (FDC) once the calibration pilot records a cuisine or dish-type gap. The pilot has not run yet, so no gap is recorded and **no source is chosen here**. This is input to that decision: it describes each candidate against what the app needs, so the developer can pick one quickly when a gap appears.

What a source must supply, from [`DocumentedFood`](../../Sources/AnalysisContract/FoodSearch.swift) and the FDC adapter [`FoodDataCentralRecord`](../../Sources/FoodDataCentral/FoodDataCentralRecord.swift):

- Calories (kcal), protein, carbohydrates and fat per 100 g. Records that are only per 100 mL are left out.
- A source name and a stable record ID.
- Serving units with a documented gram weight and quantity basis, where the source has them. Grams are never guessed.
- A key-based API is called from the backend. A downloadable dataset can be packaged instead ([`IMPLEMENTATION_PLAN.md`](../../IMPLEMENTATION_PLAN.md) step 3).

For comparison, the FDC adapter reads energy in kcal (nutrient 1008, falling back to 2048 and 2047) and carbohydrate **by difference** (nutrient 1005), which includes dietary fibre ([`FoodDataCentralRecord.swift`](../../Sources/FoodDataCentral/FoodDataCentralRecord.swift)).

How this was checked: on 2026-10-23 I opened each publisher's page and, where a file was offered, downloaded it and read its column headers and a sample of rows. Links point to the pages and files I opened. Anything I could not confirm from a primary source is marked **unverified**. Licence summaries are a reading of the published terms, not legal advice.

## Comparison

| Source | Foods | Mixed dishes | Energy | Carbohydrate | Portions with grams | Record ID | Access | English names | Commercial app use |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FDC (current baseline) | Survey, Foundation, SR Legacy | Yes (Survey) | kcal | By difference, incl. fibre | Yes | FDC ID | Key-based API | Yes | Yes |
| Japan MEXT 8th ed., 2023 enlarged | 2,538 | About 55 prepared dishes, many cooked forms | kJ and kcal | Several: available (mono eq. and mass), available by difference, total by difference | No | 5-digit food number | Excel download | No (2015 edition only) | Yes, with attribution |
| India IFCT 2017 | 528 | No, raw foods | kJ only | Available, by difference | No | Food code (A001) | PDF book | Yes | Needs NIN written permission |
| India INDB (derived from IFCT) | 1,014 recipes, 1,095 items | Yes, recipes | kJ and kcal | Not stated | Serving unit text, grams unverified | Recipe code (ASC001) | Excel on GitHub | Yes | No licence stated |
| UK CoFID 2021 | 2,887 | Yes, many homemade and takeaway dishes | kJ and kcal | Available, as monosaccharide equivalents | No | Food code (11-1135) | Excel download | Yes | Yes, OGL v3 |
| Australia AFCD Release 3 | 1,588 | Few | kJ only | Available | Few, via AUSNUT | Public Food Key (F002258) | Excel download | Yes | Yes, CC BY 4.0 (site-wide statement) |
| Australia AUSNUT 2023 | 3,741 | Yes, many | kJ only | Available | Yes, 9,816 measures | Public Food Key | Excel download | Yes | Yes, CC BY 4.0 (site-wide statement) |
| Canada CNF 2015 | 5,690 | Some (mixed dishes, fast foods groups) | kJ and kcal | By difference | Yes, conversion factors | FoodID | CSV, Excel, Access; keyless JSON API | Yes (and French) | Yes, with attribution (archived terms) |
| FAO/INFOODS WAFCT 2019 | 1,028 | 94, mostly Burkina Faso | kJ and kcal | Available, by difference | No | Code (01_015) | Excel download | Yes (and French) | No, CC BY-NC-SA 3.0 IGO |
| Open Food Facts | Unverified | Packaged ready meals only | kJ and kcal | Label value, definition varies by country | Serving size text and grams | Barcode | API (keyless, rate-limited) and nightly dumps | Partly | Yes, ODbL share-alike |
| Korea MFDS food nutrient DB | Unverified | Yes, a dish (음식) file | kcal | Unverified | Serving reference amount, unverified | Food code | Key-based API | Unverified | Yes, "no restriction" |
| Brazil TBCA 7.x | Over 5,700 | Over 4,000 preparations | kJ and kcal | Total and available, by difference | Yes, household measures | Unverified | Website only | Partial | No, reproduction and sale not permitted |

## Japan: Standard Tables of Food Composition in Japan (MEXT)

The latest edition is the *Standard Tables of Food Composition in Japan, Eighth Revised Edition, Updated and Enlarged Version 2023* (日本食品標準成分表（八訂）増補2023年). Its [publisher page](https://www.mext.go.jp/a_menu/syokuhinseibun/mext_00001.html) links a [main data workbook](https://www.mext.go.jp/content/20260327-mxt_kagsei-mext-000029402_02.xlsx) and errata dated 2026-03-27, plus an [e-book of the text chapters](https://www.mext.go.jp/content/20260327-mxt_kagsei-mext-000029402_0001.pdf). The 2020 base edition is on a [separate page](https://www.mext.go.jp/a_menu/syokuhinseibun/mext_01110.html).

1. **Coverage.** The e-book's summary table gives 2,538 foods for 2023 (2,478 for 2020). The workbook I opened has 2,539 data rows across 18 food-group sheets. Many records are cooked forms (boiled, grilled, tempura). Group 18, 調理済み流通食品類 (prepared and distributed foods), has 55 food numbers, including chicken, beef and pork curry, oyakodon and gyudon toppings, croquettes and hamburg steak. Most other Japanese dishes (ramen bowls, sushi sets, bento) are not present as whole dishes.
2. **Nutrients.** All four values exist. The workbook carries INFOODS tagnames in a header row: energy as `ENERC` (kJ) and `ENERC_KCAL` (kcal); protein as `PROTCAA` (amino-acid based) and `PROT-`; fat as `FATNLEA` (triacylglycerol equivalents) and `FAT-`; carbohydrate as `CHOAVLM` (available, monosaccharide equivalents), `CHOAVL` (available, mass), `CHOAVLDF-` (available, by difference), `FIB-` and `CHOCDF-` (total, by difference). `CHOCDF-` is the closest match to FDC's carbohydrate by difference. The e-book lists component-specific energy factors (for example 16 kJ/g for available carbohydrate in monosaccharide equivalents and 17 kJ/g for protein). The extracted Japanese text was too garbled to confirm which component the energy calculation prefers when several exist, so that detail is **unverified**. Values are written as text in several forms: `Tr`, `(0)`, `-`, and parenthesised estimates such as `(11.3)`. An importer must parse these explicitly. The workbook has a refuse-percentage column (`REFUSE`, 廃棄率), which fits per-100 g edible-portion values. I did not find the edible-portion statement in the files I opened, so that is **unverified**.
3. **Portions.** The main table has no household measures or serving weights. No portion columns appear in the workbook.
4. **Identity.** Each row has a 5-digit food number (食品番号, for example `01001`) and an index number (索引番号).
5. **Access.** Excel download, no authentication, no API. Revisions are irregular: 2015 (7th), 2020 (8th), 2023 enlarged, with errata files in between. Food names are **Japanese only** in the 2020 and 2023 files. An [English 7th edition (2015)](https://www.mext.go.jp/en/policy/science_technology/policy/title01/detail01/sdetail01/sdetail01/1385122.htm) has an [English workbook](https://www.mext.go.jp/component/english/__icsFiles/afieldfile/2017/12/25/1374049_1r12_1.xlsx) with English names (for example "Japanese curry, beef, retort-pouch"). It covers fewer foods, so foods new since 2015, including most of group 18, would need translation. Whether 2015 food numbers map one-to-one onto 2023 foods is **unverified**.
6. **Licence.** The [MEXT website terms](https://www.mext.go.jp/b_menu/1351168.htm) allow copying, transmission and adaptation, and are stated to be compatible with CC BY 4.0. Key line: "商用利用も可能です。" ("Commercial use is also possible."). Attribution follows the form "出典：文部科学省ホームページ", with a note when the data have been edited. The terms also say numerical data and simple tables are not copyright works. Neither data page states food-table-specific terms.

## India: Indian Food Composition Tables 2017 (ICMR-NIN)

Published as a book and [PDF](https://nin.res.in/ebooks/IFCT2017.pdf) by the National Institute of Nutrition, Hyderabad.

1. **Coverage.** The preface says 528 key foods and 151 components, from regional composite samples averaged over six regions. The general-information chapter says all data except poultry and egg "pertains to raw food". There are no cooked dishes or recipes.
2. **Nutrients.** The proximate table has `PROTCNT`, `FATCE`, `CHOAVLDF` (available carbohydrate, by difference, so fibre is excluded) and `ENERC` in **kJ only**. The text says energy uses Atwater factors and gives "1 kcal = 4.18 kJ". All values are "per 100g edible portion" (table header). Values carry ± standard deviations in the same cell, which an importer would have to strip.
3. **Portions.** None.
4. **Identity.** Food codes such as `A001` (group letter plus number).
5. **Access.** PDF only. I found no machine-readable download from NIN. The INDB project README says the IFCT data "must be requested from the original source". English names, with scientific names.
6. **Licence.** Copyright 2017 NIN. Reproduction is allowed for personal use with acknowledgement. Key line: "no part of this publication can be stored or reproduced in any electronic format" ([PDF](https://nin.res.in/ebooks/IFCT2017.pdf), front matter), without NIN's prior written permission. An app product needs that permission.

## India: Indian Nutrient Databank (INDB)

An academic databank built on IFCT 2017 and 2004, with UK CoFID and FDC values for missing ingredients. Described in [Vijayakumar et al., 2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC11277795) and published in a [GitHub repository](https://github.com/lindsayjaacks/Indian-Nutrient-Databank-INDB-).

1. **Coverage.** 1,014 commonly consumed recipes and 1,095 raw items (paper). Recipes come from two Delhi cookery manuals (490 and 378 recipes) and 148 food blogs (README). This is the only candidate with a large set of Indian cooked dishes. The paper notes it still needs more regional dishes.
2. **Nutrients.** [`INDB.xlsx`](https://github.com/lindsayjaacks/Indian-Nutrient-Databank-INDB-/blob/main/INDB.xlsx) has `energy_kj`, `energy_kcal`, `carb_g`, `protein_g`, `fat_g` per 100 g, plus `unit_serving_*` columns per serving. The carbohydrate definition is not stated; it inherits IFCT's available carbohydrate for most ingredients and CoFID's or FDC's for others, so it is mixed (**unverified** per record).
3. **Portions.** [`recipes_servingsize.xlsx`](https://github.com/lindsayjaacks/Indian-Nutrient-Databank-INDB-/blob/main/recipes_servingsize.xlsx) has `no_of_servings`, `size_of_servings` and `servings_unit` (for example "tea cup", "glass"). It gives no gram weight per serving unit. The paper says recipes record total weight and number of servings, which could document grams per serving, but I did not confirm a gram column, so this is **unverified**.
4. **Identity.** Recipe codes with a source prefix (`ASC001`, `BFP…`, `OSR…`).
5. **Access.** Excel files in a public GitHub repository, last pushed 2025-04-08. English names with local names in brackets, for example "Raw mango drink (Aam panna)".
6. **Licence.** The repository has no licence file (GitHub reports none). The paper's CC BY licence covers the article, not the data. The data also derive from IFCT 2017, whose terms restrict electronic products. Redistribution in an app is **not cleared**; it would need permission from the authors and likely NIN.

## UK: Composition of Foods Integrated Dataset (CoFID)

*McCance and Widdowson's The Composition of Foods Integrated Dataset 2021*, on the [GOV.UK publication page](https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid), with a [data workbook](https://assets.publishing.service.gov.uk/media/60538b91e90e07527df82ae4/McCance_Widdowsons_Composition_of_Foods_Integrated_Dataset_2021..xlsx) and a [user guide](https://assets.publishing.service.gov.uk/media/60538e66d3bf7f03249bac58/McCance_and_Widdowsons_Composition_of_Foods_integrated_dataset_2021.pdf).

1. **Coverage.** The Proximates sheet has 2,887 food codes. It includes many recipe-calculated dishes eaten in the UK: South Asian dishes (bhajis, curries, dhal, biryani, samosas), Chinese takeaway dishes (chow mein, sweet and sour), kebabs, falafel, plantain and lasagne. 564 strings in the workbook contain "homemade". A separate [old foods file](https://assets.publishing.service.gov.uk/media/60538ba4e90e07527f645f88/CoFID_oldFoods.xlsx) holds 2008 foods not re-validated since.
2. **Nutrients.** Columns `Protein (g)`, `Fat (g)`, `Carbohydrate (g)`, `Energy (kcal) (kcal)` and `Energy (kJ) (kJ)`. Per the user guide, carbohydrate is **available carbohydrate expressed as monosaccharide equivalents**, from summed starch and sugars, "contrasting with figures for carbohydrate by difference". Energy uses 3.75 kcal/g for that carbohydrate. Values are per 100 g, except alcoholic beverages per 100 mL. Values are per edible portion; foods weighed with waste say "weighed with" in the name and carry an edible conversion factor. `Tr` means trace and `N` means present but unknown.
3. **Portions.** None in the files.
4. **Identity.** Food codes such as `11-1135`. The guide says each food has a unique code, and a food whose data change gets a new code, with the earlier one in a "Previous" column. That suits traceability.
5. **Access.** Excel download, no authentication, no API. Updates in 2008, 2015, 2019 and 2021, none since. English names.
6. **Licence.** The page says content is under the [Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/). Key line: "exploit the Information commercially and non-commercially". Attribution: "Contains public sector information licensed under the Open Government Licence v3.0."

## Australia: Australian Food Composition Database (AFCD) and AUSNUT 2023 (FSANZ)

Food Standards Australia New Zealand publishes two related datasets that share the Public Food Key.

**AFCD Release 3** ([download page](https://www.foodstandards.gov.au/science-data/food-nutrient-databases/afcd/australian-food-composition-database-download-excel-files), [About Release 3 PDF](https://www.foodstandards.gov.au/sites/default/files/2025-12/About%20the%20Australian%20Food%20Composition%20Database%20-%20Release%203.pdf)):

1. **Coverage.** 1,588 foods (the [Food Details workbook](https://www.foodstandards.gov.au/sites/default/files/2025-12/AFCD%20Release%203%20-%20Food%20Details.xlsx) has 1,588 keys). Mostly ingredients and commercial products. Of 417 recipes, 210 are cooked red meats (About PDF). Asian items are mostly sauces and pastes, such as "Sauce, butter chicken, commercial".
2. **Nutrients.** The [Nutrient profiles workbook](https://www.foodstandards.gov.au/sites/default/files/2025-12/AFCD%20Release%203%20-%20Nutrient%20profiles.xlsx) has a per-100 g sheet and a separate per-100 mL sheet for liquids. Energy is **kJ only**, in two columns: "Energy with dietary fibre, equated" and "Energy, without dietary fibre, equated". Carbohydrate is "Available carbohydrate, with sugar alcohols" and "without sugar alcohols", so fibre is excluded. "Analysed portion" and "Unanalysed portion" columns describe the edible part.
3. **Portions.** The About PDF says only "a small number of foods" have a common serve size, aligned with AUSNUT 2023.
4. **Identity.** Public Food Key such as `F002258`, which the workbook says "remains the same for each equivalent food across our food composition publications".
5. **Access.** Excel download, no authentication, no API. Releases: Release 3 is dated December 2025. English names.

**AUSNUT 2023** ([food nutrients page](https://www.foodstandards.gov.au/science-data/food-nutrient-databases/ausnut/food-nutrients), [food measures page](https://www.foodstandards.gov.au/science-data/food-nutrient-databases/ausnut/food-measures)):

1. **Coverage.** 3,741 foods built for the national nutrition survey, with many mixed dishes. The [nutrient profiles workbook](https://www.foodstandards.gov.au/sites/default/files/2025-09/AUSNUT%202023%20-%20Food%20nutrient%20profiles.xlsx?v=20250903) has 74 names containing "curry", 16 sushi entries, savoury dumplings, laksa, kebabs and tacos.
2. **Nutrients.** Same structure as AFCD: kJ only, with and without fibre; available carbohydrate.
3. **Portions.** The [food measures workbook](https://www.foodstandards.gov.au/sites/default/files/2025-08/AUSNUT%202023%20-%20Food%20measures.xlsx?v=20250903) has columns `Public food key`, `Food name`, `Measure ID`, `Quantity`, `Descriptor 2`, `Descriptor 3`, `Gram amount`, `Volume`. The [About the food measures PDF](https://www.foodstandards.gov.au/sites/default/files/2025-08/AUSNUT%202023%20-%20About%20the%20food%20measures.pdf?v=20250829) gives 9,816 measures for 3,741 foods. These map well to `DocumentedServingUnit` (quantity, name, grams). One caution: "density" rows hold grams per mL, not a serving, so they are not serving units.
4. **Identity.** Public Food Key, shared with AFCD.
5. **Access.** Excel download, no authentication. English names.

**Licence for both.** The [FSANZ copyright page](https://www.foodstandards.gov.au/copyright) says website material is "provided under a Creative Commons Attribution 4.0 Australia (CC BY 4.0) licence", including commercial use, with credit to "Food Standards Australia New Zealand". It excludes third-party material and anything "expressly noted otherwise". The page does not name AFCD or AUSNUT, and some AFCD values are borrowed from other tables (one sampling note cites IFCT 2017), so dataset-specific coverage is **unverified**. Confirm with FSANZ before shipping.

## Canada: Canadian Nutrient File (CNF 2015)

Health Canada's [download page](https://www.canada.ca/en/health-canada/services/food-nutrition/healthy-eating/nutrient-data/canadian-nutrient-file-2015-download-files.html) offers CSV, Excel and Access archives. The [user guide](https://www.canada.ca/en/health-canada/services/food-nutrition/healthy-eating/nutrient-data/canadian-nutrient-file-compilation-canadian-food-composition-data-users-guide.html) documents them.

1. **Coverage.** 5,690 foods (user guide, and 5,690 rows in `FOOD NAME.csv`). Groups include "Mixed Dishes" and "Fast Foods", mostly North American dishes (for example "Chop suey, with meat, canned"). Much of the data derives from USDA: `FOOD SOURCE.csv` has several "FOOD BASED ON DATA FROM USDA" codes, and the guide puts "no change from USDA" at 57.25% of nutrient records.
2. **Nutrients.** `NUTRIENT NAME.csv` defines 203 protein, 204 fat, 205 "CARBOHYDRATE, TOTAL (BY DIFFERENCE)", 208 energy in kcal and 268 energy in kJ. The guide says values are "per 100 g of food (edible portion)" and energy uses the Atwater system. Its carbohydrate matches FDC's definition.
3. **Portions.** `CONVERSION FACTOR.csv` links `FoodID` and `MeasureID` to `ConversionFactorValue`, and `MEASURE NAME.csv` names the measure (for example "1 fish (500 g)", "250ml"). The guide gives nutrient per measure as V×W/100, so the gram weight is factor × 100. The [serving-size API](https://food-nutrition.canada.ca/api/canadian-nutrient-file/servingsize/?lang=en&type=json&id=2) returns entries such as "no serving specified" with factor 0, which must be dropped.
4. **Identity.** Integer `FoodID` (also `FoodCode`).
5. **Access.** Bulk files, plus a JSON or XML API that answered without a key, for example the [food endpoint](https://food-nutrition.canada.ca/api/canadian-nutrient-file/food/?lang=en&type=json&id=2). API rate limits are **unverified**. No release since 2015 is listed; a newer edition is **unverified**. English and French names.
6. **Licence.** The [copyright guidelines](https://www.canada.ca/en/health-canada/services/food-nutrition/healthy-eating/nutrient-data/copyright-guidelines-canadian-nutrient-file.html) say the CNF "may be downloaded and used without further permission", if Health Canada is cited as "(Canadian Nutrient File, Health Canada, 2015)" and values are not modified (other serving sizes are allowed). The page is marked archived. Commercial use is not addressed explicitly. A listing under the Open Government Licence (Canada) appears in search results, but the open.canada.ca record refused access, so that is **unverified**.

## FAO/INFOODS regional tables

The [INFOODS databases page](https://www.fao.org/infoods/infoods/tables-and-databases/faoinfoods-databases) lists one regional table, West Africa. Others are below under "Other tables considered".

**West African Food Composition Table 2019 (WAFCT 2019)**, with a [data workbook](https://www.fao.org/fileadmin/user_upload/faoweb/2020/WAFCT_2019.xlsx) and a [user guide](https://www.fao.org/3/ca7779b/CA7779B.PDF):

1. **Coverage.** 1,028 food entries, 94 of them mixed dishes (guide). The workbook has a "09 Mixed dishes" sheet. The mixed-dish names I checked are labelled Burkina Faso: leaf sauces, okra sauces, stews and jollof variants. Staples from elsewhere in the region (kenkey, fufu, gari) appear as single foods. Common Nigerian or Ghanaian dishes such as egusi soup did not appear in my search.
2. **Nutrients.** Per 100 g edible portion (sheet names say "per 100g EP"). Columns `ENERC` in kJ and kcal, `PROTCNT`, `FAT` or `[FATCE]`, and `CHOAVLDF` (available carbohydrate, by difference). The guide gives the energy formula including fibre at 8 kJ/g. Square brackets mark lower-quality or alternative-method values, which an importer must handle.
3. **Portions.** No household measures. Edible-portion coefficients and yield factors exist.
4. **Identity.** Codes such as `01_015` (group and number). The guide says codes changed for foods that moved food group since 2012.
5. **Access.** Excel and PDF download, no authentication. English and French names.
6. **Licence.** CC BY-NC-SA 3.0 IGO (guide copyright page). Key line: "copied, redistributed and adapted for non-commercial purposes". The guide routes commercial use through an FAO licence request (www.fao.org/contact-us/licence-request).

## Open Food Facts

A crowdsourced database of packaged products. See the [data page](https://world.openfoodfacts.org/data), [API introduction](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/) and [terms of use](https://world.openfoodfacts.org/terms-of-use).

1. **Coverage.** Packaged products worldwide, including snacks, drinks and some ready meals. No home-cooked or restaurant dishes. The product count is not stated on the pages I opened (**unverified**).
2. **Nutrients.** A [sample product](https://world.openfoodfacts.org/api/v2/product/3017620422003.json) returns `nutriments.energy-kcal_100g`, `energy-kj_100g`, `proteins_100g`, `carbohydrates_100g` and `fat_100g`. The [nutrition schema](https://github.com/openfoodfacts/openfoodfacts-server/blob/main/docs/api/ref/schemas/product_nutrition.yaml) defines `_100g` as per "100g (or 100ml for liquids)", so liquids are per 100 mL and the adapter must leave them out, as the FDC adapter does. Carbohydrate is the label value, so its definition follows the product's market: EU labels count carbohydrate "metabolised by humans" ([Regulation 1169/2011, Annex I](https://www.legislation.gov.uk/eur/2011/1169/annex/I)) and exclude fibre, while US labels compute total carbohydrate by subtraction and include fibre ([21 CFR 101.9(c)(6)](https://www.law.cornell.edu/cfr/text/21/101.9)). The record does not say which applies. Values are entered by contributors; the terms say Open Food Facts "does not guarantee its accuracy".
3. **Portions.** `serving_size` is free text, and `serving_quantity` with `serving_quantity_unit` (g or ml) is its normalized form ([product schema](https://github.com/openfoodfacts/openfoodfacts-server/blob/main/docs/api/ref/schemas/product_misc.yaml)). Only gram servings would qualify.
4. **Identity.** The barcode (`code`). Products can be edited or merged, so the stored values may later differ from the live record.
5. **Access.** Reads need no key but require a custom User-Agent. Limits are 15 product reads and 10 searches per minute per IP, and the docs say not to use search for search-as-you-type. For more than a few hundred products the docs point to dumps (JSONL, CSV, Parquet, MongoDB), "generated nightly". Names are in many languages; English is often missing.
6. **Licence.** Key line: "The Open Food Facts database is available under the Open Database License (ODbL)." Contents are under the DbCL, images under CC BY-SA. The terms allow commercial use, require attribution to Open Food Facts with a link, and require derivative databases to be shared alike.

## Additional candidates found

**Korea: MFDS food nutrient database (식품의약품안전처_식품영양성분DB정보).** A REST API in JSON or XML on [data.go.kr](https://www.data.go.kr/data/15127578/openapi.do), with [metadata](https://www.data.go.kr/biz/dcat/metadata/15127578.do). The ministry builds four files: integrated, raw, processed and dishes (음식). The listing describes food code, name, category, energy, carbohydrate, protein, fat, reference amount, single-serving reference and food weight. It needs a service key (so it would sit on the backend) and allows 10,000 calls on a development account. Licence key line: "이용허락범위 제한 없음" ("no restriction on the scope of use"). Exact field names, the per-100 g basis, English names, the dish count and the carbohydrate definition are all **unverified**, because the field specification is visible only after applying for a key.

**Brazil: TBCA (Tabela Brasileira de Composição de Alimentos), version 7.3.** The [TBCA site](https://www.tbca.net.br/) says version 7.2 has over 5,700 foods, over 4,000 of them preparations, with values per household measure. It reports kJ and kcal, total and available carbohydrate by difference. There is no download or API. Key line: "Não é permitida a comercialização." ("Sale is not permitted."). Reproduction and alteration are also prohibited, so the app could not package or serve it without an agreement.

**Mexico: Tabla de composición de alimentos extendida 2019 (INCMNSZ, via CONABIO).** The [technical notes](https://siagro.conabio.gob.mx/nutricion/download/Detalles_tecnicos.pdf) describe 3,928 records in 17 groups, mostly raw foods per 100 g edible portion. Carbohydrate is by difference using crude fibre. Records have an original `clave` and a `conabio_id`. The [data dictionary](https://siagro.conabio.gob.mx/nutricion/download/Diccionario_datos.pdf) lists an English `food_description`. The licence, the energy unit and a current download link are **unverified**: the old site now redirects to an application page that showed no terms.

**Southeast Asia: ASEAN and Thai tables (INMU, Mahidol University).** The [electronic ASEAN database](https://inmu.mahidol.ac.th/aseanfoods/composition_data.html) is a 2014 PDF compiled from six national tables, marked "All rights reserved". The [Thai FCD](https://inmu.mahidol.ac.th/thaifcd/content/1) (version 3, August 2025) is online for analysis only; key line: "Non-commercial users are authorised to access and use the data free of charge". Commercial use needs permission.

## Other tables considered

- **Kenya Food Composition Tables 2018** (FAO and Government of Kenya). The [FAO listing](https://www.fao.org/food-composition/tables-and-databases/detail/kenya-food-composition-tables/en) offers an Excel file and says "Free access". The licence, food count and mixed-dish coverage are **unverified**.
- **China Food Composition Tables** (China CDC). Not researched from a primary source. Availability as open data and the licence are **unverified**.
- **Middle Eastern tables.** I found no open national table to verify. CoFID and AUSNUT carry some dishes (falafel, hummus, kebabs).

## Normalization pitfalls

- **kJ to kcal.** IFCT, AFCD and AUSNUT give energy in kJ only. Divide by 4.184 (the [CNF guide](https://www.canada.ca/en/health-canada/services/food-nutrition/healthy-eating/nutrient-data/canadian-nutrient-file-compilation-canadian-food-composition-data-users-guide.html) factor; IFCT prints 4.18). Where a source publishes kcal, use its value instead of converting, because each source computes kcal with its own factors. AFCD and AUSNUT have two energy columns. "With dietary fibre" counts fibre energy, which is closer to how FDC's Atwater-based energy treats fibre within carbohydrate by difference. That choice is a judgment; record it in the adapter.
- **Carbohydrate definitions.** FDC and CNF use total carbohydrate by difference, including fibre. IFCT, WAFCT, AFCD and AUSNUT use available carbohydrate, excluding fibre. CoFID uses available carbohydrate as monosaccharide equivalents, which reads higher than the mass of starch it came from. MEXT offers both kinds (`CHOCDF-` and the available columns). Open Food Facts follows the label's market. A dish matched from an available-carbohydrate source will read lower than its FDC twin by roughly its fibre content. Options: keep the source's own value and accept the skew, or add the source's dietary fibre to available-by-difference values to approximate total by difference. Monosaccharide-equivalent values cannot be converted that simply. Whichever is chosen, the adapter should document it.
- **Edible portion.** Most tables are per 100 g edible portion (IFCT, CNF, WAFCT, CoFID, the Mexican table). Foods "weighed with" waste in CoFID and refuse percentages in MEXT and WAFCT describe as-purchased weight. The app's grams are what the person ate, so use edible-portion values and never apply refuse factors to them.
- **Per 100 mL records.** CoFID alcoholic drinks, the AFCD "Liquids only per 100 mL" sheet, and Open Food Facts liquids are per 100 mL. Use the per-100 g values where the source has them, otherwise leave the record out, as the FDC adapter does.
- **Non-numeric values.** `Tr`, `N`, `(0)`, `-`, parenthesised estimates (MEXT), bracketed lower-quality values (WAFCT) and "value ± SD" cells (IFCT PDF). Decide per source whether trace is 0 and whether an estimate is acceptable. A missing protein, fat, carbohydrate or energy value should drop the record, as the FDC adapter does.
- **Duplicate foods across sources.** CNF is largely USDA data. AFCD borrows from FDC SR Legacy and names the FDC ID in its sampling notes. INDB fills gaps from CoFID and FDC. The same food can therefore appear from two sources with near-identical numbers. Search results should show the source name so the person can tell them apart (issue #13 requires this). An adapter could also skip a borrowed record when its origin is already served.
- **Cooked versus raw.** IFCT and the Mexican table are mostly raw. Matching a cooked dish to raw ingredient values, or cooked rice to raw rice, causes large errors because of water gain or loss. MEXT, CoFID, AUSNUT and WAFCT name the cooking state ("boiled", "homemade", "takeaway"); keep that text in the displayed name.
- **Serving units.** CNF gives grams as factor × 100 and includes zero-factor "no serving specified" rows. AUSNUT density rows are grams per mL, not servings. INDB serving units such as "tea cup" have no documented grams in the file I read. Open Food Facts servings can be in mL. Only units with documented grams should become `DocumentedServingUnit` gram weights. Otherwise leave `gramWeight` nil.
- **Record identity across releases.** CoFID issues a new food code when a food's data change. WAFCT recoded foods that changed group. MEXT keeps food numbers across editions but values change between editions. Store the edition with the record ID, for example in the source name ("CoFID 2021"), so a saved meal entry stays traceable.
- **Names.** MEXT 2020 and 2023 names are Japanese only. The UI is English, so an English name must come from the 2015 English edition or a documented translation, and the original name should stay with the record.

## Shortlist by likely gap

This maps gaps the pilot might record to the sources that would cover them. It is not a recommendation.

| Likely gap | Sources that cover it | Trade-offs |
| --- | --- | --- |
| South Asian curries, dals, biryani, rice plates | INDB; CoFID; AUSNUT 2023 | INDB has the most Indian recipes, with kcal and English names, but has no data licence and derives from IFCT, so it needs permission first. CoFID is openly licensed with many homemade South Asian dishes as cooked in the UK, but its carbohydrate is in monosaccharide equivalents and it has no portions. AUSNUT has curry entries with gram measures under CC BY 4.0 (to confirm), but kJ only and fewer Indian dishes. IFCT 2017 covers raw ingredients only and needs NIN permission. |
| Japanese dishes | MEXT 2023; AUSNUT 2023 (sushi) | MEXT is authoritative, CC BY-compatible and free for commercial use, but names are Japanese only, it has no portions, its values need text parsing, and few whole dishes exist beyond curries, donburi toppings and fried foods. AUSNUT has sushi with gram measures. |
| West African stews and sauces | WAFCT 2019 | The only open regional table with mixed dishes. The licence is non-commercial (an FAO licence request is needed for commercial use), the dishes are mostly from Burkina Faso, and there are no portions. |
| East African dishes | Kenya FCT 2018 | Details and licence unverified. |
| Southeast Asian dishes | AUSNUT 2023 (laksa, dumplings); Thai FCD | Thai FCD is non-commercial without permission, and the ASEAN database is all rights reserved and dated 2014. |
| Korean dishes | MFDS food nutrient API | No restriction on use and a dish file exist, but it needs a key on the backend, field names are unverified, and names are likely Korean only. |
| Chinese takeaway dishes | CoFID; AUSNUT 2023; CNF | These are Western takeaway versions. No open Chinese national table was verified. |
| Mexican and Latin American dishes | FDC Survey foods first; TBCA; Mexican INCMNSZ table | TBCA has over 4,000 preparations with household measures, but forbids reproduction and sale. The Mexican table is mostly raw and its licence is unverified. FDC's US survey foods may already cover common Mexican-American dishes (check before adding a source). |
| Middle Eastern dishes | CoFID; AUSNUT 2023 | Only a few dishes (falafel, hummus, kebabs). No open national table verified. |
| Packaged snacks and drinks | Open Food Facts | Barcode IDs and serving grams, open for commercial use, but share-alike, crowdsourced accuracy, label-dependent carbohydrate, per-100 mL liquids, and rate limits that rule out live search-as-you-type. The nightly dump can be packaged or loaded by the backend. |
| General North American foods | CNF | Mostly duplicates FDC, so it adds little for a cuisine gap. |
