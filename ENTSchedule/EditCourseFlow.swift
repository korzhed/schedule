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
    
    private var currentDoseSlots: [DoseSlot] {
        let maxSlots = medications.map { $0.timesPerDay }.max() ?? 0
        return (1...maxSlots).map { i in
            if let original = course.doseSlots.first(where: { $0.indexInDay == i }) {
                return original
            } else {
                // Создаём новый слот с дефолтным временем (например, 9:00/10:00/...) и нужным номером
                let hour = 9 + (i - 1)
                let comps = DateComponents(hour: hour, minute: 0)
                return DoseSlot(id: UUID(), indexInDay: i, time: comps)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                
                // ЛЕКАРСТВА
                Section("Лекарства") {
                    ForEach($medications) { $med in
                        TextField("Название", text: $med.name)
                        TextField("Дозировка", text: $med.dosage)
                        Stepper(value: $med.timesPerDay, in: 1...8) {
                            Text("Приёмов в день: \(med.timesPerDay)")
                        }
                        .onChange(of: med.timesPerDay) { newValue, oldValue in
                            // Если количество слотов уменьшилось, убираем "висячие" slotTimes/slotMedications
                            if newValue < oldValue {
                                let maxSlot = medications.map { $0.timesPerDay }.max() ?? 0
                                slotTimes = slotTimes.filter { $0.key <= maxSlot }
                                slotMedications = slotMedications.filter { $0.key <= maxSlot }
                            }
                        }
                        Stepper(value: $med.durationInDays, in: 1...365) {
                            Text("Длительность: \(med.durationInDays) дней")
                        }
                        TextField("Комментарий", text: Binding(
                            get: { med.comment ?? "" },
                            set: { med.comment = $0.isEmpty ? nil : $0 }
                        ))
                    }
                }




                // ИНФОРМАЦИЯ
                Section("Информация") {
                    TextField("Название курса", text: $courseName)
                    
                    HStack {
                        Text("Приёмов в день")
                        Spacer()
                        Text("\(course.doseSlots.count)")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }

                    DatePicker(
                        "Дата начала",
                        selection: $startDate,
                        displayedComponents: [.date]
                    )

                    Toggle("Напоминания", isOn: $remindersEnabled)

                    if remindersEnabled {
                        Picker("За сколько минут до приёма", selection: $reminderOffsetMinutes) {
                            Text("В момент приёма").tag(0)
                            Text("За 5 минут").tag(5)
                            Text("За 10 минут").tag(10)
                            Text("За 30 минут").tag(30)
                        }
                    }
                }

                // РАСПИСАНИЕ ПРИЁМОВ
                Section("Расписание приёмов") {
                    ForEach(currentDoseSlots, id: \.indexInDay) { slot in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Приём \(slot.indexInDay)")
                                    .font(.headline)
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
                            .font(.subheadline)
                        }
                        .padding(.vertical, 4)
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
        return medications.filter { $0.timesPerDay >= slotIndex }
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
        updated.medications = medications
        updated.startDate = startDate
        updated.name = courseName.isEmpty ? nil : courseName
        updated.remindersEnabled = remindersEnabled
        updated.reminderOffsetMinutes = reminderOffsetMinutes
        let maxDuration = medications.map(\.durationInDays).max() ?? 0
        updated.totalDurationInDays = maxDuration
        // Сохраняем актуальный список слотов (приёмов в день)
        let newSlots = (1...(medications.map { $0.timesPerDay }.max() ?? 0)).map { i -> DoseSlot in
            if let t = slotTimes[i] {
                // Используем пользовательское время, если оно есть
                return DoseSlot(id: UUID(), indexInDay: i, time: Calendar.current.dateComponents([.hour, .minute], from: t))
            } else if let original = course.doseSlots.first(where: { $0.indexInDay == i }) {
                return original
            } else {
                // По умолчанию 9:00, 10:00, ...
                let hour = 9 + (i - 1)
                let comps = DateComponents(hour: hour, minute: 0)
                return DoseSlot(id: UUID(), indexInDay: i, time: comps)
            }
        }
        updated.doseSlots = newSlots
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

