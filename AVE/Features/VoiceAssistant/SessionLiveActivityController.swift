#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

/// Pilote la Live Activity depuis l'app (mises à jour LOCALES : pas de push en v1).
/// Démarrée au premier plan, terminée à la fin de session. Elle n'ouvre pas le micro : c'est
/// `UIBackgroundModes: audio` et la session audio qui le permettent, l'indicateur micro d'iOS reste visible.
@MainActor
public final class SessionLiveActivityController: SessionActivityPresenting {
    private var activity: ActivityHandle?

    public init() {}

    public func start() {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Une activité restée après un arrêt brutal de l'app serait trompeuse : on la ferme.
        for stale in Activity<AVESessionAttributes>.activities {
            let handle = ActivityHandle(stale)
            Task { await handle.end() }
        }
        let content = ActivityContent(state: AVESessionAttributes.ContentState(phaseRaw: LiveActivityPhase.idle.rawValue),
                                      staleDate: nil)
        // La Live Activity est un confort : un refus (fond, limite système) ne doit jamais gêner la conversation.
        if let requested = try? Activity.request(attributes: AVESessionAttributes(startedAt: .now), content: content,
                                                 pushType: nil) {
            activity = ActivityHandle(requested)
        }
    }

    public func update(_ phase: LiveActivityPhase) {
        guard let activity else { return }
        let state = AVESessionAttributes.ContentState(phaseRaw: phase.rawValue)
        Task { await activity.update(state) }
    }

    public func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end() }
    }
}

/// `Activity` n'est pas `Sendable` dans le SDK iOS 26.5, alors que `update` et `end` sont des méthodes asynchrones
/// NON isolées : les appeler depuis l'acteur principal « envoie » l'objet, ce que Swift 6 refuse (constaté sur
/// Codemagic). Cette boîte porte l'objet jusqu'à des méthodes non isolées. `@unchecked` : nous ne lisons ni ne
/// modifions l'état de l'activité nous-mêmes, nous ne faisons qu'appeler ces deux méthodes d'ActivityKit.
private struct ActivityHandle: @unchecked Sendable {
    private let activity: Activity<AVESessionAttributes>

    init(_ activity: Activity<AVESessionAttributes>) { self.activity = activity }

    func update(_ state: AVESessionAttributes.ContentState) async {
        // Contenu construit ici (et non sur l'acteur principal) : rien d'autre à faire traverser que l'état, Sendable.
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    func end() async {
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}
#endif
