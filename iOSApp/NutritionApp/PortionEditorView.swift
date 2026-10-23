import NutritionCore
import SwiftUI

/// Amount and unit fields for a portion: grams or one of the food's serving units. Each serving unit shows its
/// documented quantity basis ("1 cup = 158 g"); a unit without a known gram weight shows why it can't be used.
struct PortionFields: View {
    let units: [PresentedPortionUnit]
    @Binding var unit: PortionUnit
    @Binding var quantity: Double?

    private var selected: PresentedPortionUnit? { units.first { $0.unit == unit } }

    var body: some View {
        Picker("Unit", selection: $unit) {
            ForEach(units) { option in
                Text(option.name).tag(option.unit)
            }
        }
        TextField("Amount (\(selected?.name ?? "g"))", value: $quantity, format: .number)
            .keyboardType(.decimalPad)
        if let basis = selected?.quantityBasis {
            Text(basis).font(.caption).foregroundStyle(.secondary)
        }
        if let note = selected?.conversionUnavailableNote {
            Text(note).font(.caption).foregroundStyle(.orange)
        }
    }

    /// True when the chosen unit can convert to grams and an amount is entered.
    var canSubmit: Bool {
        quantity != nil && selected?.conversionUnavailableNote == nil
    }
}

/// Corrects a reviewed food's portion; the nutrition estimate updates as soon as it is applied.
struct PortionEditorView: View {
    @Bindable var model: MealEntryModel
    let food: PresentedReviewedFood
    @Environment(\.dismiss) private var dismiss

    @State private var unit: PortionUnit
    @State private var quantity: Double?

    init(model: MealEntryModel, food: PresentedReviewedFood) {
        self.model = model
        self.food = food
        _unit = State(initialValue: food.selectedPortionUnit)
        _quantity = State(initialValue: food.portionQuantity)
    }

    var body: some View {
        let fields = PortionFields(units: food.portionUnits, unit: $unit, quantity: $quantity)
        NavigationStack {
            Form {
                Section {
                    fields
                } header: {
                    Text(food.name)
                } footer: {
                    Text("Currently \(food.portion) · \(SourceLabel.text(food.sourceName, food.sourceRecordID))")
                }
                if let message = model.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
            }
            .navigationTitle("Portion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        guard let quantity else { return }
                        model.changePortion(of: food.id, quantity: quantity, unit: unit)
                        if model.errorMessage == nil { dismiss() }
                    }
                    .disabled(!fields.canSubmit)
                }
            }
        }
    }
}
