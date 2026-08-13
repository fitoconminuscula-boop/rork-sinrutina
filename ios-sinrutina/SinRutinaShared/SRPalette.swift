import SwiftUI

/// The single source of truth for SinRutina's colours. It now reads the person's
/// appearance profile, so the app, the widget, the Live Activity and the share
/// sheet all follow the same theme and accent.
///
/// Because the store is `@Observable`, any view that reads one of these values
/// redraws by itself when the profile changes — that is what makes the preview in
/// Settings update instantly.
@MainActor
enum SRPalette {
    private static var values: SRPaletteValues { SRAppearanceStore.shared.palette }

    static var background: Color { values.background }
    static var surface: Color { values.surface }
    static var elevatedSurface: Color { values.elevatedSurface }
    static var primary: Color { values.primary }
    static var primarySoft: Color { values.primarySoft }
    static var onPrimary: Color { values.onPrimary }
    static var ink: Color { values.ink }
    static var secondaryInk: Color { values.secondaryInk }
    static var sky: Color { values.sky }
    static var periwinkle: Color { values.periwinkle }
    static var lavender: Color { values.lavender }
    static var blush: Color { values.blush }
    static var mint: Color { values.mint }
    static var divider: Color { values.divider }
    static var shadow: Color { values.shadow }
}
