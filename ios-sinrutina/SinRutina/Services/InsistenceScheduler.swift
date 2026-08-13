#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
#endif
import Foundation
import Observation
import SwiftUI
import UserNotifications

/// One insistence system per task, using only legitimate system APIs.
///
/// * Suave / Normal / Importante → local notifications with rising interruption level.
/// * No me dejes olvidarlo → AlarmKit, the only sanctioned way to break through
///   silent mode and Focus. There are no fake calls and no endless background
///   vibration: if AlarmKit is unavailable we degrade to a time sensitive
///   notification and say so.
@MainActor
@Observable
final class InsistenceScheduler: NSObject {
    static let shared = InsistenceScheduler()

    enum Authorization: Equatable {
        case notDetermined
        case granted
        case denied
        case provisional
    }

    private(set) var notificationAuthorization: Authorization = .notDetermined
    private(set) var alarmAuthorizationGranted = false
    private(set) var lastErrorMessage: String?

    static let categoryIdentifier = "SR_TASK_REMINDER"
    private static let doneAction = "SR_DONE"
    private static let snoozeAction = "SR_SNOOZE"
    private static let openAction = "SR_OPEN"

    private override init() {
        super.init()
    }

    // MARK: - Setup

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // The three answers an alarm or notification may offer.
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [
                UNNotificationAction(identifier: Self.doneAction, title: "Hecho", options: []),
                UNNotificationAction(identifier: Self.snoozeAction, title: "Posponer 15 min", options: []),
                UNNotificationAction(identifier: Self.openAction, title: "Abrir SinRutina", options: [.foreground]),
            ],
            intentIdentifiers: [],
            options: []
        )
        // "Salir a tiempo" answers different questions, so it gets its own category.
        let leaveCategory = UNNotificationCategory(
            identifier: DepartureTimeEngine.notificationCategory,
            actions: [
                UNNotificationAction(
                    identifier: DepartureTimeEngine.departedAction,
                    title: "Estoy saliendo",
                    options: []
                ),
                UNNotificationAction(
                    identifier: DepartureTimeEngine.openAction,
                    title: "Ver la hora de salida",
                    options: [.foreground]
                ),
            ],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category, leaveCategory])
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .ephemeral: notificationAuthorization = .granted
        case .provisional: notificationAuthorization = .provisional
        case .denied: notificationAuthorization = .denied
        case .notDetermined: notificationAuthorization = .notDetermined
        @unknown default: notificationAuthorization = .notDetermined
        }
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            alarmAuthorizationGranted = AlarmManager.shared.authorizationState == .authorized
        }
        #endif
    }

    @discardableResult
    func requestNotificationAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
            return granted
        } catch {
            lastErrorMessage = "iOS no pudo activar las notificaciones."
            return false
        }
    }

    @discardableResult
    func requestAlarmAuthorization() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                let state = try await AlarmManager.shared.requestAuthorization()
                alarmAuthorizationGranted = state == .authorized
                return alarmAuthorizationGranted
            } catch {
                lastErrorMessage = "iOS no pudo autorizar las alarmas."
                return false
            }
        }
        #endif
        return false
    }

    var isAlarmKitAvailable: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    // MARK: - Scheduling

    /// Applies the task's insistence level. Always cancels first so a task never
    /// ends up with two competing reminders.
    func schedule(for task: TaskItem) async {
        await cancel(for: task)
        guard let fireDate = task.remindAt, fireDate > Date() else { return }

        if task.insistence.usesAlarmKit, await ensureAlarmReady() {
            if await scheduleAlarm(for: task, at: fireDate) { return }
        }
        await scheduleNotification(for: task, at: fireDate)
    }

    func cancel(for task: TaskItem) async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])

        #if canImport(AlarmKit)
        if #available(iOS 26.0, *),
           let identifier = task.alarmIdentifier,
           let uuid = UUID(uuidString: identifier) {
            try? AlarmManager.shared.cancel(id: uuid)
        }
        #endif
        task.alarmIdentifier = nil
    }

    /// Pushes a reminder 15 minutes forward. Used by the notification action.
    func snooze(taskID: String, minutes: Int = 15) {
        let content = UNMutableNotificationContent()
        content.title = "SinRutina"
        content.body = "Retomamos esto en cuanto puedas."
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["taskID": taskID]
        content.interruptionLevel = .active
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(minutes) * 60, repeats: false)
        let request = UNNotificationRequest(identifier: taskID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Notifications

    private func scheduleNotification(for task: TaskItem, at fireDate: Date) async {
        if notificationAuthorization == .notDetermined {
            await requestNotificationAuthorization()
        }
        guard notificationAuthorization == .granted || notificationAuthorization == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = task.nextStep ?? "Un paso pequeño y ya está empezado."
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["taskID": task.id.uuidString]

        switch task.insistence {
        case .gentle:
            content.interruptionLevel = .passive
            content.sound = nil
        case .normal:
            content.interruptionLevel = .active
            content.sound = .default
        case .important, .unmissable:
            content.interruptionLevel = .timeSensitive
            content.sound = .defaultCritical
        }

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: task.id.uuidString,
            content: content,
            trigger: trigger
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            lastErrorMessage = "No pudimos programar el aviso."
        }
    }

    // MARK: - AlarmKit

    private func ensureAlarmReady() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            if AlarmManager.shared.authorizationState == .authorized { return true }
            return await requestAlarmAuthorization()
        }
        #endif
        return false
    }

    private func scheduleAlarm(for task: TaskItem, at fireDate: Date) async -> Bool {
        #if canImport(AlarmKit)
        guard #available(iOS 26.0, *) else { return false }
        let alarmID = UUID()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: fireDate)
        guard let hour = components.hour, let minute = components.minute else { return false }

        let stopButton = AlarmButton(
            text: "Hecho",
            textColor: .white,
            systemImageName: "checkmark"
        )
        let openButton = AlarmButton(
            text: "Abrir",
            textColor: .white,
            systemImageName: "arrow.up.forward.app"
        )
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: task.title),
            stopButton: stopButton,
            secondaryButton: openButton,
            secondaryButtonBehavior: .custom
        )
        let attributes = AlarmAttributes<SRAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: SRAlarmMetadata(
                taskID: task.id.uuidString,
                taskTitle: task.title,
                nextStep: task.nextStep
            ),
            tintColor: SRDesign.primary
        )
        let schedule = Alarm.Schedule.relative(
            .init(time: .init(hour: hour, minute: minute), repeats: .never)
        )
        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: nil,
            schedule: schedule,
            attributes: attributes,
            stopIntent: SRAlarmDoneIntent(alarmID: alarmID.uuidString, taskID: task.id.uuidString),
            secondaryIntent: SRAlarmOpenIntent(alarmID: alarmID.uuidString, taskID: task.id.uuidString),
            sound: .default
        )
        do {
            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
            task.alarmIdentifier = alarmID.uuidString
            return true
        } catch {
            lastErrorMessage = "iOS no aceptó la alarma. Usamos un aviso urgente."
            return false
        }
        #else
        return false
        #endif
    }
}

extension InsistenceScheduler: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let taskID = userInfo["taskID"] as? String

        if response.notification.request.content.categoryIdentifier == DepartureTimeEngine.notificationCategory {
            let eventID = userInfo["eventID"] as? String
            switch response.actionIdentifier {
            case DepartureTimeEngine.departedAction:
                if let eventID {
                    // Starts measuring the real trip from the notification itself.
                    await MainActor.run { PersonalTravelEngine.shared.startLeaving(eventID: eventID) }
                }
            default:
                SRCommandBus.send(SRPendingCommand(kind: .openDeparture))
            }
            return
        }

        switch response.actionIdentifier {
        case Self.doneAction:
            SRCommandBus.send(SRPendingCommand(kind: .finishCurrent, taskID: taskID))
        case Self.snoozeAction:
            if let taskID {
                await MainActor.run { InsistenceScheduler.shared.snooze(taskID: taskID) }
            }
        default:
            SRCommandBus.send(SRPendingCommand(kind: .startCurrent, taskID: taskID))
        }
    }
}
