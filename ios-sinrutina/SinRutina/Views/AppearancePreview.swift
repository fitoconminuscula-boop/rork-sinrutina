import SwiftUI

/// A small, honest replica of the "Ahora" screen used inside Ajustes → Apariencia.
///
/// It reads the same appearance profile the real screen does, so changing an
/// option updates it immediately without leaving Settings. It is deliberately not
/// interactive: it shows, it does not act.
struct AppearancePreview: View {
    @State private var appearance = SRAppearanceStore.shared

    private var profile: SRAppearanceProfile { appearance.profile }

    private var spacing: CGFloat { 14 * profile.density.spacingScale }
    private var padding: CGFloat { 16 * profile.density.paddingScale }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, spacing)

            Text("Ahora")
                .font(.title3.weight(.bold))
                .foregroundStyle(SRDesign.ink)
                .padding(.bottom, spacing * 0.7)

            if profile.nowLayout == .context, profile.shows(.nextEvent) {
                contextChip
                    .padding(.bottom, spacing * 0.7)
            }

            taskCard

            if profile.nowLayout == .context {
                VStack(spacing: 8 * profile.density.spacingScale) {
                    miniStatusRow(title: "Esperando", count: 1, tint: SRDesign.lavender, symbol: "hourglass")
                    if profile.density.showsSecondaryDetail {
                        miniStatusRow(title: "Algún día", count: 4, tint: SRDesign.mint, symbol: "leaf")
                    }
                }
                .padding(.top, spacing)
            }
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SRDesign.background)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(SRDesign.divider.opacity(0.7), lineWidth: 0.8)
        }
        .animation(SRDesign.standardAnimation, value: profile)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vista previa de la pantalla Ahora con la apariencia elegida")
    }

    private var header: some View {
        HStack {
            if profile.shows(.logo) {
                SRLogo(size: 22, showsWordmark: true)
            } else {
                Text("SinRutina")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SRDesign.primary)
            }
            Spacer()
            Image(systemName: "moon.stars")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SRDesign.secondaryInk)
        }
    }

    private var contextChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 10, weight: .semibold))
            Text(profile.shows(.calendarName) ? "24 min libres · Trabajo" : "24 min libres")
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(SRDesign.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(SRDesign.primarySoft)
        .clipShape(Capsule(style: .continuous))
    }

    private var taskCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TAREA ACTUAL")
                .font(.caption2.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(SRDesign.primary)
                .padding(.bottom, spacing * 0.6)

            HStack(alignment: .top, spacing: 12) {
                SRIconBadge(symbol: "doc.text", tint: SRDesign.primary, size: 34 * profile.density.rowScale)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Enviar antecedentes Palermo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SRDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if profile.nowLayout == .context, profile.shows(.reason) {
                        Text("Lo tienes vencido y cabe en el hueco de ahora.")
                            .font(.caption2)
                            .foregroundStyle(SRDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if profile.shows(.duration) || profile.shows(.dueTime) {
                        HStack(spacing: 8) {
                            if profile.shows(.duration) {
                                Label("7 min", systemImage: "clock")
                            }
                            if profile.shows(.dueTime) {
                                Label("18:00", systemImage: "bell")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(SRDesign.secondaryInk)
                    }
                }
            }

            if profile.shows(.timeProgress) {
                ProgressView(value: 0.34)
                    .tint(SRDesign.primary)
                    .padding(.top, spacing * 0.7)
            }

            Button("Empezar") { }
                .buttonStyle(SRPrimaryButtonStyle())
                .allowsHitTesting(false)
                .padding(.top, spacing)

            Text("No quiero hacer esto")
                .font(.caption.weight(.medium))
                .foregroundStyle(SRDesign.primary)
                .frame(maxWidth: .infinity)
                .padding(.top, spacing * 0.6)
        }
        .padding(padding)
        .srCard(radius: 20)
    }

    private func miniStatusRow(title: String, count: Int, tint: Color, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.12))
                .clipShape(Circle())
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(SRDesign.ink)
            Spacer(minLength: 6)
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(SRDesign.secondaryInk)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40 * profile.density.rowScale)
        .srCard(radius: 14)
    }
}
