import SwiftUI
import UIKit

/// The raw colour values of one palette in one appearance. Every theme is written
/// out by hand — the dark theme is a real design, not an inverted light one.
nonisolated struct SRThemeTokens: Sendable {
    var background: SRRGB
    var surface: SRRGB
    var elevatedSurface: SRRGB
    var primary: SRRGB
    var ink: SRRGB
    var secondaryInk: SRRGB
    var sky: SRRGB
    var periwinkle: SRRGB
    var lavender: SRRGB
    var blush: SRRGB
    var mint: SRRGB
    var divider: SRRGB
    var isDark: Bool

    static func tokens(for theme: SRTheme, scheme: ColorScheme) -> SRThemeTokens {
        switch theme {
        case .dark:
            return .darkTheme
        case .system:
            return scheme == .dark ? .darkTheme : .pastel
        case .pastel:
            return scheme == .dark ? .darkTheme : .pastel
        case .blue:
            return scheme == .dark ? .darkTheme.retinted(SRRGB(hex: "#6FA6FF")!) : .blue
        case .lavender:
            return scheme == .dark ? .darkTheme.retinted(SRRGB(hex: "#B08BFA")!) : .lavender
        case .mint:
            return scheme == .dark ? .darkTheme.retinted(SRRGB(hex: "#3EDCB0")!) : .mint
        case .warm:
            return scheme == .dark ? .warmDark : .warm
        case .mono:
            return scheme == .dark ? .monoDark : .mono
        }
    }

    /// Keeps a theme recognisable in dark mode by swapping only its action colour.
    func retinted(_ newPrimary: SRRGB) -> SRThemeTokens {
        var copy = self
        copy.primary = newPrimary
        return copy
    }

    // MARK: Light families

    static let pastel = SRThemeTokens(
        background: SRRGB(hex: "#FAFAF8")!,
        surface: SRRGB(hex: "#FFFFFF")!,
        elevatedSurface: SRRGB(hex: "#FFFFFF")!,
        primary: SRRGB(hex: "#4B5FE3")!,
        ink: SRRGB(hex: "#14172B")!,
        secondaryInk: SRRGB(hex: "#666D85")!,
        sky: SRRGB(hex: "#6FA8F0")!,
        periwinkle: SRRGB(hex: "#8B9BF5")!,
        lavender: SRRGB(hex: "#A78BFA")!,
        blush: SRRGB(hex: "#F87FA6")!,
        mint: SRRGB(hex: "#3FCFA5")!,
        divider: SRRGB(hex: "#ECECE8")!,
        isDark: false
    )

    static let blue = SRThemeTokens(
        background: SRRGB(hex: "#F7F9FC")!,
        surface: SRRGB(hex: "#FFFFFF")!,
        elevatedSurface: SRRGB(hex: "#FFFFFF")!,
        primary: SRRGB(hex: "#1668E3")!,
        ink: SRRGB(hex: "#0D1A2B")!,
        secondaryInk: SRRGB(hex: "#5C6B80")!,
        sky: SRRGB(hex: "#62A8F0")!,
        periwinkle: SRRGB(hex: "#6E93EC")!,
        lavender: SRRGB(hex: "#8B93E0")!,
        blush: SRRGB(hex: "#E8809A")!,
        mint: SRRGB(hex: "#3BBFA6")!,
        divider: SRRGB(hex: "#E6EBF2")!,
        isDark: false
    )

    static let lavender = SRThemeTokens(
        background: SRRGB(hex: "#FAF8FD")!,
        surface: SRRGB(hex: "#FFFFFF")!,
        elevatedSurface: SRRGB(hex: "#FFFFFF")!,
        primary: SRRGB(hex: "#7C4DE8")!,
        ink: SRRGB(hex: "#1F1733")!,
        secondaryInk: SRRGB(hex: "#6C6488")!,
        sky: SRRGB(hex: "#A6A9F5")!,
        periwinkle: SRRGB(hex: "#9384EE")!,
        lavender: SRRGB(hex: "#B292F5")!,
        blush: SRRGB(hex: "#EE8FBC")!,
        mint: SRRGB(hex: "#56C9B4")!,
        divider: SRRGB(hex: "#EDE7F7")!,
        isDark: false
    )

    static let mint = SRThemeTokens(
        background: SRRGB(hex: "#F5FBF8")!,
        surface: SRRGB(hex: "#FFFFFF")!,
        elevatedSurface: SRRGB(hex: "#FFFFFF")!,
        primary: SRRGB(hex: "#0E826A")!,
        ink: SRRGB(hex: "#0D2A24")!,
        secondaryInk: SRRGB(hex: "#547A70")!,
        sky: SRRGB(hex: "#6FBBD4")!,
        periwinkle: SRRGB(hex: "#6FA3C7")!,
        lavender: SRRGB(hex: "#93A8D0")!,
        blush: SRRGB(hex: "#E09182")!,
        mint: SRRGB(hex: "#2CBF9B")!,
        divider: SRRGB(hex: "#DFEFE8")!,
        isDark: false
    )

    static let warm = SRThemeTokens(
        background: SRRGB(hex: "#FDF8F3")!,
        surface: SRRGB(hex: "#FFFFFF")!,
        elevatedSurface: SRRGB(hex: "#FFFFFF")!,
        primary: SRRGB(hex: "#BB542E")!,
        ink: SRRGB(hex: "#33231B")!,
        secondaryInk: SRRGB(hex: "#856E5D")!,
        sky: SRRGB(hex: "#E5B394")!,
        periwinkle: SRRGB(hex: "#DC9878")!,
        lavender: SRRGB(hex: "#CE96A2")!,
        blush: SRRGB(hex: "#F09A92")!,
        mint: SRRGB(hex: "#9EB894")!,
        divider: SRRGB(hex: "#F1E4D8")!,
        isDark: false
    )

    static let mono = SRThemeTokens(
        background: SRRGB(hex: "#F7F7F6")!,
        surface: SRRGB(hex: "#FFFFFF")!,
        elevatedSurface: SRRGB(hex: "#FFFFFF")!,
        primary: SRRGB(hex: "#1A1A1C")!,
        ink: SRRGB(hex: "#0F0F11")!,
        secondaryInk: SRRGB(hex: "#6B6B70")!,
        sky: SRRGB(hex: "#A5A5AA")!,
        periwinkle: SRRGB(hex: "#939398")!,
        lavender: SRRGB(hex: "#8B8B90")!,
        blush: SRRGB(hex: "#77777C")!,
        mint: SRRGB(hex: "#87878C")!,
        divider: SRRGB(hex: "#E8E8E6")!,
        isDark: false
    )

    // MARK: Dark families

    static let darkTheme = SRThemeTokens(
        background: SRRGB(hex: "#0C0D12")!,
        surface: SRRGB(hex: "#14161D")!,
        elevatedSurface: SRRGB(hex: "#1C1F28")!,
        primary: SRRGB(hex: "#8B9DFF")!,
        ink: SRRGB(hex: "#F2F3F8")!,
        secondaryInk: SRRGB(hex: "#9AA0B4")!,
        sky: SRRGB(hex: "#74AEF5")!,
        periwinkle: SRRGB(hex: "#8E9DFA")!,
        lavender: SRRGB(hex: "#B49BFB")!,
        blush: SRRGB(hex: "#FB8FB0")!,
        mint: SRRGB(hex: "#45D3AA")!,
        divider: SRRGB(hex: "#262A36")!,
        isDark: true
    )

    static let warmDark = SRThemeTokens(
        background: SRRGB(hex: "#14100D")!,
        surface: SRRGB(hex: "#1E1815")!,
        elevatedSurface: SRRGB(hex: "#29211C")!,
        primary: SRRGB(hex: "#F0956A")!,
        ink: SRRGB(hex: "#F8EFE8")!,
        secondaryInk: SRRGB(hex: "#BFA694")!,
        sky: SRRGB(hex: "#E0AE8C")!,
        periwinkle: SRRGB(hex: "#DC9A76")!,
        lavender: SRRGB(hex: "#D29CA8")!,
        blush: SRRGB(hex: "#F5A093")!,
        mint: SRRGB(hex: "#A8BE9C")!,
        divider: SRRGB(hex: "#332821")!,
        isDark: true
    )

    static let monoDark = SRThemeTokens(
        background: SRRGB(hex: "#0D0D0F")!,
        surface: SRRGB(hex: "#16161A")!,
        elevatedSurface: SRRGB(hex: "#1F1F24")!,
        primary: SRRGB(hex: "#F0F0F3")!,
        ink: SRRGB(hex: "#F7F7F9")!,
        secondaryInk: SRRGB(hex: "#97979E")!,
        sky: SRRGB(hex: "#8C8C94")!,
        periwinkle: SRRGB(hex: "#9E9EA6")!,
        lavender: SRRGB(hex: "#88888F")!,
        blush: SRRGB(hex: "#B2B2BA")!,
        mint: SRRGB(hex: "#9A9AA2")!,
        divider: SRRGB(hex: "#2A2A31")!,
        isDark: true
    )
}

/// The colours the interface actually draws with, already resolved for a profile.
/// Each value is a dynamic colour, so a theme that follows iOS keeps working
/// inside widgets and the Live Activity without extra plumbing.
nonisolated struct SRPaletteValues: Sendable {
    var background: Color
    var surface: Color
    var elevatedSurface: Color
    var primary: Color
    var primarySoft: Color
    var ink: Color
    var secondaryInk: Color
    var sky: Color
    var periwinkle: Color
    var lavender: Color
    var blush: Color
    var mint: Color
    var divider: Color
    var shadow: Color
    /// Text colour that is guaranteed to be readable on top of `primary`.
    var onPrimary: Color

    static func resolve(_ profile: SRAppearanceProfile) -> SRPaletteValues {
        let light = SRResolvedTokens(profile: profile, scheme: .light)
        let dark = SRResolvedTokens(profile: profile, scheme: .dark)

        func pair(_ keyPath: KeyPath<SRResolvedTokens, SRRGB>) -> Color {
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? dark[keyPath: keyPath].uiColor
                    : light[keyPath: keyPath].uiColor
            })
        }

        return SRPaletteValues(
            background: pair(\.background),
            surface: pair(\.surface),
            elevatedSurface: pair(\.elevatedSurface),
            primary: pair(\.primary),
            primarySoft: pair(\.primarySoft),
            ink: pair(\.ink),
            secondaryInk: pair(\.secondaryInk),
            sky: pair(\.sky),
            periwinkle: pair(\.periwinkle),
            lavender: pair(\.lavender),
            blush: pair(\.blush),
            mint: pair(\.mint),
            divider: pair(\.divider),
            shadow: Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor.black.withAlphaComponent(0.34)
                    : UIColor.black.withAlphaComponent(0.045)
            }),
            onPrimary: pair(\.onPrimary)
        )
    }
}

/// One appearance of one profile: theme tokens with the chosen accent applied and
/// every derived colour checked for contrast.
nonisolated struct SRResolvedTokens: Sendable {
    var background: SRRGB
    var surface: SRRGB
    var elevatedSurface: SRRGB
    var primary: SRRGB
    var primarySoft: SRRGB
    var ink: SRRGB
    var secondaryInk: SRRGB
    var sky: SRRGB
    var periwinkle: SRRGB
    var lavender: SRRGB
    var blush: SRRGB
    var mint: SRRGB
    var divider: SRRGB
    var onPrimary: SRRGB

    init(profile: SRAppearanceProfile, scheme: ColorScheme) {
        let tokens = SRThemeTokens.tokens(for: profile.theme, scheme: scheme)
        background = tokens.background
        surface = tokens.surface
        elevatedSurface = tokens.elevatedSurface
        ink = tokens.ink
        secondaryInk = tokens.secondaryInk
        sky = tokens.sky
        periwinkle = tokens.periwinkle
        lavender = tokens.lavender
        blush = tokens.blush
        mint = tokens.mint
        divider = tokens.divider

        // The accent replaces the action colour only. Backgrounds, text and the
        // rest of the palette keep belonging to the theme.
        let requested: SRRGB? = {
            switch profile.accent {
            case .theme: return nil
            case .custom: return profile.customAccent
            default: return profile.accent.base
            }
        }()

        var action = requested ?? tokens.primary
        if tokens.isDark {
            // On dark surfaces the accent is also used as text, so it has to be
            // light enough to read.
            action = action.madeReadableOnDarkSurface(tokens.surface)
            onPrimary = action.contrast(with: .white) >= 3.4 ? .white : SRRGB(hex: "#12141F")!
        } else {
            if requested != nil {
                action = action.madeReadableUnderWhiteText()
            }
            onPrimary = action.contrast(with: .white) >= 3.4 ? .white : tokens.ink
        }
        primary = action

        // A quiet wash of the accent for chips, badges and soft fills.
        primarySoft = tokens.isDark
            ? action.blended(with: tokens.background, amount: 0.74)
            : action.blended(with: SRRGB.white, amount: 0.87)
    }
}
