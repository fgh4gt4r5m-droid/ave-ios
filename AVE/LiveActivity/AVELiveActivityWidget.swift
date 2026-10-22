// Cible « extension Widget » (non incluse dans le package SwiftPM). Elle ne lie PAS AVEKit : `project.yml` compile ici
// directement AVESessionAttributes.swift, LiveActivityPhase.swift et AVEPalette.swift (fichiers sans dépendance).
// Voir LIVEACTIVITY.md.
import ActivityKit
import SwiftUI
import WidgetKit

@main
struct AVEWidgets: WidgetBundle {
    var body: some Widget { AVELiveActivityWidget() }
}

struct AVELiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AVESessionAttributes.self) { context in
            LockScreenView(phase: livePhase(context.state), startedAt: context.attributes.startedAt)
        } dynamicIsland: { context in
            let current = livePhase(context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: current.symbolName).font(.title2).accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(current.label).font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
                        .monospacedDigit()
                        .frame(width: 56)
                        .accessibilityLabel("Durée de la conversation")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("African Voice Engine").font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: current.symbolName).accessibilityLabel(current.label)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: current.symbolName).accessibilityLabel(current.label)
            }
            .keylineTint(Color(AVEPalette.blue))
        }
    }
}

/// Fonction libre (non isolée) plutôt que méthode du widget : les closures d'`ActivityConfiguration` ne sont pas
/// forcément isolées à l'acteur principal, alors qu'une méthode d'un `Widget` l'est.
private func livePhase(_ state: AVESessionAttributes.ContentState) -> LiveActivityPhase {
    LiveActivityPhase(rawValue: state.phaseRaw) ?? .idle
}

/// Même conversion que dans AVEKit (`AVETheme.swift`), qui n'est pas lié à cette extension.
private extension Color {
    init(_ c: AVEColor) {
        self.init(red: Double(c.red) / 255, green: Double(c.green) / 255, blue: Double(c.blue) / 255)
    }
}

private struct LockScreenView: View {
    let phase: LiveActivityPhase
    let startedAt: Date

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: phase.symbolName)
                .font(.title2)
                .foregroundStyle(Color(AVEPalette.navy))
                .frame(width: 44, height: 44)
                .background(Color(AVEPalette.blue), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text("African Voice Engine").font(.caption).foregroundStyle(.secondary)
                Text(phase.label).font(.headline)
            }
            Spacer()
            Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                .monospacedDigit()
                .accessibilityLabel("Durée de la conversation")
        }
        .padding()
        .activityBackgroundTint(Color(AVEPalette.navy))
        .activitySystemActionForegroundColor(Color(AVEPalette.blue))
        .accessibilityElement(children: .combine)
    }
}
