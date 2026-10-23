import Foundation

// The accuracy report as Markdown, for a pilot's calibration-report.md and validation-report.md. It carries no
// date or machine detail, so the same records always render the same text.

extension AccuracyReport {
    public var markdown: String {
        var lines = [
            "# \(split == .calibration ? "Calibration" : "Validation") accuracy report",
            "",
            "\(overall.mealCount) evaluated \(overall.mealCount == 1 ? "meal" : "meals") from the \(split.rawValue) set.",
            "",
        ]
        if split == .calibration {
            lines += [
                "Calibration results only set the pass criteria. They do not show that the app is ready for a broad "
                    + "launch: only the held-out validation set, scored against the frozen criteria, can.",
                "",
            ]
        }
        lines += [
            "- **Pre-review**: photo suggestions accepted as offered, before any review (the automatic estimate).",
            "- **Reviewed**: the saved meal entry after the person's review (the final nutrition estimate).",
            "- Error is estimate minus reference; \"abs.\" is its mean absolute value, \"%\" the mean absolute error "
                + "as a percentage of the reference (meals with a zero reference value for a nutrient are left out "
                + "of its %). Missing foods: reference foods the stage left out, as a share of all reference foods.",
            "",
        ]
        let sections: [(String, [GroupAccuracy])] = [
            ("All meals", [overall]),
            ("By cuisine", byCuisine),
            ("By dish type", byDishType),
        ]
        for (title, groups) in sections {
            lines += [
                "## \(title)",
                "",
                "| Group | Meals | Stage | Calories error (kcal) | Calories abs. (kcal) | Calories % "
                    + "| Protein abs. (g) | Protein % | Carbohydrates abs. (g) | Carbohydrates % | Fat abs. (g) | Fat % "
                    + "| Missing foods | Median correction time |",
                "|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
            ]
            for group in groups {
                for stage in EstimateStage.allCases {
                    lines.append(Self.row(group, stage))
                }
            }
            lines.append("")
        }
        lines += ["## Gaps", ""]
        lines += gaps.isEmpty ? ["None identified."] : gaps.map { "- \($0.description)" }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func row(_ group: GroupAccuracy, _ stage: EstimateStage) -> String {
        let accuracy = group[stage]
        let correctionTime = stage == .reviewed ? group.medianCorrectionTime.map { "\(whole($0)) s" } : nil
        let cells = [
            group.name,
            "\(group.mealCount)",
            stage.title,
            whole(accuracy.calories.meanError),
            whole(accuracy.calories.meanAbsoluteError),
            percent(accuracy.calories.meanAbsolutePercentError),
            tenths(accuracy.protein.meanAbsoluteError),
            percent(accuracy.protein.meanAbsolutePercentError),
            tenths(accuracy.carbohydrates.meanAbsoluteError),
            percent(accuracy.carbohydrates.meanAbsolutePercentError),
            tenths(accuracy.fat.meanAbsoluteError),
            percent(accuracy.fat.meanAbsolutePercentError),
            "\(whole(accuracy.missingFoodRate * 100)) %",
            correctionTime ?? "–",
        ]
        return "| " + cells.joined(separator: " | ") + " |"
    }
}

extension ValidationScore {
    /// The criteria results followed by the validation accuracy report.
    public var markdown: String {
        func day(_ date: Date) -> String {
            ISO8601DateFormatter.string(from: date, timeZone: TimeZone(identifier: "UTC")!, formatOptions: [.withFullDate])
        }
        var lines = [
            "# Validation against the frozen pass criteria",
            "",
            "Scored on \(day(scoredOn)). Pass criteria frozen on \(day(criteria.frozenOn)) from "
                + "\(criteria.calibrationMealIDs.count) evaluated calibration meals (calibration fingerprint "
                + "\(criteria.calibrationFingerprint)).",
            "",
            passed
                ? "**Accuracy gate: passed.** The validation supports a broad launch."
                : "**Accuracy gate: not passed.** The validation does not support a broad launch.",
            "",
            "| Stage | Measure | Applies to | At most | Measured | Passed |",
            "|---|---|---|---:|---|---|",
        ]
        for result in results {
            let criterion = result.criterion
            let measured = result.measurements
                .map { "\($0.group) \($0.value.map(tenths) ?? "not measurable")" }
                .joined(separator: "; ")
            lines.append("| " + [
                criterion.stage.title, criterion.metric.title, criterion.scope.title, tenths(criterion.atMost),
                measured.isEmpty ? "no meals" : measured, result.passed ? "Yes" : "No",
            ].joined(separator: " | ") + " |")
        }
        lines += ["", "Rationale:", ""]
        lines += results.map { "- \($0.criterion.metric.title), \($0.criterion.scope.title.lowercased()): \($0.criterion.rationale)" }
        lines += [
            "",
            "## Cuisine and dish-type failures",
            "",
            "Each criterion applied to every cuisine and dish type on its own, whatever its scope.",
            "",
        ]
        lines += groupFailures.isEmpty ? ["None."] : groupFailures.map { "- \($0.description)" }
        lines += [
            "",
            "## What the app may claim",
            "",
            "> \(reliability.statement)",
            "",
            "Written to estimate-reliability.json. The app's `EstimateReliability.published` must match it, and "
                + "docs/calibration/launch-decision.md records the decision.",
            "",
            "",
        ]
        return lines.joined(separator: "\n") + report.markdown
    }
}

extension GroupFailure: CustomStringConvertible {
    public var description: String {
        let measure = "\(criterion.stage.title.lowercased()) \(criterion.metric.title.lowercased())"
        let limit = "the limit of \(tenths(criterion.atMost)) for \(criterion.scope.title.lowercased())"
        let measured = value.map { "\(measure) \(tenths($0)), over \(limit)" } ?? "\(measure) not measurable against \(limit)"
        return "\(group) (\(grouping.title)): \(measured)."
    }
}

extension PassCriterion.Metric {
    var title: String {
        switch self {
        case .caloriesPercentError: return "Calories %"
        case .proteinPercentError: return "Protein %"
        case .carbohydratesPercentError: return "Carbohydrates %"
        case .fatPercentError: return "Fat %"
        case .missingFoodPercent: return "Missing foods %"
        case .medianCorrectionTime: return "Median correction time (s)"
        }
    }
}

extension PassCriterion.Scope {
    var title: String {
        switch self {
        case .allMeals: return "All meals"
        case .eachCuisine: return "Each cuisine"
        case .eachDishType: return "Each dish type"
        }
    }
}

extension EstimateStage {
    var title: String {
        switch self {
        case .preReview: return "Pre-review"
        case .reviewed: return "Reviewed"
        }
    }
}

extension ReportGrouping {
    var title: String {
        switch self {
        case .cuisine: return "cuisine"
        case .dishType: return "dish type"
        }
    }
}

extension AccuracyGap: CustomStringConvertible {
    public var description: String {
        switch self {
        case .fewCuisines(let count):
            return "Covers \(count) cuisine\(count == 1 ? "" : "s"); a pilot needs several."
        case .fewDishTypes(let count):
            return "Covers \(count) dish type\(count == 1 ? "" : "s"); a pilot needs several."
        case let .fewMeals(grouping, name, mealCount):
            return "\(name) (\(grouping.title)): only \(mealCount) evaluated meal\(mealCount == 1 ? "" : "s")."
        case .notEvaluated(let mealIDs):
            return "Not evaluated yet: \(mealIDs.joined(separator: ", "))."
        case let .noPhotoSuggestions(mealID, message):
            return "\(mealID): photo analysis gave no suggestions (\"\(message)\"), so its pre-review estimate is empty."
        case let .missedAfterReview(mealID, foodNames):
            return "\(mealID): still missing after review: \(foodNames.joined(separator: ", "))."
        case .suggestionsWithoutEstimate(let foodNames):
            return "Suggestions without a documented food or portion conversion: \(foodNames.joined(separator: ", "))."
        case .customFoodsAfterReview(let foodNames):
            return "Custom foods entered for want of a documented food: \(foodNames.joined(separator: ", "))."
        case let .highCalorieError(stage, grouping, name, percentError, overallPercentError):
            return "\(name) (\(grouping.title)): \(stage.title.lowercased()) calorie error \(percent(percentError)), "
                + "against \(percent(overallPercentError)) for all meals."
        case let .reviewDidNotReduceCalorieError(grouping, name, before, after):
            return "\(name) (\(grouping.title)): review did not reduce calorie error (\(percent(before)) before, "
                + "\(percent(after)) after)."
        }
    }
}

/// Rounded to a whole number, never shown as "-0".
func whole(_ value: Double) -> String {
    String(format: "%.0f", value.rounded() + 0)
}

func tenths(_ value: Double) -> String {
    String(format: "%.1f", (value * 10).rounded() / 10 + 0)
}

func percent(_ value: Double?) -> String {
    value.map { "\(tenths($0)) %" } ?? "–"
}
