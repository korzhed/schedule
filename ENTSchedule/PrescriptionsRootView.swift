import SwiftUI

struct PrescriptionsRootView: View {

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var notificationService: NotificationService

    @State private var showAddPrescription: Bool = false

    var body: some View {

        NavigationStack {

            ZStack {

                Color(.systemBackground)
                    .ignoresSafeArea()

                Group {
                    if appState.courses.isEmpty {

                        VStack(spacing: 24) {

                            ContentUnavailableView(
                                "Нет назначений",
                                systemImage: "doc.text.magnifyingglass",
                                description: Text("Добавьте первое назначение, чтобы начать отслеживание приёма лекарств")
                            )

                            Button {
                                showAddPrescription = true
                            } label: {
                                Text("Добавить")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .buttonBorderShape(.roundedRectangle(radius: 12))
                            .tint(.blue)
                            .padding(.horizontal, 20)

                            Spacer()
                        }
                        .padding(.top, 32)

                    } else {

                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {

                                LazyVStack(spacing: 12) {
                                    ForEach(appState.courses.sorted(by: { $0.createdAt > $1.createdAt })) { course in
                                        NavigationLink(value: course) {
                                            CourseRowView(course: course)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.horizontal, 16)
                                    }
                                }
                                .padding(.bottom, 16)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Назначения")          // маленький системный заголовок
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(for: Course.self) { course in
                CourseDetailView(courseId: course.id)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddPrescription = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddPrescription) {
                AddPrescriptionFlow(onComplete: { newCourse in
                    // Курс уже добавлен внутри ScheduleStepView.createCourse
                    if newCourse.remindersEnabled {
                        notificationService.scheduleNotifications(for: newCourse)
                    }
                    showAddPrescription = false
                })
                .environmentObject(appState)
                .environmentObject(notificationService)
            }
        }
    }

    private func deleteCourses(at offsets: IndexSet) {
        let sortedCourses = appState.courses.sorted(by: { $0.createdAt > $1.createdAt })
        for index in offsets {
            if let courseIndex = appState.courses.firstIndex(where: { $0.id == sortedCourses[index].id }) {
                appState.courses.remove(at: courseIndex)
            }
        }
    }
}

/// MARK: - CourseRowView

struct CourseRowView: View {

    @EnvironmentObject private var appState: AppState

    let course: Course

    private var overallProgress: Double {
        appState.getOverallProgress(for: course) // 0...1
    }

    private var progressPercentText: String {
        "\(Int(overallProgress * 100))%"
    }

    var body: some View {

        HStack(spacing: 12) {

            // Левая часть: текстовый контент
            VStack(alignment: .leading, spacing: 12) {

                // Название препаратов
                Text(course.medications.map { $0.name }.joined(separator: ", "))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Кол‑во лекарств и приёмов в день
                HStack(spacing: 12) {
                    Label("\(course.medications.count) лекарств", systemImage: "pills.fill")
                    Label("\(course.doseSlots.count) приёмов/день", systemImage: "clock.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                // Дата начала
                HStack {
                    Text("Начало: \(course.startDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            // Правая часть: вертикальный индикатор прогресса
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(.systemGray5))

                GeometryReader { geo in
                    let height = max(4, geo.size.height * overallProgress)

                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.blue)
                            .frame(height: height)
                    }
                }
            }
            .frame(width: 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// MARK: - AddPrescriptionFlow

struct AddPrescriptionFlow: View {

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var notificationService: NotificationService
    @Environment(\.dismiss) private var dismiss

    let onComplete: (Course) -> Void

    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            PrescriptionInputStepView(
                onNext: { medications in
                    print("FLOW onNext medications =", medications.map { "\($0.name) \($0.timesPerDay)x" })
                    navigationPath.append(medications)
                }
            )
            .navigationDestination(for: [MedicationItem].self) { medications in
                ScheduleStepView(
                    parsedMedications: medications,
                    onComplete: { createdCourse in
                        onComplete(createdCourse)
                        dismiss()
                    }
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
        }
    }
}

