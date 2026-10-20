import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// The workout and its rests as the Lock Screen and the Dynamic Island show them. Between rests:
// the routine, the time since it started, and the set to do now with what it asks for. During a
// rest: the in-app shape, a clock and a shrinking bar in the accent colour, the set the rest is
// for, and the Android notification's buttons (iOS 17 and later; the intents live in
// App/RestActivity.swift). The system runs both clocks and the bar itself from their dates, so
// nothing has to wake the app every second.

@main
struct RestWidgetBundle: WidgetBundle {
    var body: some Widget {
        RestLiveActivity()
    }
}

struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            // Opaque, in the app's own background (capacitor.config.json backgroundColor): the
            // clocks and the secondary buttons are white, and a translucent tint lets a light
            // wallpaper wash them out.
            Group {
                if context.state.resting {
                    RestLockScreen(attributes: context.attributes, state: context.state, over: context.isStale)
                } else {
                    WorkoutLockScreen(attributes: context.attributes, state: context.state)
                }
            }
            .background(appBackground)
            .activityBackgroundTint(appBackground)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            let accent = Color.argb(s.accent)
            let over = context.isStale && s.resting
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(s.resting ? context.attributes.title : s.workoutTitle, systemImage: s.resting ? "timer" : "dumbbell.fill")
                        .font(.headline)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if s.resting {
                            RestClock(attributes: context.attributes, state: s, over: over)
                        } else {
                            WorkoutClock(state: s)
                        }
                    }
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if s.resting {
                        VStack(alignment: .leading, spacing: 10) {
                            RestUpNext(state: s)
                                .padding(.horizontal, 4)
                            RestBar(state: s, over: over)
                            RestButtons(attributes: context.attributes, state: s, over: over)
                        }
                    } else {
                        WorkoutSet(attributes: context.attributes, state: s)
                            .padding(.horizontal, 4)
                    }
                }
            } compactLeading: {
                Image(systemName: s.resting ? (s.paused ? "pause.fill" : "timer") : "dumbbell.fill")
                    .foregroundStyle(accent)
            } compactTrailing: {
                Group {
                    if s.resting {
                        RestClock(attributes: context.attributes, state: s, over: over)
                    } else {
                        Text(s.pendingDone ? "✓" : s.nextDetail)
                    }
                }
                .font(.body.monospacedDigit())
                .foregroundStyle(accent)
                .lineLimit(1)
                .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: s.resting ? (s.paused ? "pause.fill" : "timer") : "dumbbell.fill")
                    .foregroundStyle(accent)
            }
            .keylineTint(accent)
        }
    }
}

private let appBackground = Color(red: 12 / 255, green: 14 / 255, blue: 18 / 255)

private struct RestLockScreen: View {
    let attributes: RestActivityAttributes
    let state: RestActivityAttributes.ContentState
    let over: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(over ? attributes.doneTitle : attributes.title, systemImage: "timer")
                    .font(.headline)
                    .foregroundStyle(Color.argb(state.accent))
                    .lineLimit(1)
                Spacer(minLength: 8)
                RestClock(attributes: attributes, state: state, over: over)
                    .font(.system(size: 34, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            // Its own row, the full width: beside the clock a long exercise name had no room.
            RestUpNext(state: state)
            RestBar(state: state, over: over)
            RestButtons(attributes: attributes, state: state, over: over)
        }
        .padding(16)
    }
}

/// Between rests: the routine and how long it has run, then the set to do now.
private struct WorkoutLockScreen: View {
    let attributes: RestActivityAttributes
    let state: RestActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(state.workoutTitle, systemImage: "dumbbell.fill")
                    .font(.headline)
                    .foregroundStyle(Color.argb(state.accent))
                    .lineLimit(1)
                Spacer(minLength: 8)
                WorkoutClock(state: state)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.65))
            }
            WorkoutSet(attributes: attributes, state: state)
        }
        .padding(16)
    }
}

/// The set to do now: the exercise and which set on one line, then what it asks for in large
/// type, and Done to tick it (iOS 17). After Done, a check until the page moves the card on to
/// the next set.
private struct WorkoutSet: View {
    let attributes: RestActivityAttributes
    let state: RestActivityAttributes.ContentState

    var body: some View {
        if !state.nextName.isEmpty {
            let accent = Color.argb(state.accent)
            VStack(alignment: .leading, spacing: 6) {
                (Text(state.nextName).fontWeight(.semibold).foregroundColor(.white)
                    + Text(state.nextSet.isEmpty ? "" : "  " + state.nextSet).foregroundColor(.white.opacity(0.65)))
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Text(state.nextDetail)
                        .font(.system(size: 30, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 8)
                    if state.pendingDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(accent)
                    } else if canAct, #available(iOS 17.0, *) {
                        Button(intent: SetDoneIntent()) {
                            Label(attributes.done, systemImage: "checkmark")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(accent)
                        .foregroundStyle(Color.argb(state.ink))
                    }
                }
            }
        }
    }

    private var canAct: Bool { state.setIdx >= 0 && !state.pendingDone }
}

/// Time since the session started, counting up. Nothing for a session without a start.
private struct WorkoutClock: View {
    let state: RestActivityAttributes.ContentState

    var body: some View {
        if let start = state.startedAt {
            Text(start, style: .timer)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// The set the rest is for: the exercise in bold, then which set and what it asks for —
/// "Bench Press · Set 3/4 · 60×8". Nothing after the workout's last set.
private struct RestUpNext: View {
    let state: RestActivityAttributes.ContentState

    var body: some View {
        if !state.nextName.isEmpty {
            let rest = [state.nextSet, state.nextDetail].filter { !$0.isEmpty }.joined(separator: " · ")
            (Text(state.nextName).fontWeight(.semibold).foregroundColor(.white)
                + Text(rest.isEmpty ? "" : "  " + rest).foregroundColor(.white.opacity(0.65)))
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

private struct RestClock: View {
    let attributes: RestActivityAttributes
    let state: RestActivityAttributes.ContentState
    let over: Bool

    var body: some View {
        if state.paused {
            Text(clock(state.leftSec))
        } else if over || state.endsAt <= Date() {
            Text("0:00")
        } else {
            Text(timerInterval: Date()...state.endsAt, countsDown: true)
                .multilineTextAlignment(.trailing)
        }
    }

    private func clock(_ sec: Double) -> String {
        let s = Int(sec.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct RestBar: View {
    let state: RestActivityAttributes.ContentState
    let over: Bool

    var body: some View {
        let accent = Color.argb(state.accent)
        Group {
            if state.paused {
                ProgressView(value: min(state.leftSec, state.totalSec), total: max(1, state.totalSec))
            } else if over || state.endsAt <= Date() {
                ProgressView(value: 0, total: 1)
            } else {
                // The bar runs over the whole rest; a lower bound past now (after −15 s) is clamped.
                let start = min(Date(), state.endsAt.addingTimeInterval(-max(1, state.totalSec)))
                ProgressView(timerInterval: start...state.endsAt, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            }
        }
        .progressViewStyle(.linear)
        .tint(accent)
        .labelsHidden()
    }
}

private struct RestButtons: View {
    let attributes: RestActivityAttributes
    let state: RestActivityAttributes.ContentState
    let over: Bool

    var body: some View {
        if #available(iOS 17.0, *), !over {
            let accent = Color.argb(state.accent)
            let ink = Color.argb(state.ink)
            HStack(spacing: 8) {
                Button(intent: RestNudgeIntent(seconds: -15)) { pill(attributes.minus) }
                    .tint(.white.opacity(0.18))
                Button(intent: RestPauseIntent()) { pill(state.paused ? attributes.resume : attributes.pause) }
                    .tint(accent)
                    .foregroundStyle(ink)
                Button(intent: RestNudgeIntent(seconds: 15)) { pill(attributes.plus) }
                    .tint(.white.opacity(0.18))
                Button(intent: RestSkipIntent()) { pill(attributes.skip) }
                    .tint(.white.opacity(0.18))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
    }
}

private extension Color {
    /// ARGB as the page sends it (lib/rest-alert.js accentColors). A factory rather than an
    /// init: the preview canvas cannot compile a delegating init in an extension.
    static func argb(_ v: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255,
            opacity: Double((v >> 24) & 0xFF) / 255
        )
    }
}

// ---- Previews (Xcode canvas): the workout, then a rest running, paused and over, in each place the system shows them ----

#if DEBUG
@available(iOS 17.0, *)
private extension RestActivityAttributes {
    static let preview = RestActivityAttributes(
        title: "Rest", doneTitle: "Rest over — next set!",
        pause: "Pause", resume: "Resume", minus: "− 15s", plus: "+ 15s", skip: "Skip", done: "Done",
        sound: true
    )
}

@available(iOS 17.0, *)
private extension RestActivityAttributes.ContentState {
    static func rest(endsIn: Double, left: Double, paused: Bool = false) -> Self {
        Self(resting: true, inWorkout: true, workoutTitle: "Push Day", startedAt: Date().addingTimeInterval(-754),
             endsAt: Date().addingTimeInterval(endsIn), totalSec: 90, leftSec: left, paused: paused,
             accent: 0xFF30D158, ink: 0xFF000000, nextName: "Bench Press", nextSet: "Set 3/4", nextDetail: "60×8",
             setIdx: 0, setI: 2, pendingDone: false)
    }
    static let workout = Self(resting: false, inWorkout: true, workoutTitle: "Push Day", startedAt: Date().addingTimeInterval(-754),
                              endsAt: Date(), totalSec: 1, leftSec: 0, paused: false,
                              accent: 0xFF30D158, ink: 0xFF000000, nextName: "Bench Press", nextSet: "Set 1/4", nextDetail: "60×8",
                              setIdx: 0, setI: 0, pendingDone: false)
    static let running = rest(endsIn: 75, left: 75)
    static let paused = rest(endsIn: 0, left: 42, paused: true)
    static let over = rest(endsIn: -1, left: 0)
}

@available(iOS 17.0, *)
#Preview("Lock Screen", as: .content, using: RestActivityAttributes.preview) {
    RestLiveActivity()
} contentStates: {
    RestActivityAttributes.ContentState.workout
    RestActivityAttributes.ContentState.running
    RestActivityAttributes.ContentState.paused
    RestActivityAttributes.ContentState.over
}

@available(iOS 17.0, *)
#Preview("Dynamic Island expanded", as: .dynamicIsland(.expanded), using: RestActivityAttributes.preview) {
    RestLiveActivity()
} contentStates: {
    RestActivityAttributes.ContentState.workout
    RestActivityAttributes.ContentState.running
    RestActivityAttributes.ContentState.paused
}

@available(iOS 17.0, *)
#Preview("Dynamic Island compact", as: .dynamicIsland(.compact), using: RestActivityAttributes.preview) {
    RestLiveActivity()
} contentStates: {
    RestActivityAttributes.ContentState.workout
    RestActivityAttributes.ContentState.running
    RestActivityAttributes.ContentState.paused
}

@available(iOS 17.0, *)
#Preview("Dynamic Island minimal", as: .dynamicIsland(.minimal), using: RestActivityAttributes.preview) {
    RestLiveActivity()
} contentStates: {
    RestActivityAttributes.ContentState.running
}
#endif
