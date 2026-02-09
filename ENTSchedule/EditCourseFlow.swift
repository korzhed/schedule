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

    @State private var medications: [MedicationItem]
    @State private var courseMedicationsState: [CourseMedication]

    @State private var slotTimes: [Int: Date] = [:]
    @State private var originalSlotTimes: [Int: Date] = [:]

    @State private var showAddMedication: Bool = false
    @State private var selectedSlotForAdding: Int? = nil
    @State private var showAddFromText: Bool = false
    @State private var showRedistributeAlert: Bool = false
    @State private var changedBoundarySlotIndex: Int? = nil

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
        _courseMedicationsState = State(initialValue: course.courseMedications)
    }

    // Все потенциальные слоты: берём максимум из уже существующих и требуемых по timesPerDay
    private var currentDoseSlots: [DoseSlot] {
        let existingMax = course.doseSlots.map { $0.indexInDay }.max() ?? 0
        let desiredMax = medications.map { $0.timesPerDay }.max() ?? 0
        let maxSlots = max(existingMax, desiredMax)

        return (1...maxSlots).map { i in
            if let original = course.doseSlots.first(where: { $0.indexInDay == i }) {
                return original
            } else {
                // Новый слот с дефолтным временем по 3 часа, начиная с 9:00
                let baseHour = 9
                let hour = baseHour + (i - 1) * 3
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
                            adjustSlotsForMedication(
                                medicationId: med.id,
                                newTimesPerDay: newValue,
                                oldTimesPerDay: oldValue
                            )
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
                        Text("\(currentDoseSlots.count)")
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
                    Button("Распределить по дню") {
                        redistributeAllSlotsBetweenMinAndMax()
                    }

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
                                        set: { newValue in
                                            _ = slotTimes[slot.indexInDay] ?? timeFromComponents(slot.time)
                                            slotTimes[slot.indexInDay] = newValue

                                            let indices = currentDoseSlots.map { $0.indexInDay }.sorted()
                                            if let first = indices.first, let last = indices.last,
                                               slot.indexInDay == first || slot.indexInDay == last {
                                                changedBoundarySlotIndex = slot.indexInDay
                                                showRedistributeAlert = true
                                            }
                                        }
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
            .alert("Выровнять промежутки времени?", isPresented: $showRedistributeAlert) {
                Button("Отмена", role: .cancel) {
                    showRedistributeAlert = false
                    changedBoundarySlotIndex = nil
                }
                Button("Выровнять") {
                    redistributeAllSlotsBetweenMinAndMax()
                    showRedistributeAlert = false
                    changedBoundarySlotIndex = nil
                }
            }
            .sheet(isPresented: $showAddMedication) {
                if let slotIndex = selectedSlotForAdding {
                    MedicationPickerView(
                        allMedications: $medications,
                        selectedMedicationIds: Binding(
                            get: {
                                let ids = courseMedicationsState
                                    .filter { $0.slotIndexes.contains(slotIndex) }
                                    .map { $0.medicationId }
                                return Set(ids)
                            },
                            set: { newValue in
                                applySelection(newValue, forSlot: slotIndex)
                            }
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
    
    // Равномерно распределяем все слоты между минимальным и максимальным временем
    private func redistributeAllSlotsBetweenMinAndMax() {
        // Берём индексы всех слотов, которые есть сейчас
        let indices = currentDoseSlots.map { $0.indexInDay }.sorted()
        guard indices.count >= 2 else { return }

        let firstIndex = indices.first!
        let lastIndex = indices.last!

        // Находим исходные слоты по индексам
        let firstSlot = currentDoseSlots.first(where: { $0.indexInDay == firstIndex })
        let lastSlot = currentDoseSlots.first(where: { $0.indexInDay == lastIndex })

        // Фактические даты для первого и последнего:
        // если пользователь уже менял время — берём из slotTimes,
        // иначе используем время из DoseSlot.time (по умолчанию)
        let firstDate = slotTimes[firstIndex]
            ?? timeFromComponents(firstSlot?.time ?? DateComponents(hour: 8, minute: 0))

        let lastDate = slotTimes[lastIndex]
            ?? timeFromComponents(lastSlot?.time ?? DateComponents(hour: 20, minute: 0))

        let totalInterval = lastDate.timeIntervalSince(firstDate)
        guard totalInterval > 0 else { return }

        let step = totalInterval / Double(indices.count - 1)

        for (offset, index) in indices.enumerated() {
            if index == firstIndex {
                slotTimes[index] = firstDate
            } else if index == lastIndex {
                slotTimes[index] = lastDate
            } else {
                let date = firstDate.addingTimeInterval(step * Double(offset))
                slotTimes[index] = date
            }
        }
    }


    private func getMedications(for slotIndex: Int) -> [MedicationItem] {
        let medIds = courseMedicationsState
            .filter { $0.slotIndexes.contains(slotIndex) }
            .map { $0.medicationId }

        return medications.filter { medIds.contains($0.id) }
    }

    private func removeMedication(_ medicationId: UUID, from slotIndex: Int) {
        guard let idx = courseMedicationsState.firstIndex(where: { $0.medicationId == medicationId }) else {
            return
        }
        var cm = courseMedicationsState[idx]
        cm.slotIndexes.removeAll { $0 == slotIndex }
        courseMedicationsState[idx] = cm
    }

    // Применяем выбор из пикера к courseMedicationsState
    private func applySelection(_ newIds: Set<UUID>, forSlot slotIndex: Int) {
        let existingIds = Set(
            courseMedicationsState
                .filter { $0.slotIndexes.contains(slotIndex) }
                .map { $0.medicationId }
        )

        let toAdd = newIds.subtracting(existingIds)
        let toRemove = existingIds.subtracting(newIds)

        // Добавляем
        for id in toAdd {
            if let idx = courseMedicationsState.firstIndex(where: { $0.medicationId == id }) {
                var cm = courseMedicationsState[idx]
                if !cm.slotIndexes.contains(slotIndex) {
                    cm.slotIndexes.append(slotIndex)
                    cm.slotIndexes.sort()
                }
                courseMedicationsState[idx] = cm
            } else {
                courseMedicationsState.append(
                    CourseMedication(
                        id: UUID(),
                        medicationId: id,
                        slotIndexes: [slotIndex]
                    )
                )
            }
        }

        // Удаляем
        for id in toRemove {
            guard let idx = courseMedicationsState.firstIndex(where: { $0.medicationId == id }) else { continue }
            var cm = courseMedicationsState[idx]
            cm.slotIndexes.removeAll { $0 == slotIndex }
            courseMedicationsState[idx] = cm
        }
    }

    // Перераспределяем слоты для конкретного лекарства при изменении timesPerDay
    private func adjustSlotsForMedication(
        medicationId: UUID,
        newTimesPerDay: Int,
        oldTimesPerDay: Int
    ) {
        guard newTimesPerDay > 0 else { return }

        let cmIndex = courseMedicationsState.firstIndex(where: { $0.medicationId == medicationId })
        var cm = cmIndex.flatMap { courseMedicationsState[$0] }
            ?? CourseMedication(id: UUID(), medicationId: medicationId, slotIndexes: [])

        var currentIndexes = cm.slotIndexes.sorted()
        let allSlots = currentDoseSlots.sorted { $0.indexInDay < $1.indexInDay }

        if newTimesPerDay <= currentIndexes.count {
            // Уменьшаем: оставляем самые ранние слоты
            currentIndexes = Array(currentIndexes.prefix(newTimesPerDay))
        } else {
            // Увеличиваем: создаём недостающие приёмы с новыми слотами
            let targets = generateEvenDatesForMedication(timesPerDay: newTimesPerDay)

            // Уже используемые индексы для этого лекарства
            var usedIndexes = Set(currentIndexes)

            for target in targets {
                if usedIndexes.count >= newTimesPerDay { break }

                // Ищем свободный слот (без этого лекарства) с ближайшим временем
                let candidate = allSlots
                    .sorted { lhs, rhs in
                        timeIntervalBetween(lhs.time, target) < timeIntervalBetween(rhs.time, target)
                    }
                    .first(where: { slot in
                        !usedIndexes.contains(slot.indexInDay)
                    })

                if let candidate = candidate {
                    usedIndexes.insert(candidate.indexInDay)
                } else {
                    // Если подходящих слотов нет — создаём новый индекс
                    let newIndex = (allSlots.map { $0.indexInDay }.max() ?? 0) + 1
                    usedIndexes.insert(newIndex)
                }
            }

            currentIndexes = Array(usedIndexes).sorted()
        }

        cm.slotIndexes = currentIndexes

        if let idx = cmIndex {
            courseMedicationsState[idx] = cm
        } else {
            courseMedicationsState.append(cm)
        }
    }


    // Равномерные целевые времена для лекарства между 8:00 и 20:00
    private func generateEvenDatesForMedication(timesPerDay: Int) -> [Date] {
        guard timesPerDay > 0 else { return [] }

        let calendar = Calendar.current
        let baseDate = startDate

        var startComponents = calendar.dateComponents([.year, .month, .day], from: baseDate)
        startComponents.hour = 8
        startComponents.minute = 0

        var endComponents = startComponents
        endComponents.hour = 20
        endComponents.minute = 0

        let start = calendar.date(from: startComponents) ?? baseDate
        let end = calendar.date(from: endComponents) ?? baseDate

        let startTime = start.timeIntervalSince1970
        let endTime = end.timeIntervalSince1970

        if timesPerDay == 1 {
            let mid = (startTime + endTime) / 2
            return [Date(timeIntervalSince1970: mid)]
        }

        let step = (endTime - startTime) / Double(timesPerDay - 1)
        return (0..<timesPerDay).map { i in
            Date(timeIntervalSince1970: startTime + step * Double(i))
        }
    }

    private func timeIntervalBetween(_ components: DateComponents, _ date: Date) -> TimeInterval {
        let calendar = Calendar.current
        var base = calendar.dateComponents([.year, .month, .day], from: date)
        base.hour = components.hour ?? 0
        base.minute = components.minute ?? 0
        let componentsDate = calendar.date(from: base) ?? date
        return abs(componentsDate.timeIntervalSince(date))
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

        // Пересчитываем слоты по максимальному timesPerDay
        let maxTimesPerDay = medications.map { $0.timesPerDay }.max() ?? 0

        // Гарантируем, что для всех индексов 1...maxTimesPerDay есть время в slotTimes
        // Если времени нет, равномерно распределяем приёмы между 8:00 и 20:00
        if maxTimesPerDay > 0 {
            let calendar = Calendar.current
            let base = calendar.startOfDay(for: Date())

            let startHour = 8.0
            let endHour = 20.0
            let slotsCount = Double(maxTimesPerDay)
            let step = (endHour - startHour) / max(1.0, slotsCount - 1.0)

            for i in 1...maxTimesPerDay {
                if slotTimes[i] == nil {
                    let hour = Int(round(startHour + Double(i - 1) * step))
                    slotTimes[i] = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
                }
            }
        }

        let newSlots: [DoseSlot] = (1...maxTimesPerDay).map { i in
            let t = slotTimes[i] ?? Date()
            let comps = Calendar.current.dateComponents([.hour, .minute], from: t)
            return DoseSlot(id: UUID(), indexInDay: i, time: comps)
        }
        updated.doseSlots = newSlots

        // Нормализуем courseMedications относительно новых слотов
        let normalized = normalizedCourseMedications(for: updated, newSlots: newSlots)

        // Удаляем слоты, в которых нет ни одного лекарства, и переиндексируем 1...N
        let usedIndexes = Set(normalized.flatMap { $0.slotIndexes })
        let filteredSlots = newSlots
            .filter { usedIndexes.contains($0.indexInDay) }
            .sorted { $0.indexInDay < $1.indexInDay }

        let reindexedSlots: [DoseSlot] = filteredSlots.enumerated().map { offset, slot in
            var s = slot
            s.indexInDay = offset + 1
            return s
        }

        let indexMapping: [Int: Int] = Dictionary(uniqueKeysWithValues:
            zip(filteredSlots.map { $0.indexInDay }, reindexedSlots.map { $0.indexInDay })
        )

        // Перенекидываем индексы в courseMedications по новой нумерации
        let remappedCourseMedications: [CourseMedication] = normalized.map { cm in
            var copy = cm
            copy.slotIndexes = cm.slotIndexes.compactMap { indexMapping[$0] }.sorted()
            return copy
        }

        updated.doseSlots = reindexedSlots
        updated.courseMedications = remappedCourseMedications

        return updated

    }

    private func normalizedCourseMedications(
        for course: Course,
        newSlots: [DoseSlot]
    ) -> [CourseMedication] {
        let validIndexes = Set(newSlots.map { $0.indexInDay })

        var result = courseMedicationsState.map { cm -> CourseMedication in
            var copy = cm
            copy.slotIndexes = copy.slotIndexes.filter { validIndexes.contains($0) }
            return copy
        }

        result.removeAll { $0.slotIndexes.isEmpty }
        return result
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
