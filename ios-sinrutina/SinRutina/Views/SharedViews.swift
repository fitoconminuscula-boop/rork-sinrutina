import SwiftUI

struct SRSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(SRDesign.secondaryInk)
    }
}

struct SRStatusRow: View {
    let title: String
    let count: Int
    let symbol: String
    let tint: Color
    let action: () -> Void

    @Environment(\.srMetrics) private var metrics

    var body: some View {
        Button(action: {
            SRHaptics.light()
            action()
        }) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12))
                    .clipShape(Circle())

                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(SRDesign.ink)

                Spacer(minLength: 10)

                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(SRDesign.secondaryInk)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.7))
            }
            .padding(.horizontal, 18)
            .frame(minHeight: metrics.statusRowHeight)
            .srCard(radius: metrics.rowRadius)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityHint("Abre esta sección")
    }
}

/// One line of quiet context: a small symbol and a short sentence, optionally
/// tappable. It exists so context never needs a card of its own.
struct SRQuietContextLine: View {
    let symbol: String
    let text: String
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { line }
                .buttonStyle(SRPressStyle())
        } else {
            line
        }
    }

    private var line: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.6)
            }
        }
        .foregroundStyle(SRDesign.primary)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(SRDesign.primarySoft.opacity(0.65))
        .clipShape(Capsule(style: .continuous))
        .accessibilityLabel(text)
    }
}

/// A brief, unmistakable confirmation that a tap did something. It disappears on
/// its own and never asks for anything.
struct SRFlashLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(SRDesign.mint)
            Text(text)
                .foregroundStyle(SRDesign.secondaryInk)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.footnote)
        .accessibilityLabel(text)
    }
}

struct SRIconBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 54

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.37, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.13))
            .clipShape(Circle())
    }
}
