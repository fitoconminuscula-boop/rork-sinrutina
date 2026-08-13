import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The sign on the door.
///
/// Deliberately as simple as possible: what you are doing, and two buttons.
/// Everything that needs thinking happens inside SinRutina, not here. The shield
/// reads the same appearance profile as the app, so the colours are the ones the
/// person chose.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    nonisolated override init() {
        super.init()
    }

    nonisolated override func configuration(shielding application: Application) -> ShieldConfiguration {
        Self.make()
    }

    nonisolated override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        Self.make()
    }

    nonisolated override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        Self.make()
    }

    nonisolated override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        Self.make()
    }

    // MARK: - Building

    nonisolated private static func make() -> ShieldConfiguration {
        let context = SRShieldBridge.readContext()
        let tokens = SRResolvedTokens(profile: SRAppearanceReader.profile(), scheme: .light)
        let darkTokens = SRResolvedTokens(profile: SRAppearanceReader.profile(), scheme: .dark)

        func adaptive(_ light: SRRGB, _ dark: SRRGB) -> UIColor {
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark.uiColor : light.uiColor
            }
        }

        let title = context.map { "Estás haciendo\n\($0.taskTitle)" } ?? "Estás en una sesión de SinRutina"
        let subtitle = context?.nextStep

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: adaptive(tokens.background, darkTokens.background).withAlphaComponent(0.92),
            icon: nil,
            title: ShieldConfiguration.Label(
                text: title,
                color: adaptive(tokens.ink, darkTokens.ink)
            ),
            subtitle: subtitle.map {
                ShieldConfiguration.Label(
                    text: $0,
                    color: adaptive(tokens.secondaryInk, darkTokens.secondaryInk)
                )
            },
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Seguir",
                color: adaptive(tokens.onPrimary, darkTokens.onPrimary)
            ),
            primaryButtonBackgroundColor: adaptive(tokens.primary, darkTokens.primary),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Solicitar pausa",
                color: adaptive(tokens.secondaryInk, darkTokens.secondaryInk)
            )
        )
    }
}
