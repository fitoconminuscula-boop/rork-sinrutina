import SwiftUI
import SwiftData

struct EndOfDayView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [TaskItem]

    private var completedToday: Int {
        tasks.filter { task in
            guard let completedAt = task.completedAt else { return false }
            return Calendar.current.isDateInToday(completedAt)
        }.count
    }

    private var pendingCount: Int {
        tasks.filter { $0.state == .now || $0.state == .after || $0.state == .someday }.count
    }

    private var waitingCount: Int {
        tasks.filter { $0.state == .waiting }.count
    }

    private var tomorrowTask: TaskItem? {
        NextActionEngine().recommendations(from: tasks)
            .first(where: { $0.state == .after || $0.state == .someday })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                SRLogo(size: 32)
                Text("Cierre del día")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SRDesign.primary)
            }
            .padding(.bottom, 20)

            Text("Hoy cerraste \(completedToday) asuntos.")
                .font(.title2.weight(.semibold))
                .foregroundStyle(SRDesign.ink)
            Text("Quedaron \(pendingCount) pendientes.")
                .font(.title3)
                .foregroundStyle(SRDesign.secondaryInk)
                .padding(.top, 5)
            Text("\(waitingCount) dependen de otras personas.")
                .font(.title3)
                .foregroundStyle(SRDesign.secondaryInk)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 8) {
                Text("Mañana importa:")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SRDesign.primary)
                Text(tomorrowTask?.title ?? "Nada urgente por adelantado")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(SRDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SRDesign.primarySoft.opacity(0.55))
            .clipShape(.rect(cornerRadius: 18))
            .padding(.top, 30)

            Spacer()

            Button("Listo") {
                SRHaptics.light()
                dismiss()
            }
            .buttonStyle(SRPrimaryButtonStyle())
        }
        .padding(.horizontal, SRDesign.pagePadding)
        .padding(.top, 30)
        .padding(.bottom, 18)
        .background(SRDesign.background.ignoresSafeArea())
    }
}
