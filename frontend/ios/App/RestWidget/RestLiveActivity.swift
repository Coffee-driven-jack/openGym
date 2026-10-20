import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// The rest countdown as the Lock Screen and the Dynamic Island show it: the in-app shape, a clock
// and a shrinking bar in the accent colour, plus the Android notification's buttons (iOS 17 and
// later; the intents live in App/RestActivity.swift). The system runs the clock and the bar itself
// from the end date, so nothing has to wake the app every second.

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
            // clock and the secondary buttons are white, and a translucent tint lets a light
            // wallpaper wash them out.
            RestLockScreen(attributes: context.attributes, state: context.state, over: context.isStale)
                .background(appBackground)
                .activityBackgroundTint(appBackground)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            let accent = Color.argb(s.accent)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.title, systemImage: "timer")
                        .font(.headline)
                        .foregroundStyle(accent)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestClock(attributes: context.attributes, state: s, over: context.isStale)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        RestUpNext(state: s)
                            .padding(.horizontal, 4)
                        RestBar(state: s, over: context.isStale)
                        RestButtons(attributes: context.attributes, state: s, over: context.isStale)
                    }
                }
            } compactLeading: {
                Image(systemName: s.paused ? "pause.fill" : "timer")
                    .foregroundStyle(accent)
            } compactTrailing: {
                RestClock(attributes: context.attributes, state: s, over: context.isStale)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(accent)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: s.paused ? "pause.fill" : "timer")
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

// ---- Previews (Xcode canvas): running, paused and over, in each place the system shows it ----

#if DEBUG
@available(iOS 17.0, *)
private extension RestActivityAttributes {
    static let preview = RestActivityAttributes(
        title: "Rest", doneTitle: "Rest over — next set!",
        pause: "Pause", resume: "Resume", minus: "− 15s", plus: "+ 15s", skip: "Skip",
        sound: true
    )
}

@available(iOS 17.0, *)
private extension RestActivityAttributes.ContentState {
    static let running = Self(endsAt: Date().addingTimeInterval(75), totalSec: 90, leftSec: 75, paused: false, accent: 0xFF30D158, ink: 0xFF000000, nextName: "Bench Press", nextSet: "Set 3/4", nextDetail: "60×8")
    static let paused = Self(endsAt: Date(), totalSec: 90, leftSec: 42, paused: true, accent: 0xFF30D158, ink: 0xFF000000, nextName: "Bench Press", nextSet: "Set 3/4", nextDetail: "60×8")
    static let over = Self(endsAt: Date().addingTimeInterval(-1), totalSec: 90, leftSec: 0, paused: false, accent: 0xFF30D158, ink: 0xFF000000, nextName: "Bench Press", nextSet: "Set 3/4", nextDetail: "60×8")
}

@available(iOS 17.0, *)
#Preview("Lock Screen", as: .content, using: RestActivityAttributes.preview) {
    RestLiveActivity()
} contentStates: {
    RestActivityAttributes.ContentState.running
    RestActivityAttributes.ContentState.paused
    RestActivityAttributes.ContentState.over
}

@available(iOS 17.0, *)
#Preview("Dynamic Island expanded", as: .dynamicIsland(.expanded), using: RestActivityAttributes.preview) {
    RestLiveActivity()
} contentStates: {
    RestActivityAttributes.ContentState.running
    RestActivityAttributes.ContentState.paused
}

@available(iOS 17.0, *)
#Preview("Dynamic Island compact", as: .dynamicIsland(.compact), using: RestActivityAttributes.preview) {
    RestLiveActivity()
} contentStates: {
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
