import SwiftUI

/// The SinRutina mark, reused across headers and sheets so the brand stays
/// consistent. How much it shows up is up to the person: "Presencia visual"
/// changes its size, whether the wordmark appears and whether it takes one short
/// breath when it arrives. It never loops, and it is never a face or a character.
struct SRLogo: View {
    var size: CGFloat = 30
    var showsWordmark: Bool = false
    /// Set to false for places where the mark is the subject rather than chrome.
    var respectsPresence: Bool = true

    @State private var appearance = SRAppearanceStore.shared
    @State private var hasBreathed = false

    private var presence: SRPresenceLevel {
        respectsPresence ? appearance.profile.presence : .normal
    }

    private var resolvedSize: CGFloat {
        (size * presence.scale).rounded()
    }

    private var showsText: Bool {
        showsWordmark && presence.showsWordmark
    }

    var body: some View {
        HStack(spacing: resolvedSize * 0.36) {
            mark
            if showsText {
                Text("SinRutina")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(SRDesign.ink)
                    .kerning(-0.1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SinRutina")
    }

    private var mark: some View {
        Image("Logo")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: resolvedSize, height: resolvedSize)
            .clipShape(.rect(cornerRadius: resolvedSize * 0.28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: resolvedSize * 0.28, style: .continuous)
                    .stroke(SRDesign.primary.opacity(0.16), lineWidth: 0.6)
            }
            .shadow(
                color: SRDesign.primary.opacity(presence == .minimal ? 0.08 : 0.16),
                radius: resolvedSize * 0.22,
                y: resolvedSize * 0.09
            )
            .scaleEffect(hasBreathed ? 1 : 0.94)
            .opacity(hasBreathed ? 1 : 0.92)
            .onAppear {
                guard presence.breathesOnAppear, SRDesign.effectiveMotion != .reduced else {
                    hasBreathed = true
                    return
                }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                    hasBreathed = true
                }
            }
    }
}

/// Large centered lockup used at the top of sheets and quiet screens.
struct SRLogoLockup: View {
    var size: CGFloat = 56
    var caption: String?

    @State private var appearance = SRAppearanceStore.shared

    var body: some View {
        VStack(spacing: 10) {
            if appearance.profile.presence.showsInSheets {
                SRLogo(size: size)
            }
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
