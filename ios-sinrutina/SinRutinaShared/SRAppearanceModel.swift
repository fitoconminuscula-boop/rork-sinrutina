import SwiftUI

// MARK: - Colour maths

/// A plain sRGB triple so themes and custom accents can be blended and checked
/// for contrast before they ever reach the screen. This is what lets SinRutina
/// offer personalisation without letting anyone build an illegible interface.
nonisolated struct SRRGB: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    init?(hex: String) {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else { return nil }
        self.init(
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    var hex: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    var color: Color { Color(red: red, green: green, blue: blue) }

    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }

    func blended(with other: SRRGB, amount: Double) -> SRRGB {
        let t = min(max(amount, 0), 1)
        return SRRGB(
            red + (other.red - red) * t,
            green + (other.green - green) * t,
            blue + (other.blue - blue) * t
        )
    }

    /// WCAG relative luminance.
    var luminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    func contrast(with other: SRRGB) -> Double {
        let a = luminance
        let b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static let white = SRRGB(1, 1, 1)
    static let black = SRRGB(0, 0, 0)

    /// Darkens a colour just enough for white label text to stay readable on top
    /// of it. Used for every accent, including colours the person picks freely.
    func madeReadableUnderWhiteText(minimumContrast: Double = 4.3) -> SRRGB {
        var candidate = self
        var steps = 0
        while candidate.contrast(with: .white) < minimumContrast, steps < 30 {
            candidate = candidate.blended(with: .black, amount: 0.06)
            steps += 1
        }
        return candidate
    }

    /// Lightens a colour so it can be read as text on a dark surface.
    func madeReadableOnDarkSurface(_ surface: SRRGB, minimumContrast: Double = 4.3) -> SRRGB {
        var candidate = self
        var steps = 0
        while candidate.contrast(with: surface) < minimumContrast, steps < 30 {
            candidate = candidate.blended(with: .white, amount: 0.07)
            steps += 1
        }
        return candidate
    }
}

// MARK: - Themes

/// Whole palettes, each one designed on purpose. There is no free-form colour
/// editing of backgrounds or text: only these families.
nonisolated enum SRTheme: String, Codable, CaseIterable, Sendable, Identifiable {
    case pastel
    case blue
    case lavender
    case mint
    case warm
    case mono
    case dark
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pastel: return "Pastel"
        case .blue: return "Azul"
        case .lavender: return "Lavanda"
        case .mint: return "Menta"
        case .warm: return "Cálido"
        case .mono: return "Monocromo"
        case .dark: return "Oscuro"
        case .system: return "Seguir sistema"
        }
    }

    var summary: String {
        switch self {
        case .pastel: return "El original de SinRutina"
        case .blue: return "Sobrio y monocromático"
        case .lavender: return "Lavanda y periwinkle"
        case .mint: return "Fresco y neutro"
        case .warm: return "Blush, arena y melocotón"
        case .mono: return "Blancos, grises y un color"
        case .dark: return "Oscuro de verdad"
        case .system: return "Claro u oscuro según iOS"
        }
    }

    /// `nil` lets iOS decide; everything else is a deliberate design choice.
    var forcedColorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .system: return nil
        default: return .light
        }
    }

    /// Small strip used in the theme picker so the choice is made by looking.
    var swatch: [SRRGB] {
        let tokens = SRThemeTokens.tokens(for: self, scheme: self == .dark ? .dark : .light)
        return [tokens.background, tokens.primary, tokens.sky, tokens.lavender, tokens.blush]
    }
}

// MARK: - Accent

/// A short, curated list. Anything outside it goes through the custom picker and
/// is still corrected for contrast before use.
nonisolated enum SRAccent: String, Codable, CaseIterable, Sendable, Identifiable {
    case theme
    case periwinkle
    case pastelBlue
    case lavender
    case blush
    case mint
    case peach
    case slate
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .theme: return "Del tema"
        case .periwinkle: return "Periwinkle"
        case .pastelBlue: return "Azul pastel"
        case .lavender: return "Lavanda"
        case .blush: return "Rosa blush"
        case .mint: return "Menta"
        case .peach: return "Melocotón"
        case .slate: return "Gris azulado"
        case .custom: return "Personalizado"
        }
    }

    /// The base colour before contrast correction. `nil` means "use the theme's own".
    var base: SRRGB? {
        switch self {
        case .theme, .custom: return nil
        case .periwinkle: return SRRGB(hex: "#4B5FE3")
        case .pastelBlue: return SRRGB(hex: "#1668E3")
        case .lavender: return SRRGB(hex: "#7C4DE8")
        case .blush: return SRRGB(hex: "#D22E5E")
        case .mint: return SRRGB(hex: "#0D8068")
        case .peach: return SRRGB(hex: "#B9532D")
        case .slate: return SRRGB(hex: "#4A5C73")
        }
    }

    /// Only these appear as swatches; `theme` and `custom` get their own controls.
    static var pickable: [SRAccent] {
        [.periwinkle, .pastelBlue, .lavender, .blush, .mint, .peach, .slate]
    }
}

// MARK: - Shape and rhythm

nonisolated enum SRButtonShape: String, Codable, CaseIterable, Sendable, Identifiable {
    case soft
    case minimal
    case compact

    var id: String { rawValue }

    var label: String {
        switch self {
        case .soft: return "Suave"
        case .minimal: return "Minimal"
        case .compact: return "Compacto"
        }
    }

    var detail: String {
        switch self {
        case .soft: return "Radios algo mayores"
        case .minimal: return "Más recto y discreto"
        case .compact: return "Menos alto"
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .soft: return 20
        case .minimal: return 11
        case .compact: return 14
        }
    }

    var controlHeight: CGFloat {
        switch self {
        case .soft: return 54
        case .minimal: return 52
        case .compact: return 46
        }
    }
}

nonisolated enum SRDensity: String, Codable, CaseIterable, Sendable, Identifiable {
    case airy
    case normal
    case compact

    var id: String { rawValue }

    var label: String {
        switch self {
        case .airy: return "Aireada"
        case .normal: return "Normal"
        case .compact: return "Compacta"
        }
    }

    var spacingScale: CGFloat {
        switch self {
        case .airy: return 1.14
        case .normal: return 1
        case .compact: return 0.78
        }
    }

    var paddingScale: CGFloat {
        switch self {
        case .airy: return 1.1
        case .normal: return 1
        case .compact: return 0.84
        }
    }

    var rowScale: CGFloat {
        switch self {
        case .airy: return 1.12
        case .normal: return 1
        case .compact: return 0.82
        }
    }

    /// Compact deliberately drops the quietest layer of detail instead of just
    /// squeezing it, so the screen stays readable rather than merely smaller.
    var showsSecondaryDetail: Bool { self != .compact }
}

nonisolated enum SRVisualScale: String, Codable, CaseIterable, Sendable, Identifiable {
    case small
    case system
    case large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "Pequeña"
        case .system: return "Sistema"
        case .large: return "Grande"
        }
    }

    /// Applied on top of Dynamic Type, never instead of it.
    var factor: CGFloat {
        switch self {
        case .small: return 0.94
        case .system: return 1
        case .large: return 1.12
        }
    }
}

extension SRVisualScale {
    /// Nudges the person's Dynamic Type setting by one step instead of replacing
    /// it, and leaves accessibility sizes exactly as iOS reports them.
    func adjusted(_ size: DynamicTypeSize) -> DynamicTypeSize {
        guard self != .system, !size.isAccessibilitySize else { return size }
        let all = DynamicTypeSize.allCases
        guard let index = all.firstIndex(of: size) else { return size }
        let offset = self == .large ? 1 : -1
        let target = min(max(index + offset, 0), all.count - 1)
        return all[target]
    }
}

nonisolated enum SRCardStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case flat
    case subtle
    case separated

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flat: return "Sin tarjetas"
        case .subtle: return "Sutiles"
        case .separated: return "Separadas"
        }
    }

    var detail: String {
        switch self {
        case .flat: return "Interfaz casi plana"
        case .subtle: return "Fondos apenas diferenciados"
        case .separated: return "Contenidos más definidos"
        }
    }

    /// Depth is carried by hairlines and space, not by haze: the border does more
    /// of the work than it used to, and the shadow much less.
    var borderOpacity: Double {
        switch self {
        case .flat: return 0
        case .subtle: return 0.62
        case .separated: return 0.95
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .flat: return 0
        case .subtle: return 12
        case .separated: return 14
        }
    }

    var usesSurfaceFill: Bool { self != .flat }
}

nonisolated enum SRMotionLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case full
    case subtle
    case reduced

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full: return "Completas"
        case .subtle: return "Sutiles"
        case .reduced: return "Reducidas"
        }
    }
}

nonisolated enum SRHapticLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case none
    case soft
    case normal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Ninguna"
        case .soft: return "Suave"
        case .normal: return "Normal"
        }
    }
}

/// How present the SinRutina mark is. Never a face, never a mascot, never a
/// permanent animation.
nonisolated enum SRPresenceLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case minimal
    case normal
    case expressive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minimal: return "Mínima"
        case .normal: return "Normal"
        case .expressive: return "Expresiva"
        }
    }

    var showsWordmark: Bool { self != .minimal }
    var showsInSheets: Bool { self != .minimal }
    /// One short breath when the mark appears — it does not loop.
    var breathesOnAppear: Bool { self == .expressive }
    var scale: CGFloat {
        switch self {
        case .minimal: return 0.86
        case .normal: return 1
        case .expressive: return 1.1
        }
    }
}

nonisolated enum SRNowLayout: String, Codable, CaseIterable, Sendable, Identifiable {
    case focus
    case context

    var id: String { rawValue }

    var label: String {
        switch self {
        case .focus: return "Enfoque"
        case .context: return "Contexto"
        }
    }

    var detail: String {
        switch self {
        case .focus: return "Solo la tarea y Empezar"
        case .context: return "Añade evento, tiempo y motivo"
        }
    }
}

/// Individual pieces of secondary information. Title and primary action are not
/// on this list on purpose: they can never be hidden.
nonisolated enum SRMetadataField: String, Codable, CaseIterable, Sendable, Identifiable {
    case duration
    case dueTime
    case nextEvent
    case reason
    case calendarState
    case calendarName
    case timeProgress
    case logo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .duration: return "Duración estimada"
        case .dueTime: return "Hora límite"
        case .nextEvent: return "Próximo evento"
        case .reason: return "Razón de la recomendación"
        case .calendarState: return "Estado del calendario"
        case .calendarName: return "Nombre del calendario"
        case .timeProgress: return "Progreso temporal"
        case .logo: return "Símbolo de SinRutina"
        }
    }
}

nonisolated enum SRWidgetStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case minimal
    case contextual
    case status

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minimal: return "Minimal"
        case .contextual: return "Contextual"
        case .status: return "Estado"
        }
    }

    var detail: String {
        switch self {
        case .minimal: return "Solo la tarea actual"
        case .contextual: return "Tarea y tiempo disponible"
        case .status: return "Tarea y estado actual"
        }
    }
}

nonisolated enum SRLiveActivityStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case minimal
    case timed
    case contextual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minimal: return "Minimal"
        case .timed: return "Temporizada"
        case .contextual: return "Contextual"
        }
    }

    var detail: String {
        switch self {
        case .minimal: return "Tarea y finalizar"
        case .timed: return "Tarea y tiempo"
        case .contextual: return "Tarea, tiempo y siguiente acción"
        }
    }
}

/// Alternate icons all reuse the same simplified mark; only the palette changes.
nonisolated enum SRAppIconOption: String, Codable, CaseIterable, Sendable, Identifiable {
    case original
    case blue
    case lavender
    case mint
    case monoLight
    case monoDark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "Pastel original"
        case .blue: return "Azul"
        case .lavender: return "Lavanda"
        case .mint: return "Menta"
        case .monoLight: return "Monocromo claro"
        case .monoDark: return "Monocromo oscuro"
        }
    }

    /// `nil` means the primary icon in the asset catalog.
    var alternateIconName: String? {
        switch self {
        case .original: return nil
        case .blue: return "AppIconBlue"
        case .lavender: return "AppIconLavender"
        case .mint: return "AppIconMint"
        case .monoLight: return "AppIconMonoLight"
        case .monoDark: return "AppIconMonoDark"
        }
    }

    /// Two colours used to draw the miniature in Settings.
    var previewColors: [SRRGB] {
        switch self {
        case .original: return [SRRGB(hex: "#EAF0FF")!, SRRGB(hex: "#6487F1")!]
        case .blue: return [SRRGB(hex: "#E3EEFB")!, SRRGB(hex: "#2F6BD8")!]
        case .lavender: return [SRRGB(hex: "#EFE8FD")!, SRRGB(hex: "#7C6BD6")!]
        case .mint: return [SRRGB(hex: "#DFF3ED")!, SRRGB(hex: "#2FA58C")!]
        case .monoLight: return [SRRGB(hex: "#F2F2F4")!, SRRGB(hex: "#3A3A3C")!]
        case .monoDark: return [SRRGB(hex: "#22242C")!, SRRGB(hex: "#E7E9F2")!]
        }
    }
}

// MARK: - Profile

/// Everything the person has chosen about how SinRutina looks. Stored only on
/// this device, inside the shared app group so the widget, the Live Activity and
/// the share sheet stay in step with the app.
nonisolated struct SRAppearanceProfile: Codable, Hashable, Sendable {
    var theme: SRTheme
    var accent: SRAccent
    var customAccentHex: String?
    var density: SRDensity
    var buttonShape: SRButtonShape
    var cardStyle: SRCardStyle
    var visualScale: SRVisualScale
    var motion: SRMotionLevel
    var haptics: SRHapticLevel
    var presence: SRPresenceLevel
    var nowLayout: SRNowLayout
    var visibleMetadata: Set<SRMetadataField>
    var widgetStyle: SRWidgetStyle
    var liveActivityStyle: SRLiveActivityStyle
    var appIcon: SRAppIconOption
    /// Set once the person answers a visual suggestion, so it is not asked twice.
    var answeredSuggestions: Set<String>

    init(
        theme: SRTheme = .pastel,
        accent: SRAccent = .theme,
        customAccentHex: String? = nil,
        density: SRDensity = .airy,
        buttonShape: SRButtonShape = .soft,
        cardStyle: SRCardStyle = .subtle,
        visualScale: SRVisualScale = .system,
        motion: SRMotionLevel = .full,
        haptics: SRHapticLevel = .normal,
        presence: SRPresenceLevel = .normal,
        nowLayout: SRNowLayout = .context,
        visibleMetadata: Set<SRMetadataField> = Set(SRMetadataField.allCases),
        widgetStyle: SRWidgetStyle = .contextual,
        liveActivityStyle: SRLiveActivityStyle = .timed,
        appIcon: SRAppIconOption = .original,
        answeredSuggestions: Set<String> = []
    ) {
        self.theme = theme
        self.accent = accent
        self.customAccentHex = customAccentHex
        self.density = density
        self.buttonShape = buttonShape
        self.cardStyle = cardStyle
        self.visualScale = visualScale
        self.motion = motion
        self.haptics = haptics
        self.presence = presence
        self.nowLayout = nowLayout
        self.visibleMetadata = visibleMetadata
        self.widgetStyle = widgetStyle
        self.liveActivityStyle = liveActivityStyle
        self.appIcon = appIcon
        self.answeredSuggestions = answeredSuggestions
    }

    /// Decoded field by field so a profile saved by an older build keeps working
    /// and any new option simply starts at its default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = SRAppearanceProfile()
        self.theme = try container.decodeIfPresent(SRTheme.self, forKey: .theme) ?? fallback.theme
        self.accent = try container.decodeIfPresent(SRAccent.self, forKey: .accent) ?? fallback.accent
        self.customAccentHex = try container.decodeIfPresent(String.self, forKey: .customAccentHex)
        self.density = try container.decodeIfPresent(SRDensity.self, forKey: .density) ?? fallback.density
        self.buttonShape = try container.decodeIfPresent(SRButtonShape.self, forKey: .buttonShape) ?? fallback.buttonShape
        self.cardStyle = try container.decodeIfPresent(SRCardStyle.self, forKey: .cardStyle) ?? fallback.cardStyle
        self.visualScale = try container.decodeIfPresent(SRVisualScale.self, forKey: .visualScale) ?? fallback.visualScale
        self.motion = try container.decodeIfPresent(SRMotionLevel.self, forKey: .motion) ?? fallback.motion
        self.haptics = try container.decodeIfPresent(SRHapticLevel.self, forKey: .haptics) ?? fallback.haptics
        self.presence = try container.decodeIfPresent(SRPresenceLevel.self, forKey: .presence) ?? fallback.presence
        self.nowLayout = try container.decodeIfPresent(SRNowLayout.self, forKey: .nowLayout) ?? fallback.nowLayout
        self.visibleMetadata = try container.decodeIfPresent(Set<SRMetadataField>.self, forKey: .visibleMetadata) ?? fallback.visibleMetadata
        self.widgetStyle = try container.decodeIfPresent(SRWidgetStyle.self, forKey: .widgetStyle) ?? fallback.widgetStyle
        self.liveActivityStyle = try container.decodeIfPresent(SRLiveActivityStyle.self, forKey: .liveActivityStyle) ?? fallback.liveActivityStyle
        self.appIcon = try container.decodeIfPresent(SRAppIconOption.self, forKey: .appIcon) ?? fallback.appIcon
        self.answeredSuggestions = try container.decodeIfPresent(Set<String>.self, forKey: .answeredSuggestions) ?? []
    }

    static let original = SRAppearanceProfile()

    func shows(_ field: SRMetadataField) -> Bool {
        visibleMetadata.contains(field)
    }

    /// The colour the person chose freely, if any, already usable.
    var customAccent: SRRGB? {
        guard let customAccentHex, let rgb = SRRGB(hex: customAccentHex) else { return nil }
        return rgb
    }

    /// True when nothing has been personalised, used to hide "Restablecer".
    var isOriginal: Bool {
        var comparable = self
        comparable.answeredSuggestions = []
        return comparable == SRAppearanceProfile.original
    }
}
