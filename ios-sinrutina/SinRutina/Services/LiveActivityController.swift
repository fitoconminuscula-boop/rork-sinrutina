import ActivityKit
import Foundation
import Observation

/// Owns the Live Activity for the task in progress. Deliberately sober: one task,
/// one timer, one action.
@MainActor
@Observable
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<SRFocusAttributes>?
    private(set) var lastErrorMessage: String?

    private init() {}

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var isRunning: Bool { activity != nil }

    /// Starts (or replaces) the Live Activity for a task.
    func start(task: TaskItem, level: SRFocusLevel = .gentle) {
        guard CalendarPreferences.shared.isLiveActivityEnabled else { return }
        guard areActivitiesEnabled else { return }
        end(immediately: true)

        let attributes = SRFocusAttributes(
            taskID: task.id.uuidString,
            title: task.title,
            nextStep: task.nextStep,
            levelRaw: level.rawValue
        )
        let state = SRFocusAttributes.ContentState(
            runningSince: Date(),
            accumulatedMinutes: 0,
            plannedMinutes: task.estimatedMinutes,
            isPaused: false
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date().addingTimeInterval(Double(task.estimatedMinutes + 30) * 60)),
                pushType: nil
            )
        } catch {
            lastErrorMessage = "iOS no permitió mostrar la actividad en vivo."
        }
    }

    func pause(elapsedMinutes: Double, plannedMinutes: Int) {
        update(
            SRFocusAttributes.ContentState(
                runningSince: nil,
                accumulatedMinutes: elapsedMinutes,
                plannedMinutes: plannedMinutes,
                isPaused: true
            )
        )
    }

    /// A real break keeps the activity alive and says when it ends.
    func markBreak(elapsedMinutes: Double, plannedMinutes: Int, endsAt: Date) {
        update(
            SRFocusAttributes.ContentState(
                runningSince: nil,
                accumulatedMinutes: elapsedMinutes,
                plannedMinutes: plannedMinutes,
                isPaused: true,
                isOnBreak: true,
                breakEndsAt: endsAt
            )
        )
    }

    func resume(elapsedMinutes: Double, plannedMinutes: Int) {
        update(
            SRFocusAttributes.ContentState(
                runningSince: Date(),
                accumulatedMinutes: elapsedMinutes,
                plannedMinutes: plannedMinutes,
                isPaused: false
            )
        )
    }

    func end(immediately: Bool = false) {
        guard let activity else { return }
        let finalState = activity.content.state
        self.activity = nil
        Task {
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: immediately ? .immediate : .after(Date().addingTimeInterval(8))
            )
        }
    }

    /// Cleans up activities left behind by a previous launch.
    func reattachOrClear() {
        for existing in Activity<SRFocusAttributes>.activities {
            if activity == nil {
                activity = existing
            } else {
                Task { await existing.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }

    private func update(_ state: SRFocusAttributes.ContentState) {
        guard let activity else { return }
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }
}
