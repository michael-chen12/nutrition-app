import Foundation

/// Meal history held in memory, for tests and previews. Nothing survives the instance.
public final class InMemoryMealHistoryStore: MealHistoryStore {
    private var entries: [MealEntry.ID: MealEntry] = [:]
    private var photos: [MealPhoto.ID: Data] = [:]

    public init() {}

    public func save(_ entry: MealEntry, photoData: [MealPhoto.ID: Data]) throws {
        for photo in entry.photos where photoData[photo.id] == nil && photos[photo.id] == nil {
            throw MealHistoryStoreError.missingPhotoData(photo.id)
        }
        photos.merge(photoData) { _, new in new }
        entries[entry.id] = entry
    }

    public func mealEntries() throws -> [MealEntry] {
        Array(entries.values)
    }

    public func mealEntry(id: MealEntry.ID) throws -> MealEntry? {
        entries[id]
    }

    public func photoData(for photo: MealPhoto) throws -> Data {
        guard let data = photos[photo.id] else { throw MealHistoryStoreError.missingPhotoData(photo.id) }
        return data
    }
}
