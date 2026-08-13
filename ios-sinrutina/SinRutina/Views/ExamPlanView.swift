import SwiftUI
import SwiftData

/// The reparto before an exam or a delivery.
///
/// SinRutina proposes sittings that fit real gaps and says out loud when the
/// material does not fit in the time left. Each row is accepted one at a time:
/// nothing is written to the calendar and nothing is created in bulk.
struct ExamPlanView: View {
    let task: TaskItem
    let materialMinutes: Int?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics

    @State private var plan: ExamPlanner.Plan?
    @State private var acceptedSlots: Set<Date> = []
    @State private var isBuilding = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                if isBuilding {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Mirando tus calendarios…")
                            .font(.subheadline)
                            .foregroundStyle(SRDesign.secondaryInk)
                    }
                    .padding(.top, 22)
                } else if let plan, !plan.sessions.isEmpty {
                    if plan.isOverloaded {
                        overloadNotice(plan)
                            .padding(.top, 18)
                    }

                    sessionsBlock(plan)
                        .padding(.top, 18)

                    Text("Si te saltas una sesión, vuelvo a repartir lo que queda en lugar de acumularlo.")
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .padding(.top, 16)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    emptyState
                        .padding(.top, 22)
                }
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, 36)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .task {
            await build()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SRPresenceView(state: .neutral, size: 34)
                Spacer()
                Button("Cerrar") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SRDesign.secondaryInk)
            }
            Text("Reparto")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(SRDesign.ink)
            if let plan {
                Text(plan.summary)
                    .font(.footnote)
                    .foregroundStyle(SRDesign.secondaryInk)
            }
        }
        .padding(.top, 20)
    }

    private func overloadNotice(_ plan: ExamPlanner.Plan) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SRDesign.blush)
            Text("Quedan \(plan.unplacedMinutes) minutos de material sin hueco antes de la fecha. Conviene recortar el objetivo en lugar de apretar los días.")
                .font(.footnote)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srSurface(radius: metrics.rowRadius, accent: SRDesign.blush)
    }

    private func sessionsBlock(_ plan: ExamPlanner.Plan) -> some View {
        VStack(spacing: 0) {
            ForEach(plan.sessions) { session in
                HStack(alignment: .center, spacing: 13) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.dayLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SRDesign.ink)
                        Text("\(session.timeLabel) · \(session.minutes) min")
                            .font(.caption)
                            .foregroundStyle(SRDesign.secondaryInk)
                    }
                    .frame(width: 108, alignment: .leading)

                    Text(session.focus)
                        .font(.footnote)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 6)

                    if acceptedSlots.contains(session.start) {
                        Label("Añadida", systemImage: "checkmark")
                            .font(.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(SRDesign.mint)
                    } else {
                        Button {
                            accept(session)
                        } label: {
                            Text("Añadir")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SRDesign.onPrimary)
                                .padding(.horizontal, 13)
                                .frame(height: 32)
                                .background(SRDesign.primary)
                                .clipShape(Capsule(style: .continuous))
                        }
                        .buttonStyle(SRPressStyle())
                    }
                }
                .padding(.vertical, 13)

                if session.id != plan.sessions.last?.id {
                    Divider().overlay(SRDesign.divider)
                }
            }
        }
        .padding(.horizontal, 14)
        .srCard(radius: metrics.rowRadius)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No encontré huecos")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SRDesign.ink)
            Text(
                CalendarService.shared.access.canRead
                    ? "Tus calendarios están llenos hasta la fecha. Recortar el objetivo funciona mejor que quitarte horas de sueño."
                    : "Conecta tus calendarios para que pueda repartir el material en huecos reales."
            )
            .font(.subheadline)
            .foregroundStyle(SRDesign.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
    }

    private func build() async {
        isBuilding = true
        if CalendarService.shared.access.canRead {
            await CalendarService.shared.reloadUpcoming(within: 24 * 14)
        }
        let result = ExamPlanner.plan(for: task, materialMinutes: materialMinutes)
        withAnimation(SRDesign.softAnimation) {
            plan = result
            isBuilding = false
        }
    }

    private func accept(_ session: ExamPlanner.Session) {
        ExamPlanner.accept(session, for: task, context: modelContext)
        withAnimation(SRDesign.quickAnimation) {
            acceptedSlots.insert(session.start)
        }
        SRHaptics.success()
    }
}
