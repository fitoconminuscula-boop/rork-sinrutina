import SwiftUI
import UIKit

/// A visual suggestion SinRutina may offer — never apply on its own.
struct SRAppearanceSuggestion: Identifiable, Equatable {
    let id: String
    let message: String
    let acceptLabel: String
    /// The change that would be made, applied only if the person says yes.
    let change: (inout SRAppearanceProfile) -> Void

    static func == (lhs: SRAppearanceSuggestion, rhs: SRAppearanceSuggestion) -> Bool {
        lhs.id == rhs.id
    }
}

/// Looks for a useful reason to propose a visual change, and nothing else.
///
/// Every signal here is something observable about how the interface is being
/// used — text size, Reduce Motion, how much information is switched off. It
/// never guesses at moods or states of mind, and it never changes anything by
/// itself: the person decides, always.
@MainActor
enum SRAppearanceAdvisor {
    static func suggestion(
        for profile: SRAppearanceProfile,
        typeSize: DynamicTypeSize,
        systemScheme: ColorScheme
    ) -> SRAppearanceSuggestion? {
        // 1. Big text plus a squeezed layout is a real legibility problem.
        if typeSize >= .xxLarge, profile.density != .airy {
            return SRAppearanceSuggestion(
                id: "airy-for-large-text",
                message: "Sueles usar SinRutina con texto grande. Con una interfaz más aireada se lee mejor sin perder nada.",
                acceptLabel: "Usar aireada"
            ) { $0.density = .airy }
        }

        // 2. The system already asked for less movement.
        if UIAccessibility.isReduceMotionEnabled, profile.motion != .reduced {
            return SRAppearanceSuggestion(
                id: "match-reduce-motion",
                message: "Tienes activado Reducir movimiento en iOS. Podemos dejarlo también así dentro de SinRutina.",
                acceptLabel: "Reducir animaciones"
            ) { $0.motion = .reduced }
        }

        // 3. Most secondary information is already off: the focus layout matches
        //    that choice better than the contextual one.
        let hiddenCount = SRMetadataField.allCases.count - profile.visibleMetadata.count
        if hiddenCount >= 4, profile.nowLayout == .context {
            return SRAppearanceSuggestion(
                id: "focus-layout",
                message: "Has ocultado buena parte de la información secundaria. La composición Enfoque va en la misma dirección.",
                acceptLabel: "Probar Enfoque"
            ) { $0.nowLayout = .focus }
        }

        // 4. A light theme pinned while iOS is in dark mode.
        if systemScheme == .dark, profile.theme.forcedColorScheme == .light {
            return SRAppearanceSuggestion(
                id: "follow-system",
                message: "Tu iPhone está en oscuro y SinRutina se mantiene claro. Puede seguir la apariencia del sistema.",
                acceptLabel: "Seguir sistema"
            ) { $0.theme = .system }
        }

        return nil
    }
}
