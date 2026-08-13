import SwiftUI

/// What SinRutina is doing right now, expressed without a face, a mascot or a
/// character: one S curve, one pastel dot, and the smallest possible movement.
nonisolated enum SRPresenceState: String, CaseIterable, Sendable {
    case neutral
    case suggesting
    case waiting
    case focusing
    case completed

    var accessibilityLabel: String {
        switch self {
        case .neutral: return "SinRutina en calma"
        case .suggesting: return "SinRutina tiene una sugerencia"
        case .waiting: return "SinRutina esperando"
        case .focusing: return "SinRutina acompañando el enfoque"
        case .completed: return "Hecho"
        }
    }
}

/// The visual presence of SinRutina.
///
/// It is a shape, not a personality: the curve leans, the dot travels a little,
/// and that is the whole vocabulary. It obeys the appearance profile (accent,
/// presence level, motion) and stops moving entirely when motion is reduced.
struct SRPresenceView: View {
    var state: SRPresenceState = .neutral
    var size: CGFloat = 46

    @State private var appearance = SRAppearanceStore.shared

    private var presence: SRPresenceLevel { appearance.profile.presence }
    private var resolvedSize: CGFloat { (size * presence.scale).rounded() }
    private var isStill: Bool { SRDesign.effectiveMotion == .reduced || presence == .minimal }

    private var tint: Color {
        switch state {
        case .neutral: return SRDesign.primary
        case .suggesting: return SRDesign.primary
        case .waiting: return SRDesign.lavender
        case .focusing: return SRDesign.sky
        case .completed: return SRDesign.mint
        }
    }

    /// Where the dot rests along the curve. Each state has its own position, so
    /// the difference is legible even without movement.
    private var dotProgress: Double {
        switch state {
        case .neutral: return 0.5
        case .suggesting: return 0.72
        case .waiting: return 0.28
        case .focusing: return 0.9
        case .completed: return 1
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(state == .neutral ? 0.1 : 0.15))

            SRCurveShape()
                .stroke(
                    tint.opacity(0.85),
                    style: StrokeStyle(lineWidth: resolvedSize * 0.075, lineCap: .round)
                )
                .padding(resolvedSize * 0.26)

            SRCurveDot(progress: dotProgress, diameter: resolvedSize * 0.17)
                .fill(tint)
                .padding(resolvedSize * 0.26)
                .shadow(color: tint.opacity(0.35), radius: resolvedSize * 0.09, y: 1)
        }
        .frame(width: resolvedSize, height: resolvedSize)
        .animation(SRDesign.softAnimation, value: state)
        .onChange(of: state) { _, _ in
            guard !isStill else { return }
            SRHaptics.light()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
    }

}

/// The S curve of the SinRutina mark, drawn as a path so a point can travel it.
private struct SRCurveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: rect.maxX * 0.15, y: rect.minY - rect.height * 0.05),
            control2: CGPoint(x: rect.maxX * 0.85, y: rect.maxY + rect.height * 0.05)
        )
        return path
    }
}

/// A dot placed along the same curve, so presence reads as one object.
private struct SRCurveDot: Shape {
    var progress: Double
    var diameter: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(progress, 0), 1)
        // Cubic Bézier evaluated at t, matching SRCurveShape's control points.
        let p0 = CGPoint(x: rect.minX, y: rect.maxY)
        let p1 = CGPoint(x: rect.maxX * 0.15, y: rect.minY - rect.height * 0.05)
        let p2 = CGPoint(x: rect.maxX * 0.85, y: rect.maxY + rect.height * 0.05)
        let p3 = CGPoint(x: rect.maxX, y: rect.minY)
        let t = clamped
        let mt = 1 - t
        let x = mt * mt * mt * p0.x + 3 * mt * mt * t * p1.x + 3 * mt * t * t * p2.x + t * t * t * p3.x
        let y = mt * mt * mt * p0.y + 3 * mt * mt * t * p1.y + 3 * mt * t * t * p2.y + t * t * t * p3.y
        return Path(
            ellipseIn: CGRect(
                x: x - diameter / 2,
                y: y - diameter / 2,
                width: diameter,
                height: diameter
            )
        )
    }
}

/// A presence badge with one quiet line of text next to it, used in banners.
struct SRPresenceLine: View {
    let state: SRPresenceState
    let text: String
    var size: CGFloat = 34

    var body: some View {
        HStack(spacing: 11) {
            SRPresenceView(state: state, size: size)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
