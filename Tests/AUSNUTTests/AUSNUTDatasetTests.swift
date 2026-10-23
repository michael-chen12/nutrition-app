import AnalysisContract
import AUSNUT
import XCTest

/// FSANZ AUSNUT 2023 foods, normalized to the shared per-100 g documented food representation. Most fixtures are
/// hand-built in the shape of the CSV exports of the two AUSNUT 2023 workbooks (title row, then the header row,
/// then one row per food or measure); one test reads the packaged data itself.
final class AUSNUTDatasetTests: XCTestCase {
    func test_aFoodBecomesADocumentedFoodPer100gWithItsPublicFoodKeyAndKilocaloriesFromEnergyWithFibre() throws {
        let dataset = try AUSNUTDataset(nutrientProfilesCSV: Self.nutrientProfiles, measuresCSV: Self.measures)

        let food = try XCTUnwrap(dataset.foods.first { $0.recordID == "F008991" })

        XCTAssertEqual(food.name, "Sushi, beef")
        XCTAssertEqual(food.sourceName, "FSANZ AUSNUT 2023")
        // 612 kJ / 4.184 kJ per kcal. Carbohydrate is AUSNUT's published available carbohydrate (with sugar
        // alcohols), not FDC's total by difference.
        XCTAssertEqual(food.nutrientsPer100g.calories, 146.2715, accuracy: 0.0001)
        XCTAssertEqual(food.nutrientsPer100g.protein, 7.3)
        XCTAssertEqual(food.nutrientsPer100g.fat, 1.9)
        XCTAssertEqual(food.nutrientsPer100g.carbohydrates, 23.7)
    }

    func test_documentedGramMeasuresBecomeServingUnitsAndDensityRowsAreLeftOut() throws {
        let dataset = try AUSNUTDataset(nutrientProfilesCSV: Self.nutrientProfiles, measuresCSV: Self.measures)
        let units = Dictionary(uniqueKeysWithValues: dataset.foods.map { ($0.recordID, $0.servingUnits) })

        XCTAssertEqual(units["F008991"], [
            DocumentedServingUnit(name: "piece", quantityBasis: 1, gramWeight: 33),
            DocumentedServingUnit(name: "roll", quantityBasis: 1, gramWeight: 104),
        ])
        // A measure with a volume keeps it in its name, so same-named measures of different sizes stay apart.
        XCTAssertEqual(units["F007661"], [
            DocumentedServingUnit(name: "tablespoon, 20 mL", quantityBasis: 1, gramWeight: 15.2),
            DocumentedServingUnit(name: "cup, 250 mL", quantityBasis: 1, gramWeight: 190),
        ])
        XCTAssertEqual(units["F000994"], [
            DocumentedServingUnit(name: "can, 375 mL", quantityBasis: 1, gramWeight: 376.875),
            DocumentedServingUnit(name: "bottle, long neck, 750 mL", quantityBasis: 1, gramWeight: 753.75),
            DocumentedServingUnit(name: "500 mL", quantityBasis: 1, gramWeight: 502.5),
        ])
        XCTAssertEqual(units["F003387"], [], "Curry has only a density row: grams per mL, not a serving")
    }

    func test_aFoodMissingANutrientIsLeftOutAndASheetMissingAColumnIsRefused() throws {
        let profiles = Self.nutrientProfiles + """

        13801002,F008992,Recipe,"Sushi, california roll",550,540,5.9,,20,20,1
        """

        let dataset = try AUSNUTDataset(nutrientProfilesCSV: profiles, measuresCSV: Self.measures)

        XCTAssertFalse(dataset.foods.contains { $0.recordID == "F008992" }, "No fat value: cannot back an estimate")
        XCTAssertEqual(dataset.foods.count, 4)
        let withoutFat = Self.nutrientProfiles.replacingOccurrences(of: "Total fat (g)", with: "Fat (g)")
        XCTAssertThrowsError(try AUSNUTDataset(nutrientProfilesCSV: withoutFat, measuresCSV: Self.measures)) {
            XCTAssertEqual($0 as? AUSNUTError, .missingColumn("Total fat (g)"))
        }
    }

    func test_searchFindsFoodsWhoseNameHasEveryQueryWordClosestNamesFirst() throws {
        let dataset = try Self.dataset(named: [
            ("F007649", "Rice, cooked, for making sushi"),
            ("F009009", "Sushi, salmon"),
            ("F008991", "Sushi, beef"),
            ("F010532", "Dumpling, savoury, meat & vegetable, purchased frozen, cooked"),
            ("F003651", "Dumpling, savoury, meat, fried"),
            ("F003657", "Dumpling, sweet, soaked in syrup"),
            ("F003387", "Curry, homemade, fish"),
        ])

        XCTAssertEqual(dataset.search("sushi", limit: 10).map(\.name), [
            "Sushi, salmon", "Sushi, beef", "Rice, cooked, for making sushi",
        ])
        // Case, plurals and word prefixes ("veg") match; every word must.
        XCTAssertEqual(dataset.search("Savoury Dumplings veg", limit: 10).map(\.recordID), ["F010532"])
        XCTAssertEqual(dataset.search("dumpling meat", limit: 10).map(\.recordID), ["F003651", "F010532"])
        XCTAssertEqual(dataset.search("fish curries", limit: 10).map(\.recordID), ["F003387"])
        XCTAssertEqual(dataset.search("dumpling", limit: 2).map(\.recordID), ["F003651", "F003657"])
        XCTAssertEqual(dataset.search("sushi pizza", limit: 10), [])
        XCTAssertEqual(dataset.search(" , ", limit: 10), [])
    }

    func test_thePackagedAUSNUT2023DataLoadsEveryFoodWithItsMeasures() throws {
        let dataset = try AUSNUTDataset.packaged()

        // The workbook lists 3,741 foods, all with the four values an estimate needs.
        XCTAssertEqual(dataset.foods.count, 3741)
        let sushi = try XCTUnwrap(dataset.foods.first { $0.recordID == "F008991" })
        XCTAssertEqual(sushi.name, "Sushi, beef")
        XCTAssertEqual(sushi.nutrientsPer100g.protein, 7.3)
        XCTAssertEqual(sushi.servingUnits, [
            DocumentedServingUnit(name: "piece", quantityBasis: 1, gramWeight: 33),
            DocumentedServingUnit(name: "roll", quantityBasis: 1, gramWeight: 104),
        ])
        // The prawn laksa's name has 10 words besides "laksa", the beef, chicken or pork laksa's 11.
        XCTAssertEqual(dataset.search("laksa", limit: 10).map(\.recordID), ["F008589", "F008588"])
    }

    /// Foods with the given keys and names and the same illustrative nutrients, without measures.
    static func dataset(named foods: [(key: String, name: String)]) throws -> AUSNUTDataset {
        let rows = foods.map { #"1,\#($0.key),Recipe,"\#($0.name)",600,590,7,2,23,23,1"# }
        return try AUSNUTDataset(
            nutrientProfilesCSV: (nutrientProfiles.split(separator: "\n").prefix(3).map(String.init) + rows)
                .joined(separator: "\n"),
            measuresCSV: measures
        )
    }

    // MARK: Fixtures in the AUSNUT 2023 export shapes

    /// "Food nutrient profiles" sheet: a subset of its columns, in its order, including the alternatives the
    /// adapter must not read (energy without fibre, carbohydrate without sugar alcohols).
    static let nutrientProfiles = """
    AUSNUT 2023 - Food nutrient profiles (per 100 g),,,,,,,,,,
    ,,,,,,,,,,
    Survey ID,Public food key,Derivation,Food name,Energy with dietary fibre (kJ),Energy without dietary fibre (kJ),Protein (g),Total fat (g),"Available carbohydrate, with sugar alcohols (g)","Available carbohydrate, without sugar alcohols (g)",Dietary fibre (g)
    13801001,F008991,Recipe,"Sushi, beef",612,603,7.3,1.9,23.7,23.5,1.2
    12102003,F007661,Analysed,"Rice, white, cooked",659,646,3.1,0.2,34.700000000000003,34.700000000000003,0.8
    29101002,F000994,Analysed,"Beer, full strength (alcohol 4-4.9% v/v)",155,155,0.3,0,2.4,2.4,0
    15601004,F003387,Recipe,"Curry, homemade, fish",476,458,12.6,4.2,5.2,5.2,2.2000000000000002
    """

    /// "AUSNUT 2023" sheet of the food measures workbook. Its descriptor headers end in a line break.
    static let measures = """
    AUSNUT 2023 - Food measures
    Survey ID,Public food key,Food name,Measure ID,Quantity,"Descriptor 1
    ",Descriptor 2,Descriptor 3,"Descriptor 4
    ",Gram amount,Volume,
    13801001,F008991,"Sushi, beef",45001,1,density,,,,0.95,0,
    13801001,F008991,"Sushi, beef",45002,1,piece,,,,33,0,
    12102003,F007661,"Rice, white, cooked",41289,1,density,cooked,,,0.76,0,
    12102003,F007661,"Rice, white, cooked",41290,1,tablespoon,,,,15.2,20,
    12102003,F007661,"Rice, white, cooked",41291,1,cup,,,,190,250,
    29101002,F000994,"Beer, full strength (alcohol 4-4.9% v/v)",40306,1,density,,,,1.0049999999999999,1,
    29101002,F000994,"Beer, full strength (alcohol 4-4.9% v/v)",40308,1,can,,,,376.875,375,
    29101002,F000994,"Beer, full strength (alcohol 4-4.9% v/v)",40312,1,bottle,long neck,,,753.75,750,
    29101002,F000994,"Beer, full strength (alcohol 4-4.9% v/v)",40313,1,millilitres,500,,,502.5,500,
    15601004,F003387,"Curry, homemade, fish",44061,1,density,,,,1.1000000000000001,0,
    13801001,F008991,"Sushi, beef",45003,1,roll,,,,104,0,
    """
}
