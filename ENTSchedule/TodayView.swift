import SwiftUI

/// Элемент приёма для конкретного дня
struct IntakeItem: Identifiable, Hashable {
    let id: UUID
    let courseId: UUID
    let courseName: String
    let slotIndexInDay: Int
    let time: DateComponents
    let medications: [MedicationItem]
    let date: Date
}

struct TodayView: View {

    @EnvironmentObject private var appState: AppState

    let date: Date
    let intakes: [IntakeItem]

    private var canInteract: Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let day = calendar.startOfDay(for: date)
        return day <= today
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            Group {
                if intakes.isEmpty {
                    ScrollView {
                        VStack(spacing: 16) {
                            Spacer().frame(height: 40)

                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)

                            Text("В этот день приёмов нет")
                                .font(.headline)
                                .foregroundColor(.primary)

                            Text("Добавьте курс в разделе \"Назначения\", чтобы увидеть здесь запланированные приёмы.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)

                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(intakes) { item in
                                TodayIntakeCard(
                                    item: item,
                                    date: date,
                                    canInteract: canInteract
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }
}

// MARK: - Карточка приёма

private struct TodayIntakeCard: View {

    @EnvironmentObject private var appState: AppState

    let item: IntakeItem
    let date: Date
    let canInteract: Bool

    private var timeString: String {
        let hour = item.time.hour ?? 0
        let minute = item.time.minute ?? 0

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"

        let calendar = Calendar.current
        let date = calendar.date(from: components) ?? Date()
        return formatter.string(from: date)
    }

    private func status(for medication: MedicationItem) -> IntakeStatus {
        appState.getIntakeStatus(
            courseId: item.courseId,
            medicationId: medication.id,
            slotIndexInDay: item.slotIndexInDay,
            date: date
        )
    }

    private func setStatus(_ status: IntakeStatus, for medication: MedicationItem) {
        guard canInteract else { return }

        appState.markIntake(
            courseId: item.courseId,
            medicationId: medication.id,
            slotIndexInDay: item.slotIndexInDay,
            date: date,
            status: status
        )
    }

    private func color(for status: IntakeStatus) -> Color {
        switch status {
        case .taken:
            return .green
        case .skipped:
            return .orange
        case .pending:
            return .gray.opacity(0.5)
        }
    }

    /// Можно ли уже показывать контрол (когда время приёма наступило или прошло)
    private func canShowStatusIcon(now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        var components = item.time
        components.calendar = calendar

        let slotDate = calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: 0,
            of: date
        ) ?? date

        return slotDate <= now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // верхняя строка: время и курс
            HStack(alignment: .firstTextBaseline) {
                Text(timeString)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)

                Spacer()

                Text(item.courseName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // лекарства
            ForEach(item.medications) { med in
                let s = status(for: med)
                let showIcon = canShowStatusIcon()

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(med.name)
                                .font(.body)
                                .foregroundColor(.primary)

                            Text(med.dosage)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let comment = med.comment, !comment.isEmpty {
                                Text(comment)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }

                        Spacer()

                        if showIcon && canInteract {
                            Button {
                                let current = s
                                let newStatus: IntakeStatus
                                switch current {
                                case .pending:
                                    // первый тап после наступления времени — считаем, что принял
                                    newStatus = .taken
                                case .taken:
                                    // переключаемся на "пропустил"
                                    newStatus = .skipped
                                case .skipped:
                                    // снова "принял"
                                    newStatus = .taken
                                }

                                setStatus(newStatus, for: med)
                            } label: {
                                Group {
                                    switch s {
                                    case .pending:
                                        Image(systemName: "circle")
                                            .foregroundColor(color(for: s))
                                    case .taken:
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(color(for: s))
                                    case .skipped:
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(color(for: s))
                                    }
                                }
                                .font(.title3)
                            }
                            .buttonStyle(.plain)
                        } else if showIcon && !canInteract {
                            // прошлые дни: только отображаем статус
                            Image(
                                systemName: s == .taken
                                    ? "checkmark.circle.fill"
                                    : (s == .skipped ? "xmark.circle.fill" : "circle")
                            )
                            .font(.title3)
                            .foregroundStyle(color(for: s))
                        }
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .modifier(SwipeStatusModifier(
                        canInteract: canInteract && canShowStatusIcon(),
                        onTaken: { setStatus(.taken, for: med) },
                        onSkipped: { setStatus(.skipped, for: med) }
                    ))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .opacity(canInteract ? 1.0 : 0.4)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Модификатор свайпа

private struct SwipeStatusModifier: ViewModifier {
    let canInteract: Bool
    let onTaken: () -> Void
    let onSkipped: () -> Void

    func body(content: Content) -> some View {
        if canInteract {
            content
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        onTaken()
                    } label: {
                        Label("Принял", systemImage: "checkmark")
                    }
                    .tint(.green)

                    Button {
                        onSkipped()
                    } label: {
                        Label("Пропустил", systemImage: "xmark")
                    }
                    .tint(.orange)
                }
        } else {
            content
        }
    }
}

// MARK: - Preview

struct TodayView_Previews: PreviewProvider {
    static var previews: some View {
        let appState = AppState()

        let med = MedicationItem(
            id: UUID(),
            name: "Амоксициллин",
            dosage: "500 мг",
            timesPerDay: 3,
            durationInDays: 7,
            comment: "После еды"
        )

        let item = IntakeItem(
            id: UUID(),
            courseId: UUID(),
            courseName: "Тестовый курс",
            slotIndexInDay: 1,
            time: DateComponents(hour: 9, minute: 0),
            medications: [med],
            date: Date()
        )

        return Group {
            NavigationStack {
                TodayView(
                    date: Date(),
                    intakes: [item]
                )
                .environmentObject(appState)
            }
            .preferredColorScheme(.light)

            NavigationStack {
                TodayView(
                    date: Date(),
                    intakes: [item]
                )
                .environmentObject(appState)
            }
            .preferredColorScheme(.dark)
        }
    }
}

