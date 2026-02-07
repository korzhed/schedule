import SwiftUI

struct CourseDetailView: View {

    @EnvironmentObject private var appState: AppState
    @State private var showEditSheet: Bool = false

    let courseId: UUID

    private var course: Course {
        appState.courses.first(where: { $0.id == courseId }) ?? appState.courses.first(where: { _ in false }) ?? Course(id: courseId, createdAt: Date(), startDate: Date(), name: nil, medications: [], doseSlots: [], courseMedications: [], remindersEnabled: false, reminderOffsetMinutes: 0, totalDurationInDays: 0)
    }

    var body: some View {
        List {
            //TodayProgressSection(progress: todayProgress)
            MedicationsSection(medications: course.medications)
            InfoSection(course: course)
            ScheduleSection(course: course)
                .environmentObject(appState)
            
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
            EditCourseFlow(course: course) { updatedCourse in
                appState.updateCourse(updatedCourse)
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

