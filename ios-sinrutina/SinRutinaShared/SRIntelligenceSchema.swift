#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// Guided generation schema. The model fills these fields; SinRutina validates
/// every value afterwards and only then hands it to the business rules.
@available(iOS 26.0, *)
@Generable
nonisolated struct SRGeneratedCapture {
    @Guide(description: "Título corto en español, imperativo, máximo 7 palabras, sin fechas ni horas")
    var title: String

    @Guide(description: "Minutos que costaría hacerlo de verdad", .range(1...240))
    var estimatedMinutes: Int

    @Guide(description: "Estado sugerido", .anyOf(["ahora", "despues", "esperando", "algun_dia"]))
    var suggestedState: String

    @Guide(description: "Hora mínima a partir de la cual se puede hacer, en formato HH:mm. Cadena vacía si no se menciona")
    var availableFromTime: String

    @Guide(description: "Día relativo al que se refiere: hoy, manana o ninguno", .anyOf(["hoy", "manana", "ninguno"]))
    var relativeDay: String

    @Guide(description: "Contexto", .anyOf(["comunicación", "administrativo", "dinero", "salud", "trabajo", "casa", "estudio", "otro"]))
    var context: String

    @Guide(description: "Primera acción concreta, máximo 6 palabras, en infinitivo")
    var nextStep: String

    @Guide(description: "Nombre o relación de la persona de la que depende esto. Cadena vacía si no depende de nadie")
    var waitingFor: String

    @Guide(description: "Apps de iOS útiles para hacerlo", .maximumCount(3))
    var allowedApps: [String]

    @Guide(description: "Si es demasiado grande, entre 0 y 3 trozos concretos. Lista vacía si ya es pequeño", .maximumCount(3))
    var subtasks: [String]
}

@available(iOS 26.0, *)
@Generable
nonisolated struct SRGeneratedMicroActions {
    @Guide(description: "Acciones diminutas en español, cada una de menos de 2 minutos", .count(3))
    var actions: [String]
}

@available(iOS 26.0, *)
@Generable
nonisolated struct SRGeneratedDraft {
    @Guide(description: "Mensaje breve y educado en español, máximo 4 líneas")
    var message: String
}

/// Study planning: a broad objective turned into concrete movements.
@available(iOS 26.0, *)
@Generable
nonisolated struct SRGeneratedStudyPlan {
    @Guide(description: "Objetivo de la sesión en una frase corta, en español, sin motivación")
    var objective: String

    @Guide(description: "Entre 2 y 4 pasos concretos de estudio, en español, en infinitivo", .maximumCount(4))
    var steps: [String]

    @Guide(description: "Minutos de cada paso, en el mismo orden que los pasos", .maximumCount(4))
    var minutes: [Int]
}

/// One explanation of a fragment, kept honest about what it does not know.
@available(iOS 26.0, *)
@Generable
nonisolated struct SRGeneratedExplanation {
    @Guide(description: "Explicación en español, entre 2 y 6 frases, sin listas ni motivación")
    var body: String

    @Guide(description: "Origen principal de la explicación", .anyOf(["documento", "externa", "inferencia"]))
    var provenance: String

    @Guide(description: "Una pregunta de recuperación sobre lo explicado. Cadena vacía si no procede")
    var followUpQuestion: String
}

/// Recall questions produced at the end of a study session.
@available(iOS 26.0, *)
@Generable
nonisolated struct SRGeneratedQuestions {
    @Guide(description: "Preguntas de recuperación en español, abiertas y concretas", .maximumCount(5))
    var questions: [String]

    @Guide(description: "Concepto al que corresponde cada pregunta, en el mismo orden", .maximumCount(5))
    var concepts: [String]
}

/// Contrast between the person's own material and what was found outside.
@available(iOS 26.0, *)
@Generable
nonisolated struct SRGeneratedComparison {
    @Guide(description: "En qué coinciden el material y las fuentes externas", .maximumCount(3))
    var agreements: [String]

    @Guide(description: "En qué se diferencian", .maximumCount(3))
    var differences: [String]

    @Guide(description: "Perspectivas alternativas que aparecen fuera", .maximumCount(2))
    var alternativeViews: [String]

    @Guide(description: "Contradicciones claras. Lista vacía si no hay ninguna", .maximumCount(2))
    var contradictions: [String]

    @Guide(description: "Información más reciente que el material. Lista vacía si no hay", .maximumCount(2))
    var recentInformation: [String]
}

/// What a search should actually ask for. Keeps the person's document at home:
/// only these short strings ever leave the device.
@available(iOS 26.0, *)
@Generable
nonisolated struct SRGeneratedSearchQuery {
    @Guide(description: "Consulta de búsqueda breve, máximo 12 palabras, sin datos personales")
    var query: String

    @Guide(description: "Palabras clave sueltas, sin nombres propios de personas", .maximumCount(5))
    var keywords: [String]
}

/// Reading an email: what it is and whether it needs the person at all.
@available(iOS 26.0, *)
@Generable
nonisolated struct SRGeneratedMailAnalysis {
    @Guide(description: "Resumen del correo en una o dos frases, en español")
    var summary: String

    @Guide(description: "true si el correo pide una acción de quien lo recibe")
    var needsAction: Bool

    @Guide(description: "Acción concreta que le toca a quien recibe el correo, máximo 7 palabras")
    var action: String

    @Guide(description: "Minutos que costaría atenderlo", .range(1...120))
    var estimatedMinutes: Int

    @Guide(description: "Fecha límite mencionada en el correo, formato YYYY-MM-DD. Cadena vacía si no se menciona")
    var deadline: String

    @Guide(description: "Borrador de respuesta en español, breve y educado. Cadena vacía si no requiere respuesta")
    var replyDraft: String

    @Guide(description: "Persona de la que se quedaría esperando respuesta. Cadena vacía si no aplica")
    var waitingFor: String
}

/// A reply rewritten in a requested register.
@available(iOS 26.0, *)
@Generable
nonisolated struct SRGeneratedReply {
    @Guide(description: "Respuesta de correo en español, lista para enviar, sin firma inventada")
    var body: String

    @Guide(description: "Asunto sugerido. Cadena vacía si se mantiene el original")
    var subject: String
}

@available(iOS 26.0, *)
@Generable
nonisolated struct SRGeneratedSummary {
    @Guide(description: "Resumen en español de una o dos frases")
    var summary: String

    @Guide(description: "Título corto en español, máximo 7 palabras")
    var title: String
}
#endif
