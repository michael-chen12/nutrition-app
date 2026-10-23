import NutritionCalibration
import NutritionCore
import SwiftUI

/// Developer screen for the calibration pilot (debug builds only): run a reference meal as a trial, review it in
/// the usual meal entry review, then label which reference foods each stage missed.
struct CalibrationPilotView: View {
    @Bindable var model: CalibrationModel
    @Environment(\.dismiss) private var dismiss
    @State private var isReviewing = false
    @State private var isLabelling = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Copy a pilot folder named \(model.pilotFolderName) into this app's files (Finder or the "
                        + "Files app), then run each reference meal. See docs/calibration/README.md.")
                        .font(.footnote)
                }
                mealSection("Calibration meals", split: .calibration)
                mealSection("Validation meals", split: .validation)
                if let report = model.calibrationReport {
                    Section("Calibration report") {
                        NavigationLink("Show report") {
                            ScrollView {
                                Text(report).font(.caption.monospaced()).textSelection(.enabled).padding()
                            }
                        }
                    }
                }
                if let message = model.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
            }
            .navigationTitle("Calibration pilot")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Reload", systemImage: "arrow.clockwise", action: model.reload) }
            }
            .overlay {
                if model.isAnalyzing { ProgressView("Analyzing photos…") }
            }
            .sheet(isPresented: $isReviewing, onDismiss: reviewEnded) {
                if let review = model.trialReview {
                    NewMealEntryView(model: review, isPresented: $isReviewing, title: "Review trial meal")
                }
            }
            .sheet(isPresented: $isLabelling) {
                if let meal = model.trial?.referenceMeal {
                    TrialLabelsView(model: model, meal: meal, isPresented: $isLabelling)
                }
            }
        }
    }

    private func mealSection(_ title: String, split: ReferenceMeal.Split) -> some View {
        Section(title) {
            ForEach(model.meals.filter { $0.split == split }) { meal in
                let isEvaluated = model.evaluatedMealIDs.contains(meal.id)
                Button {
                    Task {
                        await model.startTrial(meal)
                        isReviewing = model.trialReview != nil
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(meal.id)
                            Text("\(meal.cuisine) · \(meal.dishType)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isEvaluated { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                }
                .disabled(!model.mealIDsOpenForTrial.contains(meal.id) || model.isAnalyzing)
            }
        }
    }

    /// Saved: label the missed foods. Cancelled: the trial is dropped and the meal can be run again.
    private func reviewEnded() {
        if model.isTrialMealEntrySaved {
            isLabelling = true
        } else {
            model.discardTrial()
        }
    }
}

/// The developer marks which reference foods photo analysis found and which the saved meal entry includes.
struct TrialLabelsView: View {
    let model: CalibrationModel
    let meal: ReferenceMeal
    @Binding var isPresented: Bool
    @State private var foundByAnalysis: Set<ReferenceFood.ID>
    @State private var inReviewedEntry: Set<ReferenceFood.ID>

    init(model: CalibrationModel, meal: ReferenceMeal, isPresented: Binding<Bool>) {
        self.model = model
        self.meal = meal
        _isPresented = isPresented
        _foundByAnalysis = State(initialValue: Self.foodIDs(of: meal))
        _inReviewedEntry = State(initialValue: Self.foodIDs(of: meal))
    }

    private static func foodIDs(of meal: ReferenceMeal) -> Set<ReferenceFood.ID> {
        Set(meal.referenceFoods.map(\.id))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(meal.referenceFoods) { food in
                        VStack(alignment: .leading) {
                            Text(food.name)
                            Text("\(food.grams, format: .number) g").font(.caption).foregroundStyle(.secondary)
                            Toggle("Found by photo analysis", isOn: membership(food.id, in: $foundByAnalysis))
                            Toggle("In the reviewed meal entry", isOn: membership(food.id, in: $inReviewedEntry))
                        }
                    }
                } footer: {
                    Text("Turn off a reference food no photo suggestion stood for, or one the saved meal entry "
                        + "left out.")
                }
                if let message = model.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
            }
            .navigationTitle(meal.id)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        model.discardTrial()
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Record") {
                        let all = Self.foodIDs(of: meal)
                        model.finishTrial(
                            missedByAnalysis: all.subtracting(foundByAnalysis),
                            missedAfterReview: all.subtracting(inReviewedEntry)
                        )
                        if model.trial == nil { isPresented = false }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func membership(_ id: ReferenceFood.ID, in set: Binding<Set<ReferenceFood.ID>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { isOn in
                if isOn { set.wrappedValue.insert(id) } else { set.wrappedValue.remove(id) }
            }
        )
    }
}
