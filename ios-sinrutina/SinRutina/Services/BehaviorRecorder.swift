import Foundation
import SwiftData

/// The single door into the local behaviour profile.
///
/// Everything recorded here is an observable fact: a duration, a timing, a choice.
/// Nothing here infers a state of mind, and none of it leaves the device.
@MainActor
enum BehaviorRecorder {
    static func profile(context: ModelContext) -> BehaviorProfile {
        let descriptor = FetchDescriptor<BehaviorProfile>()
        let existing = (try? context.fetch(descriptor))?.first
        if let existing { return existing }
        let created = BehaviorProfile()
        context.insert(created)
        return created
    }

    static func recordCompletion(for task: TaskItem, actualMinutes: Double, context: ModelContext) {
        let profile = profile(context: context)
        profile.recordCompletion(
            estimatedMinutes: task.estimatedMinutes,
            actualMinutes: actualMinutes,
            hour: Calendar.current.component(.hour, from: Date())
        )
        profile.recordSession(minutes: actualMinutes, isStudy: task.isStudy)
        LearningEngine.refresh(from: profile)
    }

    static func recordActionResponse(_ response: String, context: ModelContext) {
        profile(context: context).recordActionResponse(response)
    }

    // MARK: - Adherence signals

    /// Minutes between SinRutina proposing something and the person starting it.
    static func recordTimeToStart(minutes: Double, context: ModelContext) {
        let profile = profile(context: context)
        profile.recordTimeToStart(minutes: minutes)
        LearningEngine.refresh(from: profile)
    }

    static func recordIgnoredReminder(at date: Date = Date(), context: ModelContext) {
        let profile = profile(context: context)
        profile.recordIgnoredReminder(hour: Calendar.current.component(.hour, from: date))
        LearningEngine.refresh(from: profile)
    }

    /// The micro action that actually unlocked movement.
    static func recordMicroActionWin(_ action: String, context: ModelContext) {
        let profile = profile(context: context)
        profile.recordMicroActionWin(action)
        LearningEngine.refresh(from: profile)
    }

    static func recordExplainAction(_ action: SRExplainAction, context: ModelContext) {
        let profile = profile(context: context)
        profile.recordExplainAction(action.rawValue)
        LearningEngine.refresh(from: profile)
    }

    static func recordReplyStyle(_ style: SRReplyStyle, context: ModelContext) {
        let profile = profile(context: context)
        profile.recordReplyStyle(style.rawValue)
        LearningEngine.refresh(from: profile)
    }

    static func recordRecall(hit: Bool, context: ModelContext) {
        profile(context: context).recordRecall(hit: hit)
    }

    static func recordWebSearch(context: ModelContext) {
        let profile = profile(context: context)
        profile.webSearchCount += 1
        profile.updatedAt = Date()
        LearningEngine.refresh(from: profile)
    }

    static func recordPause(context: ModelContext) {
        let profile = profile(context: context)
        profile.pauseCount += 1
        profile.updatedAt = Date()
    }

    // MARK: - Behavioural environment signals

    static func recordFocusStart(level: SRFocusLevel, context: ModelContext) {
        let profile = profile(context: context)
        profile.recordFocusStart(level: level.rawValue)
    }

    /// Called once a session closes, with what the person said about it.
    static func recordFocusOutcome(
        level: SRFocusLevel,
        finished: Bool,
        exits: Int,
        minutes: Double = 0,
        context: ModelContext
    ) {
        let profile = profile(context: context)
        profile.recordFocusOutcome(level: level.rawValue, finished: finished, exits: exits, minutes: minutes)
        profile.distractionAttemptCount += max(0, exits)
        LearningEngine.refresh(from: profile)
    }

    static func recordBreak(context: ModelContext) {
        let profile = profile(context: context)
        profile.breakCount += 1
        profile.updatedAt = Date()
    }

    static func recordEmergency(context: ModelContext) {
        let profile = profile(context: context)
        profile.emergencyCount += 1
        profile.updatedAt = Date()
        // Needing the phone back is never treated as a failure, only as evidence
        // that this environment was too tight.
        LearningEngine.refresh(from: profile)
    }

    static func recordPartialProgress(context: ModelContext) {
        let profile = profile(context: context)
        profile.partialProgressCount += 1
        profile.updatedAt = Date()
    }

    static func recordFollowUp(context: ModelContext) {
        let profile = profile(context: context)
        profile.followUpCount += 1
        profile.updatedAt = Date()
    }
}
