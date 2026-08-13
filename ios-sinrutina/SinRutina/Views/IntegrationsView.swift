import AppIntents
import SwiftUI

/// What SinRutina can do from outside the app: Siri phrases, Atajos actions,
/// the widget and how insistent notifications are allowed to be.
struct IntegrationsView: View {
    @Environment(\.srMetrics) private var metrics
    @State private var scheduler = InsistenceScheduler.shared
    @State private var showSiriTip = true

    private let phrases: [(String, String)] = [
        ("Qué hago ahora en SinRutina", "questionmark.circle"),
        ("Capturar en SinRutina", "square.and.pencil"),
        ("Estoy saturado en SinRutina", "sparkles"),
        ("Empezar esta tarea en SinRutina", "play.circle"),
        ("Pausar SinRutina", "pause.circle"),
        ("Volver a la tarea en SinRutina", "arrow.turn.down.right"),
        ("Terminé en SinRutina", "checkmark.circle"),
        ("Posponer en SinRutina", "calendar"),
        ("Marcar como esperando en SinRutina", "hourglass"),
        ("Crear recordatorio en SinRutina", "bell.badge"),
    ]

    /// Available in Atajos but deliberately without a spoken phrase: they are
    /// either ambiguous out loud or too consequential to trigger by voice.
    private let silentActions: [(String, String)] = [
        ("¿Cuándo tengo que salir?", "figure.walk.departure"),
        ("Estoy saliendo", "car"),
        ("Ya llegué", "mappin.and.ellipse"),
        ("Empezar modo enfoque", "circle.lefthalf.filled"),
        ("Avancé", "arrow.turn.down.right"),
        ("Liberar una app temporalmente", "lock.open"),
        ("Terminar modo enfoque", "stop.circle"),
        ("Devolver el acceso al iPhone", "bolt"),
        ("Crear evento", "calendar.badge.plus"),
        ("Analizar texto", "text.viewfinder"),
        ("Analizar correo", "envelope.badge"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Siri y Atajos")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(SRDesign.ink)
                    Text("Acciones, no pantallas.")
                        .font(.body)
                        .foregroundStyle(SRDesign.secondaryInk)
                }
                .padding(.top, 10)

                SiriTipView(intent: SRWhatNowIntent(), isVisible: $showSiriTip)

                VStack(alignment: .leading, spacing: 0) {
                    SRSectionLabel(text: "Puedes decir")
                        .padding(.bottom, 10)
                        .padding(.leading, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(phrases.enumerated()), id: \.offset) { index, phrase in
                            HStack(spacing: 13) {
                                Image(systemName: phrase.1)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(SRDesign.primary)
                                    .frame(width: 28, height: 28)
                                    .background(SRDesign.primarySoft)
                                    .clipShape(Circle())
                                Text("“\(phrase.0)”")
                                    .font(.subheadline)
                                    .foregroundStyle(SRDesign.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 13)
                            if index < phrases.count - 1 {
                                Divider().overlay(SRDesign.divider).padding(.leading, 41)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(SRDesign.surface)
                    .clipShape(.rect(cornerRadius: SRDesign.cardRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: SRDesign.cardRadius, style: .continuous)
                            .stroke(SRDesign.divider.opacity(0.42), lineWidth: 0.7)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    SRSectionLabel(text: "Solo en Atajos")
                        .padding(.bottom, 10)
                        .padding(.leading, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(silentActions.enumerated()), id: \.offset) { index, action in
                            HStack(spacing: 13) {
                                Image(systemName: action.1)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(SRDesign.secondaryInk)
                                    .frame(width: 28, height: 28)
                                    .background(SRDesign.secondaryInk.opacity(0.1))
                                    .clipShape(Circle())
                                Text(action.0)
                                    .font(.subheadline)
                                    .foregroundStyle(SRDesign.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 13)
                            if index < silentActions.count - 1 {
                                Divider().overlay(SRDesign.divider).padding(.leading, 41)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .srCard()

                    Text("Estas no tienen frase de voz a propósito: o son ambiguas dichas en alto, o cambian demasiado como para dispararse sin verlas.")
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .padding(.leading, 4)
                }

                VStack(alignment: .leading, spacing: 0) {
                    SRSectionLabel(text: "Avisos")
                        .padding(.bottom, 10)
                        .padding(.leading, 4)

                    VStack(spacing: 0) {
                        SettingsRow(
                            title: "Notificaciones",
                            detail: notificationDetail,
                            symbol: "bell"
                        )
                        Divider().overlay(SRDesign.divider).padding(.leading, 54)
                        SettingsRow(
                            title: "Alarmas “No me dejes olvidarlo”",
                            detail: alarmDetail,
                            symbol: "alarm.waves.left.and.right"
                        )
                    }
                    .padding(.horizontal, 16)
                    .background(SRDesign.surface)
                    .clipShape(.rect(cornerRadius: SRDesign.cardRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: SRDesign.cardRadius, style: .continuous)
                            .stroke(SRDesign.divider.opacity(0.42), lineWidth: 0.7)
                    }

                    if scheduler.notificationAuthorization == .notDetermined {
                        Button("Activar avisos") {
                            Task {
                                await scheduler.requestNotificationAuthorization()
                                SRHaptics.light()
                            }
                        }
                        .buttonStyle(SRPrimaryButtonStyle())
                        .padding(.top, 12)
                    } else if scheduler.isAlarmKitAvailable && !scheduler.alarmAuthorizationGranted {
                        Button("Autorizar alarmas") {
                            Task {
                                await scheduler.requestAlarmAuthorization()
                                SRHaptics.light()
                            }
                        }
                        .buttonStyle(SRPrimaryButtonStyle())
                        .padding(.top, 12)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    SRSectionLabel(text: "Widget y compartir")
                        .padding(.bottom, 10)
                        .padding(.leading, 4)

                    VStack(spacing: 0) {
                        SettingsRow(
                            title: "Widget de inicio",
                            detail: sharesData
                                ? "Mantén pulsada la pantalla de inicio, toca + y busca SinRutina."
                                : "No disponible en esta instalación.",
                            symbol: "square.grid.2x2"
                        )
                        Divider().overlay(SRDesign.divider).padding(.leading, 54)
                        SettingsRow(
                            title: "Compartir desde otras apps",
                            detail: sharesData
                                ? "En WhatsApp, Mail o Safari usa Compartir y elige SinRutina."
                                : "No disponible en esta instalación.",
                            symbol: "square.and.arrow.up"
                        )
                    }
                    .padding(.horizontal, 16)
                    .background(SRDesign.surface)
                    .clipShape(.rect(cornerRadius: SRDesign.cardRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: SRDesign.cardRadius, style: .continuous)
                            .stroke(SRDesign.divider.opacity(0.42), lineWidth: 0.7)
                    }

                    if !sharesData {
                        Text("Esta copia de SinRutina se instaló sin la carpeta compartida que el widget y la hoja de compartir necesitan para ver tus tareas. La app funciona igual; esas dos piezas no. Se activan solas cuando la app se instala desde TestFlight o el App Store.")
                            .font(.caption)
                            .foregroundStyle(SRDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                            .padding(.leading, 4)
                    }
                }
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, 40)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await scheduler.refreshAuthorization() }
    }

    /// Whether this install can share data with the widget and the share sheet.
    private var sharesData: Bool { SRShared.hasSharedContainer }

    private var notificationDetail: String {
        switch scheduler.notificationAuthorization {
        case .granted: return "Concedidas. Suave, Normal e Importante funcionan."
        case .provisional: return "Provisionales: llegan sin sonido al centro."
        case .denied: return "Denegadas en Ajustes de iOS."
        case .notDetermined: return "Sin pedir todavía."
        }
    }

    private var alarmDetail: String {
        guard scheduler.isAlarmKitAvailable else {
            return "Necesitan iOS 26. Aquí se usará un aviso urgente."
        }
        return scheduler.alarmAuthorizationGranted
            ? "Autorizadas. Suenan aunque tengas silencio o concentración."
            : "Se pedirán la primera vez que las uses."
    }
}
