import Foundation
import UserNotifications

/// Turns a duration into a decision: when to stop what you are doing, when to get
/// ready, and when to walk out.
///
/// It is pure arithmetic plus the rules about when SinRutina is allowed to speak.
/// It knows nothing about Core Location, maps or the calendar, so it can be reused
/// by Ahora, the widget, notifications and Live Activities without changes.
@MainActor
struct DepartureTimeEngine {
    /// Everything needed to compute one departure, gathered by the caller.
    struct Input {
        var eventID: String
        var eventTitle: String
        var destinationLabel: String
        var destinationID: UUID?
        var eventStart: Date
        var mode: SRTravelMode?
        /// Nil when there is no honest duration: the plan then asks instead.
        var estimate: TravelEstimate?
        var prepMinutes: Int
        var arriveEarlyMinutes: Int
        /// Parking and the walk to the door, when the place taught us one.
        var finalStretchMinutes: Int
        var notice: String?
    }

    static let notificationCategory = "SR_LEAVE_ON_TIME"
    static let departedAction = "SR_LEFT_NOW"
    static let openAction = "SR_LEAVE_OPEN"
    private static let notificationPrefix = "sr.leave."

    /// Minutes before leaving at which the "start closing things" phase opens.
    static let prepareLeadMinutes = 25
    /// Minutes before leaving at which "get ready" starts.
    static let getReadyLeadMinutes = 10

    // MARK: - Building

    func plan(from input: Input, now: Date = Date()) -> SRDeparturePlan {
        let targetArrival = input.eventStart.addingTimeInterval(-Double(input.arriveEarlyMinutes) * 60)
        let caution = input.estimate?.confidence.cautionMinutes ?? 0

        var leaveAt: Date?
        var startPrepAt: Date?
        if let estimate = input.estimate {
            let extras = Double(input.prepMinutes + caution + input.finalStretchMinutes) * 60
            let departure = targetArrival.addingTimeInterval(-(estimate.planningSeconds + extras))
            leaveAt = departure
            // Preparation starts before leaving, and never before the person could
            // reasonably act on it.
            startPrepAt = departure.addingTimeInterval(-Double(Self.prepareLeadMinutes) * 60)
        }

        return SRDeparturePlan(
            eventID: input.eventID,
            eventTitle: input.eventTitle,
            destinationLabel: input.destinationLabel,
            destinationID: input.destinationID,
            eventStart: input.eventStart,
            modeRaw: input.mode?.rawValue,
            estimate: input.estimate,
            prepMinutes: input.prepMinutes,
            arriveEarlyMinutes: input.arriveEarlyMinutes,
            cautionMinutes: caution,
            finalStretchMinutes: input.finalStretchMinutes,
            leaveAt: leaveAt,
            startPrepAt: startPrepAt,
            notice: input.notice,
            computedAt: now
        )
    }

    // MARK: - Speaking

    /// Schedules the phase notifications for one plan and returns the updated
    /// record, so the caller can persist what was already said.
    ///
    /// Rules: each phase speaks once, silence when the person turned it off, and a
    /// recalculation that moves the hour by a couple of minutes never speaks at all.
    func announce(
        _ plan: SRDeparturePlan,
        previous: SRDeparturePlanRecord?,
        threshold: Int,
        isInterruptionAllowed: Bool,
        now: Date = Date()
    ) async -> SRDeparturePlanRecord {
        var announced = previous?.announcedPhases ?? []
        var notifiedChangeAt = previous?.notifiedChangeAt

        cancelNotifications(eventID: plan.eventID)

        if isInterruptionAllowed, let leaveAt = plan.leaveAt, let startPrepAt = plan.startPrepAt {
            // Future phases are scheduled; past ones are simply not re-announced.
            await schedule(
                phase: .prepare,
                at: startPrepAt,
                plan: plan,
                now: now,
                announced: &announced
            )
            await schedule(
                phase: .getReady,
                at: leaveAt.addingTimeInterval(-Double(Self.getReadyLeadMinutes) * 60),
                plan: plan,
                now: now,
                announced: &announced
            )
            await schedule(
                phase: .leaveNow,
                at: leaveAt,
                plan: plan,
                now: now,
                announced: &announced
            )

            // A meaningful change to an hour already announced is worth one word.
            if let previousLeaveAt = previous?.leaveAt {
                let delta = abs(previousLeaveAt.timeIntervalSince(leaveAt) / 60)
                let isRepeatSoon = notifiedChangeAt.map { now.timeIntervalSince($0) < 20 * 60 } ?? false
                if delta >= Double(threshold),
                   !isRepeatSoon,
                   leaveAt > now.addingTimeInterval(3 * 60),
                   announced.contains(SRDeparturePhase.prepare.rawValue) {
                    await sendChangeNotification(plan, becameEarlier: previousLeaveAt > leaveAt)
                    notifiedChangeAt = now
                }
            }
        }

        return SRDeparturePlanRecord(
            eventID: plan.eventID,
            leaveAt: plan.leaveAt,
            travelMinutes: plan.estimate?.planningMinutes ?? 0,
            modeRaw: plan.modeRaw,
            announcedPhases: announced,
            notifiedChangeAt: notifiedChangeAt,
            updatedAt: now
        )
    }

    private func schedule(
        phase: SRDeparturePhase,
        at date: Date,
        plan: SRDeparturePlan,
        now: Date,
        announced: inout [String]
    ) async {
        guard date > now.addingTimeInterval(20) else {
            // The moment already passed: mark it as said so it never fires late.
            if date <= now, !announced.contains(phase.rawValue) {
                announced.append(phase.rawValue)
            }
            return
        }
        guard let content = content(for: phase, plan: plan) else { return }
        let request = UNNotificationRequest(
            identifier: Self.notificationPrefix + plan.eventID + "." + phase.rawValue,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: max(20, date.timeIntervalSince(now)),
                repeats: false
            )
        )
        try? await UNUserNotificationCenter.current().add(request)
        if !announced.contains(phase.rawValue) {
            announced.append(phase.rawValue)
        }
    }

    /// Neutral wording, always. Nothing here blames the person for anything.
    private func content(for phase: SRDeparturePhase, plan: SRDeparturePlan) -> UNMutableNotificationContent? {
        guard let leaveAt = plan.leaveAt else { return nil }
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Self.notificationCategory
        content.userInfo = ["eventID": plan.eventID]
        content.sound = .default

        switch phase {
        case .prepare:
            let minutes = max(1, Int(leaveAt.timeIntervalSince(plan.startPrepAt ?? leaveAt) / 60))
            content.title = "Preparación"
            content.body = "Tienes que salir en \(minutes) minutos. Empieza a cerrar lo que estás haciendo."
            content.interruptionLevel = .active
        case .getReady:
            content.title = "Alistarse"
            content.body = "Sales en \(Self.getReadyLeadMinutes) minutos hacia \(plan.destinationLabel)."
            content.interruptionLevel = .active
        case .leaveNow:
            content.title = "Es hora de salir"
            let time = SRWidgetSnapshot.timeFormatter.string(from: plan.eventStart)
            content.body = "\(plan.destinationLabel) · empieza a las \(time)."
            content.interruptionLevel = .timeSensitive
        case .late, .notYet:
            return nil
        }
        if plan.isSimulated {
            content.title = "Simulación · " + content.title
        }
        return content
    }

    private func sendChangeNotification(_ plan: SRDeparturePlan, becameEarlier: Bool) async {
        guard let leaveAt = plan.leaveAt else { return }
        let time = SRWidgetSnapshot.timeFormatter.string(from: leaveAt)
        let content = UNMutableNotificationContent()
        content.title = becameEarlier ? "Conviene salir antes" : "Puedes salir un poco más tarde"
        content.body = becameEarlier
            ? "Ahora conviene salir a las \(time)."
            : "Con salir a las \(time) llegas bien."
        content.categoryIdentifier = Self.notificationCategory
        content.userInfo = ["eventID": plan.eventID]
        content.interruptionLevel = .active
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.notificationPrefix + plan.eventID + ".change",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Said only when leaving right now already means arriving late. It states the
    /// fact and stops there.
    func sendLateRiskNotification(_ plan: SRDeparturePlan, lateMinutes: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Riesgo de atraso"
        content.body = "Si sales ahora, probablemente llegues unos \(lateMinutes) minutos tarde."
        content.categoryIdentifier = Self.notificationCategory
        content.userInfo = ["eventID": plan.eventID]
        content.interruptionLevel = .timeSensitive
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.notificationPrefix + plan.eventID + ".late",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelNotifications(eventID: String) {
        let identifiers = SRDeparturePhase.allCases.map {
            Self.notificationPrefix + eventID + "." + $0.rawValue
        } + [
            Self.notificationPrefix + eventID + ".change",
            Self.notificationPrefix + eventID + ".late",
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
