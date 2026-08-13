import Foundation

/// Decides how long the deliberate ten seconds should really last.
///
/// The rule that matters: friction exists to interrupt an automatic gesture, not
/// to punish. It grows a little when leaving has become reflexive, it shrinks
/// when it stops helping, and it never goes past twelve seconds.
@MainActor
enum FrictionEngine {
    static let minimumSeconds: Double = 6
    static let maximumSeconds: Double = 12

    /// Seconds of friction for a session, respecting a manual setting when there
    /// is one.
    static func seconds(level: SRFocusLevel, profileKind: SRFocusProfileKind?) -> Double {
        let preferences = SRFocusPreferences.shared.data
        if let fixed = preferences.fixedFrictionSeconds {
            return min(max(fixed, minimumSeconds), maximumSeconds)
        }

        var value = max(level.baseFrictionSeconds, minimumSeconds)

        // Leaving has become reflexive today: hold the door a little longer.
        let attempts = SRDistractionLog.recentAttempts()
        if attempts >= 6 {
            value += 2
        } else if attempts >= 3 {
            value += 1
        }

        // The gesture is always completed, so it is not breaking the habit — it is
        // only annoying. Give the seconds back.
        if SRDistractionLog.frictionIsIneffective() {
            value -= 2
        }

        // Work that is already hard does not need an extra wall.
        if profileKind == .rest { value = minimumSeconds }

        return min(max(value.rounded(), minimumSeconds), maximumSeconds)
    }

    /// Tolerance in points for the follow-the-dot gesture: generous on purpose.
    static let followTolerance: CGFloat = 46

    /// Records how the friction went, both for learning and for the honest
    /// history in Ajustes.
    static func record(
        completed: Bool,
        taskID: String?,
        profileKind: SRFocusProfileKind?,
        level: SRFocusLevel
    ) {
        SRDistractionLog.append(
            SRDistractionEvent(
                kind: completed ? .frictionCompleted : .frictionAbandoned,
                taskID: taskID,
                profileKind: profileKind?.rawValue,
                level: level
            )
        )
    }

    /// The wording used while the gesture runs. Never a scold.
    static func instruction(for style: SRFrictionStyle, seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        switch style {
        case .followDot:
            return "Mantén el dedo sobre el punto y síguelo durante \(rounded) segundos."
        case .holdPress:
            return "Mantén el dedo en el círculo durante \(rounded) segundos."
        case .slowSlide:
            return "Desliza despacio de un lado a otro durante \(rounded) segundos."
        case .countdown:
            return "Espera \(rounded) segundos sin tocar nada."
        case .biometric:
            return "Confirma con Face ID y espera \(rounded) segundos."
        }
    }
}
