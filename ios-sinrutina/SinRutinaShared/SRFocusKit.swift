import Foundation

// MARK: - Graduated levels

/// How much the iPhone changes shape for one intention.
///
/// The point is never to take the phone away: it is to remove the two or three
/// automatic gestures that end a session before it starts.
nonisolated enum SRFocusLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Reminders, friction, presence and Live Activity. Nothing is blocked.
    case gentle
    /// The apps defined as distracting are blocked; the ones the task needs stay.
    case focus
    /// Only the minimum set the task needs is available.
    case deep

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gentle: return "Suave"
        case .focus: return "Enfoque"
        case .deep: return "Profundo"
        }
    }

    var detail: String {
        switch self {
        case .gentle: return "Nada se bloquea. Solo acompañamiento."
        case .focus: return "Se bloquea lo que te distrae."
        case .deep: return "Solo lo imprescindible para esto."
        }
    }

    var symbolName: String {
        switch self {
        case .gentle: return "leaf"
        case .focus: return "circle.lefthalf.filled"
        case .deep: return "circle.inset.filled"
        }
    }

    /// True when leaving needs the deliberate ten seconds instead of one tap.
    var blocksApps: Bool { self != .gentle }

    /// Deep mode inverts the rule: everything is closed except the essentials.
    var allowsOnlyEssentials: Bool { self == .deep }

    /// Baseline seconds of friction. Adapted later, never beyond twelve.
    var baseFrictionSeconds: Double {
        switch self {
        case .gentle: return 0
        case .focus: return 8
        case .deep: return 10
        }
    }
}

// MARK: - Focus profiles

/// The families of work SinRutina already knows how to prepare for.
nonisolated enum SRFocusProfileKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case communication
    case study
    case writing
    case admin
    case rest
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .communication: return "Comunicación"
        case .study: return "Estudio"
        case .writing: return "Escritura"
        case .admin: return "Trámites"
        case .rest: return "Descanso"
        case .custom: return "A medida"
        }
    }

    var symbolName: String {
        switch self {
        case .communication: return "phone"
        case .study: return "book"
        case .writing: return "text.cursor"
        case .admin: return "folder"
        case .rest: return "moon"
        case .custom: return "square.dashed"
        }
    }

    /// Plain app names, the same vocabulary the person sees on the home screen.
    var defaultApps: [String] {
        switch self {
        case .communication: return ["Teléfono", "WhatsApp", "Mensajes", "SinRutina"]
        case .study: return ["Books", "Safari", "PDF", "Notas", "SinRutina"]
        case .writing: return ["Word", "Notas", "Archivos", "Safari", "SinRutina"]
        case .admin: return ["Safari", "Mail", "Archivos", "SinRutina"]
        case .rest: return ["Música", "Podcasts", "Libros"]
        case .custom: return ["SinRutina"]
        }
    }

    /// Sites that make sense while working like this, when web limits are on.
    var defaultDomains: [String] {
        switch self {
        case .study: return ["scholar.google.com", "wikipedia.org", "arxiv.org"]
        case .admin: return []
        case .writing: return []
        case .communication, .rest, .custom: return []
        }
    }

    var suggestedLevel: SRFocusLevel {
        switch self {
        case .communication: return .deep
        case .study: return .deep
        case .writing: return .focus
        case .admin: return .focus
        case .rest: return .gentle
        case .custom: return .focus
        }
    }

    var safariMode: SRSafariMode {
        switch self {
        case .study: return .limited
        case .writing, .admin: return .full
        case .communication, .rest, .custom: return .blocked
        }
    }

    /// The contexts SinRutina already assigns when reading a task.
    var matchingContexts: [String] {
        switch self {
        case .communication: return ["comunicación", "comunicacion"]
        case .study: return ["estudio"]
        case .writing: return ["trabajo"]
        case .admin: return ["administrativo", "dinero"]
        case .rest: return []
        case .custom: return []
        }
    }
}

/// Safari is a tool and a distraction at the same time, so it gets its own switch.
nonisolated enum SRSafariMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case blocked
    case limited
    case temporary
    case full

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blocked: return "Sin Safari"
        case .limited: return "Safari con sitios permitidos"
        case .temporary: return "Safari un rato"
        case .full: return "Safari completo"
        }
    }

    var detail: String {
        switch self {
        case .blocked: return "Durante esta tarea no hace falta."
        case .limited: return "Solo los dominios que añadas."
        case .temporary: return "Se abre cuando lo pidas y se cierra al terminar."
        case .full: return "Sin restricciones de navegación."
        }
    }

    var allowsWebLimits: Bool { self == .limited }
}

/// One reusable way of preparing the phone. Editable, renameable, deletable.
nonisolated struct SRFocusProfileDefinition: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var kind: SRFocusProfileKind
    var name: String
    /// Apps written as the person names them, shown before any block is applied.
    var appNames: [String]
    /// Domains that stay reachable while web limits are on.
    var allowedDomains: [String]
    var safariMode: SRSafariMode
    var suggestedLevel: SRFocusLevel
    /// True while the profile still matches its template.
    var isBuiltIn: Bool
    var usageCount: Int
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        kind: SRFocusProfileKind,
        name: String? = nil,
        appNames: [String]? = nil,
        allowedDomains: [String]? = nil,
        safariMode: SRSafariMode? = nil,
        suggestedLevel: SRFocusLevel? = nil,
        isBuiltIn: Bool = true,
        usageCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.name = name ?? kind.label
        self.appNames = appNames ?? kind.defaultApps
        self.allowedDomains = allowedDomains ?? kind.defaultDomains
        self.safariMode = safariMode ?? kind.safariMode
        self.suggestedLevel = suggestedLevel ?? kind.suggestedLevel
        self.isBuiltIn = isBuiltIn
        self.usageCount = usageCount
        self.updatedAt = updatedAt
    }

    /// Written as a short line: "Teléfono · WhatsApp · SinRutina".
    var appsLine: String {
        appNames.isEmpty ? "Sin apps definidas" : appNames.joined(separator: " · ")
    }

    var summary: String {
        var pieces = [suggestedLevel.label]
        if !appNames.isEmpty { pieces.append("\(appNames.count) apps") }
        if safariMode.allowsWebLimits, !allowedDomains.isEmpty {
            pieces.append("\(allowedDomains.count) sitios")
        }
        return pieces.joined(separator: " · ")
    }

    static let templates: [SRFocusProfileDefinition] = [
        SRFocusProfileDefinition(kind: .communication),
        SRFocusProfileDefinition(kind: .study),
        SRFocusProfileDefinition(kind: .writing),
        SRFocusProfileDefinition(kind: .admin),
        SRFocusProfileDefinition(kind: .rest),
    ]
}

/// Profiles as the person left them. Local, editable, reusable.
@Observable
final class SRFocusProfileStore {
    static let shared = SRFocusProfileStore()

    private(set) var profiles: [SRFocusProfileDefinition]
    /// Kinds whose suggestion the person already approved once, so SinRutina can
    /// stop asking the same question every session.
    private(set) var approvedKinds: Set<String>

    private init() {
        profiles = Self.load() ?? SRFocusProfileDefinition.templates
        approvedKinds = Set(SRShared.defaults.stringArray(forKey: SRShared.Key.focusApprovedProfiles) ?? [])
    }

    func profile(id: UUID?) -> SRFocusProfileDefinition? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }

    func profile(kind: SRFocusProfileKind) -> SRFocusProfileDefinition? {
        profiles.first { $0.kind == kind }
    }

    /// The profile that fits a task, judged only on what the task already says.
    func suggestion(context: String?, title: String, isStudy: Bool, isMail: Bool) -> SRFocusProfileDefinition? {
        if isStudy, let study = profile(kind: .study) { return study }
        if isMail, let admin = profile(kind: .admin) { return admin }
        if let context = context?.lowercased(),
           let match = profiles.first(where: { $0.kind.matchingContexts.contains(context) }) {
            return match
        }
        let lower = title.lowercased()
        if lower.contains("llamar") || lower.contains("whatsapp") || lower.contains("mensaje") {
            return profile(kind: .communication)
        }
        if lower.contains("escribir") || lower.contains("redactar") || lower.contains("informe") {
            return profile(kind: .writing)
        }
        if lower.contains("correo") || lower.contains("mail") || lower.contains("trámite") || lower.contains("tramite") {
            return profile(kind: .admin)
        }
        return nil
    }

    func upsert(_ profile: SRFocusProfileDefinition) {
        var edited = profile
        edited.updatedAt = Date()
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            edited.isBuiltIn = false
            profiles[index] = edited
        } else {
            profiles.append(edited)
        }
        persist()
    }

    func remove(_ profile: SRFocusProfileDefinition) {
        profiles.removeAll { $0.id == profile.id }
        persist()
    }

    func restoreTemplates() {
        profiles = SRFocusProfileDefinition.templates
        persist()
    }

    /// Adds an app to a profile after the person approved it.
    func addApp(_ name: String, to profile: SRFocusProfileDefinition) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard var stored = self.profile(id: profile.id) else { return }
        guard !stored.appNames.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        stored.appNames.append(trimmed)
        upsert(stored)
    }

    func recordUse(_ profile: SRFocusProfileDefinition) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].usageCount += 1
        persist()
    }

    func isApproved(_ kind: SRFocusProfileKind) -> Bool {
        approvedKinds.contains(kind.rawValue)
    }

    func approve(_ kind: SRFocusProfileKind) {
        approvedKinds.insert(kind.rawValue)
        SRShared.defaults.set(Array(approvedKinds), forKey: SRShared.Key.focusApprovedProfiles)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        SRShared.defaults.set(data, forKey: SRShared.Key.focusProfiles)
    }

    private static func load() -> [SRFocusProfileDefinition]? {
        guard let data = SRShared.defaults.data(forKey: SRShared.Key.focusProfiles),
              let decoded = try? JSONDecoder().decode([SRFocusProfileDefinition].self, from: data),
              !decoded.isEmpty else { return nil }
        return decoded
    }
}

// MARK: - Friction

/// Ways of confirming "quiero cambiar de rumbo" that all take the same deliberate
/// effort, so nobody is excluded by a gesture their hands cannot do.
nonisolated enum SRFrictionStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case followDot
    case holdPress
    case slowSlide
    case countdown
    case biometric

    var id: String { rawValue }

    var label: String {
        switch self {
        case .followDot: return "Seguir el punto"
        case .holdPress: return "Mantener pulsado"
        case .slowSlide: return "Deslizar despacio"
        case .countdown: return "Cuenta atrás"
        case .biometric: return "Face ID y espera"
        }
    }

    var detail: String {
        switch self {
        case .followDot: return "Sigues un punto que se mueve lentamente."
        case .holdPress: return "Mantienes el dedo quieto en un punto fijo."
        case .slowSlide: return "Deslizas de un lado a otro sin prisa."
        case .countdown: return "Esperas mirando la cuenta, sin tocar nada."
        case .biometric: return "Confirmas con Face ID y esperas unos segundos."
        }
    }

    var symbolName: String {
        switch self {
        case .followDot: return "point.topleft.down.to.point.bottomright.curvepath"
        case .holdPress: return "hand.point.up.left"
        case .slowSlide: return "arrow.left.and.right"
        case .countdown: return "timer"
        case .biometric: return "faceid"
        }
    }

    /// True when a finger has to stay on the screen for the whole time.
    var needsContinuousTouch: Bool {
        self == .followDot || self == .holdPress || self == .slowSlide
    }
}

/// How long a transition should last, and whether it may change on its own.
nonisolated enum SRTransitionMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case off
    case short
    case long

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Sin transición"
        case .short: return "30 segundos"
        case .long: return "60 segundos"
        }
    }

    var seconds: Double {
        switch self {
        case .off: return 0
        case .short: return 30
        case .long: return 60
        }
    }
}

/// Everything the person decided about the behavioural environment. Local only.
nonisolated struct SRFocusPreferencesData: Codable, Hashable, Sendable {
    var defaultLevel: SRFocusLevel
    var showsTimer: Bool
    /// "Solo tarea": name, next action, Terminé. Nothing else.
    var onlyTaskMode: Bool
    var frictionStyle: SRFrictionStyle
    /// Nil means SinRutina may adapt the length within 6–12 seconds.
    var fixedFrictionSeconds: Double?
    var transitionMode: SRTransitionMode
    /// Whether SinRutina may propose new distracting apps for a profile.
    var suggestsDistractors: Bool
    /// Whether the preparation screen appears even for Suave.
    var alwaysPrepares: Bool
    /// Whether restrictions are relaxed while a real break is running.
    var relaxesOnBreak: Bool

    init(
        defaultLevel: SRFocusLevel = .gentle,
        showsTimer: Bool = true,
        onlyTaskMode: Bool = false,
        frictionStyle: SRFrictionStyle = .followDot,
        fixedFrictionSeconds: Double? = nil,
        transitionMode: SRTransitionMode = .short,
        suggestsDistractors: Bool = true,
        alwaysPrepares: Bool = false,
        relaxesOnBreak: Bool = true
    ) {
        self.defaultLevel = defaultLevel
        self.showsTimer = showsTimer
        self.onlyTaskMode = onlyTaskMode
        self.frictionStyle = frictionStyle
        self.fixedFrictionSeconds = fixedFrictionSeconds
        self.transitionMode = transitionMode
        self.suggestsDistractors = suggestsDistractors
        self.alwaysPrepares = alwaysPrepares
        self.relaxesOnBreak = relaxesOnBreak
    }

    /// Field by field, so a profile written by an older build keeps working.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = SRFocusPreferencesData()
        defaultLevel = try container.decodeIfPresent(SRFocusLevel.self, forKey: .defaultLevel) ?? fallback.defaultLevel
        showsTimer = try container.decodeIfPresent(Bool.self, forKey: .showsTimer) ?? fallback.showsTimer
        onlyTaskMode = try container.decodeIfPresent(Bool.self, forKey: .onlyTaskMode) ?? fallback.onlyTaskMode
        frictionStyle = try container.decodeIfPresent(SRFrictionStyle.self, forKey: .frictionStyle) ?? fallback.frictionStyle
        fixedFrictionSeconds = try container.decodeIfPresent(Double.self, forKey: .fixedFrictionSeconds)
        transitionMode = try container.decodeIfPresent(SRTransitionMode.self, forKey: .transitionMode) ?? fallback.transitionMode
        suggestsDistractors = try container.decodeIfPresent(Bool.self, forKey: .suggestsDistractors) ?? fallback.suggestsDistractors
        alwaysPrepares = try container.decodeIfPresent(Bool.self, forKey: .alwaysPrepares) ?? fallback.alwaysPrepares
        relaxesOnBreak = try container.decodeIfPresent(Bool.self, forKey: .relaxesOnBreak) ?? fallback.relaxesOnBreak
    }
}

@Observable
final class SRFocusPreferences {
    static let shared = SRFocusPreferences()

    private(set) var data: SRFocusPreferencesData

    private init() {
        if let stored = SRShared.defaults.data(forKey: SRShared.Key.focusPreferences),
           let decoded = try? JSONDecoder().decode(SRFocusPreferencesData.self, from: stored) {
            data = decoded
        } else {
            data = SRFocusPreferencesData()
        }
    }

    func update(_ transform: (inout SRFocusPreferencesData) -> Void) {
        var copy = data
        transform(&copy)
        data = copy
        guard let encoded = try? JSONEncoder().encode(copy) else { return }
        SRShared.defaults.set(encoded, forKey: SRShared.Key.focusPreferences)
    }

    /// Whether the "¿Qué necesitas para terminar esto?" screen is worth showing.
    func needsPreparation(level: SRFocusLevel, isApproved: Bool) -> Bool {
        if data.alwaysPrepares { return true }
        if level.blocksApps { return true }
        return !isApproved
    }
}

// MARK: - Distraction history

/// One attempt at leaving, recorded without judgement so profiles can improve.
nonisolated struct SRDistractionEvent: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        /// A blocked app was opened while a session was running.
        case blockedAppAttempt
        /// The person asked for the way out.
        case pauseRequested
        /// The friction was completed.
        case frictionCompleted
        /// The friction was abandoned halfway.
        case frictionAbandoned
        /// A break was granted.
        case breakGranted
        /// The person came back after a break or an exit.
        case returned
        /// The session ended without finishing the task.
        case leftSession
        /// One app was released for this session only.
        case appReleased
        /// Everything was lifted through Urgencia.
        case emergency
    }

    var id: UUID
    var kind: Kind
    var createdAt: Date
    var taskID: String?
    /// The kind of work, so suggestions can be specific ("en escritura…").
    var profileKind: String?
    var level: String
    /// App name when SinRutina can know it. Often nil: iOS does not tell.
    var appLabel: String?

    init(
        id: UUID = UUID(),
        kind: Kind,
        createdAt: Date = Date(),
        taskID: String? = nil,
        profileKind: String? = nil,
        level: SRFocusLevel = .gentle,
        appLabel: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.taskID = taskID
        self.profileKind = profileKind
        self.level = level.rawValue
        self.appLabel = appLabel
    }
}

/// Local memory of how sessions really go. Never shown as a scoreboard.
nonisolated enum SRDistractionLog {
    static func append(_ event: SRDistractionEvent) {
        var events = all()
        events.append(event)
        // Enough to notice a pattern, not enough to become a diary.
        events = Array(events.suffix(240))
        guard let data = try? JSONEncoder().encode(events) else { return }
        SRShared.defaults.set(data, forKey: SRShared.Key.distractionLog)
    }

    static func all() -> [SRDistractionEvent] {
        guard let data = SRShared.defaults.data(forKey: SRShared.Key.distractionLog),
              let decoded = try? JSONDecoder().decode([SRDistractionEvent].self, from: data) else {
            return []
        }
        return decoded
    }

    static func clear() {
        SRShared.defaults.removeObject(forKey: SRShared.Key.distractionLog)
    }

    /// Attempts to leave during the last hours, used to size the friction.
    static func recentAttempts(within hours: Double = 24) -> Int {
        let cutoff = Date().addingTimeInterval(-hours * 3_600)
        return all().filter {
            $0.createdAt > cutoff && ($0.kind == .blockedAppAttempt || $0.kind == .pauseRequested)
        }.count
    }

    /// Attempts inside the current session, so the app can ask instead of push.
    static func attempts(taskID: String?, since: Date) -> Int {
        guard let taskID else { return 0 }
        return all().filter {
            $0.taskID == taskID && $0.createdAt >= since &&
            ($0.kind == .blockedAppAttempt || $0.kind == .pauseRequested)
        }.count
    }

    /// The app most often reached for during one kind of work.
    static func mostAttemptedApp(profileKind: SRFocusProfileKind, minimum: Int = 3) -> (name: String, count: Int)? {
        var counts: [String: Int] = [:]
        for event in all() where event.profileKind == profileKind.rawValue && event.kind == .blockedAppAttempt {
            guard let label = event.appLabel, !label.isEmpty else { continue }
            counts[label, default: 0] += 1
        }
        guard let best = counts.max(by: { $0.value < $1.value }), best.value >= minimum else { return nil }
        return (best.key, best.value)
    }

    /// Share of exits that ended with the person coming back.
    static func returnRate() -> Double? {
        let events = all()
        let exits = events.filter { $0.kind == .breakGranted || $0.kind == .leftSession }.count
        guard exits >= 4 else { return nil }
        let returns = events.filter { $0.kind == .returned }.count
        return min(Double(returns) / Double(exits), 1)
    }

    /// True when friction keeps being completed: it is not breaking anything, so
    /// SinRutina should stop leaning on it.
    static func frictionIsIneffective() -> Bool {
        let recent = all().suffix(40)
        let completed = recent.filter { $0.kind == .frictionCompleted }.count
        let abandoned = recent.filter { $0.kind == .frictionAbandoned }.count
        guard completed + abandoned >= 6 else { return false }
        return Double(completed) / Double(completed + abandoned) > 0.85
    }
}

// MARK: - Session snapshot and recovery

/// What a running session looks like from outside the app: enough to rebuild it
/// after a relaunch, and enough to know when restrictions have gone orphan.
nonisolated struct SRFocusSessionSnapshot: Codable, Hashable, Sendable {
    enum Phase: String, Codable, Sendable {
        case running
        case paused
        case onBreak
    }

    var taskID: String
    var title: String
    var nextStep: String?
    var levelRaw: String
    var profileID: UUID?
    var profileKindRaw: String?
    var startedAt: Date
    /// Seconds already worked before the current stretch.
    var accumulated: Double
    var phase: Phase
    /// When a granted break ends.
    var breakEndsAt: Date?
    /// App released for this session only.
    var releasedApp: String?
    var restrictionsActive: Bool
    var exitAttempts: Int
    var plannedMinutes: Int
    var lastProgressNote: String?
    var updatedAt: Date

    var level: SRFocusLevel { SRFocusLevel(rawValue: levelRaw) ?? .gentle }
    var profileKind: SRFocusProfileKind? { profileKindRaw.flatMap(SRFocusProfileKind.init(rawValue:)) }

    func elapsed(at date: Date = Date()) -> Double {
        guard phase == .running else { return accumulated }
        return accumulated + max(0, date.timeIntervalSince(startedAt))
    }

    /// A session nobody has touched for hours is treated as abandoned, and its
    /// restrictions are lifted rather than left hanging.
    func isStale(at date: Date = Date()) -> Bool {
        date.timeIntervalSince(updatedAt) > 6 * 3_600
    }
}

nonisolated enum SRFocusSessionStore {
    static func write(_ snapshot: SRFocusSessionSnapshot?) {
        guard let snapshot, let data = try? JSONEncoder().encode(snapshot) else {
            SRShared.defaults.removeObject(forKey: SRShared.Key.focusSession)
            return
        }
        SRShared.defaults.set(data, forKey: SRShared.Key.focusSession)
    }

    static func read() -> SRFocusSessionSnapshot? {
        guard let data = SRShared.defaults.data(forKey: SRShared.Key.focusSession),
              let decoded = try? JSONDecoder().decode(SRFocusSessionSnapshot.self, from: data) else {
            return nil
        }
        return decoded
    }
}

// MARK: - Shield bridge

/// What the shield shows and what it sends back. The shield itself stays as
/// simple as a door sign: everything complicated happens inside SinRutina.
nonisolated struct SRShieldContext: Codable, Hashable, Sendable {
    var taskTitle: String
    var nextStep: String?
    var levelRaw: String
    var isActive: Bool
    var updatedAt: Date

    init(taskTitle: String, nextStep: String? = nil, level: SRFocusLevel, isActive: Bool = true) {
        self.taskTitle = taskTitle
        self.nextStep = nextStep
        self.levelRaw = level.rawValue
        self.isActive = isActive
        self.updatedAt = Date()
    }
}

nonisolated struct SRShieldSignal: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// "Seguir": the person chose to stay with the task.
        case stayed
        /// "Solicitar pausa": the friction screen should open.
        case pauseRequested
    }

    var kind: Kind
    var appLabel: String?
    var createdAt: Date

    init(kind: Kind, appLabel: String? = nil, createdAt: Date = Date()) {
        self.kind = kind
        self.appLabel = appLabel
        self.createdAt = createdAt
    }
}

nonisolated enum SRShieldBridge {
    static func writeContext(_ context: SRShieldContext?) {
        guard let context, let data = try? JSONEncoder().encode(context) else {
            SRShared.defaults.removeObject(forKey: SRShared.Key.shieldContext)
            return
        }
        SRShared.defaults.set(data, forKey: SRShared.Key.shieldContext)
    }

    static func readContext() -> SRShieldContext? {
        guard let data = SRShared.defaults.data(forKey: SRShared.Key.shieldContext),
              let decoded = try? JSONDecoder().decode(SRShieldContext.self, from: data) else {
            return nil
        }
        return decoded
    }

    static func send(_ signal: SRShieldSignal) {
        guard let data = try? JSONEncoder().encode(signal) else { return }
        SRShared.defaults.set(data, forKey: SRShared.Key.shieldSignal)
    }

    /// Reads and clears. Signals older than fifteen minutes are dropped so an old
    /// tap never hijacks a new session.
    static func take() -> SRShieldSignal? {
        guard let data = SRShared.defaults.data(forKey: SRShared.Key.shieldSignal),
              let decoded = try? JSONDecoder().decode(SRShieldSignal.self, from: data) else {
            return nil
        }
        SRShared.defaults.removeObject(forKey: SRShared.Key.shieldSignal)
        guard Date().timeIntervalSince(decoded.createdAt) < 900 else { return nil }
        return decoded
    }
}
