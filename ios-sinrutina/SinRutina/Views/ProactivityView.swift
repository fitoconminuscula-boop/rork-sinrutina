import SwiftUI

/// "Sugerencias de SinRutina".
///
/// One global dial plus a switch per area. The dial decides how often SinRutina may
/// speak first; the switches decide about what. Silence is always a valid setting.
struct ProactivityView: View {
    @Environment(\.srMetrics) private var metrics
    @State private var preferences = SRProactivityPreferences.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header

                levelBlock

                domainsBlock

                budgetBlock

                Label(
                    "Que ignores un aviso nunca hace que SinRutina insista más fuerte.",
                    systemImage: "hand.raised"
                )
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, 40)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .navigationTitle("Sugerencias")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sugerencias de SinRutina")
                .font(.title.weight(.bold))
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Cuándo puede hablar primero, y de qué.")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
        }
        .padding(.top, 12)
    }

    private var levelBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Cuánto interviene")

            Picker("Nivel", selection: Binding(
                get: { preferences.level },
                set: { newValue in
                    preferences.setLevel(newValue)
                    SRHaptics.light()
                }
            )) {
                ForEach(SRProactivityLevel.allCases) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)

            Text(preferences.level.explanation)
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)

            HStack(spacing: 16) {
                Label("\(preferences.level.dailyBudget) al día como máximo", systemImage: "number")
                Label("\(preferences.level.minimumGapMinutes) min de silencio entre avisos", systemImage: "clock")
            }
            .font(.caption2)
            .foregroundStyle(SRDesign.secondaryInk)
            .padding(.top, 2)
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
    }

    private var domainsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "De qué puede hablar")
                .padding(.bottom, 10)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(SRProactivityDomain.allCases) { domain in
                    Toggle(isOn: Binding(
                        get: { preferences.isEnabled(domain) },
                        set: { newValue in
                            preferences.setEnabled(newValue, for: domain)
                            SRHaptics.light()
                        }
                    )) {
                        HStack(spacing: 13) {
                            Image(systemName: domain.symbolName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(SRDesign.primary)
                                .frame(width: 30, height: 30)
                                .background(SRDesign.primarySoft)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(domain.label)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(SRDesign.ink)
                                Text(domain.explanation)
                                    .font(.caption)
                                    .foregroundStyle(SRDesign.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .tint(SRDesign.primary)
                    .padding(.vertical, 13)

                    if domain != SRProactivityDomain.allCases.last {
                        Divider().overlay(SRDesign.divider).padding(.leading, 43)
                    }
                }
            }
            .padding(.horizontal, 16)
            .srCard()
        }
    }

    private var budgetBlock: some View {
        let budget = preferences.budget
        return VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Hoy")
            HStack(spacing: 6) {
                ForEach(0..<preferences.level.dailyBudget, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index < budget.spentToday ? SRDesign.primary : SRDesign.divider.opacity(0.5))
                        .frame(height: 6)
                }
            }
            .animation(SRDesign.quickAnimation, value: budget.spentToday)

            Text(
                budget.spentToday == 0
                    ? "Hoy no ha hecho falta interrumpirte."
                    : "Ha hablado \(budget.spentToday) \(budget.spentToday == 1 ? "vez" : "veces") hoy."
            )
            .font(.caption)
            .foregroundStyle(SRDesign.secondaryInk)

            if budget.ignoredRatio > 0.5 {
                Text("Últimamente los avisos no te sirven, así que voy a hablar menos.")
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
    }
}
