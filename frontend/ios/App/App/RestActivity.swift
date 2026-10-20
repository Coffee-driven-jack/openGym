import Foundation
import UserNotifications
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(AppIntents)
import AppIntents
#endif

// The rest countdown on the Lock Screen and in the Dynamic Island: the iOS counterpart of the
// Android rest notification (RestTimerService.java). This file is in both targets — the app,
// which starts and moves the Live Activity, and RestWidget, which draws it. The buttons' intents
// are LiveActivityIntents, so the system runs them in the app's process (launched in the
// background if it has to be), never in the widget's: everything here that acts runs in the app.

/// What the end-of-rest notification needs, kept outside the Live Activity: it must still fire
/// with Live Activities switched off, and on an iOS too old to have them.
enum RestEnd {
    static let notificationId = "opengym.rest-over"
    private static let key = "opengym.rest.end"

    /// Set by RestAlertPlugin. With the app in front the page plays the end itself, so the
    /// notification is only handed to the system while the app is away; a cold launch by one of
    /// the buttons leaves it false, which is what it is then.
    static var appInFront = false

    struct Booking: Codable {
        var at: Date
        var title: String
        var sound: Bool
    }

    static var booking: Booking? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Booking.self, from: d)
    }

    static func book(at: Date, title: String, sound: Bool) {
        let b = Booking(at: at, title: title, sound: sound)
        if let d = try? JSONEncoder().encode(b) { UserDefaults.standard.set(d, forKey: key) }
        if appInFront { withdraw() } else { post(b) }
    }

    /// Off the books entirely: Skip, Dismiss, a pause.
    static func cancel() {
        UserDefaults.standard.removeObject(forKey: key)
        withdraw()
    }

    /// The app came to the front: the page takes the end over, the booking stays for when it leaves.
    static func withdraw() {
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: [notificationId])
        c.removeDeliveredNotifications(withIdentifiers: [notificationId])
    }

    /// The app went away: an end still ahead goes to the system.
    static func postIfBooked() {
        if let b = booking, b.at > Date() { post(b) }
    }

    private static func post(_ b: Booking) {
        let content = UNMutableNotificationContent()
        content.title = b.title
        if b.sound { content.sound = .default }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, b.at.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger))
    }
}

/// What the buttons did, for the page to mirror in its bar — the same event the Android
/// notification sends (RestAlertPlugin.emit): type, endsAt and the times in milliseconds.
enum RestEvents {
    static let name = Notification.Name("opengym.rest.event")
    /// The last event not yet handed to the page: a button pressed while the app was not running
    /// at all, or before the plugin was up, still reaches it on the next launch.
    static let pendingKey = "opengym.rest.pendingEvent"

    static func emit(_ type: String, endsAt: Date?, totalSec: Double, leftSec: Double, paused: Bool) {
        let data: [String: Any] = [
            "type": type,
            "endsAt": endsAt.map { ($0.timeIntervalSince1970 * 1000).rounded() } ?? 0,
            "totalMs": (totalSec * 1000).rounded(),
            "leftMs": (leftSec * 1000).rounded(),
            "paused": paused,
        ]
        UserDefaults.standard.set(data, forKey: pendingKey)
        NotificationCenter.default.post(name: name, object: nil, userInfo: data)
    }
}

#if canImport(ActivityKit)
@available(iOS 16.2, *)
struct RestActivityAttributes: ActivityAttributes, Hashable {
    struct ContentState: Codable, Hashable {
        /// The end of the countdown while it runs.
        var endsAt: Date
        /// The whole rest, for the bar; ±15 s moves it with the time left, as on Android.
        var totalSec: Double
        /// The time held while paused.
        var leftSec: Double
        var paused: Bool
        /// ARGB, as the page sends it (lib/rest-alert.js accentColors).
        var accent: UInt32
        var ink: UInt32
        /// The set this rest is for (lib/rest-up-next.js): "Bench Press", "Set 3/4", "60×8".
        /// Empty after the last set of the workout.
        var nextName: String
        var nextSet: String
        var nextDetail: String

        func left(at now: Date = Date()) -> Double { paused ? leftSec : max(0, endsAt.timeIntervalSince(now)) }
    }

    // The labels arrive translated from the page; they are fixed for one Live Activity, and a
    // rest that changes them (a language switch) starts a new one.
    var title: String
    var doneTitle: String
    var pause: String
    var resume: String
    var minus: String
    var plus: String
    var skip: String
    var sound: Bool
}

@available(iOS 16.2, *)
enum RestLive {
    typealias State = RestActivityAttributes.ContentState

    static var current: Activity<RestActivityAttributes>? { Activity<RestActivityAttributes>.activities.first }

    /// Shows this rest: moves the Live Activity already up when its labels match, or replaces it.
    /// False when Live Activities are off for the app; the notification is booked either way.
    @discardableResult
    static func show(_ attributes: RestActivityAttributes, _ state: State) async -> Bool {
        let content = ActivityContent(state: state, staleDate: state.paused ? nil : state.endsAt)
        let all = Activity<RestActivityAttributes>.activities
        if let a = all.first, a.attributes == attributes, a.activityState == .active {
            for other in all.dropFirst() { await other.end(nil, dismissalPolicy: .immediate) }
            await a.update(content)
            return true
        }
        for a in all { await a.end(nil, dismissalPolicy: .immediate) }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        do {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            return true
        } catch {
            return false
        }
    }

    static func update(_ change: (inout State) -> Void) async {
        guard let a = current else { return }
        var s = a.content.state
        change(&s)
        await a.update(ActivityContent(state: s, staleDate: s.paused ? nil : s.endsAt))
    }

    static func endAll() async {
        for a in Activity<RestActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
    }

    // ---- the buttons ----

    static func togglePause() async {
        guard let a = current else { return }
        var s = a.content.state
        let now = Date()
        if s.paused {
            s.endsAt = now.addingTimeInterval(s.leftSec)
            s.paused = false
            RestEnd.book(at: s.endsAt, title: a.attributes.doneTitle, sound: a.attributes.sound)
        } else {
            let left = s.left(at: now)
            if left <= 0 { return }   // already over; nothing left to hold
            s.leftSec = left
            s.paused = true
            RestEnd.cancel()
        }
        await a.update(ActivityContent(state: s, staleDate: s.paused ? nil : s.endsAt))
        RestEvents.emit("pause", endsAt: s.paused ? nil : s.endsAt, totalSec: s.totalSec, leftSec: s.left(at: now), paused: s.paused)
    }

    static func nudge(_ delta: Double) async {
        guard let a = current else { return }
        var s = a.content.state
        let now = Date()
        // endsAt may already be behind us when +15 lands on the last second: count from now.
        let left = s.left(at: now) + delta
        if left <= 0 { await skip(); return }
        s.totalSec = max(1, s.totalSec + delta)
        if s.paused {
            s.leftSec = left
        } else {
            s.endsAt = now.addingTimeInterval(left)
            RestEnd.book(at: s.endsAt, title: a.attributes.doneTitle, sound: a.attributes.sound)
        }
        await a.update(ActivityContent(state: s, staleDate: s.paused ? nil : s.endsAt))
        RestEvents.emit("adjust", endsAt: s.paused ? nil : s.endsAt, totalSec: s.totalSec, leftSec: left, paused: s.paused)
    }

    static func skip() async {
        RestEnd.cancel()
        await endAll()
        RestEvents.emit("skip", endsAt: nil, totalSec: 0, leftSec: 0, paused: false)
    }
}

#if canImport(AppIntents)
@available(iOS 17.0, *)
struct RestPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or resume the rest"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await RestLive.togglePause()
        return .result()
    }
}

@available(iOS 17.0, *)
struct RestNudgeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Change the rest"
    static var isDiscoverable = false

    @Parameter(title: "Seconds")
    var seconds: Int

    init() {}
    init(seconds: Int) { self.seconds = seconds }

    func perform() async throws -> some IntentResult {
        await RestLive.nudge(Double(seconds))
        return .result()
    }
}

@available(iOS 17.0, *)
struct RestSkipIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip the rest"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await RestLive.skip()
        return .result()
    }
}
#endif
#endif
