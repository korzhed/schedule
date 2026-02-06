//
// MedicationDetailView.swift
// ENTSchedule
//

import SwiftUI

struct MedicationDetailView: View {

    @Binding var medication: MedicationItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Основное") {
                TextField("Название", text: $medication.name)
                TextField("Дозировка (например, 3 капли)", text: $medication.dosage)

                Stepper(
                    "Приёмов в день: \(medication.timesPerDay)",
                    value: $medication.timesPerDay,
                    in: 1...10
                )

                Stepper(
                    "Длительность (дней): \(medication.durationInDays)",
                    value: $medication.durationInDays,
                    in: 1...60
                )
            }

            Section("Комментарий") {
                TextField(
                    "Например: в каждую ноздрю",
                    text: Binding(
                        get: { medication.comment ?? "" },
                        set: { medication.comment = $0.isEmpty ? nil : $0 }
                    ),
                    axis: .vertical
                )
                .lineLimit(2...4)
            }
        }
        .navigationTitle(medication.name.isEmpty ? "Лекарство" : medication.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") {
                    dismiss()
                }
            }
        }
    }
}
