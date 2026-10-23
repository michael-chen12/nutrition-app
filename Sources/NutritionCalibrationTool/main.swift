import Foundation
import NutritionCalibration

// Developer command line for a calibration pilot directory (see docs/calibration/README.md). Every decision is
// in NutritionCalibration's CalibrationPilot; this only reads arguments and prints.

let usage = """
    Usage:
      nutrition-calibration report <pilot directory>
          Writes calibration-report.md from the calibration meals and their evaluations, and prints it.
      nutrition-calibration freeze-criteria <pilot directory> <criteria JSON file>
          Freezes the pass criteria (a JSON array of PassCriterion) into pass-criteria.json.
      nutrition-calibration score-validation <pilot directory>
          Scores the validation set against the frozen pass criteria, writes validation-report.md, and prints it.
    """

func standardError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first, arguments.count >= 2 else {
    standardError(usage)
    exit(64)
}
let pilot = CalibrationPilot(directory: URL(fileURLWithPath: arguments[1], isDirectory: true))

do {
    switch (command, arguments.count) {
    case ("report", 2):
        print(try pilot.writeCalibrationReport().markdown, terminator: "")
    case ("freeze-criteria", 3):
        let criteria = try CalibrationPilot.decoder.decode(
            [PassCriterion].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2]))
        )
        let frozen = try pilot.freezePassCriteria(criteria, on: Date())
        print("Froze \(frozen.criteria.count) pass criteria against \(frozen.calibrationMealIDs.count) calibration meals.")
    case ("score-validation", 2):
        let score = try pilot.scoreValidation()
        print(score.markdown, terminator: "")
        exit(score.passed ? 0 : 1)
    default:
        standardError(usage)
        exit(64)
    }
} catch {
    standardError("nutrition-calibration: \(error)")
    exit(2)
}
