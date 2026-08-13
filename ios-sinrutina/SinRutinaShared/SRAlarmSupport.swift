#if canImport(AlarmKit)
import AlarmKit
#endif
import AppIntents
import Foundation

/// Metadata attached to a SinRutina alarm. Shared with the widget so the Dynamic
/// Island and Lock Screen presentations can keep the app's own wording.
#if canImport(AlarmKit)
@available(iOS 26.0, *)
nonisolated struct SRAlarmMetadata: AlarmMetadata {
    let taskID: String
    let taskTitle: String
    let nextStep: String?

    init(taskID: String, taskTitle: String, nextStep: String? = nil) {
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.nextStep = nextStep
    }
}
#endif

/// "Hecho" on an alarm. It only records the intention; the app applies the rules,
/// so an alarm can never delete or rewrite anything on its own.
struct SRAlarmDoneIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Hecho"
    static let description = IntentDescription("Marca como hecha la tarea de la alarma de SinRutina.")

    @Parameter(title: "Alarma")
    var alarmID: String

    @Parameter(title: "Tarea")
    var taskID: String

    init() {
        self.alarmID = ""
        self.taskID = ""
    }

    init(alarmID: String, taskID: String) {
        self.alarmID = alarmID
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), let uuid = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.stop(id: uuid)
        }
        #endif
        SRCommandBus.send(SRPendingCommand(kind: .finishCurrent, taskID: taskID.isEmpty ? nil : taskID))
        return .result()
    }
}

/// "Abrir SinRutina" on an alarm.
struct SRAlarmOpenIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Abrir SinRutina"
    static let description = IntentDescription("Abre SinRutina en la tarea de la alarma.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Alarma")
    var alarmID: String

    @Parameter(title: "Tarea")
    var taskID: String

    init() {
        self.alarmID = ""
        self.taskID = ""
    }

    init(alarmID: String, taskID: String) {
        self.alarmID = alarmID
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), let uuid = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.stop(id: uuid)
        }
        #endif
        SRCommandBus.send(SRPendingCommand(kind: .startCurrent, taskID: taskID.isEmpty ? nil : taskID))
        return .result()
    }
}

/// "Terminé" from the Live Activity of a task in progress.
struct SRFinishFocusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Terminé"
    static let description = IntentDescription("Cierra la tarea que tienes en marcha en SinRutina.")

    @Parameter(title: "Tarea")
    var taskID: String

    init() { self.taskID = "" }

    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        SRCommandBus.send(SRPendingCommand(kind: .finishCurrent, taskID: taskID.isEmpty ? nil : taskID))
        return .result()
    }
}
