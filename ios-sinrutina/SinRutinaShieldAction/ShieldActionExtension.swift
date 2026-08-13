import ManagedSettings

/// What the two buttons on the shield do.
///
/// "Seguir" simply closes the attempt and leaves the person with their task.
/// "Solicitar pausa" writes a signal for the app and closes: the deliberate ten
/// seconds live inside SinRutina, never here. This extension can never lift a
/// restriction by itself.
final class ShieldActionExtension: ShieldActionDelegate {

    nonisolated override init() {
        super.init()
    }

    nonisolated override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(Self.respond(to: action))
    }

    nonisolated override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(Self.respond(to: action))
    }

    nonisolated override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(Self.respond(to: action))
    }

    nonisolated private static func respond(to action: ShieldAction) -> ShieldActionResponse {
        switch action {
        case .primaryButtonPressed:
            // Staying with the task is recorded as what it is: a decision.
            SRShieldBridge.send(SRShieldSignal(kind: .stayed))
            SRDistractionLog.append(SRDistractionEvent(kind: .blockedAppAttempt))
            return .close
        case .secondaryButtonPressed:
            SRShieldBridge.send(SRShieldSignal(kind: .pauseRequested))
            SRDistractionLog.append(SRDistractionEvent(kind: .pauseRequested))
            return .close
        @unknown default:
            return .none
        }
    }
}
