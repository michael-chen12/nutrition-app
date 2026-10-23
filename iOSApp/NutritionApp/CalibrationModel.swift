import Foundation
import NutritionCalibration
import NutritionCore
import Observation

/// Observable mirror of a calibration pilot for the developer calibration screens (ticket #12). Holds no
/// decisions of its own: the pilot's protocol and `CalibrationTrial` live in NutritionCalibration.
@Observable
@MainActor
final class CalibrationModel: Identifiable {
    let id = UUID()
    private let pilot: CalibrationPilot
    private let gateway: MealAnalysisGateway
    /// Where trial meal entries are saved, apart from the person's meal history.
    private let trialStoreDirectory: URL

    private(set) var meals: [ReferenceMeal] = []
    private(set) var evaluatedMealIDs: Set<ReferenceMeal.ID> = []
    /// Meals a trial can be run for now (the pilot decides: calibration before the freeze, validation after).
    private(set) var mealIDsOpenForTrial: Set<ReferenceMeal.ID> = []
    private(set) var calibrationReport: String?
    var errorMessage: String?

    /// The trial in progress, and the meal entry model the person reviews it in.
    private(set) var trial: CalibrationTrial?
    private(set) var trialReview: MealEntryModel?
    private(set) var isAnalyzing = false

    init(pilotDirectory: URL, trialStoreDirectory: URL, gateway: MealAnalysisGateway) {
        pilot = CalibrationPilot(directory: pilotDirectory)
        self.trialStoreDirectory = trialStoreDirectory
        self.gateway = gateway
        reload()
    }

    /// The pilot in the app's Documents folder (shared through Finder and the Files app), analyzed through the
    /// same backend as everyday meal entries.
    static func makeDefault() -> CalibrationModel {
        CalibrationModel(
            pilotDirectory: .documentsDirectory.appending(path: "CalibrationPilot"),
            trialStoreDirectory: .applicationSupportDirectory.appending(path: "CalibrationTrials"),
            gateway: HTTPMealAnalysisGateway(backendURL: NutritionApp.analysisBackendURL)
        )
    }

    var pilotFolderName: String { pilot.directory.lastPathComponent }

    func reload() {
        do {
            try FileManager.default.createDirectory(at: pilot.directory, withIntermediateDirectories: true)
            meals = try pilot.referenceMeals()
            evaluatedMealIDs = Set(try pilot.evaluations().map(\.referenceMealID))
            mealIDsOpenForTrial = Set(try pilot.mealsOpenForTrial())
            calibrationReport = try pilot.calibrationReport().markdown
            errorMessage = nil
        } catch {
            errorMessage = "The pilot can't be read: \(error)"
        }
    }

    /// Uploads the meal's photos for one analysis (recording the pre-review estimate) and opens its review.
    func startTrial(_ meal: ReferenceMeal) async {
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let trial = try CalibrationTrial(
                referenceMeal: meal,
                photos: try pilot.photos(for: meal),
                gateway: gateway,
                store: try FileMealHistoryStore(directory: trialStoreDirectory.appending(path: meal.id))
            )
            try await trial.analyzePhotos()
            let review = MealEntryModel(workflow: trial.workflow)
            review.refreshDraftReview()
            self.trial = trial
            trialReview = review
            errorMessage = nil
        } catch {
            errorMessage = "The trial can't start: \(error)"
        }
    }

    /// Whether the person saved the trial's reviewed meal entry.
    var isTrialMealEntrySaved: Bool { trial?.isMealEntrySaved ?? false }

    /// Records the trial's evaluation with the developer's missed-food labels and closes the trial.
    func finishTrial(missedByAnalysis: Set<ReferenceFood.ID>, missedAfterReview: Set<ReferenceFood.ID>) {
        guard let trial else { return }
        do {
            try pilot.record(try trial.finish(missedByAnalysis: missedByAnalysis, missedAfterReview: missedAfterReview))
            discardTrial()
            reload()
        } catch {
            errorMessage = "The evaluation can't be recorded: \(error)"
        }
    }

    /// Ends the trial without recording it; the meal can be run again.
    func discardTrial() {
        trial = nil
        trialReview = nil
    }
}
