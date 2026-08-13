import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// SinRutina's intelligence layer.
///
/// Design rules, in order of importance:
/// 1. It only ever *proposes*. It cannot write, move, complete or delete anything.
/// 2. Everyday work happens on device. There is no server and no network call.
/// 3. If Apple Intelligence is missing, the deterministic Spanish reader takes
///    over and the app behaves identically, only less nuanced.
///
/// All model access is serialised inside this actor so the Neural Engine is never
/// asked for two things at once.
actor SRIntelligenceService {
    static let shared = SRIntelligenceService()

    private init() {}

    // MARK: - Availability

    nonisolated var availability: SRIntelligenceAvailability {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return .requiresNewerOS }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .notEnabled
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.modelNotReady):
            return .modelNotReady
        default:
            return .deviceNotEligible
        }
        #else
        return .requiresNewerOS
        #endif
    }

    /// Warms the model up so the first capture does not feel slow.
    func prepare() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), availability.isAvailable {
            LanguageModelSession().prewarm()
        }
        #endif
    }

    // MARK: - Capture

    /// Turns free text into a structured proposal. Never throws: the caller always
    /// receives something usable.
    func suggestion(for rawText: String, now: Date = Date()) async -> SRCaptureSuggestion {
        let fallback = SRHeuristics.suggestion(for: rawText, now: now)
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return fallback }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), availability.isAvailable else { return fallback }
        let instructions = """
        Eres el lector de SinRutina, una app española contra la procrastinación.
        Conviertes lo que escribe una persona en datos estructurados.
        Escribe SIEMPRE en español. Sé literal: NO inventes personas, fechas ni tareas \
        que no aparezcan en el texto. Si algo no se menciona, deja el campo vacío. \
        El título describe la acción, nunca incluye la hora.
        """
        do {
            let session = makeSession(instructions: instructions)
            let response = try await session.respond(
                to: "Texto de la persona: \"\(trimmed)\"",
                generating: SRGeneratedCapture.self,
                options: GenerationOptions(sampling: .greedy)
            )
            return merge(response.content, fallback: fallback, rawText: trimmed, now: now)
        } catch {
            logFailure("captura", error)
            return fallback
        }
        #else
        return fallback
        #endif
    }

    // MARK: - Micro actions for "Estoy saturado"

    func microActions(for title: String, context: String?) async -> [String] {
        let fallback = SRHeuristics.microActions(for: title, context: context)

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), availability.isAvailable else { return fallback }
        let instructions = """
        Eres el lector de SinRutina. La persona está saturada y necesita acciones \
        diminutas, físicas y concretas, de menos de dos minutos cada una. \
        Escribe en español, en infinitivo, sin motivación ni exclamaciones.
        """
        do {
            let session = makeSession(instructions: instructions)
            let response = try await session.respond(
                to: "Tarea: \"\(title)\". Dame los tres primeros movimientos.",
                generating: SRGeneratedMicroActions.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let cleaned = response.content.actions
                .map { sanitize($0, maxWords: 9) }
                .filter { !$0.isEmpty }
            return cleaned.count >= 2 ? cleaned : fallback
        } catch {
            logFailure("microacciones", error)
            return fallback
        }
        #else
        return fallback
        #endif
    }

    // MARK: - Splitting a task that is too big

    func split(title: String) async -> [String] {
        let lower = SRHeuristics.normalized(title)
        let fallback = SRHeuristics.splitIfTooBig(title: title, lower: lower, minutes: 90)

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), availability.isAvailable else { return fallback }
        let instructions = """
        Eres el lector de SinRutina. Divides una tarea demasiado grande en trozos \
        pequeños y ordenados. Cada trozo se puede hacer en menos de 20 minutos. \
        Escribe en español, en infinitivo.
        """
        do {
            let session = makeSession(instructions: instructions)
            let response = try await session.respond(
                to: "Divide esto en tres pasos: \"\(title)\"",
                generating: SRGeneratedMicroActions.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let cleaned = response.content.actions
                .map { sanitize($0, maxWords: 10) }
                .filter { !$0.isEmpty }
            return cleaned.count >= 2 ? cleaned : fallback
        } catch {
            logFailure("dividir", error)
            return fallback
        }
        #else
        return fallback
        #endif
    }

    // MARK: - Waiting follow-up

    /// Writes a draft the person can copy. SinRutina never sends anything.
    func followUpDraft(taskTitle: String, person: String?, days: Int) async -> String {
        let fallback = SRHeuristics.followUpDraft(taskTitle: taskTitle, person: person, days: days)

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), availability.isAvailable else { return fallback }
        let instructions = """
        Eres el lector de SinRutina. Escribes borradores de seguimiento breves, \
        educados y sin rodeos, en español. Nunca envías nada: solo propones el texto. \
        Máximo cuatro líneas.
        """
        do {
            let session = makeSession(instructions: instructions)
            let who = person.map { "Va dirigido a \($0)." } ?? "No sabemos el nombre."
            let response = try await session.respond(
                to: "Asunto pendiente: \"\(taskTitle)\". Llevamos \(days) días esperando. \(who)",
                generating: SRGeneratedDraft.self
            )
            let message = response.content.message.trimmingCharacters(in: .whitespacesAndNewlines)
            return message.count >= 20 ? message : fallback
        } catch {
            logFailure("seguimiento", error)
            return fallback
        }
        #else
        return fallback
        #endif
    }

    // MARK: - Shared text from other apps

    /// Reads a message shared from WhatsApp, Mail or anywhere else and proposes
    /// what SinRutina should do with it.
    func interpretSharedText(_ rawText: String, sourceApp: String?, now: Date = Date()) async -> SRCaptureSuggestion {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        var fallback = SRHeuristics.suggestion(for: trimmed, now: now)
        fallback.summary = SRHeuristics.summary(of: trimmed)
        if trimmed.count > 90 {
            // A long paste is almost always something to answer.
            fallback.title = replyTitle(for: trimmed, fallbackTitle: fallback.title, sourceApp: sourceApp)
            fallback.nextStep = fallback.nextStep ?? "Escribir dos frases y enviar"
        }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), availability.isAvailable else { return fallback }
        let origin = sourceApp.map { "Viene de \($0)." } ?? ""
        let instructions = """
        Eres el lector de SinRutina. Recibes un texto que alguien ha compartido con \
        la app desde otra aplicación. \(origin) Decides qué acción le corresponde a la \
        persona que usa SinRutina, no a quien escribió el texto. Si el texto es un \
        mensaje de otra persona, la acción normalmente es responder. \
        Escribe SIEMPRE en español y NO inventes datos.
        """
        do {
            let session = makeSession(instructions: instructions)
            let clipped = String(trimmed.prefix(1_200))
            let response = try await session.respond(
                to: "Texto compartido:\n\"\(clipped)\"",
                generating: SRGeneratedCapture.self,
                options: GenerationOptions(sampling: .greedy)
            )
            var merged = merge(response.content, fallback: fallback, rawText: clipped, now: now)
            merged.summary = fallback.summary
            return merged
        } catch {
            logFailure("texto compartido", error)
            return fallback
        }
        #else
        return fallback
        #endif
    }

    // MARK: - Summaries and short titles

    func summarize(_ rawText: String) async -> (title: String, summary: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = (SRHeuristics.shortTitle(from: trimmed), SRHeuristics.summary(of: trimmed))
        guard trimmed.count > 60 else { return fallback }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), availability.isAvailable else { return fallback }
        do {
            let session = makeSession(instructions: "Resumes textos en español de forma breve y neutra. NO inventes datos.")
            let response = try await session.respond(
                to: "Resume esto:\n\"\(String(trimmed.prefix(1_200)))\"",
                generating: SRGeneratedSummary.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let title = sanitize(response.content.title, maxWords: 8)
            let summary = response.content.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                title.isEmpty ? fallback.0 : title,
                summary.isEmpty ? fallback.1 : summary
            )
        } catch {
            logFailure("resumen", error)
            return fallback
        }
        #else
        return fallback
        #endif
    }

    // MARK: - Model plumbing

    #if canImport(FoundationModels)
    /// A fresh session per request keeps prompts short and stops one capture from
    /// contaminating the next. Because this is an actor, requests are serialised.
    @available(iOS 26.0, *)
    private func makeSession(instructions: String) -> LanguageModelSession {
        LanguageModelSession(instructions: instructions)
    }

    @available(iOS 26.0, *)
    private func merge(
        _ generated: SRGeneratedCapture,
        fallback: SRCaptureSuggestion,
        rawText: String,
        now: Date
    ) -> SRCaptureSuggestion {
        var result = fallback
        result.usedOnDeviceModel = true

        let title = sanitize(generated.title, maxWords: 9)
        if title.count >= 3 { result.title = title }

        if generated.estimatedMinutes >= 1 {
            result.estimatedMinutes = min(max(generated.estimatedMinutes, 1), 240)
        }

        if let state = state(from: generated.suggestedState) {
            result.suggestedState = state
        }

        let waiting = sanitize(generated.waitingFor, maxWords: 4)
        if !waiting.isEmpty, waiting.count >= 3, SRHeuristics.normalized(rawText).contains(SRHeuristics.normalized(waiting).prefix(4)) {
            result.waitingFor = waiting
            result.suggestedState = .waiting
        } else if fallback.waitingFor == nil, result.suggestedState == .waiting, waiting.isEmpty {
            // The model claimed a dependency it cannot name: do not trust it.
            result.suggestedState = fallback.suggestedState
        }

        if let parsed = date(fromTime: generated.availableFromTime, relativeDay: generated.relativeDay, now: now) {
            result.availableFrom = parsed
            if result.suggestedState == .now { result.suggestedState = .after }
        } else {
            result.availableFrom = fallback.availableFrom
        }

        let context = generated.context.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !context.isEmpty, context != "otro" { result.context = context }

        let step = sanitize(generated.nextStep, maxWords: 8)
        if step.count >= 3 { result.nextStep = step }

        let apps = generated.allowedApps
            .map { sanitize($0, maxWords: 3) }
            .filter { !$0.isEmpty }
        if !apps.isEmpty { result.allowedApps = Array(apps.prefix(3)) }

        let subtasks = generated.subtasks
            .map { sanitize($0, maxWords: 10) }
            .filter { $0.count >= 5 }
        result.subtasks = Array(subtasks.prefix(3))

        return result
    }
    #endif

    private func state(from raw: String) -> TaskState? {
        switch SRHeuristics.normalized(raw) {
        case "ahora": return .now
        case "despues", "despues de": return .after
        case "esperando": return .waiting
        case "algun_dia", "algun dia": return .someday
        default: return nil
        }
    }

    private func date(fromTime raw: String, relativeDay: String, now: Date) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":")
        guard let hour = Int(parts.first ?? ""), hour >= 0, hour <= 23 else { return nil }
        let minute = parts.count > 1 ? min(Int(parts[1]) ?? 0, 59) : 0

        let calendar = Calendar.current
        var day = now
        if SRHeuristics.normalized(relativeDay) == "manana" {
            day = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        }
        guard let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return nil }
        if candidate <= now, SRHeuristics.normalized(relativeDay) != "manana" {
            return calendar.date(byAdding: .day, value: 1, to: candidate)
        }
        return candidate
    }

    /// Strips quotes, trailing punctuation and runaway length from model output.
    private func sanitize(_ raw: String, maxWords: Int) -> String {
        var text = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”«».,;:-–—*•"))
        guard !text.isEmpty else { return "" }
        let words = text.split(separator: " ").map(String.init)
        if words.count > maxWords {
            text = words.prefix(maxWords).joined(separator: " ")
        }
        return String(text.prefix(1)).uppercased() + String(text.dropFirst())
    }

    private func replyTitle(for text: String, fallbackTitle: String, sourceApp: String?) -> String {
        if let person = SRHeuristics.detectPerson(in: text, lower: SRHeuristics.normalized(text)) {
            return "Responder a \(person)"
        }
        if let sourceApp, !sourceApp.isEmpty {
            return "Responder en \(sourceApp)"
        }
        return fallbackTitle
    }

    private func logFailure(_ task: String, _ error: Error) {
        // Never log the person's text, only the failing step.
        print("[SinRutina] Apple Intelligence no pudo completar \(task): \(type(of: error))")
    }
}
