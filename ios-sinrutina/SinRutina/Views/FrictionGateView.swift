import SwiftUI

/// The deliberate seconds between "quiero salir de aquí" and actually leaving.
///
/// It is not a punishment and not a lock: it is the amount of attention that
/// interrupts an automatic gesture. There is no scolding, no shaking, no red, and
/// there is always an alternative for hands that cannot follow a moving dot.
struct FrictionGateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics

    /// Seconds this gate asks for.
    let seconds: Double
    /// Shown above the gesture so the person knows what they are leaving.
    let taskTitle: String
    let onCompleted: () -> Void
    /// Lifting everything because something real happened.
    let onEmergency: () -> Void

    @State private var appearance = SRAppearanceStore.shared
    @State private var preferences = SRFocusPreferences.shared
    @State private var style: SRFrictionStyle = .followDot
    @State private var progress: Double = 0
    @State private var isEngaged = false
    @State private var showsAlternatives = false
    @State private var dotAngle: Double = 0
    @State private var lastTick: Date?
    @State private var slideDirection: Double = 1
    @State private var lastSlideX: CGFloat?

    private var isStill: Bool { SRDesign.effectiveMotion == .reduced }
    private var remaining: Double { max(0, seconds - progress) }
    private var isComplete: Bool { progress >= seconds }

    var body: some View {
        ZStack {
            SRDesign.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Text("Seguir con la tarea")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SRDesign.primary)
                    }
                    Spacer()
                    Button {
                        SRHaptics.light()
                        onEmergency()
                        dismiss()
                    } label: {
                        Text("Urgencia")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SRDesign.secondaryInk)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(SRDesign.surface)
                            .clipShape(Capsule(style: .continuous))
                    }
                    .accessibilityHint("Devuelve el acceso completo al iPhone ahora mismo")
                }
                .padding(.horizontal, metrics.pagePadding)
                .padding(.top, 16)

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 10) {
                    Text("¿Quieres cambiar de rumbo?")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(SRDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Estás haciendo \(taskTitle).")
                        .font(.subheadline)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(FrictionEngine.instruction(for: style, seconds: seconds))
                        .font(.footnote)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, metrics.pagePadding)

                gesture
                    .padding(.top, 26)

                Text(String(format: "%.1f s", remaining))
                    .font(.system(size: 34, weight: .medium).monospacedDigit())
                    .foregroundStyle(isEngaged || style == .countdown ? SRDesign.primary : SRDesign.secondaryInk)
                    .padding(.top, 18)
                    .accessibilityLabel("Quedan \(Int(remaining.rounded())) segundos")

                Spacer(minLength: 12)

                Button {
                    withAnimation(SRDesign.quickAnimation) { showsAlternatives.toggle() }
                } label: {
                    Text(showsAlternatives ? "Ocultar alternativas" : "Este gesto no me sirve")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SRQuietButtonStyle())
                .padding(.horizontal, metrics.pagePadding)

                if showsAlternatives {
                    alternatives
                        .padding(.top, 12)
                        .padding(.horizontal, metrics.pagePadding)
                        .transition(.opacity)
                }
            }
            .padding(.bottom, 26)
        }
        .task {
            style = preferences.data.frictionStyle
            // A gesture that needs a finger on a moving target is not for everyone.
            if isStill, style == .followDot { style = .holdPress }
        }
        .onChange(of: isComplete) { _, complete in
            guard complete else { return }
            SRHaptics.success()
            onCompleted()
            dismiss()
        }
    }

    // MARK: - Gestures

    @ViewBuilder
    private var gesture: some View {
        switch style {
        case .followDot:
            followDotGesture
        case .holdPress:
            holdGesture
        case .slowSlide:
            slideGesture
        case .countdown:
            countdownGesture
        case .biometric:
            countdownGesture
        }
    }

    /// A dot that travels a slow, smooth path. Never arcade-like: it drifts.
    private var followDotGesture: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size * 0.32
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let target = CGPoint(
                x: center.x + cos(dotAngle) * radius,
                y: center.y + sin(dotAngle * 0.8) * radius * 0.62
            )

            ZStack {
                Circle()
                    .stroke(SRDesign.primarySoft, style: StrokeStyle(lineWidth: 1.4, dash: [3, 7]))
                    .frame(width: radius * 2, height: radius * 1.24)
                    .position(center)

                Circle()
                    .fill(SRDesign.primary.opacity(isEngaged ? 0.22 : 0.12))
                    .frame(width: FrictionEngine.followTolerance * 2, height: FrictionEngine.followTolerance * 2)
                    .position(target)

                Circle()
                    .fill(SRDesign.primary)
                    .frame(width: 26, height: 26)
                    .position(target)
                    .shadow(color: SRDesign.primary.opacity(0.3), radius: 8, y: 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let distance = hypot(value.location.x - target.x, value.location.y - target.y)
                        if distance <= FrictionEngine.followTolerance {
                            engage()
                        } else {
                            // Out of tolerance: back to zero, without any drama.
                            reset()
                        }
                    }
                    .onEnded { _ in reset() }
            )
            .onAppear { startDrift() }
        }
        .frame(height: 250)
        .padding(.horizontal, metrics.pagePadding)
        .accessibilityLabel("Sigue el punto con el dedo durante \(Int(seconds)) segundos")
    }

    private var holdGesture: some View {
        Circle()
            .fill(SRDesign.primary.opacity(isEngaged ? 0.2 : 0.1))
            .frame(width: 190, height: 190)
            .overlay {
                Circle()
                    .trim(from: 0, to: min(1, progress / seconds))
                    .stroke(SRDesign.primary, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(6)
            }
            .overlay {
                Image(systemName: "hand.point.up.left")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(SRDesign.primary)
                    .allowsHitTesting(false)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in engage() }
                    .onEnded { _ in reset() }
            )
            .accessibilityLabel("Mantén el dedo aquí durante \(Int(seconds)) segundos")
    }

    private var slideGesture: some View {
        VStack(spacing: 14) {
            Capsule(style: .continuous)
                .fill(SRDesign.primarySoft)
                .frame(height: 56)
                .overlay(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(SRDesign.primary.opacity(0.28))
                        .frame(width: max(56, CGFloat(progress / seconds) * 240))
                        .allowsHitTesting(false)
                }
                .overlay {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SRDesign.primary)
                        .allowsHitTesting(false)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // Slow, continuous movement counts. Flicking does not.
                            if let last = lastSlideX {
                                let delta = value.location.x - last
                                if abs(delta) > 0.4, abs(delta) < 26 { engage() }
                            }
                            lastSlideX = value.location.x
                        }
                        .onEnded { _ in
                            lastSlideX = nil
                            reset()
                        }
                )
        }
        .padding(.horizontal, metrics.pagePadding)
        .accessibilityLabel("Desliza despacio durante \(Int(seconds)) segundos")
    }

    private var countdownGesture: some View {
        Circle()
            .stroke(SRDesign.primarySoft, lineWidth: 9)
            .frame(width: 190, height: 190)
            .overlay {
                Circle()
                    .trim(from: 0, to: min(1, progress / seconds))
                    .stroke(SRDesign.primary, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .overlay {
                Image(systemName: style == .biometric ? "faceid" : "timer")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(SRDesign.primary)
            }
            .onAppear { startCountdown() }
            .accessibilityLabel("Espera \(Int(seconds)) segundos")
    }

    private var alternatives: some View {
        VStack(spacing: 8) {
            ForEach(SRFrictionStyle.allCases) { option in
                Button {
                    withAnimation(SRDesign.quickAnimation) {
                        style = option
                        progress = 0
                        isEngaged = false
                        showsAlternatives = false
                    }
                    preferences.update { $0.frictionStyle = option }
                    if !option.needsContinuousTouch { startCountdown() }
                    SRHaptics.light()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: option.symbolName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(style == option ? SRDesign.primary : SRDesign.secondaryInk)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(SRDesign.ink)
                            Text(option.detail)
                                .font(.caption)
                                .foregroundStyle(SRDesign.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .srSurface(radius: metrics.rowRadius, accent: style == option ? SRDesign.primary : nil)
                }
                .buttonStyle(SRPressStyle())
            }
        }
    }

    // MARK: - Timing

    private func engage() {
        let now = Date()
        if !isEngaged {
            isEngaged = true
            lastTick = now
            return
        }
        guard let last = lastTick else {
            lastTick = now
            return
        }
        progress = min(seconds, progress + now.timeIntervalSince(last))
        lastTick = now
    }

    private func reset() {
        guard isEngaged || progress > 0 else { return }
        isEngaged = false
        lastTick = nil
        withAnimation(SRDesign.quickAnimation) { progress = 0 }
    }

    /// The dot drifts slowly and smoothly; with reduced motion it never moves.
    private func startDrift() {
        guard !isStill else { return }
        withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) {
            dotAngle = .pi * 2
        }
    }

    private func startCountdown() {
        guard !style.needsContinuousTouch else { return }
        Task {
            let step = 0.1
            while progress < seconds {
                try? await Task.sleep(for: .milliseconds(100))
                progress = min(seconds, progress + step)
            }
        }
    }
}
