import Foundation
import NutritionCore

/// One reference meal run through the real meal entry workflow, the way a person uses the app.
///
/// `analyzePhotos()` starts a meal entry with the reference meal's photos and uploads them together for one
/// photo analysis. The pre-review estimate is recorded at that moment, before the person changes anything. The
/// person then reviews through `workflow` (accepting, correcting, answering questions, adding foods) and saves the
/// meal entry as usual; correction time ends there. The developer then labels which reference foods each stage
/// missed and calls `finish` to get the evaluation.
public final class CalibrationTrial {
    public let referenceMeal: ReferenceMeal
    /// The meal entry workflow the person reviews the trial meal in. It saves to the trial's own store, not the
    /// person's meal history.
    public let workflow: MealEntryWorkflow
    private let photos: [TrialPhoto]
    private let store: SaveRecordingStore
    private let now: () -> Date
    private var preReview: PreReviewEstimate?
    private var photoAnalysisMessage: String?
    /// When the photo suggestions were shown: the start of correction time.
    private var suggestionsShownAt: Date?

    /// Throws `photoUploadNotConsented` unless the participant's consent covers uploading the meal photos.
    public init(
        referenceMeal: ReferenceMeal,
        photos: [TrialPhoto],
        gateway: MealAnalysisGateway,
        store: MealHistoryStore,
        now: @escaping () -> Date = Date.init
    ) throws {
        guard referenceMeal.consent.coversPhotoAnalysisUpload else {
            throw CalibrationTrialError.photoUploadNotConsented(referenceMealID: referenceMeal.id)
        }
        self.referenceMeal = referenceMeal
        self.photos = photos
        self.store = SaveRecordingStore(store, now: now)
        self.now = now
        workflow = MealEntryWorkflow(store: self.store, gateway: gateway, now: now)
    }

    /// Starts the trial's meal entry, uploads all its photos for one analysis and records the pre-review estimate.
    /// A failed analysis records an empty pre-review estimate; the person can still review the meal manually.
    @discardableResult
    public func analyzePhotos() async throws -> PhotoAnalysisPresentation {
        workflow.startNewMealEntry()
        let photoIDs = photos.map { workflow.importPhoto($0.data, fileExtension: $0.fileExtension) }
        workflow.acceptPhotoAnalysisDisclosure()
        let analysis = try await workflow.analyzePhotos(photoIDs)
        preReview = workflow.preReviewEstimate
        photoAnalysisMessage = analysis.message
        suggestionsShownAt = now()
        return analysis
    }

    /// The person has saved the reviewed meal entry, so the trial can be finished.
    public var isMealEntrySaved: Bool {
        store.lastSave != nil
    }

    /// The evaluation of the saved meal entry. Labels naming foods outside the reference meal are refused, and
    /// can be corrected and finished again.
    ///
    /// - Parameters:
    ///   - missedByAnalysis: Reference foods no photo suggestion stood for, as judged by the developer.
    ///   - missedAfterReview: Reference foods still missing from the reviewed meal entry.
    public func finish(
        missedByAnalysis: Set<ReferenceFood.ID>,
        missedAfterReview: Set<ReferenceFood.ID>
    ) throws -> MealEvaluation {
        guard let preReview, let suggestionsShownAt else { throw CalibrationTrialError.photosNotAnalyzed }
        guard let save = store.lastSave else { throw CalibrationTrialError.mealEntryNotSaved }
        let referenceFoodIDs = Set(referenceMeal.referenceFoods.map(\.id))
        if let unknown = missedByAnalysis.union(missedAfterReview).subtracting(referenceFoodIDs).sorted().first {
            throw CalibrationTrialError.unknownReferenceFood(unknown)
        }
        return MealEvaluation(
            referenceMealID: referenceMeal.id,
            preReview: StageResult(nutritionEstimate: preReview.nutritionEstimate, missedReferenceFoodIDs: missedByAnalysis),
            reviewed: StageResult(nutritionEstimate: save.entry.nutritionEstimate, missedReferenceFoodIDs: missedAfterReview),
            correctionTime: save.date.timeIntervalSince(suggestionsShownAt),
            suggestionsWithoutEstimate: preReview.suggestionsWithoutEstimate,
            customFoodsAfterReview: save.entry.reviewedFoods.filter { $0.food.source == .custom }.map(\.food.name),
            photoAnalysisMessage: photoAnalysisMessage
        )
    }
}

/// A reference meal photo's image bytes.
public struct TrialPhoto: Hashable, Sendable {
    public var data: Data
    /// e.g. "jpg" or "heic".
    public var fileExtension: String

    public init(data: Data, fileExtension: String) {
        self.data = data
        self.fileExtension = fileExtension
    }
}

public enum CalibrationTrialError: Error, Equatable {
    /// The participant's consent does not cover uploading the meal photos for photo analysis.
    case photoUploadNotConsented(referenceMealID: ReferenceMeal.ID)
    /// `finish` was called before `analyzePhotos()`.
    case photosNotAnalyzed
    /// `finish` was called before the person saved the reviewed meal entry.
    case mealEntryNotSaved
    /// A missed food named in `finish` is not one of the reference meal's foods.
    case unknownReferenceFood(ReferenceFood.ID)
}

/// The trial's store, noting when the person saves the reviewed meal entry and what it then contained.
private final class SaveRecordingStore: MealHistoryStore {
    private let store: MealHistoryStore
    private let now: () -> Date
    private(set) var lastSave: (entry: MealEntry, date: Date)?

    init(_ store: MealHistoryStore, now: @escaping () -> Date) {
        self.store = store
        self.now = now
    }

    func save(_ entry: MealEntry, photoData: [MealPhoto.ID: Data]) throws {
        try store.save(entry, photoData: photoData)
        lastSave = (entry, now())
    }

    func mealEntries() throws -> [MealEntry] { try store.mealEntries() }

    func mealEntry(id: MealEntry.ID) throws -> MealEntry? { try store.mealEntry(id: id) }

    func photoData(for photo: MealPhoto) throws -> Data { try store.photoData(for: photo) }
}
