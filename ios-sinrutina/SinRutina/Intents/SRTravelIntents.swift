import AppIntents

/// "¿Cuándo tengo que salir?" as a Shortcuts action.
///
/// It has no spoken phrase on purpose: iOS only allows ten, and this answer is
/// worth seeing rather than hearing, because it is a decision about your time.
struct SRWhenToLeaveIntent: AppIntent {
    static let title: LocalizedStringResource = "¿Cuándo tengo que salir?"
    static let description = IntentDescription(
        "Recalcula la hora de salida hacia tu próximo compromiso con lugar, usando tu propio historial de recorridos."
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SRCommandBus.send(SRPendingCommand(kind: .openDeparture))
        let engine = PersonalTravelEngine.shared

        guard engine.isEnabled else {
            return .result(
                dialog: IntentDialog("“Salir a tiempo” está desactivado. Puedes activarlo en Ajustes de SinRutina.")
            )
        }

        if let trip = engine.activeTrip {
            return .result(
                dialog: IntentDialog(
                    stringLiteral: "Ya vas camino a \(trip.destinationLabel). Salida registrada a las \(SRWidgetSnapshot.timeFormatter.string(from: trip.startedAt))."
                )
            )
        }

        await engine.refresh(reason: .userChange)

        guard let plan = engine.nextPlan else {
            let reason = engine.lastNotice
                ?? "No tienes ningún desplazamiento con lugar en las próximas horas."
            return .result(dialog: IntentDialog(stringLiteral: reason))
        }

        guard let leaveAt = plan.leaveAt, let estimate = plan.estimate else {
            return .result(
                dialog: IntentDialog(
                    stringLiteral: "Es la primera vez que vas a \(plan.destinationLabel), así que todavía no sé cuánto tardas. Dime tu estimación en la app y no me invento la hora."
                )
            )
        }

        let time = SRWidgetSnapshot.timeFormatter.string(from: leaveAt)
        var sentence = "Conviene salir a las \(time) para llegar a \(plan.eventTitle)."
        switch estimate.source {
        case .personalConfident:
            sentence += " Este recorrido suele tomarte \(estimate.rangeLabel) a esta hora."
        case .personalPartial:
            sentence += " Solo tengo \(estimate.sampleCount) viaje(s) registrados, así que uso un margen más amplio."
        case .mapKit:
            sentence += " Es una estimación de Apple Maps: aún no tengo viajes tuyos aquí."
        case .manual:
            sentence += " Uso la duración que me diste para este lugar."
        case .simulation:
            sentence += " Ojo: es una simulación, no un dato real."
        }
        return .result(dialog: IntentDialog(stringLiteral: sentence))
    }
}

/// "Estoy saliendo": associates the trip, starts measuring the real duration, and
/// stops SinRutina proposing anything else.
struct SRLeavingNowIntent: AppIntent {
    static let title: LocalizedStringResource = "Estoy saliendo"
    static let description = IntentDescription(
        "Registra la salida hacia tu próximo compromiso y mide cuánto tardas realmente."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let engine = PersonalTravelEngine.shared
        if let trip = engine.activeTrip {
            return .result(
                dialog: IntentDialog(stringLiteral: "Ya tenía registrado que vas a \(trip.destinationLabel).")
            )
        }
        guard let plan = engine.nextPlan else {
            return .result(dialog: IntentDialog("No hay ninguna salida pendiente."))
        }
        engine.startLeaving(plan)
        return .result(
            dialog: IntentDialog(
                stringLiteral: "Buen viaje. Mido cuánto tardas hasta \(plan.destinationLabel) y lo aprendo para la próxima."
            )
        )
    }
}

/// "Ya llegué": closes the trip so the measured duration becomes learning.
struct SRArrivedIntent: AppIntent {
    static let title: LocalizedStringResource = "Ya llegué"
    static let description = IntentDescription(
        "Cierra el viaje en curso y guarda cuánto tardaste realmente."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let engine = PersonalTravelEngine.shared
        guard let trip = engine.activeTrip else {
            return .result(dialog: IntentDialog("No hay ningún viaje en curso."))
        }
        let label = trip.destinationLabel
        engine.confirmArrival()
        let message = engine.lastLearnedMessage ?? "Llegada a \(label) registrada."
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
