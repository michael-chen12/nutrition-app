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

    func test_cuisinesOrDishTypesThatDifferOnlyInCaseOrSpacingAreRefused() throws {
        // Otherwise one cuisine would count as two towards a diverse set, and be reported as two groups.
        try write(meal("ramen", cuisine: "Japanese", dishType: "Soup", foods: [food("ramen", calories: 400, protein: 15, carbohydrates: 55, fat: 10)]))
        try write(meal("udon", cuisine: "japanese ", dishType: "Soup", foods: [food("udon", calories: 350, protein: 12, carbohydrates: 60, fat: 5)]))

        XCTAssertThrowsError(try pilot.referenceMeals()) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .inconsistentGroupName(.cuisine, ["Japanese", "japanese "]))
        }

        try write(meal("udon", cuisine: "Japanese", dishType: "soup", foods: [food("udon", calories: 350, protein: 12, carbohydrates: 60, fat: 5)]))
        XCTAssertThrowsError(try pilot.referenceMeals()) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .inconsistentGroupName(.dishType, ["Soup", "soup"]))
        }
    }

    func test_theReferenceMealTemplateIsInTheFormatThePilotReadsAndIsRefusedUntilFilledIn() throws {
        let template = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/calibration/reference-meal-template.json")
        let folder = directory.url.appendingPathComponent("reference-meals", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: template, to: folder.appendingPathComponent("template.json"))

        XCTAssertThrowsError(try pilot.referenceMeals()) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .invalidReferenceMeal("REPLACE-meal-id", .photoUploadNotConsented))
        }
    }

    // MARK: Evaluations

    func test_twoEvaluationFilesForOneMealAreRefusedRatherThanCountedTwice() throws {
        try write(meal("ramen", cuisine: "Japanese", dishType: "Soup", foods: [food("ramen", calories: 400, protein: 15, carbohydrates: 55, fat: 10)]))
        try pilot.record(evaluation("ramen", preReview: (300, 10, 50, 5), reviewed: (380, 14, 54, 9), correctionTime: 60))
        // e.g. Finder's copy when the pilot folder is copied in and out of the app.
        let evaluations = directory.url.appendingPathComponent("evaluations", isDirectory: true)
        try FileManager.default.copyItem(
            at: evaluations.appendingPathComponent("ramen.json"), to: evaluations.appendingPathComponent("ramen copy.json")
        )

        XCTAssertThrowsError(try pilot.evaluations()) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .duplicateEvaluation("ramen"))
        }
        XCTAssertThrowsError(try pilot.calibrationReport())
    }

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
    private let scoredOn = Date(timeIntervalSince1970: 1_794_000_000)

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
    ] + [
        (EstimateStage.reviewed, PassCriterion.Metric.proteinPercentError), (.reviewed, .carbohydratesPercentError),
        (.reviewed, .fatPercentError), (.preReview, .caloriesPercentError), (.preReview, .proteinPercentError),
        (.preReview, .carbohydratesPercentError), (.preReview, .fatPercentError),
    ].map { stage, metric in
        PassCriterion(stage: stage, metric: metric, scope: .allMeals, atMost: 80, rationale: "Generous for the pilot.")
    }

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
        for meal in calibration + validation {
            try write(meal)
            try write(photo: Data(meal.id.utf8), named: "\(meal.id).jpg")
        }
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

    func test_criteriaCoverCaloriesAndEachMacronutrientAtBothStages() throws {
        try writeCalibratedPilot()
        let reviewedCaloriesOnly = Array(criteria.prefix(4))

        XCTAssertThrowsError(try pilot.freezePassCriteria(reviewedCaloriesOnly, on: frozenOn)) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .missingNutrientCriteria([
                RequiredCriterion(stage: .preReview, metric: .caloriesPercentError),
                RequiredCriterion(stage: .preReview, metric: .proteinPercentError),
                RequiredCriterion(stage: .preReview, metric: .carbohydratesPercentError),
                RequiredCriterion(stage: .preReview, metric: .fatPercentError),
                RequiredCriterion(stage: .reviewed, metric: .proteinPercentError),
                RequiredCriterion(stage: .reviewed, metric: .carbohydratesPercentError),
                RequiredCriterion(stage: .reviewed, metric: .fatPercentError),
            ]))
        }
        XCTAssertNil(try pilot.frozenPassCriteria())
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

        XCTAssertThrowsError(try pilot.scoreValidation(on: scoredOn)) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .passCriteriaNotFrozen)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.url.appendingPathComponent("validation-report.md").path))
    }

    func test_validationIsScoredOnlyOnceEveryValidationMealIsEvaluated() throws {
        try writeCalibratedPilot()
        try pilot.freezePassCriteria(criteria, on: frozenOn)

        XCTAssertThrowsError(try pilot.scoreValidation(on: scoredOn)) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .validationIncomplete(notEvaluated: ["v-miso", "v-tacos"]))
        }
    }

    func test_aValidationSetOfOneCuisineOrDishTypeIsNotScored() throws {
        try writeCalibratedPilot()
        try FileManager.default.removeItem(at: directory.url.appendingPathComponent("reference-meals/v-tacos.json"))
        try pilot.freezePassCriteria(criteria, on: frozenOn)
        try pilot.record(evaluation("v-miso", preReview: (380, 19, 38, 9), reviewed: (390, 20, 40, 10), correctionTime: 90))

        XCTAssertThrowsError(try pilot.scoreValidation(on: scoredOn)) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .validationNotDiverse(cuisineCount: 1, dishTypeCount: 1))
        }
    }

    func test_aValidationMealCannotReuseACalibrationMealsPhoto() throws {
        try writeCalibratedPilot()
        try pilot.freezePassCriteria(criteria, on: frozenOn)
        let miso = try XCTUnwrap(try pilot.referenceMeals().first { $0.id == "v-miso" })
        try write(photo: Data("ramen".utf8), named: "v-miso.jpg")

        XCTAssertThrowsError(try pilot.photos(for: miso)) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .validationMealReusesCalibrationPhoto("v-miso", photoFileName: "v-miso.jpg"))
        }
        try evaluateValidationMeals()
        XCTAssertThrowsError(try pilot.scoreValidation(on: scoredOn)) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .validationMealReusesCalibrationPhoto("v-miso", photoFileName: "v-miso.jpg"))
        }
    }

    func test_theValidationSetIsScoredAgainstTheFrozenCriteria() throws {
        try writeCalibratedPilot()
        try pilot.freezePassCriteria(criteria, on: frozenOn)
        try evaluateValidationMeals()

        let score = try pilot.scoreValidation(on: scoredOn)

        XCTAssertEqual(score.report.split, .validation)
        XCTAssertEqual(score.report.overall.mealCount, 2)
        XCTAssertEqual(score.results.prefix(4).map(\.passed), [true, false, false, true])
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
        XCTAssertTrue(written.contains("**Accuracy gate: not passed.**"))
    }

    func test_theScoreNamesEveryCuisineAndDishTypeOverACriterionsLimitWhateverItsScope() throws {
        try writeCalibratedPilot()
        try pilot.freezePassCriteria(criteria, on: frozenOn)
        try evaluateValidationMeals()

        let score = try pilot.scoreValidation(on: scoredOn)

        // Tacos alone: reviewed calories 25 % (all-meals limit 15, so the all-meals criterion still passes; each-
        // cuisine limit 20), analysis missed 1 of 2 foods, 200 s of review. Miso is within every limit.
        XCTAssertTrue(score.results[0].passed)
        let tacosFailures = [(criteria[0], 25.0), (criteria[1], 25), (criteria[2], 50), (criteria[3], 200)]
        XCTAssertEqual(
            score.groupFailures,
            tacosFailures.map { GroupFailure(grouping: .cuisine, group: "Mexican", criterion: $0, value: $1) }
                + tacosFailures.map { GroupFailure(grouping: .dishType, group: "Taco plate", criterion: $0, value: $1) }
        )
        XCTAssertTrue(score.markdown.contains("**Accuracy gate: not passed.** The validation does not support a broad launch."))
        XCTAssertTrue(score.markdown.contains("- Mexican (cuisine): reviewed calories % 25.0, over the limit of 15.0 for all meals."))
        XCTAssertTrue(score.markdown.contains("- Taco plate (dish type): pre-review missing foods % 50.0, over the limit of 30.0 for all meals."))
    }

    func test_aPassedValidationGivesTheAccuracyClaimTheAppMayMakeWithTheGroupsThatDidWorse() throws {
        try writeCalibratedPilot()
        // Reviewed calories within 15 % for all meals, and generous nutrient limits otherwise.
        try pilot.freezePassCriteria([criteria[0]] + criteria.suffix(7), on: frozenOn)
        try evaluateValidationMeals()

        let score = try pilot.scoreValidation(on: scoredOn)

        XCTAssertTrue(score.passed)
        // Calorie errors: reviewed 2.5 % and 25 %, pre-review 5 % and 50 %. Tacos alone is over the 15 % limit.
        let expected = EstimateReliability.validated(accuracy: ValidatedAccuracy(
            validatedOn: scoredOn, mealCount: 2, cuisines: ["Japanese", "Mexican"], dishTypes: ["Soup", "Taco plate"],
            preReviewCaloriePercentError: 27.5, reviewedCaloriePercentError: 13.75,
            lessAccurateCuisines: ["Mexican"], lessAccurateDishTypes: ["Taco plate"]
        ))
        XCTAssertEqual(score.reliability, expected)
        XCTAssertEqual(
            expected.statement,
            "Tested on 2 new meals with weighed portions or known recipes (cuisines: Japanese, Mexican; dish types: "
                + "Soup, Taco plate). Reviewed estimates were off by 14 % in calories on average; photo suggestions "
                + "before review, by 28 %. Less accurate for: Mexican (cuisine), Taco plate (dish type)."
        )
        XCTAssertTrue(score.markdown.contains("> \(expected.statement)"))
        let written = try Data(contentsOf: directory.url.appendingPathComponent("estimate-reliability.json"))
        XCTAssertEqual(try CalibrationPilot.decoder.decode(EstimateReliability.self, from: written), expected)
    }

    func test_aGroupOverOnlyACorrectionTimeLimitIsNotClaimedLessAccurate() throws {
        try writeCalibratedPilot()
        let reviewedCalories = PassCriterion(
            stage: .reviewed, metric: .caloriesPercentError, scope: .allMeals, atMost: 80, rationale: "Generous for the pilot."
        )
        // Median review 145 s passes the 180 s limit; tacos alone took 200 s.
        try pilot.freezePassCriteria([reviewedCalories, criteria[3]] + criteria.suffix(7), on: frozenOn)
        try evaluateValidationMeals()

        let score = try pilot.scoreValidation(on: scoredOn)

        XCTAssertTrue(score.passed)
        XCTAssertEqual(score.groupFailures.map(\.group), ["Mexican", "Taco plate"])
        guard case .validated(let accuracy) = score.reliability else { return XCTFail("\(score.reliability)") }
        XCTAssertEqual(accuracy.lessAccurateCuisines, [])
        XCTAssertEqual(accuracy.lessAccurateDishTypes, [])
    }

    func test_aValidationThatDidNotPassLeavesTheAppWithoutAnAccuracyClaim() throws {
        try writeCalibratedPilot()
        try pilot.freezePassCriteria(criteria, on: frozenOn)
        try evaluateValidationMeals()

        let score = try pilot.scoreValidation(on: scoredOn)

        XCTAssertFalse(score.passed)
        XCTAssertEqual(score.reliability, .notValidated)
        let written = try Data(contentsOf: directory.url.appendingPathComponent("estimate-reliability.json"))
        XCTAssertEqual(try CalibrationPilot.decoder.decode(EstimateReliability.self, from: written), .notValidated)
    }

    func test_validationIsScoredOnce() throws {
        try writeCalibratedPilot()
        try pilot.freezePassCriteria(criteria, on: frozenOn)
        try evaluateValidationMeals()
        try pilot.scoreValidation(on: scoredOn)

        XCTAssertThrowsError(try pilot.scoreValidation(on: scoredOn)) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .validationAlreadyScored)
        }
    }

    func test_aWrittenAccuracyClaimAloneCountsAsScored() throws {
        try writeCalibratedPilot()
        try pilot.freezePassCriteria(criteria, on: frozenOn)
        try evaluateValidationMeals()
        try pilot.scoreValidation(on: scoredOn)
        try FileManager.default.removeItem(at: directory.url.appendingPathComponent("validation-report.md"))

        XCTAssertThrowsError(try pilot.scoreValidation(on: scoredOn)) { error in
            XCTAssertEqual(error as? CalibrationPilotError, .validationAlreadyScored)
        }
    }

    func test_criteriaCannotBeRefrozenOnceValidationHasBeenScored() throws {
        try writeCalibratedPilot()
        try pilot.freezePassCriteria(criteria, on: frozenOn)
        try evaluateValidationMeals()
        try pilot.scoreValidation(on: scoredOn)
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
        XCTAssertThrowsError(try pilot.scoreValidation(on: scoredOn)) { error in
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
