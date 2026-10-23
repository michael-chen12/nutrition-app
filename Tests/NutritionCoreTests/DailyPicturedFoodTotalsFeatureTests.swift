import Foundation
import NutritionCore
import XCTest

/// Ticket #8: a person browses meal history by day and sees the daily pictured-food total of each day's
/// saved meal entries, which is not presented as food consumed by one person.
final class DailyPicturedFoodTotalsFeatureTests: XCTestCase {
    private var directory: TemporaryDirectory!
    private var gateway: FakeMealAnalysisGateway!
    private var newYork: Calendar!

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
        gateway = FakeMealAnalysisGateway()
        gateway.foodSearchResults["rice"] = [ChooseSourceBackedFoodFeatureTests.cookedWhiteRice]
        newYork = try Self.gregorianCalendar(timeZoneIdentifier: "America/New_York")
    }

    override func tearDown() {
        directory.remove()
    }

    func test_mealHistoryGroupsSavedMealEntriesByDayWithEachDaysPicturedFoodTotal() async throws {
        let breakfast = try await saveMealEntry(at: time(2026, 10, 20, 8, 0), rice: 150)
        // Late in the evening in New York, already the next day in UTC: still assigned to 20 October.
        let lateDinner = try await saveMealEntry(at: time(2026, 10, 20, 23, 30), plantain: 80)
        let lunch = try await saveMealEntry(at: time(2026, 10, 21, 12, 30), rice: 100, sauce: 120)

        let days = try launchApp().dailyMealHistory()

        XCTAssertEqual(days.map(\.day), [dayComponents(2026, 10, 21), dayComponents(2026, 10, 20)])
        XCTAssertEqual(days.map { $0.mealEntries.map(\.id) }, [[lunch], [lateDinner, breakfast]])
        // 21 October: rice 100 g (130 kcal, 2.69 g, 28.17 g, 0.28 g) + sauce 120 g (96 kcal, 1.8 g, 10.8 g, 5.04 g).
        assertTotal(days[0].picturedFoodTotal, "226 kcal", "4.5 g", "39 g", "5.3 g")
        // 20 October: rice 150 g (195 kcal, 4.035 g, 42.255 g, 0.42 g) + plantain 80 g (120 kcal, 1.04 g, 25.6 g, 2.4 g).
        assertTotal(days[1].picturedFoodTotal, "315 kcal", "5.1 g", "67.9 g", "2.8 g")
    }

    func test_editingASavedMealEntryUpdatesOnlyItsDaysTotal() async throws {
        let breakfast = try await saveMealEntry(at: time(2026, 10, 20, 8, 0), rice: 150)
        try await saveMealEntry(at: time(2026, 10, 20, 23, 30), plantain: 80)
        try await saveMealEntry(at: time(2026, 10, 21, 12, 30), rice: 100, sauce: 120)

        let editing = try launchApp(now: time(2026, 10, 22, 9, 0))
        try editing.editMealEntry(id: breakfast)
        let riceID = try XCTUnwrap(editing.draftReview?.foods.first?.id)
        try editing.changePortion(of: riceID, grams: 200)
        try editing.saveMealEntry()

        let days = try launchApp().dailyMealHistory()
        // The edited meal entry keeps its day; no new day appears for the day it was edited on.
        XCTAssertEqual(days.map(\.day), [dayComponents(2026, 10, 21), dayComponents(2026, 10, 20)])
        // 21 October is unrelated to the edit and unchanged.
        assertTotal(days[0].picturedFoodTotal, "226 kcal", "4.5 g", "39 g", "5.3 g")
        // 20 October: rice now 200 g (260 kcal, 5.38 g, 56.34 g, 0.56 g) + plantain 80 g (120 kcal, 1.04 g, 25.6 g, 2.4 g).
        assertTotal(days[1].picturedFoodTotal, "380 kcal", "6.4 g", "81.9 g", "3 g")
        XCTAssertEqual(days[1].mealEntries.map(\.nutritionEstimate.calories), ["120 kcal", "260 kcal"])
    }

    func test_aMealEntrysDayFollowsTheCalendarAndTimeZoneTheAppIsGiven() async throws {
        // 23:30 on 20 October in New York is 03:30 on 21 October in UTC.
        let lateDinner = try await saveMealEntry(at: time(2026, 10, 20, 23, 30), plantain: 80)

        let inNewYork = try launchApp().dailyMealHistory()
        let inUTC = try launchApp(calendar: try Self.gregorianCalendar(timeZoneIdentifier: "UTC")).dailyMealHistory()

        XCTAssertEqual(inNewYork.map(\.day), [dayComponents(2026, 10, 20)])
        XCTAssertEqual(inUTC.map(\.day), [dayComponents(2026, 10, 21)])
        XCTAssertEqual(inUTC.first?.mealEntries.map(\.id), [lateDinner])
    }

    func test_dailyTotalIsLabeledAsPicturedFoodAndNotAsWhatOnePersonAte() async throws {
        try await saveMealEntry(at: time(2026, 10, 20, 8, 0), rice: 150)

        let total = try XCTUnwrap(try launchApp().dailyMealHistory().first?.picturedFoodTotal)

        XCTAssertEqual(total.label, "Daily pictured-food total")
        XCTAssertEqual(
            total.note,
            "Approximate combined nutrition estimates for all pictured food in this day's meal entries, "
                + "including food that was shared or left uneaten. It is not a measure of food consumed by one person."
        )
    }

    func test_dayWithoutSavedMealEntriesIsNotListed() throws {
        XCTAssertEqual(try launchApp().dailyMealHistory(), [])
    }

    // MARK: Helpers

    private func assertTotal(
        _ total: PresentedDailyPicturedFoodTotal,
        _ calories: String,
        _ protein: String,
        _ carbohydrates: String,
        _ fat: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            [total.calories, total.protein, total.carbohydrates, total.fat],
            [calories, protein, carbohydrates, fat],
            file: file,
            line: line
        )
    }

    static func gregorianCalendar(timeZoneIdentifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: timeZoneIdentifier))
        return calendar
    }

    private func time(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        newYork.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func dayComponents(_ year: Int, _ month: Int, _ day: Int) -> DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    private func launchApp(now: Date = Date(timeIntervalSince1970: 0), calendar: Calendar? = nil) throws -> MealEntryWorkflow {
        MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: directory.url),
            gateway: gateway,
            now: { now },
            calendar: calendar ?? newYork
        )
    }

    @discardableResult
    private func saveMealEntry(
        at date: Date,
        rice riceGrams: Double? = nil,
        sauce sauceGrams: Double? = nil,
        plantain plantainGrams: Double? = nil
    ) async throws -> MealEntry.ID {
        let workflow = try launchApp(now: date)
        workflow.startNewMealEntry()
        if let riceGrams {
            let rice = try await workflow.searchFoods(matching: "rice")
            try workflow.addFood(try XCTUnwrap(rice.results.first), grams: riceGrams)
        }
        if let sauceGrams {
            try workflow.addCustomFood(EditSavedMealEntryFeatureTests.jollofSauce, grams: sauceGrams)
        }
        if let plantainGrams {
            try workflow.addCustomFood(EditSavedMealEntryFeatureTests.friedPlantain, grams: plantainGrams)
        }
        return try workflow.saveMealEntry()
    }
}
