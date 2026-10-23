import Foundation

/// Local, on-device meal history: meal entries plus the image bytes of their meal photos.
public protocol MealHistoryStore: AnyObject {
    /// Inserts or replaces a meal entry. `photoData` must contain the image bytes for every photo of
    /// the entry that the store does not already hold; already-stored photos may be omitted.
    func save(_ entry: MealEntry, photoData: [MealPhoto.ID: Data]) throws

    /// All saved meal entries, in no particular order.
    func mealEntries() throws -> [MealEntry]

    func mealEntry(id: MealEntry.ID) throws -> MealEntry?

    /// The stored image bytes of a saved meal photo.
    func photoData(for photo: MealPhoto) throws -> Data
}

public enum MealHistoryStoreError: Error, Equatable {
    /// A meal entry references a photo whose image bytes were neither supplied nor already stored.
    case missingPhotoData(MealPhoto.ID)
}
