import SwiftUI

/// Flat pill row used for every three-way appearance choice. Custom rather than a
/// system segmented control so it inherits SinRutina's palette, shape and density
/// while keeping selection announced properly to VoiceOver.
struct SRSegmented<Option: Identifiable & Equatable>: View {
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    guard !isSelected else { return }
                    withAnimation(SRDesign.quickAnimation) { selection = option }
                    SRHaptics.light()
                } label: {
                    Text(label(option))
                        .font(.footnote.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? SRDesign.onPrimary : SRDesign.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(isSelected ? SRDesign.primary : SRDesign.primarySoft.opacity(0.55))
                        .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// A labelled block: title, optional explanation, and the control underneath.
struct SRSettingBlock<Content: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SRDesign.ink)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Horizontal strip of whole palettes. The choice is made by looking, not reading.
struct SRThemeStrip: View {
    @Binding var selection: SRTheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(SRTheme.allCases) { theme in
                    themeCard(theme)
                }
            }
            .padding(.trailing, 2)
        }
        .scrollClipDisabled(false)
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    private func themeCard(_ theme: SRTheme) -> some View {
        let isSelected = theme == selection
        let swatch = theme.swatch
        return Button {
            guard !isSelected else { return }
            withAnimation(SRDesign.standardAnimation) { selection = theme }
            SRHaptics.soft()
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(swatch[0].color)
                    HStack(spacing: 4) {
                        ForEach(Array(swatch.dropFirst().enumerated()), id: \.offset) { item in
                            Circle()
                                .fill(item.element.color)
                                .frame(width: 13, height: 13)
                        }
                    }
                }
                .frame(width: 108, height: 62)
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(SRDesign.divider.opacity(0.8), lineWidth: 0.7)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SRDesign.ink)
                    Text(theme.summary)
                        .font(.caption2)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 108, alignment: .leading)
            }
            .padding(8)
            .background(isSelected ? SRDesign.primarySoft.opacity(0.7) : Color.clear)
            .clipShape(.rect(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(isSelected ? SRDesign.primary : .clear, lineWidth: 1.4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tema \(theme.label). \(theme.summary)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The curated accent list plus the free colour picker, all corrected for
/// contrast before they reach a button.
struct SRAccentPicker: View {
    @Binding var accent: SRAccent
    @Binding var customHex: String?

    private var customColor: Color {
        (customHex.flatMap { SRRGB(hex: $0) } ?? SRRGB(hex: "#6487F1")!).color
    }

    /// Eight swatches never fit on one line of an iPhone, so they wrap instead of
    /// pushing the card past the page margin.
    private let columns = [GridItem(.adaptive(minimum: 40, maximum: 54), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                swatch(for: .theme, color: SRDesign.primary, isRing: true)
                ForEach(SRAccent.pickable) { option in
                    swatch(for: option, color: (option.base ?? SRRGB(hex: "#6487F1")!).color)
                }
            }

            HStack(spacing: 12) {
                ColorPicker(selection: Binding(
                    get: { customColor },
                    set: { newValue in
                        let resolved = SRRGB(uiColor: UIColor(newValue))
                        customHex = resolved.hex
                        accent = .custom
                        SRHaptics.light()
                    }
                ), supportsOpacity: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Color personalizado")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(SRDesign.ink)
                        Text("Se ajusta solo si haría ilegible el texto")
                            .font(.caption2)
                            .foregroundStyle(SRDesign.secondaryInk)
                    }
                }
                .tint(SRDesign.primary)
            }
            .padding(.top, 2)
        }
    }

    private func swatch(for option: SRAccent, color: Color, isRing: Bool = false) -> some View {
        let isSelected = accent == option
        return Button {
            withAnimation(SRDesign.quickAnimation) { accent = option }
            SRHaptics.light()
        } label: {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 30, height: 30)
                if isRing {
                    Circle()
                        .stroke(SRDesign.surface, lineWidth: 2)
                        .frame(width: 16, height: 16)
                }
                if isSelected {
                    Circle()
                        .stroke(SRDesign.ink.opacity(0.75), lineWidth: 1.6)
                        .frame(width: 38, height: 38)
                }
            }
            .frame(width: 40, height: 44)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Two designed compositions for the "Ahora" screen, shown as tiny wireframes so
/// the difference is visible before choosing.
struct SRNowLayoutPicker: View {
    @Binding var selection: SRNowLayout

    var body: some View {
        HStack(spacing: 12) {
            ForEach(SRNowLayout.allCases) { layout in
                card(layout)
            }
        }
    }

    private func card(_ layout: SRNowLayout) -> some View {
        let isSelected = layout == selection
        return Button {
            guard !isSelected else { return }
            withAnimation(SRDesign.standardAnimation) { selection = layout }
            SRHaptics.soft()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                sketch(layout)
                    .frame(height: 80)
                Text(layout.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SRDesign.ink)
                Text(layout.detail)
                    .font(.caption2)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(isSelected ? SRDesign.primarySoft.opacity(0.7) : SRDesign.surface.opacity(0.6))
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? SRDesign.primary : SRDesign.divider.opacity(0.6), lineWidth: isSelected ? 1.4 : 0.7)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Composición \(layout.label). \(layout.detail)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func sketch(_ layout: SRNowLayout) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            switch layout {
            case .focus:
                bar(width: 0.34, height: 5, color: SRDesign.secondaryInk.opacity(0.35))
                Spacer(minLength: 0)
                bar(width: 0.8, height: 8, color: SRDesign.ink.opacity(0.55))
                bar(width: 0.42, height: 5, color: SRDesign.secondaryInk.opacity(0.3))
                bar(width: 1, height: 14, color: SRDesign.primary)
                Spacer(minLength: 0)
            case .context:
                bar(width: 0.34, height: 5, color: SRDesign.secondaryInk.opacity(0.35))
                bar(width: 0.52, height: 6, color: SRDesign.primary.opacity(0.4))
                bar(width: 0.8, height: 8, color: SRDesign.ink.opacity(0.55))
                bar(width: 0.62, height: 5, color: SRDesign.secondaryInk.opacity(0.3))
                bar(width: 1, height: 12, color: SRDesign.primary)
                HStack(spacing: 4) {
                    bar(width: 1, height: 6, color: SRDesign.lavender.opacity(0.45))
                    bar(width: 1, height: 6, color: SRDesign.mint.opacity(0.45))
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SRDesign.background)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
    }

    private func bar(width: CGFloat, height: CGFloat, color: Color) -> some View {
        GeometryReader { proxy in
            Capsule(style: .continuous)
                .fill(color)
                .frame(width: proxy.size.width * width, height: height)
        }
        .frame(height: height)
    }
}

/// The official icon variants. Same mark, different palette.
struct SRAppIconPicker: View {
    @Binding var selection: SRAppIconOption
    let isSupported: Bool
    let errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 68, maximum: 96), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(SRAppIconOption.allCases) { option in
                    tile(option)
                }
            }
            if !isSupported {
                Text("Este iPhone no permite cambiar el icono.")
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(SRDesign.blush)
            }
        }
    }

    private func tile(_ option: SRAppIconOption) -> some View {
        let isSelected = option == selection
        let colors = option.previewColors
        return Button {
            selection = option
            SRHaptics.soft()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(colors[0].color)
                    Image("Logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 34, height: 34)
                        .opacity(option == .original ? 1 : 0)
                    if option != .original {
                        Image(systemName: "water.waves")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(colors[1].color)
                    }
                }
                .frame(width: 60, height: 60)
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(isSelected ? SRDesign.primary : SRDesign.divider.opacity(0.7), lineWidth: isSelected ? 2 : 0.7)
                }

                Text(option.label)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? SRDesign.ink : SRDesign.secondaryInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!isSupported)
        .opacity(isSupported ? 1 : 0.5)
        .accessibilityLabel("Icono \(option.label)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

extension SRRGB {
    /// Bridges a colour chosen in the system picker back into SinRutina's own
    /// colour maths, where it gets checked for contrast.
    init(uiColor: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(Double(red), Double(green), Double(blue))
    }
}
