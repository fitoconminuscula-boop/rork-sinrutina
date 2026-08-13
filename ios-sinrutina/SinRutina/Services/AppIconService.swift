import Observation
import UIKit

/// Swaps the home screen icon between the official SinRutina variants. All of
/// them draw the same simplified mark; only the palette changes.
@MainActor
@Observable
final class AppIconService {
    static let shared = AppIconService()

    private(set) var lastErrorMessage: String?

    private init() {}

    var isSupported: Bool { UIApplication.shared.supportsAlternateIcons }

    /// What iOS currently shows, which is the honest source of truth if a swap
    /// failed earlier.
    var currentOption: SRAppIconOption {
        let name = UIApplication.shared.alternateIconName
        return SRAppIconOption.allCases.first { $0.alternateIconName == name } ?? .original
    }

    /// Returns true when the icon actually changed, so the caller only stores the
    /// preference if iOS accepted it.
    func apply(_ option: SRAppIconOption) async -> Bool {
        guard isSupported else {
            lastErrorMessage = "Este iPhone no permite cambiar el icono."
            return false
        }
        guard option != currentOption else { return true }
        do {
            try await UIApplication.shared.setAlternateIconName(option.alternateIconName)
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = "iOS no aceptó el cambio de icono."
            return false
        }
    }

    /// Brings the stored preference back in line with reality, for instance after
    /// restoring a backup on another device.
    func reconcileStoredPreference() {
        let actual = currentOption
        guard SRAppearanceStore.shared.profile.appIcon != actual else { return }
        SRAppearanceStore.shared.update { $0.appIcon = actual }
    }
}
