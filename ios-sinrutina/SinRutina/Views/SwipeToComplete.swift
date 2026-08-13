import SwiftUI

/// Wraps a row so a right swipe completes it: a mint track is revealed behind the card,
/// the checkmark grows with the gesture and the row fades away once released.
struct SRSwipeToComplete<Content: View>: View {
    let radius: CGFloat
    let onComplete: () -> Void
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var isCompleting = false
    @State private var didCrossThreshold = false

    private let threshold: CGFloat = 96
    private let maxOffset: CGFloat = 148

    private var progress: Double {
        min(1, max(0, Double(offset / threshold)))
    }

    var body: some View {
        content
            .background(alignment: .leading) {
                track
            }
            .offset(x: offset)
            .opacity(isCompleting ? 0 : 1)
            .scaleEffect(isCompleting ? 0.97 : 1, anchor: .leading)
            .gesture(swipeGesture)
            .accessibilityAction(named: "Completar") { complete() }
    }

    private var track: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(SRDesign.mint.opacity(0.16 + progress * 0.24))
            .overlay(alignment: .leading) {
                Image(systemName: didCrossThreshold ? "checkmark.circle.fill" : "checkmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(SRDesign.mint)
                    .scaleEffect(0.7 + progress * 0.45)
                    .opacity(0.35 + progress * 0.65)
                    .padding(.leading, 22)
            }
            .opacity(offset > 1 ? 1 : 0)
            .allowsHitTesting(false)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard !isCompleting else { return }
                let horizontal = value.translation.width
                guard horizontal > 0, abs(horizontal) > abs(value.translation.height) else { return }
                offset = rubberBanded(horizontal)

                let crossed = offset >= threshold
                if crossed != didCrossThreshold {
                    didCrossThreshold = crossed
                    if crossed { SRHaptics.light() }
                }
            }
            .onEnded { value in
                guard !isCompleting else { return }
                if value.translation.width >= threshold {
                    complete()
                } else {
                    withAnimation(SRDesign.softAnimation) {
                        offset = 0
                        didCrossThreshold = false
                    }
                }
            }
    }

    private func rubberBanded(_ value: CGFloat) -> CGFloat {
        guard value > threshold else { return value }
        let extra = (value - threshold) * 0.32
        return min(maxOffset, threshold + extra)
    }

    private func complete() {
        guard !isCompleting else { return }
        SRHaptics.success()
        let fade = reduceMotion ? Animation.easeOut(duration: 0.2) : Animation.easeOut(duration: 0.28)
        withAnimation(fade) {
            isCompleting = true
            offset = threshold + 26
        }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 200 : 280))
            withAnimation(SRDesign.softAnimation) {
                onComplete()
            }
        }
    }
}
