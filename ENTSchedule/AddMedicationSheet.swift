// AddMedicationSheet.swift
// Created to fix missing view error in ScheduleStepView

import SwiftUI

struct AddMedicationSheet: View {
    let slotIndex: Int
    let availableMedications: [MedicationItem]
    let onAdd: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(availableMedications) { medication in
                Button {
                    onAdd(medication.id)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(medication.name)
                            .font(.headline)
                        Text(medication.dosage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let comment = medication.comment, !comment.isEmpty {
                            Text(comment)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Добавить лекарство")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#if DEBUG
struct AddMedicationSheet_Previews: PreviewProvider {
    static var previews: some View {
        AddMedicationSheet(
            slotIndex: 1,
            availableMedications: [
                MedicationItem(id: UUID(), name: "Пример 1", dosage: "10 мг", timesPerDay: 1, durationInDays: 5, comment: "Пить после еды"),
                MedicationItem(id: UUID(), name: "Пример 2", dosage: "20 мг", timesPerDay: 2, durationInDays: 7, comment: nil)
            ],
            onAdd: { _ in }
        )
    }
}
#endif
