import SwiftUI

struct EditCourseFlow: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let course: Course
    let onComplete: (Course) -> Void

    @State private var courseName: String
    @State private var startDate: Date
    @State private var remindersEnabled: Bool
    @State private var reminderOffsetMinutes: Int
    @State private var totalDurationInDays: Int

    @State private var slotTimes: [Int: Date] = [:]
    @State private var slotMedications: [Int: Set<UUID>] = [:]
    @State private var medications: [MedicationItem]

    @State private var showAddMedication: Bool = false
    @State private var selectedSlotForAdding: Int? = nil
    @State private var showAddFromText: Bool = false

    init(course: Course, onComplete: @escaping (Course) -> Void) {
        self.course = course
        self.onComplete = onComplete

        _startDate = State(initialValue: course.startDate)
        _remindersEnabled = State(initialValue: course.remindersEnabled)
        _reminderOffsetMinutes = State(initialValue: course.reminderOffsetMinutes)
        _courseName = State(
            initialValue: course.name
            ?? course.medications.map { $0.name }.joined(separator: ", ")
        )
        _medications = State(initialValue: course.medications)
        _totalDurationInDays = State(initialValue: course.totalDurationInDays)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название курса") {
                    TextField("Например: Курс от ЛОРа", text: $courseName)
                }

                Section("Дата начала") {
                    DatePicker(
                        "Начало курса",
                        selection: $startDate,
                        displayedComponents: [.date]
                    )
                }

                Section("Длительность курса") {
                    Stepper(
                        value: $totalDurationInDays,
                        in: 1...180
                    ) {
                        let weeks = Double(totalDurationInDays) / 7.0
                        if totalDurationInDays % 7 == 0 {
                            Text("\(totalDurationInDays) дней (\(Int(weeks)) нед.)")
                        } else {
                            Text("\(totalDurationInDays) дней (~\(String(format: "%.1f", weeks)) нед.)")
                        }
                    }
                }

                ForEach(course.doseSlots.sorted(by: { $0.indexInDay < $1.indexInDay })) { slot in
                    Section {
                        HStack {
                            Text("Время приёма")
                            Spacer()
                            DatePicker(
                                "",
                                selection: Binding(
                                    get: {
                                        slotTimes[slot.indexInDay] ?? timeFromComponents(slot.time)
                                    },
                                    set: { slotTimes[slot.indexInDay] = $0 }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                        }

                        let meds = getMedications(for: slot.indexInDay)
                        if meds.isEmpty {
                            Text("Нет лекарств в этом приёме")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(meds) { med in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(med.name)
                                            .font(.body)
                                        Text(med.dosage)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Button(role: .destructive) {
                                        removeMedication(med.id, from: slot.indexInDay)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }

                        Button {
                            selectedSlotForAdding = slot.indexInDay
                            showAddMedication = true
                        } label: {
                            Label("Добавить лекарство", systemImage: "plus.circle")
                        }
                    } header: {
                        Text("Приём \(slot.indexInDay)")
                    }
                }

                Section("Напоминания") {
                    Toggle("Включить напоминания", isOn: $remindersEnabled)

                    if remindersEnabled {
                        Picker("За сколько минут до приёма", selection: $reminderOffsetMinutes) {
                            Text("В момент приёма").tag(0)
                            Text("За 5 минут").tag(5)
                            Text("За 10 минут").tag(10)
                            Text("За 30 минут").tag(30)
                        }
                    }
                }
            }
            .navigationTitle("Редактирование курса")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        let updated = saveChanges()
                        onComplete(updated)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAddMedication) {
                if let slotIndex = selectedSlotForAdding {
                    MedicationPickerView(
                        allMedications: $medications,
                        selectedMedicationIds: Binding(
                            get: { slotMedications[slotIndex] ?? [] },
                            set: { slotMedications[slotIndex] = $0 }
                        ),
                        onClose: { showAddMedication = false }
                    )
                    .presentationDetents([.medium, .large])
                }
            }
        }
    }

    // MARK: - Helpers

    private func timeFromComponents(_ components: DateComponents) -> Date {
        let calendar = Calendar.current
        let now = Date()
        var base = calendar.dateComponents([.year, .month, .day], from: now)
        base.hour = components.hour ?? 9
        base.minute = components.minute ?? 0
        return calendar.date(from: base) ?? now
    }

    private func getMedications(for slotIndex: Int) -> [MedicationItem] {
        let selectedIds = slotMedications[slotIndex] ?? Set(
            course.courseMedications
                .filter { $0.slotIndexes.contains(slotIndex) }
                .map { $0.medicationId }
        )
        return medications.filter { selectedIds.contains($0.id) }
    }

    private func removeMedication(_ medicationId: UUID, from slotIndex: Int) {
        var set = slotMedications[slotIndex] ?? Set(
            course.courseMedications
                .filter { $0.slotIndexes.contains(slotIndex) }
                .map { $0.medicationId }
        )
        set.remove(medicationId)
        slotMedications[slotIndex] = set
    }

    private func saveChanges() -> Course {
        var updated = course
        updated.startDate = startDate
        updated.name = courseName.isEmpty ? nil : courseName
        updated.totalDurationInDays = totalDurationInDays
        updated.remindersEnabled = remindersEnabled
        updated.reminderOffsetMinutes = reminderOffsetMinutes
        // TODO: при необходимости добавить сохранение изменений расписания и лекарств
        return updated
    }
}

// Пример пикера лекарств для добавления в приём
struct MedicationPickerView: View {
    @Binding var allMedications: [MedicationItem]
    @Binding var selectedMedicationIds: Set<UUID>
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(allMedications) { med in
                    Button {
                        toggleSelection(med.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(med.name)
                                Text(med.dosage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedMedicationIds.contains(med.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Выбор лекарств")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { onClose() }
                }
            }
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedMedicationIds.contains(id) {
            selectedMedicationIds.remove(id)
        } else {
            selectedMedicationIds.insert(id)
        }
    }
}
