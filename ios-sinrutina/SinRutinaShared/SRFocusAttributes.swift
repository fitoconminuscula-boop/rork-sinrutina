import ActivityKit
import Foundation

/// Live Activity payload for a task in progress. Deliberately tiny: a Live
/// Activity content state must stay well under 4 KB.
nonisolated struct SRFocusAttributes: ActivityAttributes {
    public nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// When the current running stretch started. Nil while paused.
        var runningSince: Date?
        /// Minutes already spent before the current stretch.
        var accumulatedMinutes: Double
        var plannedMinutes: Int
        var isPaused: Bool
        /// True while a real break is running, so the wording is honest.
        var isOnBreak: Bool
        /// When a granted break ends.
        var breakEndsAt: Date?

        init(
            runningSince: Date?,
            accumulatedMinutes: Double,
            plannedMinutes: Int,
            isPaused: Bool,
            isOnBreak: Bool = false,
            breakEndsAt: Date? = nil
        ) {
            self.runningSince = runningSince
            self.accumulatedMinutes = max(0, accumulatedMinutes)
            self.plannedMinutes = max(1, plannedMinutes)
            self.isPaused = isPaused
            self.isOnBreak = isOnBreak
            self.breakEndsAt = breakEndsAt
        }

        /// Decoded field by field so an activity started by an older build keeps
        /// rendering instead of disappearing.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            runningSince = try container.decodeIfPresent(Date.self, forKey: .runningSince)
            accumulatedMinutes = max(0, try container.decodeIfPresent(Double.self, forKey: .accumulatedMinutes) ?? 0)
            plannedMinutes = max(1, try container.decodeIfPresent(Int.self, forKey: .plannedMinutes) ?? 10)
            isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
            isOnBreak = try container.decodeIfPresent(Bool.self, forKey: .isOnBreak) ?? false
            breakEndsAt = try container.decodeIfPresent(Date.self, forKey: .breakEndsAt)
        }

        func elapsedMinutes(at date: Date) -> Double {
            guard let runningSince else { return accumulatedMinutes }
            return accumulatedMinutes + max(0, date.timeIntervalSince(runningSince) / 60)
        }

        func remainingMinutes(at date: Date) -> Int {
            Int((Double(plannedMinutes) - elapsedMinutes(at: date)).rounded())
        }

        /// The clock the Live Activity counts down from, so the system can animate
        /// it without pushing updates every second.
        var targetDate: Date? {
            guard let runningSince else { return nil }
            let remaining = Double(plannedMinutes) - accumulatedMinutes
            return runningSince.addingTimeInterval(remaining * 60)
        }

        var statusLabel: String {
            if isOnBreak { return "Descanso" }
            return isPaused ? "En pausa" : "En marcha"
        }
    }

    var taskID: String
    var title: String
    var nextStep: String?
    /// Which level of concentration is running, so the lock screen says the truth.
    var levelRaw: String?

    var level: SRFocusLevel { levelRaw.flatMap(SRFocusLevel.init(rawValue:)) ?? .gentle }
}
