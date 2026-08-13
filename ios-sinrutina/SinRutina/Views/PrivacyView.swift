import SwiftUI
import SwiftData

/// Plain-language privacy page: what happens on the device, which permissions
/// exist and exactly what SinRutina is allowed to touch.
struct PrivacyView: View {
    @Environment(\.srMetrics) private var metrics
    @Query private var tasks: [TaskItem]
    @State private var calendars = CalendarService.shared
    @State private var reminders = ReminderService.shared
    @State private var scheduler = InsistenceScheduler.shared
    @State private var preferences = CalendarPreferences.shared
    @State private var intelligence: SRIntelligenceAvailability = .requiresNewerOS
    @State private var travelStore = LearnedRouteStore.shared
    @State private var travelPreferences = SRTravelPreferences.shared
    @State private var travelLocation = LocationLearningService.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Privacidad")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(SRDesign.ink)
                    Text("Sin servidor, sin cuentas y sin analíticas de terceros.")
                        .font(.body)
                        .foregroundStyle(SRDesign.secondaryInk)
                }
                .padding(.top, 10)

                section(title: "Qué se procesa en el dispositivo") {
                    infoRow(
                        symbol: "cpu",
                        title: "Interpretación de textos",
                        detail: intelligence.isAvailable
                            ? "Apple Intelligence lee tus frases dentro del iPhone. No sale nada a internet."
                            : "\(intelligence.shortLabel). \(intelligence.explanation)"
                    )
                    divider
                    infoRow(
                        symbol: "waveform",
                        title: "Dictado",
                        detail: "El reconocimiento de voz se pide en modo local siempre que el idioma esté descargado."
                    )
                    divider
                    infoRow(
                        symbol: "chart.line.uptrend.xyaxis",
                        title: "Recorridos aprendidos",
                        detail: travelLearningDetail
                    )
                    divider
                    infoRow(
                        symbol: "location",
                        title: "Ubicación",
                        detail: "No hay seguimiento continuo. En segundo plano solo se usan las señales de bajo consumo de iOS si tú lo activas, y el GPS preciso se enciende únicamente mientras hay un viaje en curso y se apaga al llegar."
                    )
                    divider
                    infoRow(
                        symbol: "map",
                        title: "Cuando un lugar es nuevo",
                        detail: "Solo si no tengo ningún viaje tuyo puedo preguntar a Apple Maps, y entonces salen únicamente tu origen aproximado, el destino, el medio y la hora. Nunca el nombre del evento, las notas, los participantes ni tu historial de recorridos."
                    )
                    divider
                    infoRow(
                        symbol: "lock.shield",
                        title: "Bloqueo de apps",
                        detail: "Se hace con Tiempo de uso de Apple. SinRutina no ve qué apps usas ni cuánto: solo pide a iOS que cubra las que tú elegiste, y solo mientras hay una sesión abierta. Si iOS no lo autoriza, Enfoque y Profundo quedan desactivados: nunca se simula un bloqueo."
                    )
                    divider
                    infoRow(
                        symbol: "internaldrive",
                        title: "Tus asuntos",
                        detail: "\(tasks.count) guardados en este iPhone. Se comparten solo con el widget y la hoja de compartir de SinRutina."
                    )
                }

                section(title: "Permisos") {
                    permissionRow(
                        symbol: travelLocation.access.isGranted ? "location.fill" : "location.slash",
                        title: "Localización",
                        state: travelPreferences.data.isEnabled ? travelLocation.access.label : "No se pide",
                        detail: travelPreferences.data.isEnabled
                            ? travelLocation.access.detail
                            : "“Salir a tiempo” está desactivado, así que SinRutina no pide tu ubicación en ningún momento."
                    )
                    divider
                    permissionRow(
                        symbol: "calendar",
                        title: "Calendarios",
                        state: describe(calendars.access),
                        detail: calendars.access.canRead
                            ? "\(preferences.selectedCalendarIdentifiers.count) calendario(s) activados de \(calendars.calendars.count)."
                            : "SinRutina no puede ver tus eventos."
                    )
                    divider
                    permissionRow(
                        symbol: "checklist",
                        title: "Recordatorios",
                        state: describe(reminders.access),
                        detail: preferences.isRemindersLinkEnabled
                            ? "Al completar aquí se marca también el recordatorio enlazado."
                            : "Sin sincronizar al completar."
                    )
                    divider
                    permissionRow(
                        symbol: "bell",
                        title: "Notificaciones",
                        state: describeNotifications(),
                        detail: scheduler.isAlarmKitAvailable
                            ? (scheduler.alarmAuthorizationGranted
                                ? "Las alarmas de “No me dejes olvidarlo” están autorizadas."
                                : "Las alarmas se pedirán la primera vez que uses “No me dejes olvidarlo”.")
                            : "Las alarmas reales necesitan iOS 26. Se usará un aviso urgente."
                    )
                    divider
                    permissionRow(
                        symbol: "mic",
                        title: "Micrófono",
                        state: "Solo al dictar",
                        detail: "Se activa únicamente mientras mantienes el dictado abierto."
                    )
                }

                section(title: "Qué SinRutina no hace") {
                    infoRow(symbol: "xmark.icloud", title: "No hay servidor", detail: "Ningún dato viaja a un servicio de SinRutina.")
                    divider
                    infoRow(symbol: "chart.bar.xaxis", title: "No hay telemetría", detail: "No medimos tu productividad ni tus hábitos fuera del iPhone.")
                    divider
                    infoRow(
                        symbol: "trash.slash",
                        title: "No borra por su cuenta",
                        detail: preferences.allowsAutomaticEventDeletion
                            ? "Has activado la regla que permite borrar eventos automáticamente. Puedes desactivarla en Calendarios."
                            : "Ningún automatismo puede borrar eventos ni asuntos: siempre te lo pregunta."
                    )
                    divider
                    infoRow(
                        symbol: "lock.open.trianglebadge.exclamationmark",
                        title: "No lee otras apps",
                        detail: "Solo ve lo que compartes a mano desde WhatsApp, Mail, Safari o Atajos."
                    )
                    divider
                    infoRow(
                        symbol: "point.topleft.down.curvedto.point.bottomright.up.slash",
                        title: "No guarda por dónde pasas",
                        detail: "De cada viaje se guarda la duración, el día, la franja horaria y el destino aproximado. El trazado del recorrido no se almacena nunca, y nada de esto sale del iPhone."
                    )
                }
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, 40)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            intelligence = SRIntelligenceService.shared.availability
            calendars.refreshAccessState()
            reminders.refreshAccessState()
            await scheduler.refreshAuthorization()
        }
    }

    // MARK: - Pieces

    /// States what has really been learned, and nothing more than that.
    private var travelLearningDetail: String {
        guard travelPreferences.data.isEnabled else {
            return "“Salir a tiempo” está desactivado: no se guarda ningún recorrido."
        }
        guard travelStore.hasAnyLearning else {
            return "Todavía no hay ningún recorrido aprendido. Aparecerán después de tus primeros viajes reales."
        }
        return "\(travelStore.knownDestinations.count) destino(s) y \(travelStore.totalSampleCount) viajes, guardados solo en este iPhone. Puedes verlos y borrarlos en Ajustes › Salir a tiempo."
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: title)
                .padding(.bottom, 10)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 16)
            .background(SRDesign.surface)
            .clipShape(.rect(cornerRadius: SRDesign.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: SRDesign.cardRadius, style: .continuous)
                    .stroke(SRDesign.divider.opacity(0.42), lineWidth: 0.7)
            }
        }
    }

    private var divider: some View {
        Divider().overlay(SRDesign.divider).padding(.leading, 42)
    }

    private func infoRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SRDesign.primary)
                .frame(width: 29, height: 29)
                .background(SRDesign.primarySoft)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(SRDesign.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }

    private func permissionRow(symbol: String, title: String, state: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SRDesign.primary)
                .frame(width: 29, height: 29)
                .background(SRDesign.primarySoft)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(SRDesign.ink)
                    Text(state)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SRDesign.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(SRDesign.primarySoft.opacity(0.8))
                        .clipShape(Capsule(style: .continuous))
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }

    private func describe(_ access: SRCalendarAccess) -> String {
        switch access {
        case .notDetermined: return "Sin pedir"
        case .granted: return "Concedido"
        case .writeOnly: return "Solo escritura"
        case .denied: return "Denegado"
        case .restricted: return "Restringido"
        }
    }

    private func describeNotifications() -> String {
        switch scheduler.notificationAuthorization {
        case .notDetermined: return "Sin pedir"
        case .granted: return "Concedido"
        case .provisional: return "Provisional"
        case .denied: return "Denegado"
        }
    }
}
