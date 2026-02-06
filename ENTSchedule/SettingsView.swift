import SwiftUI
import UserNotifications

struct SettingsView: View {

    @EnvironmentObject private var appState: AppState
    @State private var showResetAlert = false
    @State private var notificationsEnabled: Bool = false
    @State private var notificationsStatusDescription: String = ""

    private let storageKey = "AppStateStorage_v1"

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {

                        // Внешний вид
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Внешний вид")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            VStack(spacing: 12) {
                                Picker("Тема оформления", selection: $appState.colorScheme) {
                                    ForEach(AppColorScheme.allCases) { scheme in
                                        Text(scheme.localizedTitle).tag(scheme)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                        }

                        // Данные
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Данные")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            VStack(spacing: 12) {
                                HStack {
                                    Text("Активные курсы")
                                    Spacer()
                                    Text("\(appState.courses.count)")
                                        .foregroundStyle(.secondary)
                                }

                                HStack {
                                    Text("Лекарства (в курсах)")
                                    Spacer()
                                    Text("\(totalMedicationsCount())")
                                        .foregroundStyle(.secondary)
                                }

                                Divider()

                                Button(role: .destructive) {
                                    showResetAlert = true
                                } label: {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Очистить все данные")
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                        }

                        // Уведомления
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Уведомления")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            VStack(spacing: 12) {
                                HStack {
                                    Text("Статус уведомлений")
                                    Spacer()
                                    Text(notificationsStatusDescription)
                                        .foregroundStyle(.secondary)
                                }

                                Button {
                                    openNotificationSettings()
                                } label: {
                                    HStack {
                                        Image(systemName: "bell.badge")
                                        Text("Открыть настройки уведомлений")
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                        }

                        // Футер
                        Text("Данные приложения сохраняются локально на устройстве и не выходят за его пределы.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Очистить все данные?", isPresented: $showResetAlert) {
                Button("Отмена", role: .cancel) { }
                Button("Очистить", role: .destructive) {
                    resetAllData()
                }
            } message: {
                Text("Будут удалены все курсы, лекарства и отметки приёма. Отменить это действие будет нельзя.")
            }
            .onAppear {
                refreshNotificationStatus()
            }
        }
    }

    // MARK: - Helpers

    private func totalMedicationsCount() -> Int {
        var set = Set<UUID>()
        for course in appState.courses {
            for med in course.medications {
                set.insert(med.id)
            }
        }
        return set.count
    }

    private func resetAllData() {
        // Очистка UserDefaults, где лежит состояние AppState
        UserDefaults.standard.removeObject(forKey: storageKey)

        // Очистка текущего состояния в памяти
        appState.courses = []
        appState.medications = []
        appState.intakeStatuses = [:]
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .notDetermined:
                    notificationsStatusDescription = "Не запрошены"
                case .denied:
                    notificationsStatusDescription = "Отключены"
                case .authorized, .provisional, .ephemeral:
                    notificationsStatusDescription = "Включены"
                @unknown default:
                    notificationsStatusDescription = "Неизвестно"
                }
            }
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        } else if let url = URL(string: UIApplication.openSettingsURLString),
                  UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SettingsView()
                .environmentObject(AppState())
        }
    }
}

