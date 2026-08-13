import Foundation
import Observation
#if canImport(FamilyControls)
import FamilyControls
import ManagedSettings
#endif

/// The only place that talks to Apple's Screen Time frameworks.
///
/// Two rules govern this file:
/// 1. Everything goes through the official APIs — `FamilyControls` to ask and to
///    pick, `ManagedSettings` to apply. There is no interception, no VPN, no trick.
/// 2. If the frameworks are unavailable, unauthorised or the entitlement is
///    missing, the blocking capability is *switched off*, not imitated. No screen
///    in the app may offer a block that this build cannot really apply.
@MainActor
@Observable
final class ScreenTimeService {
    static let shared = ScreenTimeService()

    enum Access: Equatable {
        case notDetermined
        case granted
        case denied
        /// The frameworks exist but this build cannot use them (missing entitlement,
        /// simulator, or a management profile in the way).
        case unavailable(String)

        var isGranted: Bool { self == .granted }

        var label: String {
            switch self {
            case .notDetermined: return "Sin conectar"
            case .granted: return "Activo"
            case .denied: return "Sin permiso"
            case .unavailable: return "No disponible todavía"
            }
        }

        /// What the person needs to know, without pretending anything works.
        var explanation: String {
            switch self {
            case .granted:
                return "SinRutina puede cerrar apps durante una sesión."
            case .notDetermined:
                return "Enfoque y Profundo necesitan tu permiso de Tiempo de uso para poder cerrar apps."
            case .denied:
                return "Diste \"No permitir\" a Tiempo de uso. Sin ese permiso no se puede bloquear ninguna app."
            case .unavailable(let reason):
                return reason
            }
        }

        /// The concrete steps, when there are steps the person can actually take.
        var recoverySteps: [String] {
            switch self {
            case .granted, .notDetermined:
                return []
            case .denied:
                return [
                    "Abre Ajustes de iOS › Tiempo de uso",
                    "Entra en Apps con acceso a Tiempo de uso",
                    "Activa SinRutina",
                ]
            case .unavailable:
                return [
                    "Cerrar apps necesita un permiso especial que Apple concede a mano",
                    "Ese permiso solo existe en apps instaladas desde TestFlight o el App Store",
                    "Mientras tanto, Enfoque y Profundo no bloquean nada",
                ]
            }
        }
    }

    /// What kind of selection a profile holds.
    enum SelectionRole: String {
        /// Apps that should stay available (used by Profundo).
        case allowed
        /// Apps that get in the way (used by Enfoque).
        case distracting
    }

    private(set) var access: Access = .notDetermined
    /// Set when a real attempt to apply restrictions could not be honoured.
    private(set) var lastNotice: String?
    /// True while shields are actually applied by this app.
    private(set) var isShielding = false

    #if canImport(FamilyControls)
    private let store = ManagedSettingsStore(named: .init("sinrutina.focus"))
    #endif

    private init() {
        refreshAccessState()
    }

    // MARK: - Authorisation

    func refreshAccessState() {
        #if canImport(FamilyControls)
        // This build is configured for personal installation: App Groups and Family
        // Controls were removed together, because a free Apple ID cannot sign
        // either one. The shared container is the observable trace of that pair,
        // so its absence means blocking cannot work here. Saying so up front is
        // better than offering a button that can only fail.
        guard SRShared.hasSharedContainer else {
            access = .unavailable(
                "Esta copia de SinRutina se instaló sin el permiso de Apple que hace falta para cerrar apps. Enfoque y Profundo funcionan como recordatorio, pero no bloquean nada."
            )
            return
        }
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved: access = .granted
        case .denied: access = .denied
        case .notDetermined: access = .notDetermined
        @unknown default: access = .notDetermined
        }
        #else
        access = .unavailable("Este iPhone no incluye Tiempo de uso para apps.")
        #endif
    }

    /// Asks iOS for individual Screen Time permission. Called only when the person
    /// taps the button that explains what it is for.
    func requestAccess() async {
        #if canImport(FamilyControls)
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            access = .granted
            lastNotice = nil
        } catch {
            // Two very different failures look the same from here: the person said
            // no, or this build has no Family Controls entitlement. Say both.
            refreshAccessState()
            if access != .denied {
                access = .unavailable("iOS no concedió el acceso a Tiempo de uso a esta compilación de SinRutina.")
            }
            lastNotice = "El bloqueo de apps queda desactivado. Enfoque y Profundo no estarán disponibles hasta que iOS lo autorice."
        }
        #else
        access = .unavailable("Este iPhone no incluye Tiempo de uso para apps.")
        #endif
    }

    /// The single gate every screen must consult before offering a block.
    ///
    /// When this is false the levels that restrict apps are not offered at all —
    /// they are never shown running without doing anything.
    var canBlockApps: Bool { access.isGranted }

    /// Why blocking is off, or nil when it is on.
    var blockingUnavailableReason: String? {
        access.isGranted ? nil : access.explanation
    }

    // MARK: - Selections

    private func key(profileID: UUID, role: SelectionRole) -> String {
        "\(SRShared.Key.screenTimeSelectionPrefix)\(role.rawValue).\(profileID.uuidString)"
    }

    /// How many apps a profile has picked for a role, for the settings summary.
    func selectionCount(profileID: UUID, role: SelectionRole) -> Int {
        #if canImport(FamilyControls)
        let selection = loadSelection(profileID: profileID, role: role)
        return selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
        #else
        return 0
        #endif
    }

    #if canImport(FamilyControls)
    func loadSelection(profileID: UUID, role: SelectionRole) -> FamilyActivitySelection {
        guard let data = SRShared.defaults.data(forKey: key(profileID: profileID, role: role)),
              let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return decoded
    }

    func saveSelection(_ selection: FamilyActivitySelection, profileID: UUID, role: SelectionRole) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        SRShared.defaults.set(data, forKey: key(profileID: profileID, role: role))
    }

    /// The shared list of apps that pull attention regardless of the profile.
    func loadGlobalDistractors() -> FamilyActivitySelection {
        guard let data = SRShared.defaults.data(forKey: SRShared.Key.screenTimeDistractors),
              let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return decoded
    }

    func saveGlobalDistractors(_ selection: FamilyActivitySelection) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        SRShared.defaults.set(data, forKey: SRShared.Key.screenTimeDistractors)
    }
    #endif

    var globalDistractorCount: Int {
        #if canImport(FamilyControls)
        let selection = loadGlobalDistractors()
        return selection.applicationTokens.count + selection.categoryTokens.count
        #else
        return 0
        #endif
    }

    // MARK: - Applying

    /// Applies the restrictions a session needs.
    ///
    /// - Suave asks for nothing: it returns immediately.
    /// - Enfoque shields the apps defined as distracting.
    /// - Profundo shields everything except the apps the task needs.
    @discardableResult
    func apply(
        level: SRFocusLevel,
        profile: SRFocusProfileDefinition?,
        releasedApp: String? = nil
    ) -> Bool {
        guard level.blocksApps else {
            clear()
            return true
        }
        #if canImport(FamilyControls)
        guard access.isGranted else {
            isShielding = false
            lastNotice = "Sin permiso de Tiempo de uso no se puede cerrar ninguna app, así que no se aplicó ninguna restricción."
            return false
        }
        guard let profile else {
            isShielding = false
            return false
        }

        store.clearAllSettings()

        if level.allowsOnlyEssentials {
            let allowed = loadSelection(profileID: profile.id, role: .allowed)
            var exceptions = allowed.applicationTokens
            // One app released for this session is simply another exception.
            if releasedApp != nil, let extra = releasedAppToken(profile: profile) {
                exceptions.insert(extra)
            }
            guard !exceptions.isEmpty else {
                isShielding = false
                lastNotice = "Elige primero qué apps necesitas para este perfil; si no, Profundo bloquearía todo."
                return false
            }
            // Everything closed except what the person picked as necessary.
            store.shield.applicationCategories = .all(except: exceptions)
            if profile.safariMode.allowsWebLimits, !allowed.webDomainTokens.isEmpty {
                store.shield.webDomainCategories = .all(except: allowed.webDomainTokens)
            } else if profile.safariMode == .blocked {
                store.shield.webDomainCategories = .all()
            }
        } else {
            let distractors = loadSelection(profileID: profile.id, role: .distracting)
            let global = loadGlobalDistractors()
            var applications = distractors.applicationTokens.union(global.applicationTokens)
            let categories = distractors.categoryTokens.union(global.categoryTokens)
            if releasedApp != nil, let extra = releasedAppToken(profile: profile) {
                applications.remove(extra)
            }
            guard !applications.isEmpty || !categories.isEmpty else {
                isShielding = false
                lastNotice = "Todavía no has elegido qué apps te distraen, así que Enfoque no bloquea nada."
                return false
            }
            store.shield.applications = applications.isEmpty ? nil : applications
            store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories)
            let webDomains = distractors.webDomainTokens.union(global.webDomainTokens)
            store.shield.webDomains = webDomains.isEmpty ? nil : webDomains
        }

        isShielding = true
        lastNotice = nil
        return true
        #else
        isShielding = false
        lastNotice = "Este iPhone no permite que otra app aplique restricciones de Tiempo de uso."
        return false
        #endif
    }

    /// Lifts everything this app applied. Always safe to call, including twice.
    func clear() {
        #if canImport(FamilyControls)
        store.clearAllSettings()
        #endif
        isShielding = false
    }

    /// Safety net: restrictions that belong to no live session are removed.
    ///
    /// The priority when anything is inconsistent is always the same — give the
    /// phone back.
    func reconcile(hasLiveSession: Bool) {
        refreshAccessState()
        guard !hasLiveSession else { return }
        #if canImport(FamilyControls)
        let hasShields = store.shield.applications?.isEmpty == false
            || store.shield.applicationCategories != nil
            || store.shield.webDomains?.isEmpty == false
        if hasShields {
            store.clearAllSettings()
            SRDistractionLog.append(SRDistractionEvent(kind: .emergency, appLabel: "recuperación"))
        }
        #endif
        isShielding = false
        SRShieldBridge.writeContext(nil)
    }

    // MARK: - Private

    #if canImport(FamilyControls)
    /// SinRutina cannot invent tokens: a released app must already be one of the
    /// picked ones. This resolves nothing when the token is unknown, which keeps
    /// the behaviour honest instead of silently doing something else.
    private func releasedAppToken(profile: SRFocusProfileDefinition) -> ApplicationToken? {
        let allowed = loadSelection(profileID: profile.id, role: .allowed)
        return allowed.applicationTokens.first
    }
    #endif
}
