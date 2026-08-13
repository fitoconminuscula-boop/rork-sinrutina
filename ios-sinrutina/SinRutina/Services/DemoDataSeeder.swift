import Foundation
import Observation
import SwiftData

/// The demonstration mode, and the only place invented content may exist.
///
/// Three rules, without exceptions:
/// 1. It is never on by itself. Somebody has to turn it on in Ajustes.
/// 2. While it is on, the app says so on screen and every invented item carries
///    the label "Demostración".
/// 3. Turning it off deletes everything it created.
///
/// Nothing outside this file may create tasks, mail, materials, times or results
/// that did not come from the person or from a real system API.
@MainActor
@Observable
final class DemoDataMode {
    static let shared = DemoDataMode()

    private(set) var isActive: Bool

    private init() {
        isActive = SRShared.defaults.bool(forKey: SRShared.Key.demoModeActive)
    }

    /// Inserts the example content and marks the mode as active.
    func activate(context: ModelContext) {
        guard !isActive else { return }
        DemoDataSeeder.insert(context: context)
        isActive = true
        SRShared.defaults.set(true, forKey: SRShared.Key.demoModeActive)
        SRTaskCommands.refreshOutsideSurfaces(context: context)
    }

    /// Removes every invented item. Anything the person created stays.
    func deactivate(context: ModelContext) {
        DemoDataSeeder.removeAll(context: context)
        isActive = false
        SRShared.defaults.set(false, forKey: SRShared.Key.demoModeActive)
        SRTaskCommands.refreshOutsideSurfaces(context: context)
    }

    /// Safety net on launch: if the flag is off, no example item may survive.
    func reconcile(context: ModelContext) {
        guard !isActive else { return }
        let descriptor = FetchDescriptor<TaskItem>()
        let leftovers = ((try? context.fetch(descriptor)) ?? []).filter(\.isDemo)
        guard !leftovers.isEmpty else { return }
        DemoDataSeeder.removeAll(context: context)
        SRTaskCommands.refreshOutsideSurfaces(context: context)
    }
}

/// Builds and tears down the example content used by `DemoDataMode`.
@MainActor
enum DemoDataSeeder {
    /// One sentence shown wherever demonstration content appears.
    static let disclosure = "Contenido de ejemplo, no real: ni estos asuntos ni este correo existen."

    static func insert(context: ModelContext) {
        let today = Calendar.current.startOfDay(for: Date())
        let overdue = Calendar.current.date(byAdding: .minute, value: -25, to: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)
        let waitingDate = Calendar.current.date(byAdding: .day, value: -4, to: Date())

        let current = TaskItem(title: "Enviar antecedentes Palermo", estimatedMinutes: 7, state: .now, dueDate: overdue, source: "demo", isDemo: true)
        current.isCurrent = true
        current.preferredContext = "administrativo"
        current.nextStep = "Juntar el primer archivo"
        current.allowedApps = ["Archivos", "Mail"]

        let call = TaskItem(title: "Llamar a mamá", detail: "Preguntar cómo sigue.", estimatedMinutes: 10, state: .after, dueDate: tomorrow, source: "demo", isDemo: true)
        call.preferredContext = "comunicación"
        call.nextStep = "Llamarla"
        call.allowedApps = ["Teléfono", "WhatsApp"]

        let document = TaskItem(title: "Revisar un documento", detail: "Solo mirar la primera página.", estimatedMinutes: 15, state: .after, source: "demo", isDemo: true)
        document.nextStep = "Leer solo la primera página"

        let waiting = TaskItem(title: "Esperando respuesta universidad", detail: "Seguimiento de la postulación.", estimatedMinutes: 5, state: .waiting, waitingFor: "Universidad", source: "demo", isDemo: true)
        waiting.waitingSince = waitingDate
        waiting.updatedAt = waitingDate ?? Date()

        let examDate = Calendar.current.date(byAdding: .day, value: 6, to: today)
        let study = TaskItem(
            title: "Estudiar fenomenología",
            detail: "Capítulo 4: tiempo y conciencia.",
            estimatedMinutes: 22,
            state: .after,
            dueDate: examDate,
            source: "demo",
            isDemo: true
        )
        study.preferredContext = "estudio"
        study.studyObjective = "Comprender la temporalidad vivida."
        study.nextStep = "Leer páginas 42–48"
        study.sourceMode = .mixed

        // An example email. It comes from nobody: no mailbox is ever read.
        let mail = TaskItem(
            title: "Responder a Julieta",
            detail: "Solicita confirmar recepción de los antecedentes.",
            estimatedMinutes: 6,
            state: .after,
            source: "demo",
            isDemo: true
        )
        mail.preferredContext = "comunicación"
        mail.nextStep = "Confirmar recepción en dos frases"
        mail.allowedApps = ["Mail"]
        mail.mailSender = "Julieta Ramos (ejemplo)"
        mail.mailSubject = "Antecedentes Palermo"
        mail.mailExcerpt = """
        Hola:

        ¿Puedes confirmarme que recibiste los antecedentes que te mandé el lunes? Si falta algo, avísame y lo reenvío.

        Gracias.
        """

        context.insert(current)
        context.insert(call)
        context.insert(document)
        context.insert(waiting)
        context.insert(study)
        context.insert(mail)

        let material = StudyMaterial(
            title: "Capítulo 4 — Tiempo y conciencia",
            text: """
            La distinción entre tiempo cronológico y temporalidad vivida atraviesa toda la fenomenología del tiempo. El tiempo cronológico se mide: es la sucesión homogénea de instantes que un reloj puede contar sin referencia a nadie.

            La temporalidad vivida, en cambio, no se mide, se atraviesa. Una espera de diez minutos y diez minutos de conversación ocupan el mismo intervalo cronométrico y duraciones vividas incomparables.

            La retención es la manera en que lo que acaba de pasar sigue presente sin ser recordado de forma explícita: al oír una melodía, las notas anteriores todavía sostienen la que suena ahora.

            La protención es su contraparte hacia adelante: la conciencia va delante de sí misma, anticipando lo que todavía no ocurre. Vivir el presente no es ocupar un punto, sino habitar un campo con espesor.
            """,
            kind: .note,
            taskID: study.id
        )
        material.progressNote = "Vas por la página 42"
        context.insert(material)

        try? context.save()
    }

    /// Deletes the example content, and only the example content.
    static func removeAll(context: ModelContext) {
        let descriptor = FetchDescriptor<TaskItem>()
        let items = (try? context.fetch(descriptor)) ?? []
        let demoIDs = Set(items.filter(\.isDemo).map(\.id))
        items.filter(\.isDemo).forEach(context.delete)

        // Material and review concepts belong to their task: they leave with it.
        let materials = (try? context.fetch(FetchDescriptor<StudyMaterial>())) ?? []
        materials
            .filter { $0.taskID.map(demoIDs.contains) ?? false }
            .forEach(context.delete)

        let concepts = (try? context.fetch(FetchDescriptor<ReviewConcept>())) ?? []
        concepts
            .filter { $0.taskID.map(demoIDs.contains) ?? false }
            .forEach(context.delete)

        try? context.save()
    }
}
