import SwiftUI
import UIKit

/// Shared visual language for SinRutina: soft, high-contrast pastels with quiet
/// surfaces. Colours come from `SRPalette`, which resolves the person's theme and
/// accent; proportions, shapes, motion and haptics come from the same appearance
/// profile. Reading any of these inside a view body is enough for that view to
/// redraw when the profile changes.
@MainActor
enum SRDesign {
    static var profile: SRAppearanceProfile { SRAppearanceStore.shared.profile }

    static var background: Color { SRPalette.background }
    static var surface: Color { SRPalette.surface }
    static var elevatedSurface: Color { SRPalette.elevatedSurface }
    static var primary: Color { SRPalette.primary }
    static var primarySoft: Color { SRPalette.primarySoft }
    static var onPrimary: Color { SRPalette.onPrimary }
    static var ink: Color { SRPalette.ink }
    static var secondaryInk: Color { SRPalette.secondaryInk }
    static var sky: Color { SRPalette.sky }
    static var periwinkle: Color { SRPalette.periwinkle }
    static var lavender: Color { SRPalette.lavender }
    static var blush: Color { SRPalette.blush }
    static var mint: Color { SRPalette.mint }
    static var divider: Color { SRPalette.divider }
    static var shadow: Color { SRPalette.shadow }

    static var pagePadding: CGFloat { (20 * profile.density.paddingScale).rounded() }
    static var cardRadius: CGFloat { profile.cardStyle == .flat ? 20 : 26 }
    static var rowRadius: CGFloat { profile.cardStyle == .flat ? 15 : 18 }
    static var controlHeight: CGFloat { profile.buttonShape.controlHeight }

    /// Reduce Motion always wins over the app's own preference.
    static var effectiveMotion: SRMotionLevel {
        UIAccessibility.isReduceMotionEnabled ? .reduced : profile.motion
    }

    static var standardAnimation: Animation? {
        switch effectiveMotion {
        case .full: return .spring(response: 0.34, dampingFraction: 0.86)
        case .subtle: return .easeOut(duration: 0.2)
        case .reduced: return nil
        }
    }

    static var quickAnimation: Animation? {
        switch effectiveMotion {
        case .full: return .easeOut(duration: 0.18)
        case .subtle: return .easeOut(duration: 0.14)
        case .reduced: return nil
        }
    }

    static var softAnimation: Animation? {
        switch effectiveMotion {
        case .full: return .spring(response: 0.46, dampingFraction: 0.82)
        case .subtle: return .easeOut(duration: 0.24)
        case .reduced: return nil
        }
    }

    /// Micro-interactions such as the press of a button.
    static var pressScale: CGFloat {
        switch effectiveMotion {
        case .full: return 0.985
        case .subtle: return 0.994
        case .reduced: return 1
        }
    }
}

/// Proportions derived from the live window size and from the chosen density and
/// visual scale, so tall roomy screens such as iPhone Air breathe instead of
/// stacking everything against the top edge.
struct SRMetrics: Equatable {
    var size: CGSize = CGSize(width: 393, height: 852)
    var density: SRDensity = .airy
    var visualScale: SRVisualScale = .system

    /// iPhone Air / Pro Max class heights (~912-956pt).
    var isTall: Bool { size.height >= 900 }
    var isWide: Bool { size.width >= 412 }

    /// Whether the quietest layer of information is worth drawing at all.
    var showsSecondaryDetail: Bool { density.showsSecondaryDetail }

    private var spacing: CGFloat { density.spacingScale * visualScale.factor }
    private var padding: CGFloat { density.paddingScale * visualScale.factor }
    private var rows: CGFloat { density.rowScale * visualScale.factor }

    private func scaled(_ value: CGFloat, by factor: CGFloat) -> CGFloat {
        (value * factor).rounded()
    }

    var pagePadding: CGFloat { scaled(isWide ? 24 : 20, by: padding) }
    var cardPadding: CGFloat { scaled(isTall ? 24 : 20, by: padding) }
    var cardRadius: CGFloat { scaled(isTall ? 28 : SRDesign.cardRadius, by: 1) }
    var rowRadius: CGFloat { scaled(isTall ? 20 : SRDesign.rowRadius, by: 1) }
    var rowPadding: CGFloat { scaled(isTall ? 18 : 16, by: padding) }
    var sectionSpacing: CGFloat { scaled(isTall ? 32 : 24, by: spacing) }
    var rowSpacing: CGFloat { scaled(isTall ? 12 : 10, by: spacing) }
    var headerBottom: CGFloat { scaled(isTall ? 34 : 26, by: spacing) }
    var titleBottom: CGFloat { scaled(isTall ? 22 : 16, by: spacing) }
    var pillBottomInset: CGFloat { scaled(isTall ? 20 : 12, by: spacing) }
    var scrollBottomInset: CGFloat { scaled(isTall ? 146 : 126, by: 1) }
    var contentMaxWidth: CGFloat { 620 }
    var badgeSize: CGFloat { scaled(isTall ? 58 : 52, by: rows) }
    var statusRowHeight: CGFloat { scaled(62, by: rows) }

    /// Extra optical breathing room above the hero card on tall screens.
    var heroTopLift: CGFloat { isTall && density == .airy ? 10 : 0 }
}

private struct SRMetricsKey: EnvironmentKey {
    static let defaultValue = SRMetrics()
}

extension EnvironmentValues {
    var srMetrics: SRMetrics {
        get { self[SRMetricsKey.self] }
        set { self[SRMetricsKey.self] = newValue }
    }
}

extension View {
    /// Measures the container once and publishes proportions to the whole tree.
    func srMeasureMetrics() -> some View {
        modifier(SRMetricsReader())
    }

    /// Keeps reading comfortable on wide screens without stretching content edge to edge.
    func srContentWidth(_ metrics: SRMetrics) -> some View {
        frame(maxWidth: metrics.contentMaxWidth)
            .frame(maxWidth: .infinity)
    }
}

private struct SRMetricsReader: ViewModifier {
    @State private var appearance = SRAppearanceStore.shared
    @State private var size = CGSize(width: 393, height: 852)

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { size = proxy.size }
                        .onChange(of: proxy.size) { _, newSize in
                            size = newSize
                        }
                }
                .ignoresSafeArea()
            }
            .environment(
                \.srMetrics,
                SRMetrics(
                    size: size,
                    density: appearance.profile.density,
                    visualScale: appearance.profile.visualScale
                )
            )
    }
}

extension View {
    /// Liquid Glass on iOS 26, with a soft material fallback for iOS 18.
    @ViewBuilder
    func srGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            let glass: Glass = {
                var base: Glass = .regular
                if let tint { base = base.tint(tint) }
                return interactive ? base.interactive() : base
            }()
            self.glassEffect(glass, in: shape)
        } else {
            self
                .background {
                    shape.fill(.ultraThinMaterial)
                        .overlay {
                            shape.fill(
                                .linearGradient(
                                    colors: [.white.opacity(0.34), .white.opacity(0.04)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        }
                        .overlay {
                            shape.stroke(Color.white.opacity(0.28), lineWidth: 0.7)
                        }
                        .overlay {
                            shape.fill((tint ?? SRDesign.primary).opacity(tint == nil ? 0.05 : 0.16))
                        }
                }
                .shadow(color: SRDesign.primary.opacity(0.14), radius: 18, y: 8)
        }
    }

    func srGlassCapsule(tint: Color? = nil, interactive: Bool = true) -> some View {
        srGlass(in: Capsule(style: .continuous), tint: tint, interactive: interactive)
    }
}

/// One surface treatment for the whole app, so "Sin tarjetas", "Sutiles" and
/// "Separadas" stay consistent everywhere instead of only on the main screen.
struct SRSurfaceModifier: ViewModifier {
    var radius: CGFloat?
    var accent: Color?

    func body(content: Content) -> some View {
        let style = SRDesign.profile.cardStyle
        let cornerRadius = radius ?? SRDesign.cardRadius
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let border = accent ?? SRDesign.divider

        content
            .background {
                if style.usesSurfaceFill {
                    shape.fill(SRDesign.surface)
                } else {
                    // Almost flat: only the faintest lift off the page.
                    shape.fill(SRDesign.surface.opacity(0.42))
                }
            }
            .clipShape(shape)
            .overlay {
                if style.borderOpacity > 0 {
                    shape.stroke(
                        border.opacity(accent == nil ? style.borderOpacity : min(style.borderOpacity + 0.2, 1)),
                        lineWidth: style == .separated ? 1 : 0.7
                    )
                }
            }
            .shadow(
                color: style.shadowRadius > 0 ? SRDesign.shadow : .clear,
                radius: style.shadowRadius,
                y: style.shadowRadius > 0 ? 4 : 0
            )
    }
}

extension View {
    func srCard(radius: CGFloat? = nil) -> some View {
        modifier(SRSurfaceModifier(radius: radius, accent: nil))
    }

    /// A surface that borrows a tint for its outline, used for banners that must
    /// be noticed without shouting.
    func srSurface(radius: CGFloat? = nil, accent: Color? = nil) -> some View {
        modifier(SRSurfaceModifier(radius: radius, accent: accent))
    }
}

/// Flat, solid and uniform. The shape option changes radius and height only —
/// never gradients, gloss, depth or heavy shadows.
struct SRPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = SRDesign.profile.buttonShape
        return configuration.label
            .font(shape == .compact ? .subheadline.weight(.semibold) : .headline.weight(.semibold))
            .foregroundStyle(SRDesign.onPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: shape.controlHeight)
            .background(isEnabled ? SRDesign.primary : SRDesign.primary.opacity(0.38))
            .clipShape(.rect(cornerRadius: shape.cornerRadius))
            .scaleEffect(configuration.isPressed ? SRDesign.pressScale : 1)
            .animation(SRDesign.quickAnimation, value: configuration.isPressed)
    }
}

struct SRQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(SRDesign.primary)
            .opacity(configuration.isPressed ? 0.62 : 1)
            .animation(SRDesign.quickAnimation, value: configuration.isPressed)
    }
}

/// Haptics only for moments that mean something: starting, finishing, changing
/// state, ending the ten seconds of friction, confirming something important.
@MainActor
enum SRHaptics {
    private static var level: SRHapticLevel { SRDesign.profile.haptics }

    static func light() {
        switch level {
        case .none: return
        case .soft: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
        case .normal: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    static func soft() {
        switch level {
        case .none: return
        case .soft: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
        case .normal: UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    static func success() {
        switch level {
        case .none: return
        case .soft: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.85)
        case .normal: UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
