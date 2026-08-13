import Foundation

/// Where the answers are allowed to come from. The person owns this decision:
/// SinRutina never widens the sources on its own.
nonisolated enum SRSourceMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Only the attached material. No network, ever.
    case onlyMine
    /// The material first, the web only to fill a real gap.
    case mixed
    /// Mostly external sources, because there is no material yet.
    case fromScratch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onlyMine: return "Solo mi material"
        case .mixed: return "Material + web"
        case .fromScratch: return "Buscar desde cero"
        }
    }

    var explanation: String {
        switch self {
        case .onlyMine: return "No se consulta nada fuera de este iPhone."
        case .mixed: return "Se busca fuera solo cuando falta algo."
        case .fromScratch: return "Se responde sobre todo con fuentes externas."
        }
    }

    var allowsWeb: Bool { self != .onlyMine }

    var symbolName: String {
        switch self {
        case .onlyMine: return "doc.text"
        case .mixed: return "doc.text.magnifyingglass"
        case .fromScratch: return "globe"
        }
    }
}

/// The shape of an explanation the person asked for.
nonisolated enum SRExplainAction: String, Codable, CaseIterable, Sendable, Identifiable {
    case simpler
    case deeper
    case example
    case compare
    case quizMe
    case didntUnderstand
    case searchWeb

    var id: String { rawValue }

    /// Only the first three are shown up front; the rest live in a quiet menu.
    static var primary: [SRExplainAction] { [.simpler, .deeper, .example] }
    static var secondary: [SRExplainAction] { [.compare, .quizMe, .didntUnderstand, .searchWeb] }

    var label: String {
        switch self {
        case .simpler: return "Más simple"
        case .deeper: return "Más profundo"
        case .example: return "Dame un ejemplo"
        case .compare: return "Compáralo"
        case .quizMe: return "Pregúntame"
        case .didntUnderstand: return "No lo entendí"
        case .searchWeb: return "Buscar en la web"
        }
    }

    var symbolName: String {
        switch self {
        case .simpler: return "arrow.down.right.and.arrow.up.left"
        case .deeper: return "arrow.up.left.and.arrow.down.right"
        case .example: return "lightbulb"
        case .compare: return "arrow.left.arrow.right"
        case .quizMe: return "questionmark.circle"
        case .didntUnderstand: return "hand.raised"
        case .searchWeb: return "globe"
        }
    }

    /// Instruction fragment handed to the model.
    var instruction: String {
        switch self {
        case .simpler: return "Explícalo de la forma más simple posible, con frases cortas."
        case .deeper: return "Profundiza: matices, condiciones y por qué importa."
        case .example: return "Da un ejemplo concreto y cotidiano."
        case .compare: return "Compáralo con una idea vecina y marca la diferencia."
        case .quizMe: return "Termina con una pregunta que obligue a recordar lo esencial."
        case .didntUnderstand: return "La explicación anterior no se entendió: cambia de ángulo por completo."
        case .searchWeb: return "Usa la información externa aportada y dilo con claridad."
        }
    }

    var needsWeb: Bool { self == .searchWeb }
}

/// Authority tier used to rank external sources for academic work.
nonisolated enum SRSourceTier: Int, Codable, Sendable, Comparable {
    case scientificArticle = 0
    case primarySource = 1
    case university = 2
    case academicRepository = 3
    case officialBody = 4
    case technicalDocs = 5
    case qualitySecondary = 6
    case other = 7

    static func < (lhs: SRSourceTier, rhs: SRSourceTier) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .scientificArticle: return "Artículo científico"
        case .primarySource: return "Fuente primaria"
        case .university: return "Universidad"
        case .academicRepository: return "Repositorio académico"
        case .officialBody: return "Organismo oficial"
        case .technicalDocs: return "Documentación técnica"
        case .qualitySecondary: return "Fuente secundaria"
        case .other: return "Otra fuente"
        }
    }

    var symbolName: String {
        switch self {
        case .scientificArticle: return "doc.richtext"
        case .primarySource: return "text.book.closed"
        case .university: return "building.columns"
        case .academicRepository: return "books.vertical"
        case .officialBody: return "checkmark.seal"
        case .technicalDocs: return "chevron.left.forwardslash.chevron.right"
        case .qualitySecondary: return "newspaper"
        case .other: return "globe"
        }
    }
}

/// One external result, already ranked. Kept small on purpose: SinRutina stores
/// links, not scraped pages.
nonisolated struct SRWebSource: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var snippet: String
    var urlString: String
    var tier: SRSourceTier
    var host: String
    var year: Int?
    var authors: String?

    var url: URL? { URL(string: urlString) }

    var subtitle: String {
        var parts: [String] = [tier.label]
        if let authors, !authors.isEmpty { parts.append(authors) }
        if let year { parts.append(String(year)) }
        return parts.joined(separator: " · ")
    }
}

/// Where a sentence came from. Shown so the person can tell knowledge from guess.
nonisolated enum SRProvenance: String, Codable, Sendable {
    case document
    case external
    case inference

    var label: String {
        switch self {
        case .document: return "De tu material"
        case .external: return "De fuentes externas"
        case .inference: return "Interpretación del modelo"
        }
    }

    var symbolName: String {
        switch self {
        case .document: return "doc.text"
        case .external: return "globe"
        case .inference: return "sparkles"
        }
    }
}

/// An answer to "Explícame esto".
nonisolated struct SRExplanation: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var action: SRExplainAction
    var body: String
    var provenance: SRProvenance
    var sources: [SRWebSource]
    var followUpQuestion: String?
    var usedOnDeviceModel: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        action: SRExplainAction,
        body: String,
        provenance: SRProvenance,
        sources: [SRWebSource] = [],
        followUpQuestion: String? = nil,
        usedOnDeviceModel: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.action = action
        self.body = body
        self.provenance = provenance
        self.sources = sources
        self.followUpQuestion = followUpQuestion
        self.usedOnDeviceModel = usedOnDeviceModel
        self.createdAt = createdAt
    }
}

/// The answer to "¿Coincide con mi texto?".
nonisolated struct SRComparison: Codable, Hashable, Sendable {
    var agreements: [String]
    var differences: [String]
    var alternativeViews: [String]
    var contradictions: [String]
    var recentInformation: [String]
    var sources: [SRWebSource]

    var isEmpty: Bool {
        agreements.isEmpty && differences.isEmpty && alternativeViews.isEmpty
            && contradictions.isEmpty && recentInformation.isEmpty
    }
}

/// A single recall question. There are no grades, only "costó" or "salió".
nonisolated struct SRRecallQuestion: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var question: String
    var concept: String
    var expectedIdea: String?

    init(id: UUID = UUID(), question: String, concept: String, expectedIdea: String? = nil) {
        self.id = id
        self.question = question
        self.concept = concept
        self.expectedIdea = expectedIdea
    }
}

/// How the person answered a recall question. Deliberately not a score.
nonisolated enum SRRecallOutcome: String, Codable, Sendable {
    case answered
    case dontKnow
    case skipped
}

/// One concrete movement inside a study session.
nonisolated struct SRStudyStep: Codable, Hashable, Sendable, Identifiable {
    nonisolated enum Kind: String, Codable, Sendable {
        case read
        case identify
        case answer
        case write
        case review

        var symbolName: String {
            switch self {
            case .read: return "text.alignleft"
            case .identify: return "scope"
            case .answer: return "questionmark.circle"
            case .write: return "pencil"
            case .review: return "arrow.clockwise"
            }
        }
    }

    var id: UUID
    var text: String
    var minutes: Int
    var kind: Kind

    init(id: UUID = UUID(), text: String, minutes: Int, kind: Kind) {
        self.id = id
        self.text = text
        self.minutes = max(1, min(minutes, 90))
        self.kind = kind
    }
}

/// A broad objective turned into something that can be started today.
nonisolated struct SRStudyPlan: Codable, Hashable, Sendable {
    var objective: String
    var steps: [SRStudyStep]
    var usedOnDeviceModel: Bool

    var totalMinutes: Int { steps.reduce(0) { $0 + $1.minutes } }

    init(objective: String, steps: [SRStudyStep], usedOnDeviceModel: Bool = false) {
        self.objective = objective
        self.steps = steps
        self.usedOnDeviceModel = usedOnDeviceModel
    }
}

/// The privacy gate for anything that may leave the device.
///
/// It lives in the shared layer on purpose: the app, the share extension and the
/// intents all have to clean a query the exact same way.
nonisolated enum SRQueryGuard {
    /// Strips emails, long digit runs and runaway length. What comes out is short
    /// enough to be read at a glance in the UI.
    static func sanitize(_ raw: String, maxWords: Int = 14) -> String {
        var value = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(
            of: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+",
            with: " ",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: "\\b\\d{6,}\\b",
            with: " ",
            options: .regularExpression
        )
        let words = value.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        return words.prefix(maxWords).joined(separator: " ")
    }
}

/// Recognises study-shaped work without asking the person to tag anything.
nonisolated enum SRStudyDetector {
    private static let markers: [String] = [
        "estudiar", "estudio", "examen", "parcial", "final", "apuntes", "apunte",
        "leer", "lectura", "libro", "capitulo", "capítulo", "paper", "papers",
        "articulo", "artículo", "tesis", "tfg", "tfm", "curso", "clase", "asignatura",
        "temario", "tema ", "resumen", "resumir", "repasar", "repaso", "memorizar",
        "practica", "práctica", "problemas", "ejercicios", "entrega", "trabajo final",
        "seminario", "bibliografia", "bibliografía", "pdf", "aprender", "oposicion",
        "oposición", "idioma", "vocabulario", "fenomenologia", "fenomenología"
    ]

    /// True when the task is about learning something, not just doing something.
    static func isStudy(title: String, detail: String? = nil, context: String? = nil) -> Bool {
        if let context, SRHeuristics.normalized(context) == "estudio" { return true }
        let haystack = SRHeuristics.normalized([title, detail ?? ""].joined(separator: " "))
        return markers.contains { haystack.contains(SRHeuristics.normalized($0)) }
    }

    /// A calm objective line for a study task, derived from what we already know.
    static func objective(title: String, detail: String?) -> String? {
        if let detail, detail.count > 8 {
            return detail.count > 140 ? String(detail.prefix(140)) + "…" : detail
        }
        let lower = SRHeuristics.normalized(title)
        if lower.contains("examen") || lower.contains("parcial") {
            return "Cubrir lo que entra y dejar dudas por escrito."
        }
        if lower.contains("leer") || lower.contains("capitulo") || lower.contains("paper") {
            return "Entender la idea central, no terminar páginas."
        }
        if lower.contains("repasar") || lower.contains("memorizar") {
            return "Recordar sin mirar, aunque sea poco."
        }
        return nil
    }

    /// Deterministic session plan used when Apple Intelligence is not available.
    static func fallbackPlan(title: String, minutes: Int, materialTitle: String?) -> SRStudyPlan {
        let unit = max(4, minutes / 3)
        let what = materialTitle ?? title
        return SRStudyPlan(
            objective: objective(title: title, detail: nil) ?? "Empezar y dejar rastro de lo entendido.",
            steps: [
                SRStudyStep(text: "Leer un fragmento de \(what)", minutes: unit, kind: .read),
                SRStudyStep(text: "Marcar tres conceptos centrales", minutes: unit, kind: .identify),
                SRStudyStep(text: "Responder tres preguntas sin mirar", minutes: max(3, minutes - unit * 2), kind: .answer)
            ]
        )
    }

    /// The smallest possible movements when studying feels impossible.
    static func microActions(title: String, hasMaterial: Bool) -> [String] {
        var actions: [String] = []
        if hasMaterial {
            actions.append("Abrir el material")
            actions.append("Leer un párrafo")
        } else {
            actions.append("Abrir el PDF o los apuntes")
            actions.append("Leer solo un título")
        }
        actions.append("Subrayar un concepto")
        actions.append("Estudiar 2 minutos")
        actions.append("Responder una pregunta")
        return actions
    }
}
