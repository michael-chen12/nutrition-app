import Foundation

/// A food that can be reviewed into a meal entry, normalized to nutrients per 100 g,
/// with the source its nutrition values come from.
public struct Food: Codable, Hashable, Sendable {
    public var name: String
    public var nutrientsPer100g: NutrientsPer100g
    public var source: FoodSource

    public init(name: String, nutrientsPer100g: NutrientsPer100g, source: FoodSource) {
        self.name = name
        self.nutrientsPer100g = nutrientsPer100g
        self.source = source
    }

    public init(_ customFood: CustomFood) {
        self.init(name: customFood.name, nutrientsPer100g: customFood.nutrientsPer100g, source: .custom)
    }
}

/// Where a food's nutrition values come from.
public enum FoodSource: Codable, Hashable, Sendable {
    /// Values the person entered for a custom food.
    case custom
    /// A record in a documented nutrition data source.
    case documented(SourceReference)
}

/// Traceable identity of a documented nutrition record (e.g. a USDA FoodData Central food).
public struct SourceReference: Codable, Hashable, Sendable {
    /// Human-readable name of the data source, shown to the person.
    public var sourceName: String
    /// The record's identifier within that source.
    public var recordID: String

    public init(sourceName: String, recordID: String) {
        self.sourceName = sourceName
        self.recordID = recordID
    }
}

/// A food the person adds with nutrition values they provide, when no suitable reference food exists.
public struct CustomFood: Hashable, Sendable {
    public var name: String
    public var nutrientsPer100g: NutrientsPer100g

    public init(name: String, nutrientsPer100g: NutrientsPer100g) {
        self.name = name
        self.nutrientsPer100g = nutrientsPer100g
    }
}
