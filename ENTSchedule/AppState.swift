import Foundation
import Combine

// MARK: - Models

struct MedicationItem: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var dosage: String
    var timesPerDay: Int
    var durationInDays: Int
    var comment: String?
}

struct DoseSlot: Identifiable, Hashable, Codable {
    var id: UUID
    var indexInDay: Int
    var time: DateComponents
}

struct CourseMedication: Identifiable, Hashable, Codable {
    var id: UUID
    var medicationId: UUID
    var slotIndexes: [Int]
}

struct Course: Identifiable, Hashable, Codable {
    var id: UUID
    var createdAt: Date
    var startDate: Date
    var name: String?
    var medications: [MedicationItem]
    var doseSlots: [DoseSlot]
    var courseMedications: [CourseMedication]
    var remindersEnabled: Bool
    var reminderOffsetMinutes: Int
    /// Общая длительность курса в днях
    var totalDurationInDays: Int
}

// MARK: - Intake status

enum IntakeStatus: String, Codable {
    case taken
    case skipped
    case pending
}

struct IntakeKey: Hashable, Codable {
    let courseId: UUID
    let medicationId: UUID
    let slotIndexInDay: Int
    let date: Date
}

enum AppColorScheme: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }
}

// Элемент для экрана «Сегодня»
struct TodayPlannedIntake: Identifiable, Hashable {
    let id = UUID()
    let course: Course
    let slot: DoseSlot
    let medication: MedicationItem
    let time: DateComponents
}

// MARK: - Persisted state

struct PersistedAppState: Codable {
    var courses: [Course]
    var medications: [MedicationItem]
    var intakeStatuses: [IntakeKey: IntakeStatus]
    var colorScheme: AppColorScheme?
}

// MARK: - AppState

final class AppState: ObservableObject {
    @Published var courses: [Course] = []
    @Published var medications: [MedicationItem] = []
    // статус по конкретному приёму: курс + лекарство + слот + дата
    @Published var intakeStatuses: [IntakeKey: IntakeStatus] = [:]
    @Published var colorScheme: AppColorScheme = .system

    /// Сервис уведомлений, который пробрасывается из ENTScheduleApp
    private var notificationService: NotificationService?

    private let storageKey = "AppStateStorage_v1"

    init() {
        load()
    }

    // MARK: - Notifications hook

    func attachNotificationService(_ service: NotificationService) {
        self.notificationService = service
    }

    // MARK: - Courses

    func addCourse(_ course: Course) {
        courses.append(course)
        save()
        notificationService?.scheduleNotifications(for: course)
    }

    func updateCourse(_ updated: Course) {
        if let index = courses.firstIndex(where: { $0.id == updated.id }) {
            let previous = courses[index]
            courses[index] = updated
            save()

            if updated.remindersEnabled == false {
                // Если уведомления выключены для курса — снимаем все запланированные уведомления
                notificationService?.cancelNotifications(forCourseId: updated.id)
            } else {
                // Иначе перепланируем (удалит старые этого курса и создаст заново при необходимости)
                notificationService?.rescheduleNotifications(for: updated)
            }
        }
    }

    // MARK: - Intake status API

    private func key(
        courseId: UUID,
        medicationId: UUID,
        slotIndexInDay: Int,
        date: Date
    ) -> IntakeKey {
        let day = Calendar.current.startOfDay(for: date)
        return IntakeKey(
            courseId: courseId,
            medicationId: medicationId,
            slotIndexInDay: slotIndexInDay,
            date: day
        )
    }

    func markIntake(
        courseId: UUID,
        medicationId: UUID,
        slotIndexInDay: Int,
        date: Date,
        status: IntakeStatus
    ) {
        let k = key(
            courseId: courseId,
            medicationId: medicationId,
            slotIndexInDay: slotIndexInDay,
            date: date
        )

        intakeStatuses[k] = status
        save()
    }

    /// Удобный метод для UI: отмечать приём по объектам `Course` и `MedicationItem`
    func markIntake(
        course: Course,
        medication: MedicationItem,
        slotIndexInDay: Int,
        status: IntakeStatus,
        date: Date = Date()
    ) {
        markIntake(
            courseId: course.id,
            medicationId: medication.id,
            slotIndexInDay: slotIndexInDay,
            date: date,
            status: status
        )
    }

    func getIntakeStatus(
        courseId: UUID,
        medicationId: UUID,
        slotIndexInDay: Int,
        date: Date
    ) -> IntakeStatus {
        let k = key(
            courseId: courseId,
            medicationId: medicationId,
            slotIndexInDay: slotIndexInDay,
            date: date
        )

        return intakeStatuses[k] ?? .pending
    }

    // MARK: - Прогресс за сегодня по курсу

    func getTodayProgress(for course: Course) -> Double {
        let today = Calendar.current.startOfDay(for: Date())
        var total = 0
        var completed = 0

        for slot in course.doseSlots {
            let medicationIds = course.courseMedications
                .filter { $0.slotIndexes.contains(slot.indexInDay) }
                .map { $0.medicationId }

            let meds = course.medications.filter { medicationIds.contains($0.id) }

            for med in meds {
                total += 1
                let status = getIntakeStatus(
                    courseId: course.id,
                    medicationId: med.id,
                    slotIndexInDay: slot.indexInDay,
                    date: today
                )

                if status == .taken {
                    completed += 1
                }
            }
        }

        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    // MARK: - Общий прогресс курса по дням (для списка назначений)

    func getOverallProgress(for course: Course) -> Double {
        let totalDays = course.totalDurationInDays
        guard totalDays > 0 else { return 0 }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: course.startDate)
        let today = calendar.startOfDay(for: Date())
        let daysPassed = max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0)
        let clamped = min(daysPassed, totalDays)
        return Double(clamped) / Double(totalDays)
    }

    // MARK: - Сегодняшние приёмы

    func getTodayPlannedIntakes() -> [TodayPlannedIntake] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var result: [TodayPlannedIntake] = []

        for course in courses {
            let courseStart = calendar.startOfDay(for: course.startDate)
            // курс уже начался
            guard courseStart <= today else { continue }

            let totalDays = course.totalDurationInDays
            if totalDays == 0 { continue }

            let daysPassed = max(0, calendar.dateComponents([.day], from: courseStart, to: today).day ?? 0)
            // курс ещё не закончился
            guard daysPassed < totalDays else { continue }

            for slot in course.doseSlots {
                let medicationIds = course.courseMedications
                    .filter { $0.slotIndexes.contains(slot.indexInDay) }
                    .map { $0.medicationId }

                let meds = course.medications.filter { medicationIds.contains($0.id) }

                for med in meds {
                    result.append(
                        TodayPlannedIntake(
                            course: course,
                            slot: slot,
                            medication: med,
                            time: slot.time
                        )
                    )
                }
            }
        }

        // сортируем по времени приёма
        return result.sorted { lhs, rhs in
            let lh = lhs.time.hour ?? 0
            let lm = lhs.time.minute ?? 0
            let rh = rhs.time.hour ?? 0
            let rm = rhs.time.minute ?? 0
            return (lh, lm) < (rh, rm)
        }
    }

    // MARK: - Persistence

    private func save() {
        let state = PersistedAppState(
            courses: courses,
            medications: medications,
            intakeStatuses: intakeStatuses,
            colorScheme: colorScheme
        )

        do {
            let data = try JSONEncoder().encode(state)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save AppState: \(error)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }

        do {
            let decoded = try JSONDecoder().decode(PersistedAppState.self, from: data)
            courses = decoded.courses
            medications = decoded.medications
            intakeStatuses = decoded.intakeStatuses
            colorScheme = decoded.colorScheme ?? .system
        } catch {
            print("Failed to load AppState: \(error)")
        }
    }

    // MARK: - Course deletion

    func deleteCourse(withId id: UUID) {
        courses.removeAll { $0.id == id }
        save()
        // Отменяем все уведомления для этого курса
        notificationService?.cancelNotifications(forCourseId: id)
    }
}
