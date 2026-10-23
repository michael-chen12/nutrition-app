import Foundation
import NutritionCore
import XCTest

/// Behaviour every `MealHistoryStore` must share, checked against each implementation.
final class MealHistoryStoreContractTests: XCTestCase {
    private var directory: TemporaryDirectory!

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
    }

    override func tearDown() {
        directory.remove()
    }

    private func eachStore(_ check: (MealHistoryStore) throws -> Void) throws {
        try check(InMemoryMealHistoryStore())
        try check(FileMealHistoryStore(directory: directory.url))
    }

    func test_savedMealEntryAndItsPhotoCanBeReadBack() throws {
        try eachStore { store in
            let photo = MealPhoto(fileExtension: "heic")
            let entry = MealEntry(
                date: Date(timeIntervalSince1970: 1_792_000_000),
                photos: [photo],
                reviewedFoods: [ReviewedFood(
                    food: Food(
                        name: "Oat milk",
                        nutrientsPer100g: NutrientsPer100g(calories: 46, protein: 1, carbohydrates: 6.7, fat: 1.5),
                        source: .documented(SourceReference(sourceName: "USDA FoodData Central", recordID: "2257046"))
                    ),
                    portion: Portion(grams: 240),
                    uncertaintyNotes: [UncertaintyNote(detail: "Sweetened or unsweetened?")]
                )]
            )

            try store.save(entry, photoData: [photo.id: Data([1, 2, 3])])

            XCTAssertEqual(try store.mealEntries(), [entry])
            XCTAssertEqual(try store.mealEntry(id: entry.id), entry)
            XCTAssertEqual(try store.photoData(for: photo), Data([1, 2, 3]))
        }
    }

    func test_savingAnExistingMealEntryReplacesItAndKeepsStoredPhotos() throws {
        try eachStore { store in
            let photo = MealPhoto(fileExtension: "jpg")
            var entry = MealEntry(date: Date(timeIntervalSince1970: 0), photos: [photo])
            try store.save(entry, photoData: [photo.id: Data([9])])

            entry.date = Date(timeIntervalSince1970: 60)
            try store.save(entry, photoData: [:])

            XCTAssertEqual(try store.mealEntries(), [entry])
            XCTAssertEqual(try store.photoData(for: photo), Data([9]))
        }
    }

    func test_savingAMealEntryWithoutItsPhotoDataIsRejected() throws {
        try eachStore { store in
            let photo = MealPhoto(fileExtension: "jpg")
            let entry = MealEntry(date: Date(timeIntervalSince1970: 0), photos: [photo])

            XCTAssertThrowsError(try store.save(entry, photoData: [:])) { error in
                XCTAssertEqual(error as? MealHistoryStoreError, .missingPhotoData(photo.id))
            }
            XCTAssertEqual(try store.mealEntries(), [])
        }
    }
}
