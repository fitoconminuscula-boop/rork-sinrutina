import Foundation

/// Registers a reply can be written in. The person picks; SinRutina only learns
/// which one gets used, and never imposes it.
nonisolated enum SRReplyStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case brief
    case formal
    case warm
    case direct
    case human
    case concise

    var id: String { rawValue }

    var label: String {
        switch self {
        case .brief: return "Breve"
        case .formal: return "Formal"
        case .warm: return "Cálida"
        case .direct: return "Directa"
        case .human: return "Más humana"
        case .concise: return "Más concisa"
        }
    }

    var instruction: String {
        switch self {
        case .brief: return "Escríbela en tres frases como máximo."
        case .formal: return "Usa un registro formal, con usted y sin coloquialismos."
        case .warm: return "Usa un tono cercano y amable, sin exageraciones."
        case .direct: return "Ve al grano en la primera frase, sin preámbulos."
        case .human: return "Escríbela como una persona real, con naturalidad, sin sonar a plantilla."
        case .concise: return "Reduce todo lo posible sin perder información."
        }
    }
}

/// What the intelligence layer understood from an email. A proposal, like
/// everything else: nothing is created or sent until the person says so.
nonisolated struct SRMailAnalysis: Codable, Hashable, Sendable {
    var sender: String?
    var recipient: String?
    var subject: String?
    var summary: String
    var needsAction: Bool
    var action: String
    var estimatedMinutes: Int
    var deadline: Date?
    var replyDraft: String?
    var waitingFor: String?
    var excerpt: String
    var usedOnDeviceModel: Bool

    init(
        sender: String? = nil,
        recipient: String? = nil,
        subject: String? = nil,
        summary: String,
        needsAction: Bool,
        action: String,
        estimatedMinutes: Int = 8,
        deadline: Date? = nil,
        replyDraft: String? = nil,
        waitingFor: String? = nil,
        excerpt: String = "",
        usedOnDeviceModel: Bool = false
    ) {
        self.sender = sender
        self.recipient = recipient
        self.subject = subject
        self.summary = summary
        self.needsAction = needsAction
        self.action = action
        self.estimatedMinutes = max(1, min(estimatedMinutes, 120))
        self.deadline = deadline
        self.replyDraft = replyDraft
        self.waitingFor = waitingFor
        self.excerpt = excerpt
        self.usedOnDeviceModel = usedOnDeviceModel
    }

    /// A short, human title: "Correo de Julieta".
    var taskTitle: String {
        if let person = sender?.srDisplayName, !person.isEmpty {
            return needsAction ? "Responder a \(person)" : "Leer correo de \(person)"
        }
        if let subject, !subject.isEmpty {
            return needsAction ? "Responder: \(subject)" : subject
        }
        return needsAction ? "Responder un correo" : "Leer un correo"
    }

    var headline: String {
        if let person = sender?.srDisplayName, !person.isEmpty { return "Correo de \(person)" }
        return subject ?? "Correo"
    }

    /// Turns the analysis into the capture proposal the rest of the app speaks.
    func suggestion() -> SRCaptureSuggestion {
        SRCaptureSuggestion(
            title: taskTitle,
            estimatedMinutes: estimatedMinutes,
            suggestedState: needsAction ? .now : .after,
            dueDate: deadline,
            context: "comunicación",
            nextStep: action.isEmpty ? "Escribir dos frases y enviar" : action,
            allowedApps: ["Mail"],
            summary: summary,
            usedOnDeviceModel: usedOnDeviceModel
        )
    }

    /// Deterministic reading used when Apple Intelligence is unavailable.
    static func heuristic(
        sender: String?,
        recipient: String?,
        subject: String?,
        body: String,
        date: Date?,
        now: Date = Date()
    ) -> SRMailAnalysis {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = SRHeuristics.normalized([subject ?? "", trimmed].joined(separator: " "))
        let questionMarkers = ["?", "podrias", "podrías", "puedes", "necesito", "confirma",
                               "confirmar", "envia", "envía", "adjunta", "responde", "avisame",
                               "avísame", "quedamos", "cuando", "cuándo", "por favor"]
        let needsAction = questionMarkers.contains { lower.contains(SRHeuristics.normalized($0)) }
        let deadline = SRHeuristics.detectDeadline(in: lower, now: now, calendar: .current)
        let person = sender?.srDisplayName
        return SRMailAnalysis(
            sender: sender,
            recipient: recipient,
            subject: subject,
            summary: SRHeuristics.summary(of: trimmed.isEmpty ? (subject ?? "") : trimmed),
            needsAction: needsAction,
            action: needsAction ? "Escribir dos frases y enviar" : "Leer y decidir",
            estimatedMinutes: trimmed.count > 700 ? 12 : 6,
            deadline: deadline,
            replyDraft: needsAction ? fallbackDraft(person: person, subject: subject) : nil,
            waitingFor: needsAction ? person : nil,
            excerpt: String(trimmed.prefix(2_000))
        )
    }

    private static func fallbackDraft(person: String?, subject: String?) -> String {
        let greeting = person.map { "Hola \($0)," } ?? "Hola,"
        return """
        \(greeting)

        Recibido. Lo reviso y te confirmo en cuanto lo tenga.

        Gracias.
        """
    }
}

nonisolated extension String {
    /// "Julieta Pérez <j@x.com>" → "Julieta". Never invents a name.
    var srDisplayName: String {
        var value = self
        if let range = value.range(of: "<") {
            value = String(value[value.startIndex..<range.lowerBound])
        }
        value = value.replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains("@"), !value.contains(" ") {
            value = String(value.split(separator: "@").first ?? "")
                .replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "_", with: " ")
        }
        let first = value.split(separator: " ").first.map(String.init) ?? value
        guard !first.isEmpty else { return "" }
        return first.prefix(1).uppercased() + first.dropFirst()
    }
}
