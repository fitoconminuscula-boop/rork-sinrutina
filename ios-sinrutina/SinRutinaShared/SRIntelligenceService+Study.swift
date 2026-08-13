import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Study, explanation and mail reasoning.
///
/// Everything here obeys the same three rules as the rest of the intelligence
/// layer: it only proposes, it prefers the device, and it degrades to a
/// deterministic Spanish reader instead of failing.
extension SRIntelligenceService {

    // MARK: - Study sessions

    /// Turns "Estudiar capítulo 4" into movements that can start in a minute.
    func studyPlan(
        title: String,
        objective: String?,
        minutes: Int,
        materialTitle: String?,
        materialFragment: String?
    ) async -> SRStudyPlan {
        let fallback = SRStudyDetector.fallbackPlan(
            title: title,
            minutes: minutes,
            materialTitle: materialTitle
        )

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), availability.isAvailable else { return fallback }
        let instructions = """
        Eres el lector de SinRutina. Conviertes un objetivo de estudio amplio en \
        2 a 4 pasos concretos que se pueden empezar en un minuto. Cada paso indica \
        qué leer, qué identificar o qué responder. Escribe en español, en infinitivo, \
        sin motivación y sin inventar páginas ni capítulos que no aparezcan.
        """
        var prompt = "Tarea de estudio: \"\(title)\". Tiempo disponible: \(minutes) minutos."
        if let objective, !objective.isEmpty { prompt += " Objetivo: \"\(objective)\"." }
        if let materialTitle, !materialTitle.isEmpty { prompt += " Material: \"\(materialTitle)\"." }
        if let materialFragment, !materialFragment.isEmpty {
            prompt += "\nFragmento del material:\n\"\(String(materialFragment.prefix(900)))\""
        }

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: prompt,
                generating: SRGeneratedStudyPlan.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let content = response.content
            let texts = content.steps
                .map { srClean($0, maxWords: 12) }
                .filter { $0.count >= 5 }
            guard texts.count >= 2 else { return fallback }

            var steps: [SRStudyStep] = []
            for (index, text) in texts.enumerated() {
                let proposed = index < content.minutes.count ? content.minutes[index] : minutes / texts.count
                steps.append(
                    SRStudyStep(
                        text: text,
                        minutes: max(2, min(proposed, minutes)),
                        kind: SRIntelligenceService.stepKind(for: text)
                    )
                )
            }
            let objectiveLine = srClean(content.objective, maxWords: 16)
            return SRStudyPlan(
                objective: objectiveLine.count >= 8 ? objectiveLine : fallback.objective,
                steps: steps,
                usedOnDeviceModel: true
            )
        } catch {
            srLogFailure("plan de estudio", error)
            return fallback
        }
        #else
        return fallback
        #endif
    }

    // MARK: - Explaining a fragment

    /// Explains a fragment. External material is only ever included when the
    /// caller already gathered it under the person's chosen source mode.
    func explanation(
        for fragment: String,
        action: SRExplainAction,
        materialTitle: String?,
        externalContext: [SRWebSource],
        previousBody: String?
    ) async -> SRExplanation {
        let provenance: SRProvenance = externalContext.isEmpty ? .document : .external
        let fallbackBody = SRIntelligenceService.deterministicExplanation(
            fragment: fragment,
            action: action,
            sources: externalContext
        )
        var fallback = SRExplanation(
            action: action,
            body: fallbackBody,
            provenance: fragment.isEmpty && externalContext.isEmpty ? .inference : provenance,
            sources: externalContext
        )

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), availability.isAvailable else { return fallback }
        let instructions = """
        Eres el lector de SinRutina. Explicas ideas a alguien que está estudiando. \
        \(action.instruction) Escribe en español, entre 2 y 6 frases, sin listas, \
        sin motivación y sin exclamaciones. Si algo no está en el material ni en las \
        fuentes aportadas, dilo en lugar de inventarlo.
        """
        var prompt = ""
        if !fragment.isEmpty {
            prompt += "Fragmento del material\(materialTitle.map { " (\($0))" } ?? ""):\n\"\(String(fragment.prefix(1_400)))\"\n"
        }
        if !externalContext.isEmpty {
            let lines = externalContext.prefix(4).map { "- \($0.title): \($0.snippet)" }.joined(separator: "\n")
            prompt += "\nInformación externa encontrada:\n\(lines)\n"
        }
        if let previousBody, !previousBody.isEmpty, action == .didntUnderstand {
            prompt += "\nExplicación anterior que no funcionó:\n\"\(String(previousBody.prefix(500)))\"\n"
        }
        if prompt.isEmpty { prompt = "Explica el concepto pedido con honestidad sobre lo que no sabes." }

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: prompt,
                generating: SRGeneratedExplanation.self
            )
            let body = response.content.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard body.count >= 30 else { return fallback }
            let question = response.content.followUpQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
            fallback = SRExplanation(
                action: action,
                body: body,
                provenance: SRIntelligenceService.provenance(
                    fromModel: response.content.provenance,
                    hasFragment: !fragment.isEmpty,
                    hasExternal: !externalContext.isEmpty
                ),
                sources: externalContext,
                followUpQuestion: question.count >= 10 ? question : nil,
                usedOnDeviceModel: true
            )
            return fallback
        } catch {
            srLogFailure("explicación", error)
            return fallback
        }
        #else
        return fallback
        #endif
    }

    // MARK: - Search queries

    /// Decides what to ask the web. This is the privacy boundary: the returned
    /// string is the only thing that may leave the device.
    func searchQuery(for question: String, materialTitle: String?) async -> String {
        let fallback = SRQueryGuard.sanitize(
            [question, materialTitle ?? ""].joined(separator: " ")
        )

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), availability.isAvailable else { return fallback }
        let instructions = """
        Eres el lector de SinRutina. Conviertes una duda en una consulta de búsqueda \
        breve y neutra. Nunca incluyas nombres de personas, direcciones de correo, \
        ni frases largas copiadas de un documento privado. Máximo 12 palabras.
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: "Duda: \"\(String(question.prefix(300)))\"",
                generating: SRGeneratedSearchQuery.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let query = SRQueryGuard.sanitize(response.content.query)
            return query.count >= 4 ? query : fallback
        } catch {
            srLogFailure("consulta de búsqueda", error)
            return fallback
        }
        #else
        return fallback
        #endif
    }

    // MARK: - Comparing material with the web

    func comparison(
        materialFragment: String,
        sources: [SRWebSource]
    ) async -> SRComparison {
        let fallback = SRComparison(
            agreements: [],
            differences: [],
            alternativeViews: sources.prefix(2).map { "\($0.title) lo plantea desde otro ángulo." },
            contradictions: [],
            recentInformation: sources
                .filter { ($0.year ?? 0) >= Calendar.current.component(.year, from: Date()) - 3 }
                .prefix(2)
                .map { "\($0.title)\($0.year.map { " (\($0))" } ?? "")" },
            sources: sources
        )
        guard !sources.isEmpty, materialFragment.count > 80 else { return fallback }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), availability.isAvailable else { return fallback }
        let instructions = """
        Eres el lector de SinRutina. Contrastas el material de la persona con lo que \
        se ha encontrado fuera. Sé literal: si no hay contradicciones, deja la lista \
        vacía. Escribe en español, frases cortas, sin juicios.
        """
        let external = sources.prefix(4).map { "- \($0.title): \($0.snippet)" }.joined(separator: "\n")
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: """
                Material de la persona:
                "\(String(materialFragment.prefix(1_200)))"

                Fuentes externas:
                \(external)
                """,
                generating: SRGeneratedComparison.self
            )
            let content = response.content
            return SRComparison(
                agreements: content.agreements.map { srClean($0, maxWords: 20) }.filter { !$0.isEmpty },
                differences: content.differences.map { srClean($0, maxWords: 20) }.filter { !$0.isEmpty },
                alternativeViews: content.alternativeViews.map { srClean($0, maxWords: 20) }.filter { !$0.isEmpty },
                contradictions: content.contradictions.map { srClean($0, maxWords: 20) }.filter { !$0.isEmpty },
                recentInformation: content.recentInformation.map { srClean($0, maxWords: 20) }.filter { !$0.isEmpty },
                sources: sources
            )
        } catch {
            srLogFailure("comparación", error)
            return fallback
        }
        #else
        return fallback
        #endif
    }

    // MARK: - Recall questions

    func recallQuestions(
        materialFragment: String,
        objective: String?,
        count: Int
    ) async -> [SRRecallQuestion] {
        let wanted = min(max(count, 1), 5)
        let fallback = SRIntelligenceService.deterministicQuestions(
            fragment: materialFragment,
            objective: objective,
            count: wanted
        )

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), availability.isAvailable else { return fallback }
        let instructions = """
        Eres el lector de SinRutina. Escribes preguntas de recuperación sobre lo que \
        la persona acaba de estudiar. Preguntas abiertas, concretas, en español. \
        No pongas la respuesta. No inventes contenido que no esté en el material.
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: """
                Material estudiado:
                "\(String(materialFragment.prefix(1_400)))"
                Objetivo: "\(objective ?? "comprender lo esencial")"
                Escribe \(wanted) preguntas.
                """,
                generating: SRGeneratedQuestions.self
            )
            let content = response.content
            let questions = content.questions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 12 }
            guard !questions.isEmpty else { return fallback }
            return questions.prefix(wanted).enumerated().map { index, text in
                let concept = index < content.concepts.count
                    ? srClean(content.concepts[index], maxWords: 5)
                    : ""
                return SRRecallQuestion(
                    question: text,
                    concept: concept.isEmpty ? SRIntelligenceService.conceptGuess(from: text) : concept
                )
            }
        } catch {
            srLogFailure("preguntas de repaso", error)
            return fallback
        }
        #else
        return fallback
        #endif
    }

    // MARK: - Mail

    func mailAnalysis(
        sender: String?,
        recipient: String?,
        subject: String?,
        body: String,
        date: Date?,
        now: Date = Date()
    ) async -> SRMailAnalysis {
        let fallback = SRMailAnalysis.heuristic(
            sender: sender,
            recipient: recipient,
            subject: subject,
            body: body,
            date: date,
            now: now
        )
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 || (subject?.count ?? 0) >= 8 else { return fallback }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), availability.isAvailable else { return fallback }
        let instructions = """
        Eres el lector de SinRutina. Lees un correo y decides qué le toca a quien lo \
        recibe. Si el correo no pide nada, dilo. El borrador de respuesta es breve, \
        educado y sin firmar con nombres que no aparezcan. Escribe en español y no \
        inventes fechas que no estén en el texto.
        """
        var prompt = ""
        if let sender { prompt += "De: \(sender)\n" }
        if let subject { prompt += "Asunto: \(subject)\n" }
        if let date {
            prompt += "Fecha: \(ISO8601DateFormatter().string(from: date))\n"
        }
        prompt += "\n\(String(trimmed.prefix(1_600)))"

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: prompt,
                generating: SRGeneratedMailAnalysis.self
            )
            let content = response.content
            let summary = content.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let draft = content.replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let waiting = srClean(content.waitingFor, maxWords: 3)
            return SRMailAnalysis(
                sender: sender,
                recipient: recipient,
                subject: subject,
                summary: summary.count >= 12 ? summary : fallback.summary,
                needsAction: content.needsAction,
                action: srClean(content.action, maxWords: 8).isEmpty ? fallback.action : srClean(content.action, maxWords: 8),
                estimatedMinutes: content.estimatedMinutes,
                deadline: SRIntelligenceService.date(fromISODay: content.deadline) ?? fallback.deadline,
                replyDraft: draft.count >= 20 ? draft : fallback.replyDraft,
                waitingFor: waiting.isEmpty ? fallback.waitingFor : waiting,
                excerpt: String(trimmed.prefix(2_000)),
                usedOnDeviceModel: true
            )
        } catch {
            srLogFailure("análisis de correo", error)
            return fallback
        }
        #else
        return fallback
        #endif
    }

    /// Rewrites a draft in a requested register. The person always keeps the send.
    func restyleReply(
        draft: String,
        style: SRReplyStyle,
        sender: String?,
        subject: String?,
        originalExcerpt: String?
    ) async -> String {
        let fallback = SRIntelligenceService.deterministicRestyle(draft: draft, style: style, person: sender?.srDisplayName)

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), availability.isAvailable else { return fallback }
        let instructions = """
        Eres el lector de SinRutina. Reescribes un borrador de respuesta de correo. \
        \(style.instruction) Mantén los hechos, no añadas compromisos nuevos, no \
        inventes nombres ni fechas. Escribe en español. Nunca envías nada.
        """
        var prompt = "Borrador actual:\n\"\(String(draft.prefix(900)))\""
        if let originalExcerpt, !originalExcerpt.isEmpty {
            prompt += "\n\nCorreo original (resumido):\n\"\(String(originalExcerpt.prefix(600)))\""
        }
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: SRGeneratedReply.self)
            let body = response.content.body.trimmingCharacters(in: .whitespacesAndNewlines)
            return body.count >= 20 ? body : fallback
        } catch {
            srLogFailure("reescritura de respuesta", error)
            return fallback
        }
        #else
        return fallback
        #endif
    }

    // MARK: - Local helpers

    /// Same cleaning rules as the capture path, available to this file.
    private func srClean(_ raw: String, maxWords: Int) -> String {
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

    private func srLogFailure(_ step: String, _ error: Error) {
        print("[SinRutina] Apple Intelligence no pudo completar \(step): \(type(of: error))")
    }

    // MARK: - Deterministic fallbacks

    nonisolated static func stepKind(for text: String) -> SRStudyStep.Kind {
        let lower = SRHeuristics.normalized(text)
        if lower.contains("leer") || lower.contains("lectura") || lower.contains("pagina") { return .read }
        if lower.contains("identificar") || lower.contains("marcar") || lower.contains("subrayar") { return .identify }
        if lower.contains("responder") || lower.contains("pregunta") { return .answer }
        if lower.contains("escribir") || lower.contains("resumir") || lower.contains("esquema") { return .write }
        if lower.contains("repasar") || lower.contains("repaso") { return .review }
        return .read
    }

    nonisolated static func provenance(
        fromModel raw: String,
        hasFragment: Bool,
        hasExternal: Bool
    ) -> SRProvenance {
        switch SRHeuristics.normalized(raw) {
        case "documento": return hasFragment ? .document : .inference
        case "externa": return hasExternal ? .external : .inference
        default: return .inference
        }
    }

    nonisolated static func deterministicExplanation(
        fragment: String,
        action: SRExplainAction,
        sources: [SRWebSource]
    ) -> String {
        if !fragment.isEmpty {
            let summary = SRHeuristics.summary(of: fragment, maxSentences: action == .deeper ? 4 : 2)
            switch action {
            case .simpler:
                return "En corto: \(summary)"
            case .deeper:
                return "\(summary) Merece la pena fijarse en las condiciones en que esto se cumple y en qué cambia si no se cumplen."
            case .example:
                return "\(summary) Un ejemplo cotidiano ayuda: piensa en una situación tuya donde esto ocurra y descríbela en una frase."
            case .compare:
                return "\(summary) Compáralo con la idea vecina que aparece en tu material y anota en qué se separan."
            case .quizMe:
                return "\(summary) Ahora ciérralo y cuéntalo con tus palabras."
            case .didntUnderstand:
                return "Vamos por otro lado: quédate solo con esta frase del material y descarta el resto por ahora. \(summary)"
            case .searchWeb:
                if let first = sources.first {
                    return "Fuera se plantea así: \(first.snippet.isEmpty ? first.title : first.snippet)"
                }
                return summary
            }
        }
        if let first = sources.first {
            return "Sin material cargado, esto es lo que dicen las fuentes: \(first.snippet.isEmpty ? first.title : first.snippet)"
        }
        return "No hay material ni fuentes todavía. Añade el PDF, el texto o activa la búsqueda para poder explicarlo."
    }

    nonisolated static func deterministicQuestions(
        fragment: String,
        objective: String?,
        count: Int
    ) -> [SRRecallQuestion] {
        let sentences = fragment
            .split(whereSeparator: { ".!?\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 40 }
        var questions: [SRRecallQuestion] = []
        for sentence in sentences.prefix(count) {
            let concept = conceptGuess(from: sentence)
            questions.append(
                SRRecallQuestion(
                    question: "¿Qué dice tu material sobre \(concept.lowercased())?",
                    concept: concept
                )
            )
        }
        if questions.isEmpty {
            let concept = objective.map { conceptGuess(from: $0) } ?? "lo que acabas de estudiar"
            questions.append(
                SRRecallQuestion(
                    question: "¿Qué te llevas de \(concept.lowercased())?",
                    concept: concept
                )
            )
        }
        return Array(questions.prefix(count))
    }

    /// Picks the longest meaningful word group as the concept name.
    nonisolated static func conceptGuess(from text: String) -> String {
        let stop: Set<String> = ["sobre", "entre", "cuando", "porque", "aunque", "desde", "hasta",
                                 "para", "como", "esto", "este", "esta", "estos", "estas", "tiene",
                                 "material", "dice", "puede", "debe", "cual", "cuales", "diferencia"]
        let words = text
            .split(whereSeparator: { !$0.isLetter && $0 != "á" && $0 != "é" && $0 != "í" && $0 != "ó" && $0 != "ú" })
            .map(String.init)
            .filter { $0.count > 5 && !stop.contains(SRHeuristics.normalized($0)) }
        guard let best = words.max(by: { $0.count < $1.count }) else { return "el concepto" }
        return best.prefix(1).uppercased() + best.dropFirst()
    }

    nonisolated static func deterministicRestyle(draft: String, style: SRReplyStyle, person: String?) -> String {
        let greeting = person.map { "Hola \($0)," } ?? "Hola,"
        let core = draft
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("hola") }
            .joined(separator: " ")
        let body = core.isEmpty ? "Recibido. Lo reviso y te confirmo." : core
        switch style {
        case .brief, .concise:
            return "\(greeting)\n\n\(SRHeuristics.summary(of: body, maxSentences: 1))"
        case .formal:
            return "Buenos días:\n\n\(body)\n\nUn saludo cordial."
        case .warm:
            return "\(greeting)\n\n\(body)\n\nGracias por la paciencia, un abrazo."
        case .direct:
            return "\(greeting)\n\n\(body)"
        case .human:
            return "\(greeting)\n\n\(body)\n\nSi necesitas algo más, dime."
        }
    }

    nonisolated static func date(fromISODay raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 10 else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: trimmed) else { return nil }
        // A deadline in the past is almost always a misread.
        return date > Date().addingTimeInterval(-86_400) ? date : nil
    }
}
