import AppIntents
import WidgetKit

/// Intents that the widget can invoke. They live in the shared folder because
/// both the app and the widget extension must be able to see them.
///
/// None of them touch data directly: they hand a command to the app, which runs
/// it through its own rules. That is what keeps automations from silently
/// completing or deleting anything.
struct SRStartCurrentTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Empezar tarea actual"
    static let description = IntentDescription("Abre SinRutina en modo ejecución con la tarea que toca ahora.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Identificador")
    var taskID: String?

    init() {}

    init(taskID: String?) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        SRCommandBus.send(SRPendingCommand(kind: .startCurrent, taskID: taskID))
        return .result()
    }
}

struct SROpenSinRutinaIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir SinRutina"
    static let description = IntentDescription("Abre SinRutina en la pantalla Ahora.")
    static let openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        SRCommandBus.send(SRPendingCommand(kind: .whatNow))
        return .result()
    }
}

struct SROpenCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Capturar en SinRutina"
    static let description = IntentDescription("Abre la captura rápida de SinRutina.")
    static let openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        SRCommandBus.send(SRPendingCommand(kind: .openCapture))
        return .result()
    }
}
