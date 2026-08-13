import Observation
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Holds the appearance profile and keeps every surface in step with it.
///
/// The app writes; the widget and the share sheet only read. Nothing here ever
/// leaves the device: it is a small JSON blob in the shared app group.
@MainActor
@Observable
final class SRAppearanceStore {
    static let shared = SRAppearanceStore()

    private(set) var profile: SRAppearanceProfile
    /// Resolved once per change instead of on every colour lookup.
    private(set) var palette: SRPaletteValues

    private let defaults = SRShared.defaults

    private init() {
        let stored: SRAppearanceProfile = {
            guard let data = SRShared.defaults.data(forKey: SRShared.Key.appearance),
                  let decoded = try? JSONDecoder().decode(SRAppearanceProfile.self, from: data) else {
                return SRAppearanceProfile()
            }
            return decoded
        }()
        self.profile = stored
        self.palette = SRPaletteValues.resolve(stored)
    }

    /// Single entry point for every change, so persistence, palette and outside
    /// surfaces can never drift apart.
    func update(_ transform: (inout SRAppearanceProfile) -> Void) {
        var draft = profile
        transform(&draft)
        apply(draft)
    }

    func apply(_ newProfile: SRAppearanceProfile) {
        guard newProfile != profile else { return }
        profile = newProfile
        palette = SRPaletteValues.resolve(newProfile)
        persist()
        reloadOutsideSurfaces()
    }

    /// Back to the original SinRutina design, keeping the record of suggestions
    /// already answered so the app does not ask again straight away.
    func resetToOriginal() {
        var restored = SRAppearanceProfile()
        restored.answeredSuggestions = profile.answeredSuggestions
        apply(restored)
    }

    /// Reads the latest value written by another process (the share sheet, mostly).
    func reloadFromDisk() {
        guard let data = defaults.data(forKey: SRShared.Key.appearance),
              let decoded = try? JSONDecoder().decode(SRAppearanceProfile.self, from: data),
              decoded != profile else { return }
        profile = decoded
        palette = SRPaletteValues.resolve(decoded)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: SRShared.Key.appearance)
    }

    private func reloadOutsideSurfaces() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

/// Read-only access for processes that must not own state, such as the widget
/// timeline provider running before any view exists.
nonisolated enum SRAppearanceReader {
    static func profile() -> SRAppearanceProfile {
        guard let data = SRShared.defaults.data(forKey: SRShared.Key.appearance),
              let decoded = try? JSONDecoder().decode(SRAppearanceProfile.self, from: data) else {
            return SRAppearanceProfile()
        }
        return decoded
    }
}
