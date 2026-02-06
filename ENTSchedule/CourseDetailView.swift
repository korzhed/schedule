import SwiftUI

struct CourseDetailView: View {

    @EnvironmentObject private var appState: AppState
    @State private var showEditSheet: Bool = false

    let course: Course

    private var todayProgress: Double {
        appState.getTodayProgress(for: course)
    }

    var body: some View {
        List {
            TodayProgressSection(progress: todayProgress)
            MedicationsSection(medications: course.medications)
            ScheduleSection(course: course)
                .environmentObject(appState)
            InfoSection(course: course)
        }
        .navigationTitle(course.name ?? "Детали курса")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditSheet = true
                } label: {
                    Text("Редактировать")
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditCourseFlow(course: course) {
                showEditSheet = false
            }
            .environmentObject(appState)
        }
    }
}

// MARK: - Подразделы экрана

private struct TodayProgressSection: View {
    let progress: Double

    var body: some View {
        Section("Прогресс за сегодня") {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress)
                Text("\(Int(progress * 100))% доз принято сегодня")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MedicationsSection: View {
    let medications: [MedicationItem]

    var body: some View {
        Section("Лекарства") {
            ForEach(medications) { medication in
                VStack(alignment: .leading, spacing: 4) {
                    Text(medication.name)
                        .font(.headline)
                    Text(medication.dosage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("\(medication.timesPerDay) раз/день")
                        Text("•")
                        Text("\(medication.durationInDays) дней")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let comment = medication.comment, !comment.isEmpty {
                        Text(comment)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}

private struct ScheduleSection: View {
    @EnvironmentObject private var appState: AppState
    let course: Course

    var body: some View {
        Section("Расписание приёмов") {
            ForEach(sortedSlots) { slot in
                SlotRow(slot: slot, course: course)
            }
        }
    }

    private var sortedSlots: [DoseSlot] {
        course.doseSlots.sorted { $0.indexInDay < $1.indexInDay }
    }
}

private struct SlotRow: View {
    @EnvironmentObject private var appState: AppState

    let slot: DoseSlot
    let course: Course

    private var medicationsInSlot: [MedicationItem] {
        let medicationIds = course.courseMedications
            .filter { $0.slotIndexes.contains(slot.indexInDay) }
            .map { $0.medicationId }

        return course.medications.filter { medicationIds.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Приём \(slot.indexInDay)")
                    .font(.headline)
                Spacer()
                timeText
            }

            ForEach(medicationsInSlot) { med in
                MedicationIntakeRow(
                    course: course,
                    slot: slot,
                    medication: med
                )
            }
        }
    }

    private var timeText: some View {
        Group {
            if let hour = slot.time.hour,
               let minute = slot.time.minute {
                Text(String(format: "%02d:%02d", hour, minute))
                    .foregroundStyle(.secondary)
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MedicationIntakeRow: View {
    @EnvironmentObject private var appState: AppState

    let course: Course
    let slot: DoseSlot
    let medication: MedicationItem

    private var status: IntakeStatus {
        appState.getIntakeStatus(
            courseId: course.id,
            medicationId: medication.id,
            slotIndexInDay: slot.indexInDay,
            date: Date()
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(medication.name)
                    .font(.subheadline)
                Text(medication.dosage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let comment = medication.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            Text(statusLabel(status))
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusBackground(status))
                .foregroundStyle(.white)
                .clipShape(Capsule())

            Menu {
                Button("Отметить как принято") {
                    mark(.taken)
                }

                Button("Отметить как пропущено") {
                    mark(.skipped)
                }

                Button("Сбросить статус") {
                    mark(.pending)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
            }
            .padding(.leading, 20)
        }
    }

    private func mark(_ newStatus: IntakeStatus) {
        appState.markIntake(
            course: course,
            medication: medication,
            slotIndexInDay: slot.indexInDay,
            status: newStatus
        )
    }

    private func statusLabel(_ status: IntakeStatus) -> String {
        switch status {
        case .taken: return "Принято"
        case .skipped: return "Пропущено"
        case .pending: return "Ожидает"
        }
    }

    private func statusBackground(_ status: IntakeStatus) -> Color {
        switch status {
        case .taken: return .green
        case .skipped: return .red
        case .pending: return .gray
        }
    }
}

private struct InfoSection: View {
    let course: Course

    var body: some View {
        Section("Информация") {
            HStack {
                Text("Дата начала")
                Spacer()
                Text(course.startDate.formatted(date: .long, time: .omitted))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Длительность курса")
                Spacer()
                Text("\(course.totalDurationInDays) дней")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Напоминания")
                Spacer()
                Text(course.remindersEnabled ? "Включены" : "Выключены")
                    .foregroundStyle(.secondary)
            }

            if course.remindersEnabled {
                HStack {
                    Text("За сколько минут")
                    Spacer()
                    Text(reminderText(course.reminderOffsetMinutes))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func reminderText(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "В момент приёма"
        case 5: return "За 5 минут"
        case 10: return "За 10 минут"
        case 30: return "За 30 минут"
        default: return "\(minutes) мин"
        }
    }
}

// MARK: - EditCourseFlow

struct EditCourseFlow: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let course: Course
    let onComplete: () -> Void

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

    init(course: Course, onComplete: @escaping () -> Void) {
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
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Button {
                            selectedSlotForAdding = slot.indexInDay
                            showAddMedication = true
                        } label: {
                            Label("Добавить лекарство", systemImage: "plus.circle.fill")
                        }
                    } header: {
                        Text("Приём \(slot.indexInDay)")
                            .font(.headline)
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

                Section {
                    Button {
                        showAddFromText = true
                    } label: {
                        Label("Добавить новое лекарство по тексту", systemImage: "text.badge.plus")
                    }
                }
            }
            .navigationTitle("Редактировать курс")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        saveCourse()
                    }
                }
            }
            .onAppear {
                initState()
            }
            .sheet(isPresented: $showAddMedication) {
                if let slotIndex = selectedSlotForAdding {
                    AddMedicationSheet(
                        slotIndex: slotIndex,
                        parsedMedications: medications,
                        slotMedications: slotMedications,
                        onAddFromList: { medicationId in
                            addMedication(medicationId, to: slotIndex)
                        },
                        onAddManual: { newMedication in
                            medications.append(newMedication)
                            addMedication(newMedication.id, to: slotIndex)
                        }
                    )
                }
            }
            .sheet(isPresented: $showAddFromText) {
                NavigationStack {
                    PrescriptionInputStepView { newMeds in
                        mergeNewMedications(newMeds)
                        showAddFromText = false
                    }
                    .environmentObject(appState)
                }
            }
        }
    }

    // MARK: - Helpers

    private func initState() {
        for slot in course.doseSlots {
            slotTimes[slot.indexInDay] = timeFromComponents(slot.time)
        }

        for cm in course.courseMedications {
            for slotIndex in cm.slotIndexes {
                if slotMedications[slotIndex] == nil {
                    slotMedications[slotIndex] = []
                }
                slotMedications[slotIndex]?.insert(cm.medicationId)
            }
        }
    }

    private func timeFromComponents(_ components: DateComponents) -> Date {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date())
        return calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: 0,
            of: base
        ) ?? base
    }

    private func getMedications(for slotIndex: Int) -> [MedicationItem] {
        guard let medicationIds = slotMedications[slotIndex] else { return [] }
        return medications.filter { medicationIds.contains($0.id) }
    }

    private func getAvailableMedications(for slotIndex: Int) -> [MedicationItem] {
        let currentIds = slotMedications[slotIndex] ?? []
        return medications.filter { !currentIds.contains($0.id) }
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

    private func mergeNewMedications(_ newMeds: [MedicationItem]) {
        let existingIds = Set(medications.map { $0.id })
        let toAdd = newMeds.filter { !existingIds.contains($0.id) }
        guard !toAdd.isEmpty else { return }

        medications.append(contentsOf: toAdd)

        let allSlots = course.doseSlots.map { $0.indexInDay }
        for med in toAdd {
            for slotIndex in allSlots {
                if slotMedications[slotIndex] == nil {
                    slotMedications[slotIndex] = []
                }
                slotMedications[slotIndex]?.insert(med.id)
            }
        }
    }

    private func saveCourse() {
        let calendar = Calendar.current

        let updatedSlots: [DoseSlot] = course.doseSlots.map { slot in
            let date = slotTimes[slot.indexInDay] ?? timeFromComponents(slot.time)
            let components = calendar.dateComponents([.hour, .minute], from: date)
            return DoseSlot(id: slot.id, indexInDay: slot.indexInDay, time: components)
        }

        var updatedCourseMeds: [CourseMedication] = []

        for medication in medications {
            var slots: [Int] = []
            for slotIndex in course.doseSlots.map({ $0.indexInDay }) {
                if slotMedications[slotIndex]?.contains(medication.id) == true {
                    slots.append(slotIndex)
                }
            }
            if !slots.isEmpty {
                updatedCourseMeds.append(
                    CourseMedication(
                        id: UUID(),
                        medicationId: medication.id,
                        slotIndexes: slots
                    )
                )
            }
        }

        let trimmedName = courseName.trimmingCharacters(in: .whitespacesAndNewlines)

        let updatedCourse = Course(
            id: course.id,
            createdAt: course.createdAt,
            startDate: startDate,
            name: trimmedName.isEmpty ? nil : trimmedName,
            medications: medications,
            doseSlots: updatedSlots,
            courseMedications: updatedCourseMeds,
            remindersEnabled: remindersEnabled,
            reminderOffsetMinutes: reminderOffsetMinutes,
            totalDurationInDays: totalDurationInDays
        )

        appState.updateCourse(updatedCourse)
        onComplete()
        dismiss()
    }
}

// MARK: - Preview

struct CourseDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CourseDetailView(
                course: Course(
                    id: UUID(),
                    createdAt: .now,
                    startDate: .now,
                    name: "Пример курса",
                    medications: [],
                    doseSlots: [],
                    courseMedications: [],
                    remindersEnabled: true,
                    reminderOffsetMinutes: 0,
                    totalDurationInDays: 7
                )
            )
            .environmentObject(AppState())
        }
    }
}

