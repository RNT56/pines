import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PinesLiveActivitiesBundle: WidgetBundle {
    var body: some Widget {
        ModelDownloadLiveActivity()
    }
}

struct ModelDownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ModelDownloadActivityAttributes.self) { context in
            ModelDownloadActivityLockScreenView(context: context)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Pines", systemImage: "arrow.down.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(percentLabel(context.state.fractionCompleted))
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.attributes.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        ProgressView(value: context.state.fractionCompleted)
                            .tint(.accentColor)
                    }
                }
            } compactLeading: {
                Image(systemName: "arrow.down.circle.fill")
            } compactTrailing: {
                Text(percentLabel(context.state.fractionCompleted))
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "arrow.down.circle.fill")
            }
        }
    }

    private func percentLabel(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct ModelDownloadActivityLockScreenView: View {
    let context: ActivityViewContext<ModelDownloadActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Pines", systemImage: "arrow.down.circle.fill")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(context.state.status)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(context.attributes.displayName)
                .font(.headline)
                .lineLimit(1)

            ProgressView(value: context.state.fractionCompleted)
                .tint(.accentColor)

            Text(context.state.errorMessage ?? context.state.progressLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding()
    }
}
