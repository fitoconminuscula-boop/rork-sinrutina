import Foundation

/// Deterministic Spanish reader. This is SinRutina's floor: it always works,
/// offline, on any device, with or without Apple Intelligence. The on-device
/// model refines these results but never replaces the guarantees.
nonisolated enum SRHeuristics {

    // MARK: - Public entry point

    static func suggestion(for rawText: String, now: Date = Date(), calendar: Calendar = .current) -> SRCaptureSuggestion {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return SRCaptureSuggestion(title: "Algo pendiente", estimatedMinutes: 5)
        }

        let lower = normalized(text)
        let waitingFor = detectDependency(in: text, lower: lower)
        let availableFrom = detectAvailability(in: lower, now: now, calendar: calendar)
        let dueDate = detectDeadline(in: lower, now: now, calendar: calendar)
        let context = detectContext(lower)
        let minutes = detectMinutes(lower, context: context)
        let title = shortTitle(from: text)
        let subtasks = splitIfTooBig(title: title, lower: lower, minutes: minutes)

        let state: TaskState = {
            if waitingFor != nil { return .waiting }
            if let availableFrom, availableFrom > now { return .after }
            if lower.contains("algun dia") || lower.contains("algún dia") || lower.contains("cuando pueda") { return .someday }
            if dueDate != nil { return .after }
            return .now
        }()

        return SRCaptureSuggestion(
            title: title,
            estimatedMinutes: minutes,
            suggestedState: state,
            availableFrom: availableFrom,
            dueDate: dueDate,
            context: context,
            nextStep: nextStep(for: title, lower: lower, context: context),
            waitingFor: waitingFor,
            allowedApps: allowedApps(for: context, lower: lower),
            subtasks: subtasks,
            summary: nil,
            usedOnDeviceModel: false
        )
    }

    // MARK: - Title

    static func shortTitle(from rawText: String) -> String {
        var text = firstSentence(of: rawText)

        let prefixes = [
            "tengo que ", "tengo pendiente ", "debo ", "debería ", "deberia ",
            "hay que ", "necesito ", "necesitaría ", "necesitaria ",
            "recordar ", "recordarme ", "acordarme de ", "no olvidar ",
            "quiero ", "me gustaría ", "me gustaria ", "toca ", "pendiente de ",
            "por favor ",
        ]
        var didTrim = true
        while didTrim {
            didTrim = false
            let lower = normalized(text)
            for prefix in prefixes where lower.hasPrefix(prefix) {
                let remainder = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !remainder.isEmpty {
                    text = remainder
                    didTrim = true
                    break
                }
            }
        }

        // Drop trailing time qualifiers: they already live in structured fields.
        for marker in [" pero despues de", " pero después de", " despues de las", " después de las", " a partir de las", " antes de las"] {
            if let range = normalized(text).range(of: marker) {
                let cut = normalized(text).distance(from: normalized(text).startIndex, to: range.lowerBound)
                if cut > 6 {
                    text = String(text.prefix(cut)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:-–—"))
        if text.count > 62 {
            let clipped = String(text.prefix(62))
            if let lastSpace = clipped.lastIndex(of: " ") {
                text = String(clipped[clipped.startIndex..<lastSpace])
            } else {
                text = clipped
            }
        }
        guard !text.isEmpty else { return "Algo pendiente" }
        return String(text.prefix(1)).uppercased() + String(text.dropFirst())
    }

    // MARK: - Duration

    static func detectMinutes(_ lower: String, context: String?) -> Int {
        if lower.contains("media hora") { return 30 }
        if lower.contains("un cuarto de hora") { return 15 }
        if lower.contains("hora y media") { return 90 }
        if let explicit = firstNumber(before: ["minutos", "minuto", "min"], in: lower) {
            return max(1, min(explicit, 480))
        }
        if let hours = firstNumber(before: ["horas", "hora"], in: lower) {
            return max(15, min(hours * 60, 480))
        }
        if lower.contains("toda la tarde") || lower.contains("toda la mañana") { return 120 }

        switch context {
        case "comunicación": return 10
        case "administrativo": return 25
        case "trabajo": return 30
        case "casa": return 20
        case "salud": return 15
        case "dinero": return 15
        default: break
        }

        if lower.contains("llamar") || lower.contains("escribir a") || lower.contains("responder") { return 8 }
        if lower.contains("revisar") || lower.contains("leer") { return 15 }
        if lower.contains("preparar") || lower.contains("organizar") { return 40 }
        return 10
    }

    // MARK: - Availability ("después de las 6")

    static func detectAvailability(in lower: String, now: Date, calendar: Calendar) -> Date? {
        let markers = ["despues de las ", "después de las ", "a partir de las ", "desde las ", "pasadas las "]
        for marker in markers {
            if let time = time(after: marker, in: lower, now: now, calendar: calendar) {
                return time
            }
        }
        if lower.contains("por la tarde") || lower.contains("esta tarde") {
            return calendar.date(bySettingHour: 16, minute: 0, second: 0, of: dayReference(lower, now: now, calendar: calendar))
        }
        if lower.contains("por la noche") || lower.contains("esta noche") {
            return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: dayReference(lower, now: now, calendar: calendar))
        }
        if lower.contains("mañana por la mañana") {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        }
        if lower.contains("mañana") && !lower.contains("esta mañana") {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        }
        if let time = time(after: "a las ", in: lower, now: now, calendar: calendar), time > now {
            return time
        }
        return nil
    }

    // MARK: - Deadline

    static func detectDeadline(in lower: String, now: Date, calendar: Calendar) -> Date? {
        let markers = ["antes del ", "antes de las ", "para el ", "limite ", "límite ", "vence "]
        for marker in markers where lower.contains(marker) {
            if let time = time(after: marker, in: lower, now: now, calendar: calendar) {
                return time
            }
        }
        if lower.contains("hoy mismo") || lower.contains("antes de que acabe el dia") {
            return calendar.date(bySettingHour: 21, minute: 0, second: 0, of: now)
        }
        if let weekday = weekdayIndex(in: lower) {
            return nextDate(forWeekday: weekday, from: now, calendar: calendar, hour: 18)
        }
        return nil
    }

    // MARK: - Dependency on another person

    static func detectDependency(in text: String, lower: String) -> String? {
        let cues = [
            "estoy esperando", "espero que", "esperando a", "esperando que",
            "cuando me responda", "cuando me conteste", "cuando me envie", "cuando me envíe",
            "depende de", "me tiene que", "tiene que enviarme", "tiene que responderme",
            "pendiente de que", "a la espera de", "me quedo esperando",
        ]
        guard cues.contains(where: { lower.contains($0) }) else { return nil }
        if let person = detectPerson(in: text, lower: lower) { return person }
        return "otra persona"
    }

    /// Finds a person reference with a very conservative rule: only capitalised
    /// words after a relationship cue, or explicit family words.
    static func detectPerson(in text: String, lower: String) -> String? {
        let family: [(String, String)] = [
            ("mi mama", "mamá"), ("mi mamá", "mamá"), ("mi madre", "mi madre"),
            ("mi papa", "papá"), ("mi papá", "papá"), ("mi padre", "mi padre"),
            ("mi hermano", "mi hermano"), ("mi hermana", "mi hermana"),
            ("mi jefe", "mi jefe"), ("mi jefa", "mi jefa"),
            ("mi pareja", "mi pareja"), ("mi hijo", "mi hijo"), ("mi hija", "mi hija"),
            ("el medico", "el médico"), ("la doctora", "la doctora"), ("el doctor", "el doctor"),
            ("el banco", "el banco"), ("la gestoria", "la gestoría"), ("la gestoría", "la gestoría"),
        ]
        for (needle, label) in family where lower.contains(needle) {
            return label
        }

        let cues = ["con ", "a ", "de ", "que "]
        let words = text.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" }).map(String.init)
        for (index, word) in words.enumerated() where index > 0 {
            let previous = words[index - 1].lowercased() + " "
            guard cues.contains(previous) else { continue }
            guard let first = word.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first) else { continue }
            let cleaned = word.trimmingCharacters(in: CharacterSet.letters.inverted)
            guard cleaned.count >= 3 else { continue }
            return cleaned
        }
        return nil
    }

    // MARK: - Context

    static func detectContext(_ lower: String) -> String? {
        let map: [(String, [String])] = [
            ("comunicación", ["llamar", "llamada", "telefono", "teléfono", "hablar con", "escribir a", "responder", "contestar", "mensaje", "whatsapp", "correo", "mail", "email", "avisar", "preguntar a"]),
            ("administrativo", ["papeles", "papeleo", "formulario", "documento", "tramite", "trámite", "solicitud", "matricula", "matrícula", "doctorado", "certificado", "renovar", "cita previa", "declaracion", "declaración", "seguro"]),
            ("dinero", ["factura", "pagar", "pago", "banco", "transferencia", "presupuesto", "impuesto", "hacienda", "nomina", "nómina", "recibo"]),
            ("salud", ["medico", "médico", "dentista", "analitica", "analítica", "receta", "cita medica", "cita médica", "psicologo", "psicólogo", "farmacia"]),
            ("trabajo", ["reunion", "reunión", "informe", "presentacion", "presentación", "cliente", "propuesta", "proyecto", "entregar", "revisar codigo", "revisar código", "curriculum"]),
            ("casa", ["limpiar", "lavadora", "compra", "supermercado", "basura", "cocinar", "ordenar", "arreglar", "fontanero", "mudanza"]),
            ("estudio", ["estudiar", "examen", "apuntes", "leer capitulo", "leer capítulo", "tesis", "practicas", "prácticas"]),
        ]
        for (context, needles) in map where needles.contains(where: { lower.contains($0) }) {
            return context
        }
        return nil
    }

    static func allowedApps(for context: String?, lower: String) -> [String] {
        var apps: [String] = []
        if lower.contains("whatsapp") { apps.append("WhatsApp") }
        if lower.contains("llamar") || lower.contains("telefono") || lower.contains("teléfono") { apps.append("Teléfono") }
        if lower.contains("correo") || lower.contains("mail") || lower.contains("email") { apps.append("Mail") }

        if apps.isEmpty {
            switch context {
            case "comunicación": apps = ["Teléfono", "WhatsApp", "Mail"]
            case "administrativo": apps = ["Safari", "Archivos", "Mail"]
            case "dinero": apps = ["Banco", "Safari"]
            case "salud": apps = ["Teléfono", "Salud"]
            case "trabajo": apps = ["Mail", "Notas", "Calendario"]
            case "casa": apps = ["Recordatorios", "Notas"]
            case "estudio": apps = ["Notas", "Archivos"]
            default: apps = []
            }
        }
        var unique: [String] = []
        for app in apps where !unique.contains(app) { unique.append(app) }
        return Array(unique.prefix(3))
    }

    // MARK: - Next step

    static func nextStep(for title: String, lower: String, context: String?) -> String {
        if lower.contains("llamar") || lower.contains("llamada") { return "Llamarla" }
        if lower.contains("hablar con") { return "Escribirle para buscar hueco" }
        if lower.contains("responder") || lower.contains("contestar") { return "Escribir dos frases y enviar" }
        if lower.contains("correo") || lower.contains("mail") || lower.contains("email") { return "Abrir un correo nuevo" }
        if lower.contains("papeles") || lower.contains("documento") || lower.contains("formulario") { return "Juntar el primer archivo" }
        if lower.contains("pagar") || lower.contains("factura") { return "Abrir la app del banco" }
        if lower.contains("cita") { return "Buscar el número y pedir la cita" }
        if lower.contains("comprar") || lower.contains("compra") { return "Apuntar lo que falta" }
        if lower.contains("leer") || lower.contains("revisar") { return "Leer solo la primera página" }
        if lower.contains("escribir") { return "Escribir la primera frase" }

        switch context {
        case "comunicación": return "Abrir la conversación"
        case "administrativo": return "Abrir la carpeta con los papeles"
        case "trabajo": return "Abrir el documento y escribir el título"
        case "casa": return "Empezar por lo que está más a mano"
        default: return "Poner delante de ti lo que necesitas para empezar"
        }
    }

    // MARK: - Splitting

    static func splitIfTooBig(title: String, lower: String, minutes: Int) -> [String] {
        let bigCues = ["organizar", "preparar todo", "todo el", "proyecto", "mudanza", "planificar", "reformar", "declaracion", "declaración", "tesis"]
        let hasBigCue = bigCues.contains(where: { lower.contains($0) })
        guard hasBigCue || minutes >= 75 else { return [] }

        if lower.contains("papeles") || lower.contains("documento") || lower.contains("formulario") {
            return ["Listar qué papeles hacen falta", "Reunir los que ya tienes", "Pedir el que falta"]
        }
        if lower.contains("mudanza") {
            return ["Medir la habitación grande", "Pedir presupuesto a una empresa", "Sacar cajas del trastero"]
        }
        if lower.contains("reunion") || lower.contains("reunión") || lower.contains("presentacion") || lower.contains("presentación") {
            return ["Escribir los tres puntos clave", "Montar el esquema", "Repasarlo en voz alta"]
        }
        return ["Escribir en una línea cómo se ve terminado", "Hacer solo el primer trozo (10 min)", "Decidir cuándo sigue"]
    }

    // MARK: - Micro actions for "Estoy saturado"

    static func microActions(for title: String, context: String?) -> [String] {
        let lower = normalized(title)
        if lower.contains("llamar") || lower.contains("hablar") {
            return ["Buscar el número", "Respirar y marcar", "Decir solo la primera frase"]
        }
        if lower.contains("correo") || lower.contains("responder") || lower.contains("escribir") {
            return ["Abrir un mensaje nuevo", "Escribir el saludo", "Enviar aunque sea corto"]
        }
        if lower.contains("papeles") || lower.contains("documento") {
            return ["Abrir la carpeta", "Sacar un solo papel", "Ponerlo encima de la mesa"]
        }
        if lower.contains("limpiar") || lower.contains("ordenar") {
            return ["Coger una sola cosa", "Ponerla en su sitio", "Parar ahí si quieres"]
        }
        return ["Ponerlo delante de ti", "Hacer solo dos minutos", "Dejarlo empezado"]
    }

    // MARK: - Follow-up drafts

    static func followUpDraft(taskTitle: String, person: String?, days: Int) -> String {
        let who = person ?? "hola"
        let opening = person == nil ? "Hola," : "Hola \(who),"
        let subject = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let dayPart = days <= 1 ? "ayer" : "hace \(days) días"
        return """
        \(opening)

        Te escribo para retomar \(subject.lowercased()). Lo dejamos \(dayPart) y quiero cerrarlo.
        ¿Puedes decirme cómo va o si necesitas algo de mi parte?

        Gracias.
        """
    }

    // MARK: - Summaries

    static func summary(of rawText: String, maxSentences: Int = 2) -> String {
        let cleaned = rawText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }
        let sentences = cleaned
            .split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 3 }
        guard !sentences.isEmpty else { return String(cleaned.prefix(160)) }
        return sentences.prefix(maxSentences).joined(separator: ". ") + "."
    }

    // MARK: - Helpers

    static func normalized(_ text: String) -> String {
        text.lowercased().folding(options: [.diacriticInsensitive], locale: Locale(identifier: "es_ES"))
    }

    private static func firstSentence(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = trimmed.firstIndex(where: { ".!?\n".contains($0) }) else { return trimmed }
        let candidate = String(trimmed[trimmed.startIndex..<index]).trimmingCharacters(in: .whitespaces)
        return candidate.count >= 6 ? candidate : trimmed
    }

    private static func firstNumber(before keywords: [String], in lower: String) -> Int? {
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let spelled: [String: Int] = [
            "un": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5,
            "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10,
            "quince": 15, "veinte": 20, "treinta": 30, "cuarenta": 40, "cuarenta y cinco": 45,
        ]
        for (index, word) in words.enumerated() where keywords.contains(word) {
            guard index > 0 else { continue }
            let previous = words[index - 1]
            if let value = Int(previous) { return value }
            if let value = spelled[previous] { return value }
        }
        return nil
    }

    /// Reads a clock time right after a marker, understanding "6", "6:30" and "18".
    private static func time(after marker: String, in lower: String, now: Date, calendar: Calendar) -> Date? {
        guard let range = lower.range(of: marker) else { return nil }
        let tail = lower[range.upperBound...]
        let scanner = tail.prefix(24)
        var digits = ""
        var minuteDigits = ""
        var seenSeparator = false
        for character in scanner {
            if character.isNumber {
                if seenSeparator { minuteDigits.append(character) } else { digits.append(character) }
                continue
            }
            if (character == ":" || character == "." || character == "y") && !digits.isEmpty && !seenSeparator {
                seenSeparator = true
                continue
            }
            if character == " " && (digits.isEmpty || seenSeparator) { continue }
            if !digits.isEmpty { break }
            if character.isLetter { break }
        }
        guard var hour = Int(digits), hour >= 0, hour <= 24 else { return nil }
        let minute = min(Int(minuteDigits) ?? 0, 59)

        let mentionsMorning = lower.contains("de la manana") || lower.contains("de la mañana")
        let mentionsAfternoon = lower.contains("de la tarde") || lower.contains("de la noche")
        if hour < 12 {
            if mentionsAfternoon {
                hour += 12
            } else if !mentionsMorning && hour <= 8 {
                // "después de las 6" in everyday Spanish means the evening.
                hour += 12
            }
        }
        if hour >= 24 { hour = 23 }

        let day = dayReference(lower, now: now, calendar: calendar)
        guard let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return nil }
        if candidate <= now, !lower.contains("manana"), !lower.contains("mañana") {
            return calendar.date(byAdding: .day, value: 1, to: candidate)
        }
        return candidate
    }

    private static func dayReference(_ lower: String, now: Date, calendar: Calendar) -> Date {
        if lower.contains("manana") || lower.contains("mañana") {
            return calendar.date(byAdding: .day, value: 1, to: now) ?? now
        }
        if let weekday = weekdayIndex(in: lower),
           let date = nextDate(forWeekday: weekday, from: now, calendar: calendar, hour: 9) {
            return date
        }
        return now
    }

    private static func weekdayIndex(in lower: String) -> Int? {
        let days: [(String, Int)] = [
            ("domingo", 1), ("lunes", 2), ("martes", 3), ("miercoles", 4),
            ("jueves", 5), ("viernes", 6), ("sabado", 7),
        ]
        for (name, index) in days where lower.contains(name) { return index }
        return nil
    }

    private static func nextDate(forWeekday weekday: Int, from now: Date, calendar: Calendar, hour: Int) -> Date? {
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = 0
        return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
    }
}
