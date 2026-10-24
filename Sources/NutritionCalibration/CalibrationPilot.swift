import Foundation
import NutritionCore

/// A pilot directory: the study's reference meals, their meal photos and the recorded evaluations, plus the
/// pass criteria once frozen. Plain JSON and image files, so the pilot can be kept under version control and
/// every report reproduced from it.
///
///     reference-meals/<any name>.json   one ReferenceMeal each
///     photos/<file name>                the meal photos the reference meals name
///     evaluations/<meal ID>.json        one MealEvaluation per evaluated meal
///     calibration-report.md             written by `writeCalibrationReport()`
///     pass-criteria.json                FrozenPassCriteria, once frozen
///     validation-report.md              written when the validation set is scored
///     estimate-reliability.json         the accuracy claim the app may make, written with it
public final class CalibrationPilot {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Readable, stable JSON: the same records always encode to the same bytes.
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: Reference meals

    /// Every reference meal, in ID order. Throws when one is not usable for the study.
    public func referenceMeals() throws -> [ReferenceMeal] {
        var meals: [ReferenceMeal] = []
        for url in try jsonFiles(in: referenceMealsDirectory) {
            let meal = try Self.decoder.decode(ReferenceMeal.self, from: Data(contentsOf: url))
            if let problem = meal.problem {
                throw CalibrationPilotError.invalidReferenceMeal(meal.id, problem)
            }
            guard !meals.contains(where: { $0.id == meal.id }) else {
                throw CalibrationPilotError.duplicateReferenceMeal(meal.id)
            }
            meals.append(meal)
        }
        try Self.checkConsistentNames(meals.map(\.cuisine), .cuisine)
        try Self.checkConsistentNames(meals.map(\.dishType), .dishType)
        return meals.sorted { $0.id < $1.id }
    }

    /// Each cuisine and dish type is written one way, so the diversity checks and the report count it once.
    private static func checkConsistentNames(_ names: [String], _ grouping: ReportGrouping) throws {
        let spellings = Dictionary(grouping: Set(names)) { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if let variants = spellings.values.map({ $0.sorted() }).filter({ $0.count > 1 }).min(by: { $0[0] < $1[0] }) {
            throw CalibrationPilotError.inconsistentGroupName(grouping, variants)
        }
    }

    /// The meal's photos, in the order it names them. Refused for a validation meal that reuses a calibration
    /// meal's photo.
    public func photos(for meal: ReferenceMeal) throws -> [TrialPhoto] {
        if meal.split == .validation { try checkNoCalibrationPhotoIsReused(by: [meal]) }
        return try photoFiles(of: meal)
    }

    /// Validation meals must be new meals: none may show a calibration meal's photo, under any file name. A
    /// re-photographed calibration meal cannot be told apart this way; collecting new meals is the safeguard.
    private func checkNoCalibrationPhotoIsReused(by validationMeals: [ReferenceMeal]) throws {
        let calibrationPhotos = Set(try referenceMeals().filter { $0.split == .calibration }.flatMap { try photoFiles(of: $0) }.map(\.data))
        for meal in validationMeals {
            for (fileName, photo) in zip(meal.photoFileNames, try photoFiles(of: meal)) where calibrationPhotos.contains(photo.data) {
                throw CalibrationPilotError.validationMealReusesCalibrationPhoto(meal.id, photoFileName: fileName)
            }
        }
    }

    private func photoFiles(of meal: ReferenceMeal) throws -> [TrialPhoto] {
        try meal.photoFileNames.map { fileName in
            let url = photosDirectory.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw CalibrationPilotError.missingPhoto(fileName)
            }
            return TrialPhoto(data: try Data(contentsOf: url), fileExtension: url.pathExtension)
        }
    }

    // MARK: Evaluations

    /// The meals a trial can be run for now, in ID order: unevaluated calibration meals until the pass criteria
    /// are frozen, then unevaluated validation meals.
    public func mealsOpenForTrial() throws -> [ReferenceMeal.ID] {
        try unevaluatedMealIDs(in: frozenPassCriteria() == nil ? .calibration : .validation)
    }

    /// Records a trial's evaluation. Each reference meal is evaluated once: calibration meals until the pass
    /// criteria are frozen, validation meals only after, so no validation result exists before the criteria do.
    public func record(_ evaluation: MealEvaluation) throws {
        guard let meal = try referenceMeals().first(where: { $0.id == evaluation.referenceMealID }) else {
            throw CalibrationPilotError.unknownReferenceMeal(evaluation.referenceMealID)
        }
        switch (meal.split, try frozenPassCriteria() != nil) {
        case (.calibration, true): throw CalibrationPilotError.calibrationClosed
        case (.validation, false): throw CalibrationPilotError.passCriteriaNotFrozen
        default: break
        }
        let url = evaluationURL(for: evaluation.referenceMealID)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw CalibrationPilotError.alreadyEvaluated(evaluation.referenceMealID)
        }
        try FileManager.default.createDirectory(at: evaluationsDirectory, withIntermediateDirectories: true)
        try Self.encoder.encode(evaluation).write(to: url, options: .atomic)
    }

    /// Every recorded evaluation, in reference meal ID order. Throws when two are for the same meal.
    public func evaluations() throws -> [MealEvaluation] {
        let evaluations = try jsonFiles(in: evaluationsDirectory)
            .map { try Self.decoder.decode(MealEvaluation.self, from: Data(contentsOf: $0)) }
            .sorted { $0.referenceMealID < $1.referenceMealID }
        if let repeated = zip(evaluations, evaluations.dropFirst()).first(where: { $0.referenceMealID == $1.referenceMealID }) {
            throw CalibrationPilotError.duplicateEvaluation(repeated.0.referenceMealID)
        }
        return evaluations
    }

    /// The accuracy report for the calibration set. Validation meals never appear in it.
    public func calibrationReport() throws -> AccuracyReport {
        try AccuracyReport(split: .calibration, meals: referenceMeals(), evaluations: evaluations())
    }

    /// The calibration report, also written to calibration-report.md.
    @discardableResult
    public func writeCalibrationReport() throws -> AccuracyReport {
        let report = try calibrationReport()
        try Data(report.markdown.utf8).write(to: calibrationReportURL, options: .atomic)
        return report
    }

    private func unevaluatedMealIDs(in split: ReferenceMeal.Split) throws -> [ReferenceMeal.ID] {
        let evaluatedIDs = Set(try evaluations().map(\.referenceMealID))
        return try referenceMeals().filter { $0.split == split && !evaluatedIDs.contains($0.id) }.map(\.id)
    }

    // MARK: Pass criteria and validation

    /// Writes down the pass criteria, once, after every calibration meal is evaluated and before any validation
    /// scoring. They must limit calorie, protein, carbohydrate and fat error at both stages, and the calibration
    /// set must span at least two cuisines and two dish types. From then on calibration is closed.
    @discardableResult
    public func freezePassCriteria(_ criteria: [PassCriterion], on date: Date) throws -> FrozenPassCriteria {
        guard !validationScored else { throw CalibrationPilotError.validationAlreadyScored }
        guard try frozenPassCriteria() == nil else { throw CalibrationPilotError.passCriteriaAlreadyFrozen }
        guard !criteria.isEmpty else { throw CalibrationPilotError.noPassCriteria }
        if let invalid = criteria.first(where: { !$0.isValid }) {
            throw CalibrationPilotError.invalidPassCriterion(invalid)
        }
        let missing = RequiredCriterion.missing(from: criteria)
        guard missing.isEmpty else { throw CalibrationPilotError.missingNutrientCriteria(missing) }
        let calibration = try calibrationRecords()
        let notEvaluated = try unevaluatedMealIDs(in: .calibration)
        guard !calibration.meals.isEmpty, notEvaluated.isEmpty else {
            throw CalibrationPilotError.calibrationIncomplete(notEvaluated: notEvaluated)
        }
        try Self.checkDiverse(calibration.meals, else: CalibrationPilotError.calibrationNotDiverse)
        let frozen = FrozenPassCriteria(
            criteria: criteria,
            frozenOn: date,
            calibrationMealIDs: calibration.meals.map(\.id),
            calibrationFingerprint: try calibration.fingerprint()
        )
        try Self.encoder.encode(frozen).write(to: passCriteriaURL, options: .atomic)
        return frozen
    }

    /// The frozen pass criteria; nil until frozen.
    public func frozenPassCriteria() throws -> FrozenPassCriteria? {
        guard FileManager.default.fileExists(atPath: passCriteriaURL.path) else { return nil }
        return try Self.decoder.decode(FrozenPassCriteria.self, from: Data(contentsOf: passCriteriaURL))
    }

    /// Scores the held-out validation set against the frozen pass criteria, once, and writes validation-report.md
    /// and estimate-reliability.json (the accuracy claim the app may make). Refused until the criteria are frozen
    /// and every validation meal is evaluated; if the validation set spans fewer than two cuisines or dish types
    /// or reuses a calibration meal's photo; and if the calibration records have changed since freezing.
    @discardableResult
    public func scoreValidation(on date: Date) throws -> ValidationScore {
        guard !validationScored else { throw CalibrationPilotError.validationAlreadyScored }
        guard let frozen = try frozenPassCriteria() else { throw CalibrationPilotError.passCriteriaNotFrozen }
        guard try calibrationRecords().fingerprint() == frozen.calibrationFingerprint else {
            throw CalibrationPilotError.calibrationChangedSincePassCriteriaFrozen
        }
        let notEvaluated = try unevaluatedMealIDs(in: .validation)
        guard notEvaluated.isEmpty else { throw CalibrationPilotError.validationIncomplete(notEvaluated: notEvaluated) }
        let validationMeals = try referenceMeals().filter { $0.split == .validation }
        try Self.checkDiverse(validationMeals, else: CalibrationPilotError.validationNotDiverse)
        try checkNoCalibrationPhotoIsReused(by: validationMeals)
        let report = try AccuracyReport(split: .validation, meals: referenceMeals(), evaluations: evaluations())
        let score = ValidationScore(
            report: report,
            criteria: frozen,
            scoredOn: date,
            results: frozen.criteria.map { CriterionResult(criterion: $0, measurements: $0.measurements(in: report)) }
        )
        try Self.encoder.encode(score.reliability).write(to: estimateReliabilityURL, options: .atomic)
        try Data(score.markdown.utf8).write(to: validationReportURL, options: .atomic)
        return score
    }

    /// Each set of the study must span at least two cuisines and two dish types.
    private static func checkDiverse(
        _ meals: [ReferenceMeal], else error: (_ cuisineCount: Int, _ dishTypeCount: Int) -> CalibrationPilotError
    ) throws {
        let cuisineCount = Set(meals.map(\.cuisine)).count
        let dishTypeCount = Set(meals.map(\.dishType)).count
        guard cuisineCount >= 2, dishTypeCount >= 2 else { throw error(cuisineCount, dishTypeCount) }
    }

    /// Either file of a scored validation set means it was scored, even if writing the other failed.
    private var validationScored: Bool {
        [validationReportURL, estimateReliabilityURL].contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func calibrationRecords() throws -> CalibrationRecords {
        let meals = try referenceMeals().filter { $0.split == .calibration }
        let ids = Set(meals.map(\.id))
        return CalibrationRecords(meals: meals, evaluations: try evaluations().filter { ids.contains($0.referenceMealID) })
    }

    // MARK: Files

    var referenceMealsDirectory: URL { directory.appendingPathComponent("reference-meals", isDirectory: true) }
    var photosDirectory: URL { directory.appendingPathComponent("photos", isDirectory: true) }
    var evaluationsDirectory: URL { directory.appendingPathComponent("evaluations", isDirectory: true) }
    var passCriteriaURL: URL { directory.appendingPathComponent("pass-criteria.json") }
    var calibrationReportURL: URL { directory.appendingPathComponent("calibration-report.md") }
    var validationReportURL: URL { directory.appendingPathComponent("validation-report.md") }
    var estimateReliabilityURL: URL { directory.appendingPathComponent("estimate-reliability.json") }

    private func evaluationURL(for mealID: ReferenceMeal.ID) -> URL {
        evaluationsDirectory.appendingPathComponent("\(mealID).json")
    }

    private func jsonFiles(in folder: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
    }
}

public enum CalibrationPilotError: Error, Equatable {
    case invalidReferenceMeal(ReferenceMeal.ID, ReferenceMealProblem)
    /// Two reference meal files share an ID.
    case duplicateReferenceMeal(ReferenceMeal.ID)
    /// Reference meals name one cuisine or dish type in ways that differ only in case or surrounding spaces, so
    /// it would count, and be reported, as several. The names as written, sorted.
    case inconsistentGroupName(ReportGrouping, [String])
    /// Two evaluation files are for the same reference meal, which would count it twice.
    case duplicateEvaluation(ReferenceMeal.ID)
    /// A reference meal names a photo that is not in the photos folder.
    case missingPhoto(String)
    /// A validation meal's photo is identical to a calibration meal's, so it is not a new meal.
    case validationMealReusesCalibrationPhoto(ReferenceMeal.ID, photoFileName: String)
    case unknownReferenceMeal(ReferenceMeal.ID)
    /// The meal already has a recorded evaluation.
    case alreadyEvaluated(ReferenceMeal.ID)
    /// Calibration meals are not evaluated once the pass criteria are frozen.
    case calibrationClosed
    case noPassCriteria
    /// A criterion has no rationale, a negative or infinite limit, or measures correction time before review.
    case invalidPassCriterion(PassCriterion)
    /// The criteria set no limit for these nutrients at these stages.
    case missingNutrientCriteria([RequiredCriterion])
    case passCriteriaAlreadyFrozen
    /// Pass criteria are frozen only once every calibration meal is evaluated.
    case calibrationIncomplete(notEvaluated: [ReferenceMeal.ID])
    /// The calibration set must span at least two cuisines and two dish types.
    case calibrationNotDiverse(cuisineCount: Int, dishTypeCount: Int)
    /// The validation set has been scored: it is scored once, and criteria can no longer be set before seeing it.
    case validationAlreadyScored
    /// Validation meals are evaluated and scored only once the pass criteria are frozen.
    case passCriteriaNotFrozen
    case validationIncomplete(notEvaluated: [ReferenceMeal.ID])
    /// The validation set must span at least two cuisines and two dish types.
    case validationNotDiverse(cuisineCount: Int, dishTypeCount: Int)
    /// Calibration meals or evaluations differ from those the pass criteria were frozen against.
    case calibrationChangedSincePassCriteriaFrozen
}

/// The calibration meals and their evaluations, as the pass criteria are set from them.
private struct CalibrationRecords: Encodable {
    var meals: [ReferenceMeal]
    var evaluations: [MealEvaluation]

    /// FNV-1a over the records' stable JSON. It detects changes, not tampering: the pilot's version history
    /// remains the record of when the criteria were frozen.
    func fingerprint() throws -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in try CalibrationPilot.encoder.encode(self) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

/// Why a reference meal cannot be used in the study.
public enum ReferenceMealProblem: Equatable, Sendable {
    /// The ID is blank or not usable as a file name.
    case invalidID
    case noParticipantCode
    /// The participant's consent does not cover uploading the meal photos for photo analysis.
    case photoUploadNotConsented
    /// No cuisine or no dish type, so the meal cannot be reported by them.
    case missingCuisineOrDishType
    case noPhotos
    case noReferenceFoods
    /// A reference food has a blank or repeated ID, no positive weight, or nutrients that are negative or not
    /// finite.
    case invalidReferenceFood(ReferenceFood.ID)
}

extension ReferenceMeal {
    var problem: ReferenceMealProblem? {
        if id.isBlank || id.contains(where: { "/\\:".contains($0) }) { return .invalidID }
        if consent.participantCode.isBlank { return .noParticipantCode }
        if !consent.coversPhotoAnalysisUpload { return .photoUploadNotConsented }
        if cuisine.isBlank || dishType.isBlank { return .missingCuisineOrDishType }
        if photoFileNames.isEmpty { return .noPhotos }
        if referenceFoods.isEmpty { return .noReferenceFoods }
        var foodIDs = Set<ReferenceFood.ID>()
        for food in referenceFoods {
            let nutrients = food.nutrientsPer100g
            let values = [food.grams, nutrients.calories, nutrients.protein, nutrients.carbohydrates, nutrients.fat]
            guard !food.id.isBlank, foodIDs.insert(food.id).inserted,
                  values.allSatisfy({ $0.isFinite && $0 >= 0 }), food.grams > 0 else {
                return .invalidReferenceFood(food.id)
            }
        }
        return nil
    }
}

extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
