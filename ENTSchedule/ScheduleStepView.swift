import SwiftUI

struct ScheduleStepView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    let parsedMedications: [MedicationItem]
    /// Передаём наружу созданный курс
    let onComplete: (Course) -> Void

    @State private var startDate: Date = .now
    @State private var remindersEnabled: Bool = true
    @State private var reminderOffsetMinutes: Int = 0

    @State private var slotTimes: [Int: Date] = [:]
    @State private var slotMedications: [Int: Set<UUID>] = [:]

    @State private var showAddMedication: Bool = false
    @State private var selectedSlotForAdding: Int? = nil

    // Редактирование названий и дозировок
    @State private var workingMedications: [MedicationItem] = []
    @State private var medToEdit: MedicationItem? = nil
    @State private var editedName: String = ""
    @State private var editedDosage: String = ""
    @State private var showEditSheet: Bool = false
    @State private var showEditScopeAlert: Bool = false

    // выравнивание промежутков
    @State private var showAlignAlert: Bool = false
    @State private var alignTriggeredByEdgeChange: Bool = false

    // интервальный курс (каждые N часов) — даём приоритет интервалу, а не 8–20
    @State private var isIntervalBased: Bool = false

    private var maxSlots: Int {
        workingMedications.map { $0.timesPerDay }.max() ?? 1
    }

    private var canSave: Bool {
        !slotMedications.values.allSatisfy { $0.isEmpty }
    }

    var body: some View {
        Form {
            Section("Дата начала") {
                DatePicker(
                    "Начало курса",
                    selection: $startDate,
                    displayedComponents: [.date]
                )
            }

            ForEach(1...maxSlots, id: \.self) { slotIndex in
                Section {
                    HStack {
                        Text("Время приёма")
                        Spacer()
                        DatePicker(
                            "",
                            selection: Binding(
                                get: {
                                    slotTimes[slotIndex]
                                    ?? defaultTime(for: slotIndex, maxTimes: maxSlots)
                                },
                                set: { newValue in
                                    let oldValue = slotTimes[slotIndex]
                                    ?? defaultTime(for: slotIndex, maxTimes: maxSlots)
                                    slotTimes[slotIndex] = newValue
                                    handleTimeChange(
                                        slotIndex: slotIndex,
                                        oldValue: oldValue,
                                        newValue: newValue
                                    )
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }

                    let medications = getMedications(for: slotIndex)
                    if medications.isEmpty {
                        Text("Нет лекарств в этом приёме")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(medications) { med in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Button {
                                        startEdit(for: med)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(med.name)
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            Image(systemName: "pencil")
                                                .font(.system(size: 14, weight: .regular))
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)

                                    Text(med.dosage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button(role: .destructive) {
                                    removeMedication(med.id, from: slotIndex)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        selectedSlotForAdding = slotIndex
                        showAddMedication = true
                    } label: {
                        Label("Добавить лекарство", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Приём \(slotIndex)")
                        .font(.headline)
                }
            }

            if maxSlots > 1 && !isIntervalBased {
                Section {
                    Button {
                        showAlignAlert = true
                        alignTriggeredByEdgeChange = false
                    } label: {
                        Label("Выровнять промежутки времени", systemImage: "arrow.left.and.right")
                    }
                } footer: {
                    Text("Первый приём по умолчанию в 8:00, последний — в 20:00. Остальные распределяются равномерно между ними.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Напоминания") {
                Toggle("Включить напоминания", isOn: $remindersEnabled)
                if remindersEnabled {
                    Picker("За сколько минут", selection: $reminderOffsetMinutes) {
                        Text("В момент приёма").tag(0)
                        Text("За 5 минут").tag(5)
                        Text("За 10 минут").tag(10)
                        Text("За 30 минут").tag(30)
                    }
                }
            }
        }
        .navigationTitle("Расписание")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") {
                    createCourse()
                }
                .disabled(!canSave)
            }

            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") {
                    dismiss()
                }
            }
        }
        .onAppear {
            if workingMedications.isEmpty {
                workingMedications = parsedMedications

                // простая эвристика: если есть лекарства с очень частым приёмом (>6 раз), считаем курс интервальным
                isIntervalBased = workingMedications.contains { $0.timesPerDay > 6 }

                initDefaultState()
            }
        }
        .sheet(isPresented: $showAddMedication) {
            AddMedicationSheet(
                slotIndex: selectedSlotForAdding ?? 1,
                parsedMedications: workingMedications,
                slotMedications: slotMedications,
                onAddFromList: { medicationId in
                    if let slotIndex = selectedSlotForAdding {
                        addMedication(medicationId, to: slotIndex)
                    }
                },
                onAddManual: { newMedication in
                    if let slotIndex = selectedSlotForAdding {
                        workingMedications.append(newMedication)
                        addMedication(newMedication.id, to: slotIndex)
                    }
                }
            )
        }
        
        
        .alert(
            "Выровнять промежутки времени?",
            isPresented: $showAlignAlert
        ) {
            Button("Отмена", role: .cancel) { }
            Button("Выровнять") {
                alignSlotsBetweenFirstAndLast()
            }
        } message: {
            Text("Первый и последний приём останутся на своих местах, остальные будут равномерно распределены между ними.")
        }
        // Шит редактирования названия и дозировки
        .sheet(isPresented: $showEditSheet) {
            NavigationStack {
                Form {
                    Section("Название лекарства") {
                        TextField("Например: Називин", text: $editedName)
                    }

                    Section("Дозировка") {
                        TextField("Например: 500 мг", text: $editedDosage)
                    }
                }
                .navigationTitle("Редактировать")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") {
                            showEditSheet = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Далее") {
                            showEditSheet = false
                            showEditScopeAlert = true
                        }
                        .disabled(
                            editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            editedDosage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                }
            }
        }
        // Алерт: одно лекарство или все такие же
        .alert("Применить изменение?", isPresented: $showEditScopeAlert) {
            Button("Только здесь") {
                applyEdit(applyToAll: false)
            }
            Button("Во всех приёмах") {
                applyEdit(applyToAll: true)
            }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Вы хотите изменить только это появление лекарства или все такие же во всём курсе?")
        }
    }

    // MARK: - Edit helpers

    private func startEdit(for med: MedicationItem) {
        medToEdit = med
        editedName = med.name
        editedDosage = med.dosage
        showEditSheet = true
    }

    private func applyEdit(applyToAll: Bool) {
        guard let med = medToEdit else { return }

        let newName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newDosage = editedDosage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, !newDosage.isEmpty else { return }

        if applyToAll {
            // меняем все элементы с тем же id
            for idx in workingMedications.indices {
                if workingMedications[idx].id == med.id {
                    workingMedications[idx].name = newName
                    workingMedications[idx].dosage = newDosage
                }
            }
        } else {
            // меняем только первое совпадение по id
            if let idx = workingMedications.firstIndex(where: { $0.id == med.id }) {
                workingMedications[idx].name = newName
                workingMedications[idx].dosage = newDosage
            }
        }

        medToEdit = nil
    }

    // MARK: - Helpers

    private func initDefaultState() {
        if slotTimes.isEmpty {
            if isIntervalBased {
                initIntervalBasedTimes()
            } else {
                // дефолт: первый приём 8:00, последний 20:00, остальные равномерно
                alignSlotsBetweenFirstAndLast(useDefaultsIfEmpty: true)
            }
        }

        if slotMedications.isEmpty {
            slotMedications = [:]

            let totalSlots = maxSlots
            guard totalSlots > 0 else { return }

            // заранее заполняем пустые множества для всех слотов
            for slotIndex in 1...totalSlots {
                slotMedications[slotIndex] = []
            }

            for medication in workingMedications {
                let times = max(1, medication.timesPerDay)

                var targetSlots: [Int] = []

                if times >= totalSlots {
                    // Больше или равно количеству слотов — ставим в каждый слот
                    targetSlots = Array(1...totalSlots)
                } else if times == 1 {
                    // Один приём — середина по индексам
                    let middlePos = Double(totalSlots - 1) / 2.0
                    let middleIndex = 1 + Int(round(middlePos))
                    targetSlots = [middleIndex]
                } else if times == 2 {
                    // Два приёма — первый и последний слот
                    let firstIndex = 1
                    let lastIndex = totalSlots
                    targetSlots = [firstIndex, lastIndex]
                } else {
                    // 1 < times < totalSlots -> равномерное распределение по индексам
                    // позиции от 0 до totalSlots-1
                    var chosen: [Int] = []
                    for i in 0..<times {
                        let pos = Double(i) * Double(totalSlots - 1) / Double(times - 1)
                        let roundedPos = Int(round(pos))
                        let slotIndex = 1 + min(totalSlots - 1, max(0, roundedPos))
                        chosen.append(slotIndex)
                    }
                    // убираем дубли и сортируем
                    targetSlots = Array(Set(chosen)).sorted()
                }

                for slotIndex in targetSlots {
                    slotMedications[slotIndex]?.insert(medication.id)
                }
            }
        }

    }

    /// Для интервалов ("каждые N часов"): расставляем приёмы начиная с 8:00 по приблизительному шагу (24 / maxSlots), без ограничения 20:00.
    private func initIntervalBasedTimes() {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date())
        let firstTime = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: base) ?? base

        let slotsCount = maxSlots
        guard slotsCount > 0 else { return }

        let hoursStep = max(1, 24 / slotsCount)

        slotTimes = [:]
        for index in 0..<slotsCount {
            let date = calendar.date(byAdding: .hour, value: index * hoursStep, to: firstTime) ?? firstTime
            slotTimes[index + 1] = date
        }
    }

    private func defaultTime(for index: Int, maxTimes: Int) -> Date {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date())

        // если слотов один — ставим 9:00
        if maxTimes == 1 {
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? base
        }

        // первый — 8:00, последний — 20:00, остальные равномерно
        let startHour = 8.0
        let endHour = 20.0
        let slotsCount = Double(maxTimes)
        let step = (endHour - startHour) / max(1.0, slotsCount - 1.0)
        let hour = Int(round(startHour + Double(index - 1) * step))

        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
    }

    private func getMedications(for slotIndex: Int) -> [MedicationItem] {
        guard let medicationIds = slotMedications[slotIndex] else { return [] }
        return workingMedications.filter { medicationIds.contains($0.id) }
    }

    private func addMedication(_ medicationId: UUID, to slotIndex: Int) {
        if slotMedications[slotIndex] == nil {
            slotMedications[slotIndex] = []
        }
        slotMedications[slotIndex]?.insert(medicationId)
    }

    private func removeMedication(_ medicationId: UUID, from slotIndex: Int) {
        slotMedications[slotIndex]?.remove(medicationId)
    }

    // MARK: - Выравнивание слотов

    private func handleTimeChange(
        slotIndex: Int,
        oldValue: Date,
        newValue: Date
    ) {
        guard maxSlots > 1 else { return }

        let isFirst = slotIndex == 1
        let isLast = slotIndex == maxSlots

        // если подвинули первый или последний — спросим про выравнивание
        if (isFirst || isLast), !isIntervalBased {
            alignTriggeredByEdgeChange = true
            showAlignAlert = true
        }
    }

    /// Выравнивает все слоты между первым и последним.
    private func alignSlotsBetweenFirstAndLast(useDefaultsIfEmpty: Bool = false) {
        guard maxSlots > 1 else {
            // если всего один приём — просто ставим дефолт
            let t = defaultTime(for: 1, maxTimes: 1)
            slotTimes[1] = t
            return
        }

        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date())

        // время первого и последнего
        let firstTime: Date
        let lastTime: Date

        if useDefaultsIfEmpty {
            firstTime = slotTimes[1]
            ?? calendar.date(bySettingHour: 8, minute: 0, second: 0, of: base) ?? base
            lastTime = slotTimes[maxSlots]
            ?? calendar.date(bySettingHour: 20, minute: 0, second: 0, of: base) ?? base
        } else {
            firstTime = slotTimes[1]
            ?? calendar.date(bySettingHour: 8, minute: 0, second: 0, of: base) ?? base
            lastTime = slotTimes[maxSlots]
            ?? calendar.date(bySettingHour: 20, minute: 0, second: 0, of: base) ?? base
        }

        let totalInterval = lastTime.timeIntervalSince(firstTime)
        let steps = Double(maxSlots - 1)
        let stepInterval = totalInterval / max(1.0, steps)

        // первый и последний фиксируем, остальные распределяем
        for index in 1...maxSlots {
            if index == 1 {
                slotTimes[index] = firstTime
            } else if index == maxSlots {
                slotTimes[index] = lastTime
            } else {
                let offset = stepInterval * Double(index - 1)
                slotTimes[index] = Date(timeInterval: offset, since: firstTime)
            }
        }
    }

    // MARK: - Создание курса

    private func createCourse() {
        let calendar = Calendar.current

        let doseSlots: [DoseSlot] = (1...maxSlots).map { index in
            let date = slotTimes[index] ?? defaultTime(for: index, maxTimes: maxSlots)
            let components = calendar.dateComponents([.hour, .minute], from: date)
            return DoseSlot(id: UUID(), indexInDay: index, time: components)
        }

        var courseMeds: [CourseMedication] = []

        for medication in workingMedications {
            var slots: [Int] = []
            for slotIndex in 1...maxSlots {
                if slotMedications[slotIndex]?.contains(medication.id) == true {
                    slots.append(slotIndex)
                }
            }
            if !slots.isEmpty {
                courseMeds.append(
                    CourseMedication(
                        id: UUID(),
                        medicationId: medication.id,
                        slotIndexes: slots
                    )
                )
            }
        }

        let totalDuration = workingMedications.map { $0.durationInDays }.max() ?? 7

        let course = Course(
            id: UUID(),
            createdAt: Date(),
            startDate: startDate,
            name: nil,
            medications: workingMedications,
            doseSlots: doseSlots,
            courseMedications: courseMeds,
            remindersEnabled: remindersEnabled,
            reminderOffsetMinutes: reminderOffsetMinutes,
            totalDurationInDays: totalDuration
        )

        appState.addCourse(course)
        onComplete(course)
        dismiss()
    }
}

