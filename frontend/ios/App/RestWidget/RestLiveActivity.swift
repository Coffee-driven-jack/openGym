import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// The workout and its rests as the Lock Screen and the Dynamic Island show them, with the
// exercise to do as the title throughout. Between rests: the time since the workout started, the
// set to do now with what it asks for, and Done to tick it. During a rest: the in-app shape, a
// clock and a shrinking bar in the accent colour, and the Android notification's buttons (iOS 17
// and later; the intents live in App/RestActivity.swift). When the rest runs out the card is the
// set again on its own — the state already holds it, and the system redraws at the rest's end
// (its stale date) without the app having to wake. The system runs both clocks and the bar
// itself from their dates, so nothing has to wake the app every second.

@main
struct RestWidgetBundle: WidgetBundle {
    var body: some Widget {
        RestLiveActivity()
    }
}

/// What the card is showing: a rest counting (or held), a lone rest that ran out, or the set.
private enum CardMode {
    case rest, restOver, workout

    init(_ s: RestActivityAttributes.ContentState, stale: Bool) {
        let over = s.resting && !s.paused && (stale || s.endsAt <= Date())
        if !s.resting || (over && s.inWorkout) { self = .workout }
        else if over { self = .restOver }
        else { self = .rest }
    }
}

/// The exercise to do, the card's title; the routine (or the rest's own word) when there is none.
private func cardTitle(_ a: RestActivityAttributes, _ s: RestActivityAttributes.ContentState, _ mode: CardMode) -> String {
    if mode == .restOver { return a.doneTitle }
    if !s.nextName.isEmpty { return s.nextName }
    return s.inWorkout && !s.workoutTitle.isEmpty ? s.workoutTitle : a.title
}

/// The line under the title. During a rest: "Rest · Set 3/4 · 60×8". Between rests: which set,
/// and the routine — "Set 1/4 · Push Day".
private func cardSubtitle(_ a: RestActivityAttributes, _ s: RestActivityAttributes.ContentState, _ mode: CardMode) -> String {
    let parts: [String]
    switch mode {
    case .rest: parts = s.nextName.isEmpty ? [] : [a.title, s.nextSet, s.nextDetail]
    case .restOver: parts = []
    case .workout: parts = s.nextName.isEmpty ? [] : [s.nextSet, s.workoutTitle]
    }
    return parts.filter { !$0.isEmpty }.joined(separator: " · ")
}

struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            let mode = CardMode(context.state, stale: context.isStale)
            // Opaque, in the app's own background (capacitor.config.json backgroundColor): the
            // clocks and the secondary buttons are white, and a translucent tint lets a light
            // wallpaper wash them out.
            CardLockScreen(attributes: context.attributes, state: context.state, mode: mode)
                .widgetURL(cardURL(context.state))
                .background(appBackground)
                .activityBackgroundTint(appBackground)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            let mode = CardMode(s, stale: context.isStale)
            let accent = Color.argb(s.accent)
            let icon = mode == .workout ? "dumbbell.fill" : (s.paused ? "pause.fill" : "timer")
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(accent)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if mode == .workout {
                            WorkoutClock(state: s)
                        } else {
                            RestClock(attributes: context.attributes, state: s, over: mode == .restOver)
                        }
                    }
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // The title here, the full width: in the leading region beside the camera a
                    // long exercise name had no room.
                    // No icon on it (the leading region has one) and no bar under it (the clock above
                    // says the time): the island is shorter than the Lock Screen card, and a title on
                    // two lines would otherwise push the buttons out of it.
                    VStack(alignment: .leading, spacing: 6) {
                        CardTitle(attributes: context.attributes, state: s, mode: mode, icon: false)
                        // Between rests the set's number rides beside its figures instead of on a
                        // line of its own, for the same reason.
                        let sub = cardSubtitle(context.attributes, s, mode)
                        if mode != .workout && !sub.isEmpty { CardSubtitle(text: sub) }
                        CardBody(attributes: context.attributes, state: s, mode: mode, bar: false, setInline: true)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: icon)
                    .foregroundStyle(accent)
            } compactTrailing: {
                Group {
                    if mode == .workout {
                        Text(s.pendingDone ? "✓" : s.nextDetail)
                    } else {
                        RestClock(attributes: context.attributes, state: s, over: mode == .restOver)
                    }
                }
                .font(.body.monospacedDigit())
                .foregroundStyle(accent)
                .lineLimit(1)
                .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: icon)
                    .foregroundStyle(accent)
            }
            .keylineTint(accent)
            .widgetURL(cardURL(s))
        }
    }
}

/// Where a tap on the card lands (lib/workout-link.js): the workout screen, on the exercise the
/// card shows. The scheme is the app's bundle id — this extension's, less ".RestWidget" — so two
/// builds side by side never open each other.
private func cardURL(_ s: RestActivityAttributes.ContentState) -> URL? {
    guard var app = Bundle.main.bundleIdentifier else { return nil }
    if app.hasSuffix(".RestWidget") { app = String(app.dropLast(".RestWidget".count)) }
    var c = URLComponents()
    c.scheme = app
    c.host = "workout"
    if s.setIdx >= 0 { c.queryItems = [URLQueryItem(name: "idx", value: String(s.setIdx))] }
    return c.url
}

private let appBackground = Color(red: 12 / 255, green: 14 / 255, blue: 18 / 255)

/// The Lock Screen card: the exercise as the title, on a row of its own so a long name is shown
/// whole (two lines at most), then the subtitle with the clock beside it — the rest's countdown,
/// or the time since the workout started — then the body for the mode.
private struct CardLockScreen: View {
    let attributes: RestActivityAttributes
    let state: RestActivityAttributes.ContentState
    let mode: CardMode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle(attributes: attributes, state: state, mode: mode)
            HStack(alignment: .firstTextBaseline) {
                CardSubtitle(text: cardSubtitle(attributes, state, mode))
                Spacer(minLength: 8)
                if mode == .workout {
                    WorkoutClock(state: state)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.65))
                } else {
                    RestClock(attributes: attributes, state: state, over: mode == .restOver)
                        .font(.system(size: 30, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
            CardBody(attributes: attributes, state: state, mode: mode)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

/// The exercise, whole: it wraps onto a second line, and only shrinks a little past that.
private struct CardTitle: View {
    let attributes: RestActivityAttributes
    let state: RestActivityAttributes.ContentState
    let mode: CardMode
    var icon = true

    var body: some View {
        Group {
            if icon {
                Label(cardTitle(attributes, state, mode), systemImage: mode == .workout ? "dumbbell.fill" : "timer")
            } else {
                Text(cardTitle(attributes, state, mode))
            }
        }
            .font(.headline)
            .foregroundStyle(Color.argb(state.accent))
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CardSubtitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.65))
            .lineLimit(1)
    }
}

/// Under the subtitle: the rest's bar and buttons, or the set's figures and Done.
private struct CardBody: View {
    let attributes: RestActivityAttributes
    let state: RestActivityAttributes.ContentState
    let mode: CardMode
    var bar = true
    var setInline = false

    var body: some View {
        switch mode {
        case .rest, .restOver:
            VStack(alignment: .leading, spacing: 8) {
                if bar { RestBar(state: state, over: mode == .restOver) }
                RestButtons(attributes: attributes, state: state, over: mode == .restOver)
            }
        case .workout:
            WorkoutSet(attributes: attributes, state: state, setInline: setInline)
        }
    }
}

/// The set to do now: what it asks for in large type, and Done to tick it (iOS 17). After Done,
/// a check until the page moves the card on to the next set.
private struct WorkoutSet: View {
    let attributes: RestActivityAttributes
    let state: RestActivityAttributes.ContentState
    /// "Set 1/4" beside the figures, where there is no subtitle line to carry it.
    var setInline = false

    var body: some View {
        if !state.nextName.isEmpty {
            let accent = Color.argb(state.accent)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(state.nextDetail)
                    .font(.system(size: 30, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if setInline && !state.nextSet.isEmpty {
                    Text(state.nextSet)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
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
        title: "Rest", doneTitle: "Rest’s over. Next set!",
        pause: "Pause", resume: "Resume", minus: "− 15s", plus: "+ 15s", skip: "Skip", done: "Done",
        sound: true
    )
}

@available(iOS 17.0, *)
private extension RestActivityAttributes.ContentState {
    static func rest(endsIn: Double, left: Double, paused: Bool = false) -> Self {
        Self(resting: true, inWorkout: true, workoutTitle: "Push Day", startedAt: Date().addingTimeInterval(-754),
             endsAt: Date().addingTimeInterval(endsIn), totalSec: 90, leftSec: left, paused: paused,
             accent: 0xFF30D158, ink: 0xFF000000, nextName: "Dumbbell Standing Alternate Hammer Curl", nextSet: "Set 3/4", nextDetail: "14×10",
             setIdx: 0, setI: 2, pendingDone: false)
    }
    static let workout = Self(resting: false, inWorkout: true, workoutTitle: "Push Day", startedAt: Date().addingTimeInterval(-754),
                              endsAt: Date(), totalSec: 1, leftSec: 0, paused: false,
                              accent: 0xFF30D158, ink: 0xFF000000, nextName: "Dumbbell Standing Alternate Hammer Curl", nextSet: "Set 1/4", nextDetail: "14×10",
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
