import Foundation
import NutritionCalibration
import NutritionCore
import XCTest

/// Ticket #12: the accuracy report works out pre-review and final reviewed errors from recorded evaluations and
/// reference meals, shows them by cuisine and dish type, and identifies coverage and estimation gaps.
final class AccuracyReportTests: XCTestCase {
    /// Three calibration meals (every reference food is 100 g, so its values are the meal's):
    /// - ramen: Japanese soup, noodles 300 kcal + broth 100 kcal = 400 kcal, 15 g protein, 55 g carbohydrates,
    ///   10 g fat. Analysis missed the broth (300 kcal); reviewed 380 kcal. Corrected in 60 s.
    /// - pozole: Mexican soup, 500 kcal, 30/50/20 g. Analysis 600 kcal; reviewed 550 kcal. 120 s.
    /// - tacos: Mexican taco plate, tortillas 200 kcal + beans 200 kcal = 400 kcal, 17/70/5 g. Analysis failed
    ///   (nothing); reviewed exactly. 300 s.
    private let meals = [
        meal("ramen", cuisine: "Japanese", dishType: "Soup", foods: [
            food("noodles", calories: 300, protein: 10, carbohydrates: 50, fat: 5),
            food("broth", calories: 100, protein: 5, carbohydrates: 5, fat: 5),
        ]),
        meal("pozole", cuisine: "Mexican", dishType: "Soup", foods: [
            food("pozole", calories: 500, protein: 30, carbohydrates: 50, fat: 20),
        ]),
        meal("tacos", cuisine: "Mexican", dishType: "Taco plate", foods: [
            food("tortillas", calories: 200, protein: 5, carbohydrates: 40, fat: 3),
            food("beans", calories: 200, protein: 12, carbohydrates: 30, fat: 2),
        ]),
    ]
    private let evaluations = [
        evaluation(
            "ramen",
            preReview: (300, 10, 50, 5), missedByAnalysis: ["broth"],
            reviewed: (380, 14, 54, 9), correctionTime: 60
        ),
        evaluation("pozole", preReview: (600, 30, 60, 25), reviewed: (550, 30, 55, 20), correctionTime: 120),
        evaluation(
            "tacos",
            preReview: (0, 0, 0, 0), missedByAnalysis: ["beans", "tortillas"],
            reviewed: (400, 17, 70, 5), correctionTime: 300
        ),
    ]

    func test_preReviewAndReviewedErrorsAreReportedSeparatelyForTheWholeSet() throws {
        let report = try AccuracyReport(split: .calibration, meals: meals, evaluations: evaluations)

        let overall = report.overall
        XCTAssertEqual(overall.mealCount, 3)
        // Calorie errors: ramen -100 (25 %), pozole +100 (20 %), tacos -400 (100 %).
        XCTAssertEqual(overall.preReview.calories.meanError, -133.3333, accuracy: 0.001)
        XCTAssertEqual(overall.preReview.calories.meanAbsoluteError, 200, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(overall.preReview.calories.meanAbsolutePercentError), 48.3333, accuracy: 0.001)
        // Protein errors: -5 of 15 (33.3 %), 0 of 30, -17 of 17 (100 %).
        XCTAssertEqual(overall.preReview.protein.meanAbsoluteError, 7.3333, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(overall.preReview.protein.meanAbsolutePercentError), 44.4444, accuracy: 0.001)
        // 3 of 5 reference foods missed by analysis.
        XCTAssertEqual(overall.preReview.missingFoodRate, 0.6, accuracy: 0.0001)
        // Reviewed calorie errors: -20 (5 %), +50 (10 %), 0.
        XCTAssertEqual(overall.reviewed.calories.meanError, 10, accuracy: 0.001)
        XCTAssertEqual(overall.reviewed.calories.meanAbsoluteError, 23.3333, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(overall.reviewed.calories.meanAbsolutePercentError), 5, accuracy: 0.001)
        // Reviewed fat errors: -1 of 10 (10 %), 0 of 20, 0 of 5.
        XCTAssertEqual(overall.reviewed.fat.meanAbsoluteError, 0.3333, accuracy: 0.001)
        XCTAssertEqual(overall.reviewed.missingFoodRate, 0)
        XCTAssertEqual(overall.medianCorrectionTime, 120)
    }

    func test_errorsAreBrokenDownByCuisineAndByDishType() throws {
        let report = try AccuracyReport(split: .calibration, meals: meals, evaluations: evaluations)

        XCTAssertEqual(report.byCuisine.map(\.name), ["Japanese", "Mexican"])
        XCTAssertEqual(report.byCuisine.map(\.mealCount), [1, 2])
        // Mexican: pozole +100 (20 %) and tacos -400 (100 %); 2 of 3 reference foods missed.
        let mexican = report.byCuisine[1]
        XCTAssertEqual(mexican.preReview.calories.meanAbsoluteError, 250, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(mexican.preReview.calories.meanAbsolutePercentError), 60, accuracy: 0.001)
        XCTAssertEqual(mexican.preReview.missingFoodRate, 2.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(mexican.reviewed.calories.meanAbsolutePercentError), 5, accuracy: 0.001)
        XCTAssertEqual(mexican.medianCorrectionTime, 210)

        XCTAssertEqual(report.byDishType.map(\.name), ["Soup", "Taco plate"])
        // Soup: ramen 25 % and pozole 20 % before review; 5 % and 10 % after.
        let soup = report.byDishType[0]
        XCTAssertEqual(try XCTUnwrap(soup.preReview.calories.meanAbsolutePercentError), 22.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(soup.reviewed.calories.meanAbsolutePercentError), 7.5, accuracy: 0.001)
    }

    func test_aNutrientWithAZeroReferenceHasNoPercentErrorButKeepsItsAbsoluteError() throws {
        let coffee = meal("coffee", cuisine: "Italian", dishType: "Drink", foods: [
            food("espresso", calories: 2, protein: 0.1, carbohydrates: 0, fat: 0),
        ])
        let report = try AccuracyReport(
            split: .calibration,
            meals: [coffee],
            evaluations: [evaluation("coffee", preReview: (40, 2, 4, 2), reviewed: (2, 0.1, 0, 0), correctionTime: 5)]
        )

        XCTAssertNil(report.overall.preReview.fat.meanAbsolutePercentError)
        XCTAssertEqual(report.overall.preReview.fat.meanAbsoluteError, 2)
        XCTAssertEqual(try XCTUnwrap(report.overall.preReview.calories.meanAbsolutePercentError), 1900, accuracy: 0.001)
    }

    func test_aReportCoversOneSplitOnly() throws {
        let heldOut = meal("held-out", split: .validation, cuisine: "Ethiopian", dishType: "Stew", foods: [
            food("wat", calories: 300, protein: 20, carbohydrates: 10, fat: 20),
        ])
        let report = try AccuracyReport(
            split: .calibration,
            meals: meals + [heldOut],
            evaluations: evaluations + [
                evaluation("held-out", preReview: (100, 1, 1, 1), reviewed: (300, 20, 10, 20), correctionTime: 10),
            ]
        )

        XCTAssertEqual(report.overall.mealCount, 3)
        XCTAssertFalse(report.byCuisine.map(\.name).contains("Ethiopian"))
    }

    func test_theCalibrationReportSaysItDoesNotDecideBroadLaunch() throws {
        let notice = "Calibration results only set the pass criteria. They do not show that the app is ready for "
            + "a broad launch: only the held-out validation set, scored against the frozen criteria, can."

        let calibration = try AccuracyReport(split: .calibration, meals: meals, evaluations: evaluations)
        let validation = try AccuracyReport(split: .validation, meals: meals, evaluations: [])

        XCTAssertTrue(calibration.markdown.contains(notice))
        XCTAssertFalse(validation.markdown.contains(notice))
    }

    func test_gapsFlagThinGroupsAndGroupsWhoseErrorIsWellAboveTheWholeSet() throws {
        let report = try AccuracyReport(split: .calibration, meals: meals, evaluations: evaluations)

        XCTAssertEqual(report.gaps, [
            .fewMeals(.cuisine, name: "Japanese", mealCount: 1),
            .fewMeals(.cuisine, name: "Mexican", mealCount: 2),
            .fewMeals(.dishType, name: "Soup", mealCount: 2),
            .fewMeals(.dishType, name: "Taco plate", mealCount: 1),
            // 100 % calorie error, against 48.3 % for all meals.
            .highCalorieError(.preReview, .dishType, name: "Taco plate", percentError: 100, overallPercentError: 145.0 / 3),
        ])
    }

    func test_gapsFlagMissingCoverageMissedFoodsSourceGapsAndReviewThatDidNotHelp() throws {
        let curryMeals = (1...3).map { index in
            meal("curry-\(index)", cuisine: "South Asian", dishType: "Rice plate", foods: [
                food("rice", calories: 200, protein: 4, carbohydrates: 44, fat: 0.5),
                food("dal", calories: 200, protein: 12, carbohydrates: 30, fat: 4),
            ])
        }
        let notYetRun = meal("curry-4", cuisine: "South Asian", dishType: "Rice plate", foods: [
            food("rice", calories: 200, protein: 4, carbohydrates: 44, fat: 0.5),
        ])
        let report = try AccuracyReport(
            split: .calibration,
            meals: curryMeals + [notYetRun],
            evaluations: [
                evaluation("curry-1", preReview: (400, 16, 74, 4.5), reviewed: (400, 16, 74, 4.5), correctionTime: 30),
                evaluation(
                    "curry-2", preReview: (360, 14, 70, 4), reviewed: (300, 12, 60, 3), correctionTime: 40,
                    suggestionsWithoutEstimate: ["Tadka dal"], customFoodsAfterReview: ["Tadka dal"]
                ),
                evaluation(
                    "curry-3", preReview: (200, 4, 44, 0.5), missedByAnalysis: ["dal"],
                    reviewed: (200, 4, 44, 0.5), missedAfterReview: ["dal"], correctionTime: 50
                ),
            ]
        )

        XCTAssertEqual(report.gaps, [
            .fewCuisines(count: 1),
            .fewDishTypes(count: 1),
            .notEvaluated(mealIDs: ["curry-4"]),
            .missedAfterReview(mealID: "curry-3", foodNames: ["Dal"]),
            .suggestionsWithoutEstimate(foodNames: ["Tadka dal"]),
            .customFoodsAfterReview(foodNames: ["Tadka dal"]),
            // Review took curry-2 from 10 % to 25 % calorie error: 20 % before review for the group, 25 % after.
            .reviewDidNotReduceCalorieError(.cuisine, name: "South Asian", preReviewPercentError: 20, reviewedPercentError: 25),
            .reviewDidNotReduceCalorieError(.dishType, name: "Rice plate", preReviewPercentError: 20, reviewedPercentError: 25),
        ])
    }

    func test_theMarkdownReportShowsEachStageByGroupAndListsTheGaps() throws {
        let report = try AccuracyReport(split: .calibration, meals: meals, evaluations: evaluations)

        let lines = report.markdown.components(separatedBy: "\n")

        XCTAssertEqual(lines.first, "# Calibration accuracy report")
        XCTAssertTrue(lines.contains(
            "| All meals | 3 | Pre-review | -133 | 200 | 48.3 % | 7.3 | 44.4 % | 28.3 | 43.0 % | 5.0 | 58.3 % | 60 % | – |"
        ))
        XCTAssertTrue(lines.contains(
            "| All meals | 3 | Reviewed | 10 | 23 | 5.0 % | 0.3 | 2.2 % | 2.0 | 3.9 % | 0.3 | 3.3 % | 0 % | 120 s |"
        ))
        XCTAssertTrue(lines.contains(
            "| Japanese | 1 | Pre-review | -100 | 100 | 25.0 % | 5.0 | 33.3 % | 5.0 | 9.1 % | 5.0 | 50.0 % | 50 % | – |"
        ))
        XCTAssertTrue(lines.contains("- Japanese (cuisine): only 1 evaluated meal."))
        XCTAssertTrue(lines.contains(
            "- Taco plate (dish type): pre-review calorie error 100.0 %, against 48.3 % for all meals."
        ))
        XCTAssertEqual(
            report.markdown,
            try AccuracyReport(split: .calibration, meals: meals.reversed(), evaluations: evaluations.reversed()).markdown,
            "the same records give the same report"
        )
    }

    func test_aMealWhosePhotoAnalysisGaveNoSuggestionsIsAGapWithTheReasonShownToThePerson() throws {
        var recorded = evaluations
        recorded[2].photoAnalysisMessage = "Photo analysis isn't available right now."

        let report = try AccuracyReport(split: .calibration, meals: meals, evaluations: recorded)

        XCTAssertTrue(report.gaps.contains(
            .noPhotoSuggestions(mealID: "tacos", message: "Photo analysis isn't available right now.")
        ))
        XCTAssertTrue(report.markdown.contains(
            "- tacos: photo analysis gave no suggestions (\"Photo analysis isn't available right now.\"), "
                + "so its pre-review estimate is empty."
        ))
    }

    func test_anEvaluationOfAMealOutsideThePilotIsRefused() {
        XCTAssertThrowsError(try AccuracyReport(
            split: .calibration,
            meals: meals,
            evaluations: [evaluation("unknown", preReview: (1, 1, 1, 1), reviewed: (1, 1, 1, 1), correctionTime: 1)]
        )) { error in
            XCTAssertEqual(error as? AccuracyReportError, .evaluationOfUnknownMeal("unknown"))
        }
    }
}
