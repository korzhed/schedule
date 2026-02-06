import SwiftUI

struct TodayRootView: View {

    @EnvironmentObject private var appState: AppState
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    // Диапазон: прошедшие дни месяца + оставшиеся дни курса + дни до конца месяца
    private var daysRange: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!

        // максимум конца курса по всем курсам
        let maxCourseEnd: Date? = appState.courses.compactMap { course in
            let courseStart = calendar.startOfDay(for: course.startDate)
            let duration = max(1, course.totalDurationInDays)
            return calendar.date(byAdding: .day, value: duration, to: courseStart)
        }.max()

        // конец месяца
        let startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
        let endOfMonth = calendar.date(byAdding: .day, value: -1, to: startOfNextMonth)!

        // правая граница — максимум из конца курса и конца месяца
        let rightBoundary: Date
        if let maxCourseEnd {
            rightBoundary = max(maxCourseEnd, endOfMonth)
        } else {
            rightBoundary = endOfMonth
        }

        let start = startOfMonth

        var days: [Date] = []
        var current = start
        while current <= rightBoundary {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }

        return days
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Главный фон экрана — адаптивный
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // шапка: фон только под календарём и заголовком дня
                    VStack(spacing: 0) {
                        DayPickerView(
                            days: daysRange,
                            selectedDate: $selectedDate,
                            hasIntakesForDay: { date in
                                !buildIntakes(for: date).isEmpty
                            },
                            dayStatus: { date in
                                dayStatus(for: date)
                            }
                        )
                        .padding(.top, 8)

                        DayHeaderView(date: selectedDate)
                            .padding(.bottom, 4)

                        Divider()
                    }
                    .background(Color(.systemBackground)) // убираем серую «полку»

                    let intakes = buildIntakes(for: selectedDate)

                    if intakes.isEmpty {
                        // Плейсхолдер в стиле экрана «Назначения»
                        VStack(spacing: 24) {
                            ContentUnavailableView(
                                "Нет приёмов на этот день",
                                systemImage: "calendar.badge.exclamationmark",
                                description: Text("Добавьте назначение, чтобы в журнале появились запланированные приёмы.")
                            )

                            Spacer()
                        }
                        .padding(.top, 32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground))
                    } else {
                        // список приёмов
                        TodayView(
                            date: selectedDate,
                            intakes: intakes
                        )
                    }
                }
            }
            // без собственного navigationTitle, всё в шапке
        }
    }

    // MARK: - агрегированный статус дня

    enum DayStatus {
        case none    // нет приёмов
        case pending // есть, но все в ожидании
        case completed // все приняты
        case skipped   // все пропущены
        case mixed     // смесь статусов
    }

    private func dayStatus(for date: Date) -> DayStatus {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let dayIntakes = buildIntakes(for: day)
        guard !dayIntakes.isEmpty else { return .none }

        var hasTaken = false
        var hasSkipped = false
        var hasPending = false

        for item in dayIntakes {
            for med in item.medications {
                let status = appState.getIntakeStatus(
                    courseId: item.courseId,
                    medicationId: med.id,
                    slotIndexInDay: item.slotIndexInDay,
                    date: day
                )

                switch status {
                case .taken: hasTaken = true
                case .skipped: hasSkipped = true
                case .pending: hasPending = true
                }
            }
        }

        if hasTaken && !hasSkipped && !hasPending {
            return .completed
        } else if hasSkipped && !hasTaken && !hasPending {
            return .skipped
        } else if hasPending && !hasTaken && !hasSkipped {
            return .pending
        } else {
            return .mixed
        }
    }

    // используем ту же логику, что и в TodayView, но параметризуем датой
    private func buildIntakes(for date: Date) -> [IntakeItem] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        let now = Date()

        var items: [IntakeItem] = []

        for course in appState.courses {
            let courseStart = calendar.startOfDay(for: course.startDate)
            // конец курса: start + totalDurationInDays
            let duration = max(1, course.totalDurationInDays)
            guard let courseEnd = calendar.date(
                byAdding: .day,
                value: duration,
                to: courseStart
            ) else { continue }

            // показываем только дни внутри курса [start; end)
            guard courseStart <= day, day < courseEnd else { continue }

            for slot in course.doseSlots {
                // фильтр по времени только для "сегодня"
                if day == today,
                   let hour = slot.time.hour,
                   let minute = slot.time.minute {
                    let slotDate = calendar.date(
                        bySettingHour: hour,
                        minute: minute,
                        second: 0,
                        of: day
                    ) ?? day

                    guard slotDate >= now else { continue }
                }

                let medicationIds = course.courseMedications
                    .filter { $0.slotIndexes.contains(slot.indexInDay) }
                    .map { $0.medicationId }

                let medications = course.medications.filter { medicationIds.contains($0.id) }
                guard !medications.isEmpty else { continue }

                let item = IntakeItem(
                    id: UUID(),
                    courseId: course.id,
                    courseName: course.name ?? course.medications.map { $0.name }.joined(separator: ", "),
                    slotIndexInDay: slot.indexInDay,
                    time: slot.time,
                    medications: medications,
                    date: day
                )

                items.append(item)
            }
        }

        return items.sorted { lhs, rhs in
            let lhsMinutes = (lhs.time.hour ?? 0) * 60 + (lhs.time.minute ?? 0)
            let rhsMinutes = (rhs.time.hour ?? 0) * 60 + (rhs.time.minute ?? 0)
            return lhsMinutes < rhsMinutes
        }
    }

    // MARK: - Верхний календарь

    private struct DayPickerView: View {
        let days: [Date]
        @Binding var selectedDate: Date
        let hasIntakesForDay: (Date) -> Bool
        let dayStatus: (Date) -> TodayRootView.DayStatus

        private let calendar = Calendar.current

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(days, id: \.self) { day in
                        DayCircleView(
                            date: day,
                            isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                            hasIntakes: hasIntakesForDay(day),
                            status: dayStatus(day)
                        )
                        .onTapGesture {
                            selectedDate = day
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private struct DayCircleView: View {
        let date: Date
        let isSelected: Bool
        let hasIntakes: Bool
        let status: TodayRootView.DayStatus

        private let calendar = Calendar.current

        // Кириллические буквы дней недели
        private var weekdayLetter: String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ru_RU")
            formatter.dateFormat = "EE" // краткое название дня недели на русском
            let symbol = formatter.string(from: date)
            return String(symbol.prefix(1)).uppercased()
        }

        private var dayNumber: String {
            let day = calendar.component(.day, from: date)
            return "\(day)"
        }

        // цвет фона кружка
        private var backgroundColor: Color {
            if isSelected {
                return Color.accentColor
            }

            switch status {
            case .completed:
                return Color.green.opacity(0.2)
            case .skipped:
                return Color.orange.opacity(0.2)
            case .mixed:
                return Color.yellow.opacity(0.25)
            case .pending:
                return hasIntakes ? Color.accentColor.opacity(0.15) : Color(.systemBackground)
            case .none:
                return Color(.systemBackground)
            }
        }

        // цвет нижней точки
        private var dotColor: Color {
            switch status {
            case .completed:
                return .green
            case .skipped:
                return .orange
            case .mixed:
                return .yellow
            case .pending:
                return isSelected ? .white : .accentColor
            case .none:
                return .clear
            }
        }

        var body: some View {
            VStack(spacing: 4) {
                Text(weekdayLetter)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ZStack(alignment: .bottom) {
                    Circle()
                        .strokeBorder(
                            hasIntakes ? Color.clear : Color(.systemGray4),
                            lineWidth: 1
                        )
                        .background(
                            Circle().fill(backgroundColor)
                        )
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(dayNumber)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(isSelected ? .white : .primary)
                        )

                    if hasIntakes {
                        Circle()
                            .fill(dotColor)
                            .frame(width: 6, height: 6)
                            .offset(y: 4)
                    }
                }
            }
        }
    }

    // MARK: - Заголовок дня

    private struct DayHeaderView: View {
        let date: Date

        private let calendar = Calendar.current

        private var title: String {
            let today = calendar.startOfDay(for: Date())
            let selected = calendar.startOfDay(for: date)

            if selected == today {
                return "Сегодня"
            } else if selected == calendar.date(byAdding: .day, value: 1, to: today) {
                return "Завтра"
            } else {
                return date.formatted(date: .long, time: .omitted)
            }
        }

        private var subtitle: String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ru_RU")
            formatter.dateFormat = "EEEE, d MMMM"
            return formatter.string(from: date).capitalized
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(subtitle)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

