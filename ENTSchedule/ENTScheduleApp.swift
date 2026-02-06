//
//  ENTScheduleApp.swift
//  ENTSchedule
//
//  Created by vl.korzh on 30.01.2026.
//

import SwiftUI
import Combine
import UserNotifications

// MARK: - NotificationService

final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    let objectWillChange = PassthroughSubject<Void, Never>()

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error = error {
                    print("Error requesting notification authorization: \(error)")
                } else {
                    print("Notifications granted: \(granted)")
                }
            }
    }

    func clearAllScheduled() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        print("All pending notifications cleared")
    }

    /// Пересоздать уведомления для конкретного курса:
    /// 1) удалить все pending c префиксом course-{id}
    /// 2) заново вызвать scheduleNotifications(for:)
    func rescheduleNotifications(for course: Course) {
        let center = UNUserNotificationCenter.current()
        let prefix = "course-\(course.id.uuidString)-"

        center.getPendingNotificationRequests { existing in
            let toRemove = existing
                .filter { $0.identifier.hasPrefix(prefix) }
                .map { $0.identifier }

            if !toRemove.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: toRemove)
                print("Removed \(toRemove.count) notifications for course \(course.id)")
            }

            DispatchQueue.main.async {
                self.scheduleNotifications(for: course)
            }
        }
    }

    /// Планируем уведомления для одного курса:
    /// ежедневные по слотам, с учётом смещения reminderOffsetMinutes.
    func scheduleNotifications(for course: Course) {
        guard course.remindersEnabled else {
            print("Reminders disabled for course, skip scheduling")
            return
        }

        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current

        let today = calendar.startOfDay(for: Date())

        for slot in course.doseSlots {
            guard let hour = slot.time.hour, let minute = slot.time.minute else { continue }

            // Лекарства, привязанные к этому слоту
            let medicationIds = course.courseMedications
                .filter { $0.slotIndexes.contains(slot.indexInDay) }
                .map { $0.medicationId }

            let meds = course.medications.filter { medicationIds.contains($0.id) }

            // Заголовок: имя курса или первое лекарство
            let courseTitle: String = {
                if let name = course.name, !name.isEmpty {
                    return name
                }
                if let first = meds.first {
                    return first.name
                }
                return "Приём лекарств"
            }()

            // Тело: список лекарств
            let medsList = meds.isEmpty
                ? "Проверьте расписание приёма"
                : meds.map { $0.name }.joined(separator: ", ")

            // Базовое время приёма (сегодняшний день + время слота)
            var fireDate = calendar.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: today
            ) ?? Date()

            // Сдвиг на reminderOffsetMinutes ДО времени приёма
            if course.reminderOffsetMinutes > 0 {
                fireDate = fireDate.addingTimeInterval(
                    TimeInterval(-course.reminderOffsetMinutes * 60)
                )
            }

            // Если время в прошлом — сдвигаем на завтра, чтобы не шлать "задним числом"
            if fireDate < Date() {
                fireDate = calendar.date(byAdding: .day, value: 1, to: fireDate) ?? fireDate
            }

            let triggerDateComponents = calendar.dateComponents(
                [.hour, .minute],
                from: fireDate
            )

            let content = UNMutableNotificationContent()
            content.title = "Курс: \(courseTitle)"
            content.body = "Время приёма: \(medsList)"
            content.sound = .default

            // Повторяем каждый день в это время
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: triggerDateComponents,
                repeats: true
            )

            let identifier = "course-\(course.id.uuidString)-slot-\(slot.id.uuidString)"
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            center.add(request) { error in
                if let error = error {
                    print("Error scheduling notification: \(error)")
                } else {
                    print("Scheduled notification for \(fireDate) with id \(identifier)")
                }
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - App

@main
struct ENTScheduleApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var notificationService = NotificationService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(notificationService)
                .onAppear {
                    notificationService.requestAuthorization()

                    // Пробрасываем сервис в AppState,
                    // чтобы он мог сам reschedule при изменении курса
                    appState.attachNotificationService(notificationService)

                    // Если курсов нет — сразу чистим уведомления
                    if appState.courses.isEmpty {
                        notificationService.clearAllScheduled()
                    }
                }
                .onChange(of: appState.courses.count) { _, newCount in
                    if newCount == 0 {
                        notificationService.clearAllScheduled()
                    }
                }

            
        }
    }
}
