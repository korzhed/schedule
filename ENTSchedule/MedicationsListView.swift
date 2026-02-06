import SwiftUI

struct MedicationsListView: View {
    
    @EnvironmentObject private var appState: AppState
    @State private var selectedMedication: MedicationItem?
    
    // Собираем все лекарства из всех курсов
    private var allMedications: [MedicationItem] {
        var medications: [MedicationItem] = []
        for course in appState.courses {
            medications.append(contentsOf: course.medications)
        }
        return medications
    }
    
    var body: some View {
        Group {
            if allMedications.isEmpty {
                VStack(spacing: 24) {
                    ContentUnavailableView(
                        "Нет лекарств",
                        systemImage: "pills",
                        description: Text("Добавьте первое назначение, чтобы увидеть список лекарств.")
                    )
                    Spacer()
                }
                .padding(.top, 32)
            } else {
                List {
                    ForEach(allMedications) { medication in
                        Button {
                            selectedMedication = medication
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(medication.name)
                                    .font(.headline)
                                
                                HStack {
                                    Label(medication.dosage, systemImage: "scalemass")
                                    Text("•")
                                    Label("\(medication.timesPerDay) раз/день", systemImage: "clock")
                                    Text("•")
                                    Label("\(medication.durationInDays) дней", systemImage: "calendar")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                
                                if let comment = medication.comment, !comment.isEmpty {
                                    Text(comment)
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .padding(.vertical, 4)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Все лекарства")
        .sheet(item: $selectedMedication) { medication in
            NavigationStack {
                MedicationInfoView(medication: medication) { newName in
                    updateMedicationName(id: medication.id, newName: newName)
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
    
    /// Обновляем название лекарства во всех курсах, где оно встречается
    private func updateMedicationName(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        for index in appState.courses.indices {
            var course = appState.courses[index]
            var changed = false
            
            for medIndex in course.medications.indices {
                if course.medications[medIndex].id == id {
                    course.medications[medIndex].name = trimmed
                    changed = true
                }
            }
            
            if changed {
                appState.courses[index] = course
            }
        }
    }
}

// Отдельный view для просмотра и редактирования информации

struct MedicationInfoView: View {
    
    @Environment(\.dismiss) private var dismiss
    
    let medication: MedicationItem
    let onRename: (String) -> Void
    
    @State private var editedName: String = ""
    
    var body: some View {
        Form {
            Section("Основная информация") {
                TextField("Название", text: $editedName)
                LabeledContent("Дозировка", value: medication.dosage)
                LabeledContent("Раз в день", value: "\(medication.timesPerDay)")
                LabeledContent("Длительность", value: "\(medication.durationInDays) дней")
            }
            
            if let comment = medication.comment, !comment.isEmpty {
                Section("Комментарий") {
                    Text(comment)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            editedName = medication.name
        }
        .navigationTitle("Информация")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") {
                    onRename(editedName)
                    dismiss()
                }
                .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

struct MedicationsListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MedicationsListView()
                .environmentObject(AppState())
        }
    }
}
