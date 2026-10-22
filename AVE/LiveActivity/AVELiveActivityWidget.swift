// Cible « extension Widget » (non incluse dans le package SwiftPM) : à ajouter à la cible Xcode
// de l'extension, qui doit lier AVEKit. Voir ios/LIVEACTIVITY.md.
import ActivityKit
import AVEKit
import SwiftUI
import WidgetKit

@main
struct AVEWidgets: WidgetBundle {
    var body: some Widget { AVELiveActivityWidget() }
}

struct AVELiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AVESessionAttributes.self) { context in
            LockScreenView(phase: phase(context.state), startedAt: context.attributes.startedAt)
        } dynamicIsland: { context in
            let current = phase(context.state)
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

    private func phase(_ state: AVESessionAttributes.ContentState) -> LiveActivityPhase {
        LiveActivityPhase(rawValue: state.phaseRaw) ?? .idle
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
