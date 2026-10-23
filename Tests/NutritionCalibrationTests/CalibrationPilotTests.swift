import Foundation
import NutritionCalibration
import NutritionCore
import XCTest

/// Ticket #12: a pilot directory holds consented reference meals, their photos and the recorded evaluations.
/// Pass criteria are frozen after the calibration results and before any validation meal is scored.
final class CalibrationPilotTests: XCTestCase {
    private var directory: TemporaryDirectory!
    private var pilot: CalibrationPilot!

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
        pilot = CalibrationPilot(directory: directory.url)
    }

    override func tearDown() {
        directory.remove()
    }

    // MARK: Reference meals

    func test_referenceMealsAndTheirPhotosAreReadFromThePilotDirectory() throws {
        try write(ReferenceMeals.riceAndCurry)
        try write(photo: Data([0xFF, 0xD8, 0x31]), named: "pilot-001-a.jpg")

        let meals = try pilot.referenceMeals()

        XCTAssertEqual(meals, [ReferenceMeals.riceAndCurry])
        XCTAssertEqual(try pilot.photos(for: meals[0]), [TrialPhoto(data: Data([0xFF, 0xD8, 0x31]), fileExtension: "jpg")])
    }

    func test_aReferenceMealWithoutConsentToUploadItsPhotosIsRefused() throws {
        var meal = ReferenceMeals.riceAndCurry
        meal.consent.coversPhotoAnalysisUpload = false
        try write(meal)

        XCTAssertThrowsError(try pilot.referenceMeals()) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .invalidReferenceMeal("pilot-001", .photoUploadNotConsented))
        }
    }

    func test_aReferenceMealMustHaveWeighedOrRecipeFoodsAndAParticipantCode() throws {
        var noFoods = ReferenceMeals.riceAndCurry
        noFoods.referenceFoods = []
        var unweighed = ReferenceMeals.riceAndCurry
        unweighed.id = "pilot-002"
        unweighed.referenceFoods[0].grams = 0
        var anonymous = ReferenceMeals.riceAndCurry
        anonymous.id = "pilot-003"
        anonymous.consent.participantCode = " "

        for (meal, problem) in [
            (noFoods, ReferenceMealProblem.noReferenceFoods),
            (unweighed, .invalidReferenceFood("rice")),
            (anonymous, .noParticipantCode),
        ] {
            let pilot = CalibrationPilot(directory: directory.url.appendingPathComponent(meal.id))
            try write(meal, to: pilot)
            XCTAssertThrowsError(try pilot.referenceMeals()) { error in
                XCTAssertEqual(error as? CalibrationPilotError, .invalidReferenceMeal(meal.id, problem))
            }
        }
    }

    // MARK: Evaluations

    func test_recordedEvaluationsAreReadBackAndReportedForTheCalibrationSetOnly() throws {
        let meals = [
            meal("ramen", cuisine: "Japanese", dishType: "Soup", foods: [food("ramen", calories: 400, protein: 15, carbohydrates: 55, fat: 10)]),
            meal("held-out", split: .validation, cuisine: "Ethiopian", dishType: "Stew", foods: [food("wat", calories: 300, protein: 20, carbohydrates: 10, fat: 20)]),
        ]
        for meal in meals { try write(meal) }
        let ramen = evaluation("ramen", preReview: (300, 10, 50, 5), reviewed: (380, 14, 54, 9), correctionTime: 60)

        try pilot.record(ramen)

        XCTAssertEqual(try pilot.evaluations(), [ramen])
        let report = try pilot.calibrationReport()
        XCTAssertEqual(report.split, .calibration)
        XCTAssertEqual(report.overall.mealCount, 1)
        XCTAssertFalse(report.gaps.contains(.notEvaluated(mealIDs: ["held-out"])), "validation meals stay out of it")
    }

    func test_theCalibrationReportIsWrittenIntoThePilot() throws {
        try write(ReferenceMeals.riceAndCurry)
        try pilot.record(evaluation("pilot-001", preReview: (500, 30, 60, 20), reviewed: (600, 35, 65, 23), correctionTime: 60))

        let report = try pilot.writeCalibrationReport()

        let written = try String(contentsOf: directory.url.appendingPathComponent("calibration-report.md"), encoding: .utf8)
        XCTAssertEqual(written, report.markdown)
    }

    func test_validationMealsAreEvaluatedOnlyOnceTheCriteriaAreFrozen() throws {
        try writeCalibratedPilot()

        XCTAssertThrowsError(try evaluateValidationMeals()) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .passCriteriaNotFrozen)
        }
        try pilot.freezePassCriteria(criteria, on: frozenOn)
        XCTAssertNoThrow(try evaluateValidationMeals())
    }

    func test_mealsOpenForATrialAreUnevaluatedCalibrationMealsUntilTheFreezeThenUnevaluatedValidationMeals() throws {
        try writeCalibratedPilot()
        try write(meal("late", cuisine: "Thai", dishType: "Noodles", foods: [food("pad thai", calories: 600, protein: 20, carbohydrates: 80, fat: 20)]))
        XCTAssertEqual(try pilot.mealsOpenForTrial(), ["late"])

        try pilot.record(evaluation("late", preReview: (500, 1, 1, 1), reviewed: (600, 1, 1, 1), correctionTime: 60))
        try pilot.freezePassCriteria(criteria, on: frozenOn)
        XCTAssertEqual(try pilot.mealsOpenForTrial(), ["v-miso", "v-tacos"])

        try pilot.record(evaluation("v-miso", preReview: (380, 19, 38, 9), reviewed: (390, 20, 40, 10), correctionTime: 90))
        XCTAssertEqual(try pilot.mealsOpenForTrial(), ["v-tacos"])
    }

    func test_aMealIsEvaluatedOnce() throws {
        try write(ReferenceMeals.riceAndCurry)
        let first = evaluation("pilot-001", preReview: (500, 1, 1, 1), reviewed: (600, 1, 1, 1), correctionTime: 60)
        try pilot.record(first)

        XCTAssertThrowsError(try pilot.record(first)) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .alreadyEvaluated("pilot-001"))
        }
    }

    func test_anEvaluationOfAMealOutsideThePilotIsRefused() throws {
        try write(ReferenceMeals.riceAndCurry)

        XCTAssertThrowsError(try pilot.record(
            evaluation("unknown", preReview: (1, 1, 1, 1), reviewed: (1, 1, 1, 1), correctionTime: 1)
        )) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .unknownReferenceMeal("unknown"))
        }
    }

    // MARK: Pass criteria and validation

    private let frozenOn = Date(timeIntervalSince1970: 1_793_000_000)

    /// Written after reading the calibration report.
    private let criteria = [
        PassCriterion(
            stage: .reviewed, metric: .caloriesPercentError, scope: .allMeals, atMost: 15,
            rationale: "Calibration reviewed calorie error was 5 %; allow for harder meals."
        ),
        PassCriterion(
            stage: .reviewed, metric: .caloriesPercentError, scope: .eachCuisine, atMost: 20,
            rationale: "No cuisine may lag far behind."
        ),
        PassCriterion(
            stage: .preReview, metric: .missingFoodPercent, scope: .allMeals, atMost: 30,
            rationale: "Calibration analysis missed 60 % of foods; expect improvement before release."
        ),
        PassCriterion(
            stage: .reviewed, metric: .medianCorrectionTime, scope: .allMeals, atMost: 180,
            rationale: "Calibration median review took 120 s."
        ),
    ]

    /// The diverse calibration set from `AccuracyReportTests`, all evaluated, and two validation meals not yet
    /// evaluated.
    private func writeCalibratedPilot() throws {
        let calibration = [
            meal("ramen", cuisine: "Japanese", dishType: "Soup", foods: [food("ramen", calories: 400, protein: 15, carbohydrates: 55, fat: 10)]),
            meal("pozole", cuisine: "Mexican", dishType: "Soup", foods: [food("pozole", calories: 500, protein: 30, carbohydrates: 50, fat: 20)]),
            meal("tacos", cuisine: "Mexican", dishType: "Taco plate", foods: [food("tacos", calories: 400, protein: 17, carbohydrates: 70, fat: 5)]),
        ]
        let validation = [
            meal("v-miso", split: .validation, cuisine: "Japanese", dishType: "Soup", foods: [
                food("miso soup", calories: 400, protein: 20, carbohydrates: 40, fat: 10),
            ]),
            meal("v-tacos", split: .validation, cuisine: "Mexican", dishType: "Taco plate", foods: [
                food("tortillas", calories: 200, protein: 5, carbohydrates: 40, fat: 3),
                food("beans", calories: 200, protein: 12, carbohydrates: 30, fat: 2),
            ]),
        ]
        for meal in calibration + validation { try write(meal) }
        try pilot.record(evaluation("ramen", preReview: (300, 10, 50, 5), reviewed: (380, 14, 54, 9), correctionTime: 60))
        try pilot.record(evaluation("pozole", preReview: (600, 30, 60, 25), reviewed: (550, 30, 55, 20), correctionTime: 120))
        try pilot.record(evaluation("tacos", preReview: (0, 0, 0, 0), reviewed: (400, 17, 70, 5), correctionTime: 300))
    }

    /// Run once the criteria are frozen. Reviewed calorie errors: miso 10 of 400 (2.5 %), tacos 100 of 400 (25 %).
    private func evaluateValidationMeals() throws {
        try pilot.record(evaluation("v-miso", preReview: (380, 19, 38, 9), reviewed: (390, 20, 40, 10), correctionTime: 90))
        try pilot.record(evaluation(
            "v-tacos", preReview: (200, 5, 40, 3), missedByAnalysis: ["beans"], reviewed: (300, 12, 60, 4),
            correctionTime: 200
        ))
    }

    func test_criteriaCannotBeFrozenBeforeEveryCalibrationMealIsEvaluated() throws {
        try writeCalibratedPilot()
        try write(meal("late", cuisine: "Thai", dishType: "Noodles", foods: [food("pad thai", calories: 600, protein: 20, carbohydrates: 80, fat: 20)]))

        XCTAssertThrowsError(try pilot.freezePassCriteria(criteria, on: frozenOn)) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .calibrationIncomplete(notEvaluated: ["late"]))
        }
    }

    func test_criteriaCannotBeFrozenFromACalibrationSetOfOneCuisineOrDishType() throws {
        try write(meal("ramen", cuisine: "Japanese", dishType: "Soup", foods: [food("ramen", calories: 400, protein: 15, carbohydrates: 55, fat: 10)]))
        try pilot.record(evaluation("ramen", preReview: (300, 10, 50, 5), reviewed: (380, 14, 54, 9), correctionTime: 60))

        XCTAssertThrowsError(try pilot.freezePassCriteria(criteria, on: frozenOn)) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .calibrationNotDiverse(cuisineCount: 1, dishTypeCount: 1))
        }
    }

    func test_everyCriterionNeedsARationaleAndCorrectionTimeBelongsToTheReviewedStage() throws {
        try writeCalibratedPilot()
        var unexplained = criteria[0]
        unexplained.rationale = " "
        var correctionTimeBeforeReview = criteria[3]
        correctionTimeBeforeReview.stage = .preReview

        for criterion in [unexplained, correctionTimeBeforeReview] {
            XCTAssertThrowsError(try pilot.freezePassCriteria([criterion], on: frozenOn)) { error in
                XCTAssertEqual(error as? CalibrationPilotError, .invalidPassCriterion(criterion))
            }
        }
        XCTAssertThrowsError(try pilot.freezePassCriteria([], on: frozenOn)) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .noPassCriteria)
        }
    }

    func test_criteriaAreFrozenOnceAgainstTheCalibrationResults() throws {
        try writeCalibratedPilot()

        let frozen = try pilot.freezePassCriteria(criteria, on: frozenOn)

        XCTAssertEqual(frozen.criteria, criteria)
        XCTAssertEqual(frozen.frozenOn, frozenOn)
        XCTAssertEqual(frozen.calibrationMealIDs, ["pozole", "ramen", "tacos"])
        XCTAssertEqual(try CalibrationPilot(directory: directory.url).frozenPassCriteria(), frozen)
        XCTAssertThrowsError(try pilot.freezePassCriteria(criteria, on: frozenOn)) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .passCriteriaAlreadyFrozen)
        }
    }

    func test_validationIsNotScoredBeforeTheCriteriaAreFrozen() throws {
        try writeCalibratedPilot()

        XCTAssertThrowsError(try pilot.scoreValidation()) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .passCriteriaNotFrozen)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.url.appendingPathComponent("validation-report.md").path))
    }

    func test_validationIsScoredOnlyOnceEveryValidationMealIsEvaluated() throws {
        try writeCalibratedPilot()
        try pilot.freezePassCriteria(criteria, on: frozenOn)

        XCTAssertThrowsError(try pilot.scoreValidation()) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .validationIncomplete(notEvaluated: ["v-miso", "v-tacos"]))
        }
    }

    func test_theValidationSetIsScoredAgainstTheFrozenCriteria() throws {
        try writeCalibratedPilot()
        try pilot.freezePassCriteria(criteria, on: frozenOn)
        try evaluateValidationMeals()

        let score = try pilot.scoreValidation()

        XCTAssertEqual(score.report.split, .validation)
        XCTAssertEqual(score.report.overall.mealCount, 2)
        XCTAssertEqual(score.results.map(\.passed), [true, false, false, true])
        // Reviewed calorie error 13.75 % for all meals; 2.5 % Japanese and 25 % Mexican.
        XCTAssertEqual(score.results[0].measurements, [CriterionMeasurement(group: "All meals", value: 13.75)])
        XCTAssertEqual(score.results[1].measurements, [
            CriterionMeasurement(group: "Japanese", value: 2.5), CriterionMeasurement(group: "Mexican", value: 25),
        ])
        // Analysis missed 1 of 3 reference foods.
        XCTAssertEqual(try XCTUnwrap(score.results[2].measurements[0].value), 100.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(score.results[3].measurements, [CriterionMeasurement(group: "All meals", value: 145)])
        XCTAssertFalse(score.passed)
        let written = try String(contentsOf: directory.url.appendingPathComponent("validation-report.md"), encoding: .utf8)
        XCTAssertEqual(written, score.markdown)
        XCTAssertTrue(written.contains("**Result: not passed.**"))
    }

    func test_validationIsScoredOnce() throws {
        try writeCalibratedPilot()
        try pilot.freezePassCriteria(criteria, on: frozenOn)
        try evaluateValidationMeals()
        try pilot.scoreValidation()

        XCTAssertThrowsError(try pilot.scoreValidation()) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .validationAlreadyScored)
        }
    }

    func test_criteriaCannotBeRefrozenOnceValidationHasBeenScored() throws {
        try writeCalibratedPilot()
        try pilot.freezePassCriteria(criteria, on: frozenOn)
        try evaluateValidationMeals()
        try pilot.scoreValidation()
        try FileManager.default.removeItem(at: directory.url.appendingPathComponent("pass-criteria.json"))

        XCTAssertThrowsError(try pilot.freezePassCriteria(criteria, on: frozenOn)) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .validationAlreadyScored)
        }
    }

    func test_calibrationIsClosedOnceTheCriteriaAreFrozen() throws {
        try writeCalibratedPilot()
        try pilot.freezePassCriteria(criteria, on: frozenOn)
        try write(meal("late", cuisine: "Thai", dishType: "Noodles", foods: [food("pad thai", calories: 600, protein: 20, carbohydrates: 80, fat: 20)]))

        XCTAssertThrowsError(try pilot.record(
            evaluation("late", preReview: (500, 1, 1, 1), reviewed: (600, 1, 1, 1), correctionTime: 60)
        )) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .calibrationClosed)
        }
        // Calibration records changed since the criteria were set from them.
        XCTAssertThrowsError(try pilot.scoreValidation()) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .calibrationChangedSincePassCriteriaFrozen)
        }
    }

    // MARK: Helpers

    private func write(_ meal: ReferenceMeal, to pilot: CalibrationPilot? = nil) throws {
        let folder = (pilot ?? self.pilot).directory.appendingPathComponent("reference-meals", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try CalibrationPilot.encoder.encode(meal).write(to: folder.appendingPathComponent("\(meal.id).json"))
    }

    private func write(photo: Data, named fileName: String) throws {
        let folder = pilot.directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try photo.write(to: folder.appendingPathComponent(fileName))
    }
}
