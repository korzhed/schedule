import SwiftUI
    //тест
struct AddMedicationSheet: View {

    let slotIndex: Int
    let parsedMedications: [MedicationItem]   // остаются в сигнатуре, чтобы не ломать вызовы
    let slotMedications: [Int: Set<UUID>]     // тоже оставляем для совместимости

    let onAddFromList: (UUID) -> Void        // не используется, но оставляем
    let onAddManual: (MedicationItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var dosage: String = ""
    @State private var comment: String = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !dosage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Новое лекарство") {
                    TextField("Название лекарства", text: $name)
                    TextField("Дозировка", text: $dosage)
                    TextField("Комментарий (по желанию)", text: $comment)
                }
            }
            .navigationTitle("Добавить лекарство")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard canSave else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDosage = dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)

        let item = MedicationItem(
            id: UUID(),
            name: trimmedName,
            dosage: trimmedDosage,
            timesPerDay: 1,
            durationInDays: 7,
            comment: trimmedComment.isEmpty ? nil : trimmedComment
        )

        onAddManual(item)
        dismiss()
    }
}

#if DEBUG
struct AddMedicationSheet_Previews: PreviewProvider {
    static var previews: some View {
        AddMedicationSheet(
            slotIndex: 1,
            parsedMedications: [],
            slotMedications: [:],
            onAddFromList: { _ in },
            onAddManual: { _ in }
        )
    }
}
#endif

