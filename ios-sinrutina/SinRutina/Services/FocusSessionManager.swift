import Foundation
import Observation
import SwiftData
import WidgetKit

/// The single source of truth for a session in progress.
///
/// Everything about "estoy haciendo esto ahora" lives here: which task, which
/// level, which profile, which restrictions, when it started, how long it has
/// run, pauses, apps released for this session, the Live Activity, the recovery
/// state and how it ended. No other type is allowed to decide any of that.
@MainActor
@Observable
final class FocusSessionManager {
    static let shared = FocusSessionManager()

    /// The live session, mirrored to the app group so it survives a relaunch.
    private(set) var session: SRFocusSessionSnapshot?
    /// Explained out loud when SinRutina had to undo something after a failure.
    private(set) var recoveryNotice: String?
    /// Set when the shield asked for the way out, so the app opens the friction.
    private(set) var pendingPauseRequest: SRShieldSignal?
    /// Set when a session was interrupted and the person may want to come back.
    private(set) var reentry: SRFocusSessionSnapshot?

    private let screenTime = ScreenTimeService.shared

    private init() {}

    // MARK: - Reading

    var isRunning: Bool { session != nil }
    var level: SRFocusLevel { session?.level ?? .gentle }
    var restrictionsActive: Bool { session?.restrictionsActive ?? false }
    var isPaused: Bool { session?.phase == .paused }
    var isOnBreak: Bool { session?.phase == .onBreak }
    var breakEndsAt: Date? { session?.breakEndsAt }
    var releasedApp: String? { session?.releasedApp }
    var exitAttempts: Int { session?.exitAttempts ?? 0 }

    func elapsedSeconds(at date: Date = Date()) -> Double {
        session?.elapsed(at: date) ?? 0
    }

    func isRunning(taskID: UUID) -> Bool {
        session?.taskID == taskID.uuidString
    }

    /// Seconds of friction this session should ask for.
    var frictionSeconds: Double {
        FrictionEngine.seconds(level: level, profileKind: session?.profileKind)
    }

    // MARK: - Starting

    /// Prepares the phone and starts the session.
    ///
    /// Order matters: validate the profile, apply restrictions, create the session,
    /// start the Live Activity, save the start time, and only then hand the screen
    /// over. The way out is guaranteed before anything is restricted.
    @discardableResult
    func start(
        task: TaskItem,
        level: SRFocusLevel,
        profile: SRFocusProfileDefinition?,
        context: ModelContext
    ) -> Bool {
        // A session already running is closed cleanly instead of overlapping.
        if session != nil { endRestrictions() }

        let applied = screenTime.apply(level: level, profile: profile)
        let effectiveLevel: SRFocusLevel = applied ? level : (level.blocksApps ? .gentle : level)

        var snapshot = SRFocusSessionSnapshot(
            taskID: task.id.uuidString,
            title: task.title,
            nextStep: task.nextStep,
            levelRaw: effectiveLevel.rawValue,
            profileID: profile?.id,
            profileKindRaw: profile?.kind.rawValue,
            startedAt: Date(),
            accumulated: 0,
            phase: .running,
            breakEndsAt: nil,
            releasedApp: nil,
            restrictionsActive: applied && level.blocksApps,
            exitAttempts: 0,
            plannedMinutes: task.estimatedMinutes,
            lastProgressNote: nil,
            updatedAt: Date()
        )
        // Deep mode without a picked set of apps would close everything: fall back
        // rather than trap the person.
        if !applied, level.blocksApps {
            recoveryNotice = screenTime.lastNotice
            snapshot.restrictionsActive = false
        } else {
            recoveryNotice = nil
        }

        session = snapshot
        reentry = nil
        persist()

        if let profile { SRFocusProfileStore.shared.recordUse(profile) }
        LiveActivityController.shared.start(task: task, level: effectiveLevel)
        writeShieldContext()
        writeWidget()
        BehaviorRecorder.recordFocusStart(level: effectiveLevel, context: context)
        return applied || !level.blocksApps
    }

    // MARK: - Pausing and breaks

    func pause(context: ModelContext) {
        guard var snapshot = session, snapshot.phase == .running else { return }
        snapshot.accumulated = snapshot.elapsed()
        snapshot.phase = .paused
        snapshot.updatedAt = Date()
        session = snapshot
        persist()
        BehaviorRecorder.recordPause(context: context)
        LiveActivityController.shared.pause(
            elapsedMinutes: snapshot.accumulated / 60,
            plannedMinutes: snapshot.plannedMinutes
        )
        writeWidget()
    }

    func resume() {
        guard var snapshot = session, snapshot.phase != .running else { return }
        snapshot.startedAt = Date()
        snapshot.phase = .running
        snapshot.breakEndsAt = nil
        snapshot.updatedAt = Date()
        session = snapshot
        // Coming back is the whole point: restrictions return with the person.
        if snapshot.restrictionsActive {
            screenTime.apply(
                level: snapshot.level,
                profile: SRFocusProfileStore.shared.profile(id: snapshot.profileID),
                releasedApp: snapshot.releasedApp
            )
        }
        persist()
        log(.returned)
        LiveActivityController.shared.resume(
            elapsedMinutes: snapshot.accumulated / 60,
            plannedMinutes: snapshot.plannedMinutes
        )
        writeWidget()
    }

    /// A real break. Resting is not failing: the session stays alive, the clock
    /// stops, and SinRutina says when it ends.
    func grantBreak(minutes: Int, context: ModelContext) {
        guard var snapshot = session else { return }
        snapshot.accumulated = snapshot.elapsed()
        snapshot.phase = .onBreak
        snapshot.breakEndsAt = Date().addingTimeInterval(Double(minutes) * 60)
        snapshot.updatedAt = Date()
        session = snapshot

        if SRFocusPreferences.shared.data.relaxesOnBreak {
            screenTime.clear()
        }
        persist()
        log(.breakGranted)
        BehaviorRecorder.recordBreak(context: context)
        LiveActivityController.shared.pause(
            elapsedMinutes: snapshot.accumulated / 60,
            plannedMinutes: snapshot.plannedMinutes
        )
        writeWidget()
        SRHaptics.success()
    }

    /// True once a granted break has run out, so the app can ask "¿Volvemos?".
    func breakHasEnded(at date: Date = Date()) -> Bool {
        guard let breakEndsAt, isOnBreak else { return false }
        return date >= breakEndsAt
    }

    // MARK: - Exceptions

    /// Releases one app for this session only, and remembers it so the app can
    /// offer to add it to the profile afterwards.
    func release(app: String) {
        guard var snapshot = session else { return }
        snapshot.releasedApp = app
        snapshot.updatedAt = Date()
        session = snapshot
        if snapshot.restrictionsActive {
            screenTime.apply(
                level: snapshot.level,
                profile: SRFocusProfileStore.shared.profile(id: snapshot.profileID),
                releasedApp: app
            )
        }
        persist()
        log(.appReleased, appLabel: app)
    }

    /// Registers that a restricted app was reached for. It changes nothing about
    /// the session: it only makes SinRutina better at preparing the next one.
    func noteExitAttempt(appLabel: String?) {
        guard var snapshot = session else { return }
        snapshot.exitAttempts += 1
        snapshot.updatedAt = Date()
        session = snapshot
        persist()
        log(.blockedAppAttempt, appLabel: appLabel)
    }

    /// Everything off, right now. Urgency never asks for ten seconds.
    func emergency(context: ModelContext) {
        screenTime.clear()
        guard var snapshot = session else {
            SRShieldBridge.writeContext(nil)
            return
        }
        snapshot.restrictionsActive = false
        snapshot.updatedAt = Date()
        session = snapshot
        persist()
        SRShieldBridge.writeContext(nil)
        log(.emergency)
        BehaviorRecorder.recordEmergency(context: context)
    }

    // MARK: - Progress and finishing

    /// "Avancé, pero no terminé": the session closes, the progress does not.
    func noteProgress(_ note: String?) {
        guard var snapshot = session else { return }
        snapshot.lastProgressNote = note
        snapshot.updatedAt = Date()
        session = snapshot
        persist()
    }

    /// Ends the session. `completed` only reflects what the person said.
    func finish(completed: Bool, context: ModelContext) -> Double {
        let minutes = elapsedSeconds() / 60
        let snapshot = session
        if let snapshot, !completed {
            log(.leftSession)
            reentry = snapshot
        } else {
            reentry = nil
        }
        if let snapshot {
            BehaviorRecorder.recordFocusOutcome(
                level: snapshot.level,
                finished: completed,
                exits: snapshot.exitAttempts,
                context: context
            )
        }
        endRestrictions()
        session = nil
        persist()
        LiveActivityController.shared.end(immediately: !completed)
        writeWidget()
        return minutes
    }

    /// Keeps the session available for "Quedaste aquí" without holding the phone.
    func suspendForReentry() {
        guard let snapshot = session else { return }
        reentry = snapshot
        endRestrictions()
        session = nil
        persist()
        LiveActivityController.shared.end(immediately: true)
        writeWidget()
    }

    func clearReentry() {
        reentry = nil
        SRShared.defaults.removeObject(forKey: SRShared.Key.focusSession)
    }

    // MARK: - Recovery and watchdog

    /// Called on every launch and every return to the foreground.
    ///
    /// Two jobs: put a live session back together, and make sure restrictions
    /// never outlive the session that justified them. When consistency cannot be
    /// guaranteed, the phone wins.
    func restore(context: ModelContext) {
        screenTime.refreshAccessState()
        pendingPauseRequest = SRShieldBridge.take()

        guard let stored = SRFocusSessionStore.read() else {
            screenTime.reconcile(hasLiveSession: false)
            return
        }

        // An orphan session: nobody has touched it for hours.
        if stored.isStale() {
            recoveryNotice = "Había una sesión abierta desde hace horas. La cerré y devolví el iPhone a la normalidad."
            reentry = stored
            session = nil
            screenTime.reconcile(hasLiveSession: false)
            SRFocusSessionStore.write(nil)
            writeWidget()
            return
        }

        // The task may no longer exist, or may already be done elsewhere.
        guard let task = SRTaskCommands.task(withID: stored.taskID, context: context),
              task.state != .completed else {
            reentry = nil
            session = nil
            screenTime.reconcile(hasLiveSession: false)
            SRFocusSessionStore.write(nil)
            writeWidget()
            return
        }

        session = stored
        if stored.restrictionsActive, stored.phase != .onBreak {
            let applied = screenTime.apply(
                level: stored.level,
                profile: SRFocusProfileStore.shared.profile(id: stored.profileID),
                releasedApp: stored.releasedApp
            )
            if !applied {
                // Cannot guarantee the same environment: do not pretend.
                var repaired = stored
                repaired.restrictionsActive = false
                repaired.levelRaw = SRFocusLevel.gentle.rawValue
                session = repaired
                recoveryNotice = "Perdí el permiso de bloqueo, así que la sesión sigue en modo Suave."
                persist()
            }
        }
        writeShieldContext()
        writeWidget()
    }

    /// Removes every restriction this app applied and cleans the shield sign.
    private func endRestrictions() {
        screenTime.clear()
        SRShieldBridge.writeContext(nil)
    }

    func consumePauseRequest() {
        pendingPauseRequest = nil
    }

    // MARK: - Outside surfaces

    /// The widget shows the session and nothing else: no list, no counters.
    private func writeWidget() {
        guard let snapshot = session else { return }
        let statusMinutes = Int((snapshot.elapsed() / 60).rounded())
        SRWidgetStore.write(
            SRWidgetSnapshot(
                taskID: snapshot.taskID,
                title: snapshot.title,
                estimatedMinutes: snapshot.plannedMinutes,
                tone: .running,
                nextStep: snapshot.nextStep,
                openCount: 1,
                waitingCount: 0,
                runningSince: snapshot.phase == .running ? snapshot.startedAt : nil,
                runningMinutes: statusMinutes,
                isPausedSession: snapshot.phase != .running
            )
        )
        WidgetCenter.shared.reloadTimelines(ofKind: SRShared.widgetKind)
    }

    private func writeShieldContext() {
        guard let snapshot = session, snapshot.restrictionsActive else {
            SRShieldBridge.writeContext(nil)
            return
        }
        SRShieldBridge.writeContext(
            SRShieldContext(
                taskTitle: snapshot.title,
                nextStep: snapshot.nextStep,
                level: snapshot.level
            )
        )
    }

    private func persist() {
        SRFocusSessionStore.write(session)
    }

    private func log(_ kind: SRDistractionEvent.Kind, appLabel: String? = nil) {
        SRDistractionLog.append(
            SRDistractionEvent(
                kind: kind,
                taskID: session?.taskID,
                profileKind: session?.profileKindRaw,
                level: level,
                appLabel: appLabel
            )
        )
    }
}
