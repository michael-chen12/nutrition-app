import AUSNUT
import Foundation

/// Hand-built AUSNUT 2023 data in the shape of its CSV exports (see the root package's `AUSNUT` adapter), so
/// backend tests choose exactly which foods the packaged source holds. Values are illustrative.
enum AUSNUTFixtures {
    /// A dataset without foods: food search answers from FoodData Central alone.
    static let noFoods = dataset(rows: [])

    /// Two cooked white rice foods: they overlap the FDC rice fixtures.
    static let rice = dataset(rows: [
        #"12102003,F007661,Analysed,"Rice, white, cooked",659,3.1,0.2,34.7"#,
        #"12102005,F007662,Recipe,"Rice, white, cooked with coconut milk",768,3,6.8,27.3"#,
    ])

    /// `count` sushi foods, keyed F900001, F900002, ...
    static func sushi(count: Int) -> AUSNUTDataset {
        dataset(rows: (1...count).map { #"1,F9\#(String(format: "%05d", $0)),Recipe,"Sushi, kind \#($0)",612,7.3,1.9,23.7"# })
    }

    static func dataset(rows: [String]) -> AUSNUTDataset {
        try! AUSNUTDataset(
            nutrientProfilesCSV: ([
                "AUSNUT 2023 - Food nutrient profiles (per 100 g),,,,,,,",
                "Survey ID,Public food key,Derivation,Food name,Energy with dietary fibre (kJ),Protein (g),Total fat (g),\"Available carbohydrate, with sugar alcohols (g)\"",
            ] + rows).joined(separator: "\n"),
            measuresCSV: "Survey ID,Public food key,Food name,Measure ID,Quantity,Descriptor 1,Descriptor 2,Descriptor 3,Descriptor 4,Gram amount,Volume"
        )
    }
}
