import AnalysisContract
import Foundation

/// FSANZ's AUSNUT 2023 (Food Standards Australia New Zealand), packaged as CSV exports of its two workbooks:
/// "Food nutrient profiles" and "Food measures" (see `Resources/README.md`).
///
/// This adapter is how AUSNUT foods enter the shared food representation, beside the FoodData Central adapter:
/// each food becomes a `DocumentedFood` named with this source and its Public Food Key, the identifier FSANZ
/// keeps for a food across its publications.
///
/// Normalization choices (ADR 0005):
/// - Calories are "Energy with dietary fibre (kJ)" divided by 4.184 kJ per kcal. AUSNUT publishes energy in kJ
///   only; the with-fibre figure is closer to FDC's Atwater energy, which counts fibre within carbohydrate.
/// - Carbohydrates are "Available carbohydrate, with sugar alcohols (g)" as published. Available carbohydrate
///   excludes dietary fibre, so it reads lower than FDC's total by difference; it is not adjusted, so the value
///   can be traced to the record.
/// - Values are per 100 g of edible portion for every food, liquids included.
/// - Measures with a gram amount become serving units of one unit each (AUSNUT documents every measure for one
///   unit), named by their descriptors plus their volume when they have one. "density" rows give grams per mL,
///   not a serving, so they are left out.
public struct AUSNUTDataset: Sendable {
    /// Name shown to the person for every food from this source; includes the edition, as record values change
    /// between AUSNUT releases.
    public static let sourceName = "FSANZ AUSNUT 2023"

    /// Every food that can back a nutrition estimate, in the workbook's order.
    public let foods: [DocumentedFood]

    /// Reads the two sheets as CSV, located by their header rows. Throws when a sheet lacks a column the
    /// adapter needs; a food missing one of its values is left out.
    public init(nutrientProfilesCSV: String, measuresCSV: String) throws {
        let profiles = try Sheet(csv: nutrientProfilesCSV, headerStartingWith: Column.surveyID)
        let key = try profiles.column(Column.publicFoodKey)
        let name = try profiles.column(Column.foodName)
        let energy = try profiles.column(Column.energyWithDietaryFibre)
        let protein = try profiles.column(Column.protein)
        let fat = try profiles.column(Column.totalFat)
        let carbohydrates = try profiles.column(Column.availableCarbohydrateWithSugarAlcohols)
        let measures = try Sheet(csv: measuresCSV, headerStartingWith: Column.surveyID)
        let servingUnits = try Self.servingUnitsByFoodKey(in: measures)

        foods = profiles.rows.compactMap { row in
            guard let key = row.text(key), let name = row.text(name),
                  let kilojoules = row.number(energy), let protein = row.number(protein),
                  let fat = row.number(fat), let carbohydrates = row.number(carbohydrates)
            else { return nil }
            return DocumentedFood(
                name: name,
                sourceName: Self.sourceName,
                recordID: key,
                nutrientsPer100g: DocumentedNutrients(
                    calories: kilojoules / Self.kilojoulesPerKilocalorie,
                    protein: protein,
                    carbohydrates: carbohydrates,
                    fat: fat
                ),
                servingUnits: servingUnits[key] ?? []
            )
        }
        nameWords = foods.map { Self.words(in: $0.name) }
    }

    /// The AUSNUT 2023 data packaged with this module. Reading it takes a moment; load it once and keep it.
    public static func packaged() throws -> AUSNUTDataset {
        func sheet(_ name: String) throws -> String {
            guard let url = Bundle.module.url(forResource: name, withExtension: "csv", subdirectory: "Resources")
            else { throw AUSNUTError.missingPackagedData(name) }
            return try String(contentsOf: url, encoding: .utf8)
        }
        return try AUSNUTDataset(
            nutrientProfilesCSV: sheet("AUSNUT 2023 - Food nutrient profiles"),
            measuresCSV: sheet("AUSNUT 2023 - Food measures")
        )
    }

    /// The foods whose name has every word of the query, at most `limit`, most relevant first.
    ///
    /// A query word matches a name word it begins, ignoring case and accents, and a plural matches its singular
    /// ("curries" finds "Curry"). Names with fewer words beyond the query come first, then the workbook's
    /// order, so "rice white cooked" puts "Rice, white, cooked" before "Rice, white, cooked with coconut milk".
    public func search(_ query: String, limit: Int) -> [DocumentedFood] {
        let queryWords = Self.words(in: query)
        guard !queryWords.isEmpty, limit > 0 else { return [] }

        let matches = nameWords.indices.compactMap { index -> (index: Int, extraWords: Int)? in
            let words = nameWords[index]
            guard queryWords.allSatisfy({ queryWord in words.contains { Self.word($0, matches: queryWord) } })
            else { return nil }
            let extraWords = words.filter { word in !queryWords.contains { Self.word(word, matches: $0) } }.count
            return (index, extraWords)
        }
        return matches
            .sorted { ($0.extraWords, $0.index) < ($1.extraWords, $1.index) }
            .prefix(limit)
            .map { foods[$0.index] }
    }

    /// Each food's name split into words, parallel to `foods`.
    private let nameWords: [[String]]

    private static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func word(_ nameWord: String, matches queryWord: String) -> Bool {
        singularForms(of: queryWord).contains { nameWord.hasPrefix($0) }
    }

    /// The word and, for an English plural, its possible singulars: "curries" → "curry", "potatoes" → "potato",
    /// "dumplings" → "dumpling".
    private static func singularForms(of word: String) -> [String] {
        guard word.count > 2, word.hasSuffix("s") else { return [word] }
        var forms = [word, String(word.dropLast())]
        if word.hasSuffix("es") { forms.append(String(word.dropLast(2))) }
        if word.hasSuffix("ies") { forms.append(word.dropLast(3) + "y") }
        return forms
    }

    static let kilojoulesPerKilocalorie = 4.184

    /// "Descriptor 1" values with a meaning of their own.
    private enum MeasureKind {
        /// Grams per mL of the food, not a serving.
        static let density = "density"
        /// A volume in mL, given in the Volume column.
        static let millilitres = "millilitres"
    }

    /// Each food's serving units, in the sheet's order.
    private static func servingUnitsByFoodKey(in measures: Sheet) throws -> [String: [DocumentedServingUnit]] {
        let key = try measures.column(Column.publicFoodKey)
        let descriptors = try Column.descriptors.map(measures.column)
        let grams = try measures.column(Column.gramAmount)
        let volume = try measures.column(Column.volume)

        var units: [String: [DocumentedServingUnit]] = [:]
        for row in measures.rows {
            let words = descriptors.compactMap(row.text)
            guard let key = row.text(key), let grams = row.number(grams), grams > 0,
                  let kind = words.first?.lowercased(), kind != MeasureKind.density
            else { continue }
            let millilitres = row.number(volume).flatMap { $0 > 0 ? Self.millilitresText($0) : nil }
            let name: String
            if kind == MeasureKind.millilitres, let millilitres {
                name = "\(millilitres) mL"
            } else {
                name = (words + [millilitres.map { "\($0) mL" }].compactMap { $0 }).joined(separator: ", ")
            }
            units[key, default: []].append(DocumentedServingUnit(name: name, quantityBasis: 1, gramWeight: grams))
        }
        return units
    }

    /// "250" for 250 mL, "37.5" for 37.5 mL.
    private static func millilitresText(_ number: Double) -> String {
        number == number.rounded() ? String(Int(number)) : String(number)
    }

    /// Header names as the workbooks print them.
    private enum Column {
        static let surveyID = "Survey ID"
        static let publicFoodKey = "Public food key"
        static let foodName = "Food name"
        static let energyWithDietaryFibre = "Energy with dietary fibre (kJ)"
        static let protein = "Protein (g)"
        static let totalFat = "Total fat (g)"
        static let availableCarbohydrateWithSugarAlcohols = "Available carbohydrate, with sugar alcohols (g)"
        static let descriptors = ["Descriptor 1", "Descriptor 2", "Descriptor 3", "Descriptor 4"]
        static let gramAmount = "Gram amount"
        static let volume = "Volume"
    }
}

public enum AUSNUTError: Error, Equatable {
    /// The sheet has no header row starting with this column.
    case missingHeaderRow(firstColumn: String)
    /// The sheet's header row lacks a column the adapter reads.
    case missingColumn(String)
    /// The module's bundle lacks this packaged sheet.
    case missingPackagedData(String)
}

/// One sheet of an AUSNUT CSV export: the rows below its header row, with columns found by header name.
/// Title rows above the header are skipped; header names are compared without surrounding whitespace, since
/// some AUSNUT headers end in a line break.
struct Sheet {
    var header: [String]
    var rows: [Row]

    init(csv: String, headerStartingWith firstColumn: String) throws {
        let records = CSV.records(in: csv)
        guard let headerIndex = records.firstIndex(where: { $0.first.map(Self.trimmed) == firstColumn }) else {
            throw AUSNUTError.missingHeaderRow(firstColumn: firstColumn)
        }
        header = records[headerIndex].map(Self.trimmed)
        rows = records[(headerIndex + 1)...].map(Row.init)
    }

    func column(_ name: String) throws -> Int {
        guard let index = header.firstIndex(of: name) else { throw AUSNUTError.missingColumn(name) }
        return index
    }

    struct Row {
        var fields: [String]

        /// The field's text, or nil when blank.
        func text(_ column: Int) -> String? {
            guard column < fields.count else { return nil }
            let text = Sheet.trimmed(fields[column])
            return text.isEmpty ? nil : text
        }

        /// The field as a finite, non-negative number, or nil when blank or not a number.
        func number(_ column: Int) -> Double? {
            guard let value = text(column).flatMap(Double.init), value.isFinite, value >= 0 else { return nil }
            return value
        }
    }

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// RFC 4180 CSV: comma-separated fields, double-quoted where they hold commas, quotes or line breaks.
enum CSV {
    static func records(in text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var characters = text.drop { $0 == "\u{FEFF}" }.makeIterator()
        var pending = characters.next()

        while let character = pending {
            pending = characters.next()
            if inQuotes {
                if character == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = characters.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"":
                inQuotes = true
            case ",":
                record.append(field)
                field = ""
            case "\n", "\r\n", "\r":
                record.append(field)
                records.append(record)
                record = []
                field = ""
            default:
                field.append(character)
            }
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records
    }
}
