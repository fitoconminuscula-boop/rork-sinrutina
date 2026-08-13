import Foundation
import SwiftData

/// Quiet local signals used later to make recommendations more personal.
@Model
final class BehaviorProfile {
    var id: UUID
    var estimatedMinutesTotal: Double
    var actualMinutesTotal: Double
    var completedTaskCount: Int
    var acceptedActionCount: Int
    var rejectedActionCount: Int
    var postponementCount: Int
    var hourlyCompletionCountsJSON: String
    var actionResponsesJSON: String
    var updatedAt: Date

    // MARK: - Adherence layer.
    // Observable behaviour only: durations, timings and choices. Never traits.

    /// Minutes of work that actually got finished, per session, most recent last.
    var sessionMinutesJSON: String = "[]"
    /// Minutes of study that actually got done, per session.
    var studyMinutesJSON: String = "[]"
    /// Counts of reminders that produced nothing, by hour of day.
    var ignoredByHourJSON: String = "[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]"
    /// Minutes between SinRutina suggesting something and the person starting it.
    var timeToStartJSON: String = "[]"
    /// Which micro action actually unlocked movement, counted by text.
    var microActionWinsJSON: String = "{}"
    /// Which explanation shape gets asked for most.
    var explainActionCountsJSON: String = "{}"
    /// Which reply register gets used most.
    var replyStyleCountsJSON: String = "{}"
    /// How often a study session ended up needing the web.
    var webSearchCount: Int = 0
    /// How many study sessions happened at all, to keep the ratio honest.
    var studySessionCount: Int = 0
    /// How many times a session was paused midway.
    var pauseCount: Int = 0
    /// How many recall answers came back as "no sé".
    var recallMissCount: Int = 0
    /// How many recall answers came back answered.
    var recallHitCount: Int = 0
    /// How many follow-ups on waiting items were actually prepared.
    var followUpCount: Int = 0
    /// How many emails turned into an actual reply.
    var mailRepliedCount: Int = 0

    // MARK: - Behavioural environment layer.
    // What actually happens during a session: which level was used, whether the
    // task got finished, how often the person reached for something else.

    /// Per level: sessions started, finished and exit attempts, as JSON.
    var focusLevelStatsJSON: String = "{}"
    /// Attempts to open a restricted app, all levels together.
    var distractionAttemptCount: Int = 0
    /// Breaks the person asked for on purpose.
    var breakCount: Int = 0
    /// Times everything was lifted through Urgencia.
    var emergencyCount: Int = 0
    /// Sessions that ended with "Avancé, pero no terminé".
    var partialProgressCount: Int = 0

    init() {
        self.id = UUID()
        self.estimatedMinutesTotal = 0
        self.actualMinutesTotal = 0
        self.completedTaskCount = 0
        self.acceptedActionCount = 0
        self.rejectedActionCount = 0
        self.postponementCount = 0
        self.hourlyCompletionCountsJSON = "[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]"
        self.actionResponsesJSON = "{}"
        self.updatedAt = Date()
        self.sessionMinutesJSON = "[]"
        self.studyMinutesJSON = "[]"
        self.ignoredByHourJSON = "[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]"
        self.timeToStartJSON = "[]"
        self.microActionWinsJSON = "{}"
        self.explainActionCountsJSON = "{}"
        self.replyStyleCountsJSON = "{}"
        self.webSearchCount = 0
        self.studySessionCount = 0
        self.pauseCount = 0
        self.recallMissCount = 0
        self.recallHitCount = 0
        self.followUpCount = 0
        self.mailRepliedCount = 0
        self.focusLevelStatsJSON = "{}"
        self.distractionAttemptCount = 0
        self.breakCount = 0
        self.emergencyCount = 0
        self.partialProgressCount = 0
    }

    func recordCompletion(estimatedMinutes: Int, actualMinutes: Double, hour: Int) {
        estimatedMinutesTotal += Double(estimatedMinutes)
        actualMinutesTotal += actualMinutes
        completedTaskCount += 1
        let safeHour = min(max(hour, 0), 23)
        var counts = hourlyCounts
        if counts.count != 24 {
            counts = Array(repeating: 0, count: 24)
        }
        counts[safeHour] += 1
        hourlyCompletionCountsJSON = encode(counts)
        updatedAt = Date()
    }

    func recordActionResponse(_ response: String) {
        var values = actionResponses
        values[response, default: 0] += 1
        actionResponsesJSON = encode(values)
        updatedAt = Date()
    }

    var hourlyCounts: [Int] {
        guard let data = hourlyCompletionCountsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Int].self, from: data) else {
            return Array(repeating: 0, count: 24)
        }
        return decoded
    }

    var actionResponses: [String: Int] {
        guard let data = actionResponsesJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return decoded
    }

    // MARK: - Adherence recording

    /// Remembers how long a session really lasted, so proposals stop being wishful.
    func recordSession(minutes: Double, isStudy: Bool) {
        guard minutes >= 1 else { return }
        sessionMinutesJSON = encode(Array((decodeDoubles(sessionMinutesJSON) + [minutes]).suffix(40)))
        if isStudy {
            studyMinutesJSON = encode(Array((decodeDoubles(studyMinutesJSON) + [minutes]).suffix(40)))
            studySessionCount += 1
        }
        updatedAt = Date()
    }

    func recordIgnoredReminder(hour: Int) {
        var counts = decodeInts(ignoredByHourJSON, expected: 24)
        counts[min(max(hour, 0), 23)] += 1
        ignoredByHourJSON = encode(counts)
        updatedAt = Date()
    }

    func recordTimeToStart(minutes: Double) {
        guard minutes >= 0 else { return }
        timeToStartJSON = encode(Array((decodeDoubles(timeToStartJSON) + [minutes]).suffix(30)))
        updatedAt = Date()
    }

    func recordMicroActionWin(_ action: String) {
        var values = microActionWins
        values[action, default: 0] += 1
        microActionWinsJSON = encode(values)
        updatedAt = Date()
    }

    func recordExplainAction(_ action: String) {
        var values = explainActionCounts
        values[action, default: 0] += 1
        explainActionCountsJSON = encode(values)
        updatedAt = Date()
    }

    func recordReplyStyle(_ style: String) {
        var values = replyStyleCounts
        values[style, default: 0] += 1
        replyStyleCountsJSON = encode(values)
        mailRepliedCount += 1
        updatedAt = Date()
    }

    func recordRecall(hit: Bool) {
        if hit { recallHitCount += 1 } else { recallMissCount += 1 }
        updatedAt = Date()
    }

    // MARK: - Focus recording

    /// One number per level, so SinRutina can tell whether Profundo is really
    /// working better than Enfoque for this person.
    struct FocusLevelStats: Codable, Hashable, Sendable {
        var started: Int = 0
        var finished: Int = 0
        var exits: Int = 0
        var minutes: Double = 0

        var completionRate: Double? {
            guard started >= 3 else { return nil }
            return Double(finished) / Double(started)
        }
    }

    var focusLevelStats: [String: FocusLevelStats] {
        guard let data = focusLevelStatsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: FocusLevelStats].self, from: data) else {
            return [:]
        }
        return decoded
    }

    func recordFocusStart(level: String) {
        var stats = focusLevelStats
        var entry = stats[level] ?? FocusLevelStats()
        entry.started += 1
        stats[level] = entry
        focusLevelStatsJSON = encode(stats)
        updatedAt = Date()
    }

    func recordFocusOutcome(level: String, finished: Bool, exits: Int, minutes: Double) {
        var stats = focusLevelStats
        var entry = stats[level] ?? FocusLevelStats()
        if finished { entry.finished += 1 }
        entry.exits += max(0, exits)
        entry.minutes += max(0, minutes)
        stats[level] = entry
        focusLevelStatsJSON = encode(stats)
        updatedAt = Date()
    }

    /// The level that most often ends with the task actually finished. Requires
    /// real evidence on two levels before it says anything at all.
    var bestFocusLevel: String? {
        let stats = focusLevelStats.compactMapValues { entry -> Double? in entry.completionRate }
        guard stats.count >= 2 else { return nil }
        guard let best = stats.max(by: { $0.value < $1.value }),
              let worst = stats.min(by: { $0.value < $1.value }),
              best.value - worst.value >= 0.2 else { return nil }
        return best.key
    }

    /// How often sessions end with the person leaving instead of finishing.
    var exitPressure: Double? {
        let stats = focusLevelStats.values
        let started = stats.reduce(0) { $0 + $1.started }
        guard started >= 4 else { return nil }
        let exits = stats.reduce(0) { $0 + $1.exits }
        return Double(exits) / Double(started)
    }

    // MARK: - Adherence reading

    var sessionMinutes: [Double] { decodeDoubles(sessionMinutesJSON) }
    var studyMinutes: [Double] { decodeDoubles(studyMinutesJSON) }
    var timeToStartMinutes: [Double] { decodeDoubles(timeToStartJSON) }
    var ignoredByHour: [Int] { decodeInts(ignoredByHourJSON, expected: 24) }

    var microActionWins: [String: Int] { decodeCounts(microActionWinsJSON) }
    var explainActionCounts: [String: Int] { decodeCounts(explainActionCountsJSON) }
    var replyStyleCounts: [String: Int] { decodeCounts(replyStyleCountsJSON) }

    /// The session length that keeps working, rounded to a human number.
    var typicalSessionMinutes: Int? {
        let values = sessionMinutes.suffix(20)
        guard values.count >= 4 else { return nil }
        let sorted = values.sorted()
        let median = sorted[sorted.count / 2]
        return Int((median / 5).rounded()) * 5
    }

    var typicalStudyMinutes: Int? {
        let values = studyMinutes.suffix(15)
        guard values.count >= 3 else { return nil }
        let sorted = values.sorted()
        return Int((sorted[sorted.count / 2] / 5).rounded()) * 5
    }

    /// The hour where work most often actually gets finished.
    var mostProductiveHour: Int? {
        let counts = hourlyCounts
        let total = counts.reduce(0, +)
        guard total >= 6, let best = counts.indices.max(by: { counts[$0] < counts[$1] }) else { return nil }
        guard Double(counts[best]) / Double(total) > 0.18 else { return nil }
        return best
    }

    /// The hour where reminders most reliably produce nothing.
    var leastReceptiveHour: Int? {
        let counts = ignoredByHour
        let total = counts.reduce(0, +)
        guard total >= 5, let worst = counts.indices.max(by: { counts[$0] < counts[$1] }) else { return nil }
        guard counts[worst] >= 3 else { return nil }
        return worst
    }

    var averageMinutesToStart: Double? {
        let values = timeToStartMinutes.suffix(15)
        guard values.count >= 4 else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// How far real durations drift from estimates: >1 means things take longer.
    var durationDriftFactor: Double? {
        guard completedTaskCount >= 5, estimatedMinutesTotal > 0 else { return nil }
        return actualMinutesTotal / estimatedMinutesTotal
    }

    var favouriteExplainAction: String? {
        explainActionCounts.max { $0.value < $1.value }.flatMap { $0.value >= 3 ? $0.key : nil }
    }

    var favouriteReplyStyle: String? {
        replyStyleCounts.max { $0.value < $1.value }.flatMap { $0.value >= 2 ? $0.key : nil }
    }

    var favouriteMicroAction: String? {
        microActionWins.max { $0.value < $1.value }.flatMap { $0.value >= 2 ? $0.key : nil }
    }

    var webSearchShare: Double? {
        guard studySessionCount >= 4 else { return nil }
        return Double(webSearchCount) / Double(studySessionCount)
    }

    // MARK: - Decoding helpers

    private func decodeDoubles(_ json: String) -> [Double] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Double].self, from: data) else { return [] }
        return decoded
    }

    private func decodeInts(_ json: String, expected: Int) -> [Int] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Int].self, from: data),
              decoded.count == expected else {
            return Array(repeating: 0, count: expected)
        }
        return decoded
    }

    private func decodeCounts(_ json: String) -> [String: Int] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        return decoded
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
