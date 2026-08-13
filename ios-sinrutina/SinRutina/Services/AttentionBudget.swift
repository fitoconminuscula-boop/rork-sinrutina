import Foundation

/// What the person is in the middle of right now.
///
/// It decides **how much** the interface draws, never what it is allowed to do.
/// The engines, the data and the actions are identical in every context: the only
/// thing that changes is how many things compete for attention on screen.
nonisolated enum SRAttentionContext: String, Sendable {
    /// One task plus the minimum context needed to decide.
    case normal
    /// Overwhelmed: only the smallest possible movement and the way out.
    case overwhelmed
    /// A session is running: only the active task.
    case executing
    /// A real departure is close: only what is needed to leave on time.
    case leaving
    /// Studying: only the current objective and its material.
    case studying

    /// Resolves the context from real state, in order of how concrete it is.
    /// A fixed hour beats a session, and being overwhelmed beats everything.
    static func resolve(
        isOverwhelmed: Bool,
        isExecuting: Bool,
        isLeavingSoon: Bool,
        isStudying: Bool
    ) -> SRAttentionContext {
        if isOverwhelmed { return .overwhelmed }
        if isExecuting { return .executing }
        if isLeavingSoon { return .leaving }
        if isStudying { return .studying }
        return .normal
    }
}

/// How much the person is managing to start, measured only from what they did.
///
/// It is not a diagnosis and it is never shown as a score: its single use is to
/// decide whether the visible scope of a task must shrink.
nonisolated enum SRActivation: String, Sendable {
    case normal
    /// Repeatedly not started. The answer is less, never louder.
    case low
}

/// The amount of information a screen may draw.
///
/// Everything on this list is secondary by definition: the title of the task and
/// the primary action are never part of a budget, because they can never be
/// hidden. `maxAlternatives` is the hard ceiling on immediate decisions —
/// anything beyond it lives in a sheet.
nonisolated struct SRInformationBudget: Sendable {
    var context: SRAttentionContext
    var activation: SRActivation

    /// One quiet line of metadata (duration, hour) under the title.
    var showsMeta: Bool
    /// Free time or next event.
    var showsTimeContext: Bool
    /// Files, tags, allowed apps and other per-task extras.
    var showsExtras: Bool
    /// Counters for the other states of the day.
    var showsOtherStates: Bool
    /// Immediate alternatives allowed next to the primary action.
    var maxAlternatives: Int
    /// True when the visible scope must shrink to the smallest movement.
    var reducesScope: Bool

    /// The single dominant action is implicit in every budget; this is only the
    /// ceiling for everything else.
    static func make(
        context: SRAttentionContext,
        activation: SRActivation = .normal,
        prefersMinimalLayout: Bool = false
    ) -> SRInformationBudget {
        switch context {
        case .overwhelmed:
            return SRInformationBudget(
                context: context,
                activation: activation,
                showsMeta: false,
                showsTimeContext: false,
                showsExtras: false,
                showsOtherStates: false,
                maxAlternatives: 0,
                reducesScope: true
            )
        case .executing:
            return SRInformationBudget(
                context: context,
                activation: activation,
                showsMeta: !prefersMinimalLayout,
                showsTimeContext: false,
                showsExtras: false,
                showsOtherStates: false,
                maxAlternatives: prefersMinimalLayout ? 0 : 2,
                reducesScope: activation == .low
            )
        case .leaving:
            return SRInformationBudget(
                context: context,
                activation: activation,
                showsMeta: false,
                showsTimeContext: false,
                showsExtras: false,
                showsOtherStates: false,
                maxAlternatives: 1,
                reducesScope: activation == .low
            )
        case .studying:
            return SRInformationBudget(
                context: context,
                activation: activation,
                showsMeta: !prefersMinimalLayout,
                showsTimeContext: false,
                showsExtras: false,
                showsOtherStates: false,
                maxAlternatives: 1,
                reducesScope: activation == .low
            )
        case .normal:
            return SRInformationBudget(
                context: context,
                activation: activation,
                showsMeta: !prefersMinimalLayout,
                showsTimeContext: !prefersMinimalLayout,
                showsExtras: !prefersMinimalLayout,
                showsOtherStates: !prefersMinimalLayout,
                maxAlternatives: 2,
                reducesScope: activation == .low
            )
        }
    }
}

/// How one task is presented, given the current budget.
///
/// When activation is low the scope on screen shrinks: the same task is shown as
/// its smallest real movement, so the distance between "sé que tengo que
/// hacerlo" and "ya empecé" gets shorter instead of louder.
struct SRTaskFraming {
    let task: TaskItem
    /// The smallest concrete movement, already computed by the engine.
    let microStep: String
    let budget: SRInformationBudget

    /// Reduced scope needs a real step to point at; without one nothing changes.
    var isReduced: Bool {
        budget.reducesScope && !trimmedStep.isEmpty && trimmedStep != task.title
    }

    /// The line that answers "¿qué tengo que hacer?".
    var headline: String {
        isReduced ? trimmedStep : task.title
    }

    /// One short line under the headline, or nothing.
    var support: String? {
        if isReduced {
            // Where this came from, so shrinking never feels like losing the task.
            return "De: \(task.title)"
        }
        guard !trimmedStep.isEmpty, trimmedStep != task.title else { return nil }
        return trimmedStep
    }

    var primaryLabel: String {
        isReduced ? "Hacer solo eso" : "Empezar"
    }

    /// Minutes shown next to the action. With reduced scope it is the estimate of
    /// the small movement, read with the same deterministic rules used everywhere
    /// else and never larger than the task it came from.
    var minutes: Int {
        guard isReduced else { return task.estimatedMinutes }
        return SRTaskFraming.microMinutes(for: trimmedStep, ceiling: task.estimatedMinutes)
    }

    /// "Abrir el informe · 2 min": the whole decision in one glance.
    var actionLabel: String {
        "\(headline) · \(minutes) min"
    }

    private var trimmedStep: String {
        microStep.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A small movement is measured with the same reader as anything else, capped
    /// so it can never claim to be longer than the task it belongs to.
    static func microMinutes(for step: String, ceiling: Int) -> Int {
        let lower = SRHeuristics.normalized(step)
        let detected = SRHeuristics.detectMinutes(lower, context: SRHeuristics.detectContext(lower))
        let bounded = min(max(detected, 1), 5)
        return ceiling > 0 ? min(bounded, ceiling) : bounded
    }

    /// Repeated postponement, or repeatedly walking past a suggestion, is the only
    /// signal used. Nothing is inferred about the person.
    static func activation(for task: TaskItem) -> SRActivation {
        if task.procrastinationCount >= 2 { return .low }
        if task.ignoredInterventionCount >= 2 { return .low }
        return .normal
    }
}
