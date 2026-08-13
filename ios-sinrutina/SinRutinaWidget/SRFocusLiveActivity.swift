import ActivityKit
import SwiftUI
import WidgetKit

/// The Live Activity for a task in progress. Sober on purpose: one title, one
/// clock, one action.
struct SRFocusLiveActivity: Widget {
    /// Read once per render: the Live Activity follows the same appearance profile
    /// as the app, while the Dynamic Island stays deliberately clean in every style.
    private var style: SRLiveActivityStyle { SRAppearanceReader.profile().liveActivityStyle }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SRFocusAttributes.self) { context in
            lockScreen(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isOnBreak
                          ? "cup.and.saucer.fill"
                          : (context.state.isPaused ? "pause.circle.fill" : "circle.dashed.inset.filled"))
                        .font(.title3)
                        .foregroundStyle(SRPalette.primary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if style != .minimal {
                        timer(for: context.state)
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(SRPalette.ink)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SRPalette.ink)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        Text(islandDetail(context: context))
                            .font(.caption)
                            .foregroundStyle(SRPalette.secondaryInk)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button(intent: SRFinishFocusIntent(taskID: context.attributes.taskID)) {
                            Text("Terminé")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SRPalette.onPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(SRPalette.primary)
                                .clipShape(Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "circle.dashed.inset.filled")
                    .foregroundStyle(SRPalette.primary)
            } compactTrailing: {
                if style != .minimal {
                    timer(for: context.state)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(SRPalette.primary)
                        .frame(maxWidth: 44)
                }
            } minimal: {
                Image(systemName: "circle.dashed.inset.filled")
                    .foregroundStyle(SRPalette.primary)
            }
            .keylineTint(SRPalette.primary)
        }
    }

    private func lockScreen(context: ActivityViewContext<SRFocusAttributes>) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(lockScreenLabel(context: context).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(SRPalette.primary)
                Text(context.attributes.title)
                    .font(.headline)
                    .foregroundStyle(SRPalette.ink)
                    .lineLimit(2)
                if style == .contextual, let step = context.attributes.nextStep, !step.isEmpty {
                    Text(step)
                        .font(.caption)
                        .foregroundStyle(SRPalette.secondaryInk)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                if style != .minimal {
                    timer(for: context.state)
                        .font(.title2.monospacedDigit().weight(.medium))
                        .foregroundStyle(SRPalette.ink)
                }
                Button(intent: SRFinishFocusIntent(taskID: context.attributes.taskID)) {
                    Text("Terminé")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SRPalette.onPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(SRPalette.primary)
                        .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .activityBackgroundTint(SRPalette.surface)
        .activitySystemActionForegroundColor(SRPalette.primary)
    }

    /// "EN MARCHA", "EN PAUSA", "DESCANSO" — plus the level when it changes the
    /// phone, so the lock screen never hides what is restricted.
    private func lockScreenLabel(context: ActivityViewContext<SRFocusAttributes>) -> String {
        let state = context.state.statusLabel
        let level = context.attributes.level
        guard level.blocksApps else { return state }
        return "\(state) · \(level.label)"
    }

    /// The expanded island keeps one short line: state, or state plus next step.
    private func islandDetail(context: ActivityViewContext<SRFocusAttributes>) -> String {
        guard style == .contextual,
              let step = context.attributes.nextStep,
              !step.isEmpty else {
            return context.state.statusLabel
        }
        return "\(context.state.statusLabel) · \(step)"
    }

    @ViewBuilder
    private func timer(for state: SRFocusAttributes.ContentState) -> some View {
        if state.isOnBreak, let endsAt = state.breakEndsAt {
            // During a real break the clock counts the rest, not the work.
            Text(timerInterval: Date()...max(endsAt, Date().addingTimeInterval(1)), countsDown: true)
        } else if let target = state.targetDate, !state.isPaused {
            Text(timerInterval: Date()...max(target, Date().addingTimeInterval(1)), countsDown: true)
        } else {
            Text(pausedLabel(for: state))
        }
    }

    private func pausedLabel(for state: SRFocusAttributes.ContentState) -> String {
        let remaining = max(0, Double(state.plannedMinutes) - state.accumulatedMinutes)
        let minutes = Int(remaining)
        let seconds = Int((remaining - Double(minutes)) * 60)
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
