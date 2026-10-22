#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

/// Pilote la Live Activity depuis l'app (mises à jour LOCALES : pas de push en v1).
/// Démarrée au premier plan, terminée à la fin de session. Elle n'ouvre pas le micro : c'est
/// `UIBackgroundModes: audio` et la session audio qui le permettent, l'indicateur micro d'iOS reste visible.
@MainActor
public final class SessionLiveActivityController: SessionActivityPresenting {
    private var activity: Activity<AVESessionAttributes>?

    public init() {}

    public func start() {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Une activité restée après un arrêt brutal de l'app serait trompeuse : on la ferme.
        for stale in Activity<AVESessionAttributes>.activities {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
        let content = ActivityContent(state: AVESessionAttributes.ContentState(phaseRaw: LiveActivityPhase.idle.rawValue),
                                      staleDate: nil)
        // La Live Activity est un confort : un refus (fond, limite système) ne doit jamais gêner la conversation.
        activity = try? Activity.request(attributes: AVESessionAttributes(startedAt: .now), content: content, pushType: nil)
    }

    public func update(_ phase: LiveActivityPhase) {
        guard let activity else { return }
        let content = ActivityContent(state: AVESessionAttributes.ContentState(phaseRaw: phase.rawValue), staleDate: nil)
        Task { await activity.update(content) }
    }

    public func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
#endif
