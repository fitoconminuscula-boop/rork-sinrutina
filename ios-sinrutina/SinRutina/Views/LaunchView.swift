import SwiftData
import SwiftUI

/// The first thing the person sees, and the shortest thing they see.
///
/// It exists for one reason: while SinRutina restores its state — the pending
/// tasks, an interrupted focus session, a trip left open — the screen behind is
/// not yet true, and showing a half-built "Ahora" costs more attention than a
/// calm surface does.
///
/// Three rules govern it:
/// 1. It never lasts longer than the preparation it covers. There is no timed
///    branding pause: the moment the app is ready, the curtain leaves.
/// 2. It is never a gate. A swipe up, or a tap anywhere, dismisses it at once.
/// 3. It never claims progress it cannot show. The hint to swipe only appears
///    if the wait turns out to be real.
struct LaunchView: View {
    /// Flipped once the curtain is completely off screen and can stop existing.
    @Binding var isFinished: Bool

    @Environment(AppSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appearance = SRAppearanceStore.shared
    /// Where the curtain sits: 0 at rest, negative while leaving.
    @State private var offset: CGFloat = 0
    @State private var height: CGFloat = 900
    @State private var hasEntered = false
    @State private var minimumElapsed = false
    @State private var showsHint = false
    @State private var isLeaving = false

    /// Only true when the screen underneath is worth revealing.
    private var canLeave: Bool { session.isReady && minimumElapsed }

    private var isStill: Bool { SRDesign.effectiveMotion == .reduced || reduceMotion }

    var body: some View {
        ZStack {
            atmosphere
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { height = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newHeight in height = newHeight }
            }
        }
        .offset(y: offset)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .gesture(dismissDrag)
        .onTapGesture { leave() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SinRutina")
        .accessibilityHint("Desliza hacia arriba o toca para entrar")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { leave() }
        .task { await runEntrance() }
        .onChange(of: canLeave) { _, ready in
            if ready { leave() }
        }
    }

    // MARK: - Surface

    /// Depth without decoration: two still pools of the person's own accent,
    /// placed where the mark is and where the thumb rests. Nothing here moves on
    /// its own.
    private var atmosphere: some View {
        ZStack {
            SRDesign.background

            RadialGradient(
                colors: [SRDesign.primary.opacity(0.22), SRDesign.primary.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.36),
                startRadius: 4,
                endRadius: 460
            )

            RadialGradient(
                colors: [SRDesign.lavender.opacity(0.16), SRDesign.lavender.opacity(0)],
                center: UnitPoint(x: 0.12, y: 0.92),
                startRadius: 0,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            SRLogo(size: 92, respectsPresence: false)
                .scaleEffect(hasEntered ? 1 : 0.9)
                .opacity(hasEntered ? 1 : 0)

            Text("SinRutina")
                .font(.largeTitle.weight(.semibold))
                .tracking(-0.4)
                .foregroundStyle(SRDesign.ink)
                .padding(.top, 26)
                .opacity(hasEntered ? 1 : 0)

            Text("Una cosa a la vez.")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
                .padding(.top, 8)
                .opacity(hasEntered ? 0.9 : 0)

            Spacer(minLength: 0)

            hint
                .padding(.bottom, 54)
        }
        .padding(.horizontal, 32)
        .multilineTextAlignment(.center)
    }

    /// Shown only when the preparation is genuinely taking a while, so the
    /// gesture is offered exactly when there is something to skip.
    private var hint: some View {
        VStack(spacing: 6) {
            Image(systemName: "chevron.compact.up")
                .font(.system(size: 22, weight: .semibold))
            Text("Desliza para entrar")
                .font(.footnote.weight(.medium))
        }
        .foregroundStyle(SRDesign.primary.opacity(0.65))
        .opacity(showsHint ? 1 : 0)
        // The space is always reserved, so nothing below jumps when it appears.
        .frame(height: 44)
        .accessibilityHidden(true)
    }

    // MARK: - Movement

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isLeaving else { return }
                let translation = value.translation.height
                // Up follows the finger; down meets a wall, because there is
                // nothing underneath to pull towards.
                offset = translation < 0 ? translation : translation * 0.1
            }
            .onEnded { value in
                guard !isLeaving else { return }
                let projected = value.translation.height + value.predictedEndTranslation.height * 0.3
                if projected < -70 {
                    leave()
                } else {
                    withAnimation(SRDesign.softAnimation) { offset = 0 }
                }
            }
    }

    private func runEntrance() async {
        if isStill {
            hasEntered = true
        } else {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
                hasEntered = true
            }
        }

        // Long enough that the curtain never flashes, short enough that it is
        // not felt. It is the only wait this screen imposes.
        try? await Task.sleep(for: .milliseconds(420))
        minimumElapsed = true

        // If we are still here, the wait is real and worth offering a way out of.
        try? await Task.sleep(for: .milliseconds(900))
        guard !isLeaving else { return }
        withAnimation(SRDesign.standardAnimation) { showsHint = true }

        // A last resort: whatever happens behind, this screen is not allowed to
        // hold anyone hostage.
        try? await Task.sleep(for: .seconds(4))
        leave()
    }

    private func leave() {
        guard !isLeaving else { return }
        isLeaving = true
        SRHaptics.soft()

        guard !isStill else {
            isFinished = true
            return
        }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.92)) {
            offset = -(height + 120)
        }

        Task {
            try? await Task.sleep(for: .milliseconds(460))
            isFinished = true
        }
    }
}

/// Holds the app and the curtain that covers it while it wakes up.
struct RootView: View {
    @State private var showsLaunch = true

    var body: some View {
        ZStack {
            ContentView()

            if showsLaunch {
                LaunchView(isFinished: Binding(
                    get: { !showsLaunch },
                    set: { if $0 { showsLaunch = false } }
                ))
                .zIndex(1)
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(
            for: [TaskItem.self, BehaviorProfile.self, StudyMaterial.self, ReviewConcept.self],
            inMemory: true
        )
        .environment(AppSession())
}
