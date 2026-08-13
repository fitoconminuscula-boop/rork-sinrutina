import SwiftUI

/// Floating Liquid Glass pill: quick capture on the left, voice dictation on the right.
/// While dictating it grows into a listening bubble with a live level meter and transcript.
struct CapturePill: View {
    let isListening: Bool
    let level: Double
    let transcript: String
    let onCapture: () -> Void
    let onMicToggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.srMetrics) private var metrics

    private var controlSize: CGFloat { metrics.isTall ? 58 : 52 }

    var body: some View {
        VStack(spacing: metrics.isTall ? 12 : 10) {
            if isListening {
                listeningBubble
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }

            HStack(spacing: 8) {
                Button(action: onCapture) {
                    HStack(spacing: 9) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                        Text("Capturar")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(SRDesign.primary)
                    .padding(.horizontal, metrics.isTall ? 24 : 20)
                    .frame(height: controlSize)
                    .srGlassCapsule()
                }
                .buttonStyle(SRPressStyle())
                .accessibilityLabel("Captura rápida")
                .accessibilityHint("Escribe una cosa para guardarla")

                Button(action: onMicToggle) {
                    Image(systemName: isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isListening ? SRDesign.blush : SRDesign.primary)
                        .frame(width: controlSize, height: controlSize)
                        .srGlass(in: Circle(), tint: isListening ? SRDesign.blush : nil)
                        .overlay {
                            if isListening {
                                Circle()
                                    .stroke(SRDesign.blush.opacity(0.55), lineWidth: 1.4)
                                    .scaleEffect(1 + level * 0.22)
                                    .opacity(0.9 - level * 0.3)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                .buttonStyle(SRPressStyle())
                .accessibilityLabel(isListening ? "Terminar dictado" : "Dictar por voz")
                .accessibilityHint(isListening ? "Guarda lo que dijiste" : "Habla y lo guardamos")
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SRDesign.standardAnimation, value: isListening)
    }

    private var listeningBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                LevelMeter(level: level, reduceMotion: reduceMotion)
                Text("Te escucho…")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SRDesign.secondaryInk)
            }

            Text(transcript.isEmpty ? "Di lo que tengas en la cabeza." : transcript)
                .font(.callout.weight(transcript.isEmpty ? .regular : .medium))
                .foregroundStyle(transcript.isEmpty ? SRDesign.secondaryInk : SRDesign.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.15), value: transcript)
        }
        .padding(.horizontal, metrics.isTall ? 20 : 18)
        .padding(.vertical, metrics.isTall ? 17 : 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlass(in: RoundedRectangle(cornerRadius: metrics.isTall ? 30 : 26, style: .continuous), interactive: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dictando. \(transcript.isEmpty ? "Esperando tu voz" : transcript)")
    }
}

private struct LevelMeter: View {
    let level: Double
    let reduceMotion: Bool

    private let bars: [Double] = [0.45, 0.85, 0.62, 1.0, 0.5]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, weight in
                Capsule(style: .continuous)
                    .fill(SRDesign.primary.opacity(0.85))
                    .frame(width: 3, height: height(for: weight, index: index))
            }
        }
        .frame(height: 22)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }

    private func height(for weight: Double, index: Int) -> CGFloat {
        let base = 5.0
        let reach = 17.0 * weight * max(0.12, level)
        return CGFloat(base + reach)
    }
}

/// Subtle press feedback shared by the floating glass controls.
struct SRPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(SRDesign.quickAnimation, value: configuration.isPressed)
    }
}
