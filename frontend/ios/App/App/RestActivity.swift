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
    /// The events not yet handed to the page, oldest first: buttons pressed while the app was not
    /// running at all, or before the plugin was up, still reach it on the next launch — every one
    /// of them, in order.
    static let pendingKey = "opengym.rest.pendingEvents"

    static func emit(_ type: String, endsAt: Date?, totalSec: Double, leftSec: Double, paused: Bool) {
        post([
            "type": type,
            "endsAt": endsAt.map { ($0.timeIntervalSince1970 * 1000).rounded() } ?? 0,
            "totalMs": (totalSec * 1000).rounded(),
            "leftMs": (leftSec * 1000).rounded(),
            "paused": paused,
        ])
    }

    /// The workout card's Done, naming the set the card showed (lib/workout-activity.js).
    static func emitSet(_ action: String, idx: Int, i: Int) {
        post(["type": "set", "action": action, "idx": idx, "i": i])
    }

    static func takePending() -> [[String: Any]] {
        let all = UserDefaults.standard.array(forKey: pendingKey) as? [[String: Any]] ?? []
        UserDefaults.standard.removeObject(forKey: pendingKey)
        return all
    }

    private static func post(_ data: [String: Any]) {
        var all = UserDefaults.standard.array(forKey: pendingKey) as? [[String: Any]] ?? []
        all.append(data)
        UserDefaults.standard.set(Array(all.suffix(50)), forKey: pendingKey)
        NotificationCenter.default.post(name: name, object: nil, userInfo: data)
    }
}

#if canImport(ActivityKit)
@available(iOS 16.2, *)
struct RestActivityAttributes: ActivityAttributes, Hashable {
    /// One Live Activity for the whole workout: up from the start of the session with the set to
    /// do now, taken over by each rest's countdown and handed back when the rest is over or
    /// skipped. A rest outside a workout has it to itself and takes it down at its end.
    struct ContentState: Codable, Hashable {
        /// A rest is counting (or held, or just over); false shows the workout and its set.
        var resting: Bool
        /// Up for a workout (lib/workout-activity.js), not only for one rest.
        var inWorkout: Bool
        /// The routine, and when the session started (the elapsed clock).
        var workoutTitle: String
        var startedAt: Date?
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
        /// The set to do now, which during a rest is the one it is for (lib/rest-up-next.js):
        /// "Bench Press", "Set 3/4", "60×8". Empty once every set is ticked.
        var nextName: String
        var nextSet: String
        var nextDetail: String
        /// Where that set is in the session, for Done; -1 when there is none.
        var setIdx: Int
        var setI: Int
        /// Done was pressed and the page has not yet shown the next set.
        var pendingDone: Bool

        func left(at now: Date = Date()) -> Double { paused ? leftSec : max(0, endsAt.timeIntervalSince(now)) }

        /// The countdown's end is what makes it stale; nothing else ages.
        var staleDate: Date? { resting && !paused ? endsAt : nil }

        /// Back to the workout after a rest: the clock is gone, the set stays.
        mutating func endRest() {
            resting = false
            paused = false
            leftSec = 0
        }
    }

    // The labels arrive translated from the page; they are fixed for one Live Activity, and a
    // change to them (a language switch) starts a new one.
    var title: String
    var doneTitle: String
    var pause: String
    var resume: String
    var minus: String
    var plus: String
    var skip: String
    var done: String
    var sound: Bool
}

@available(iOS 16.2, *)
enum RestLive {
    typealias State = RestActivityAttributes.ContentState

    static var current: Activity<RestActivityAttributes>? { Activity<RestActivityAttributes>.activities.first }

    /// Shows this state: moves the Live Activity already up when its labels match, or replaces it.
    /// False when Live Activities are off for the app; a rest's notification is booked either way.
    @discardableResult
    static func show(_ attributes: RestActivityAttributes, _ state: State) async -> Bool {
        let content = ActivityContent(state: state, staleDate: state.staleDate)
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
        await a.update(ActivityContent(state: s, staleDate: s.staleDate))
    }

    static func endAll() async {
        for a in Activity<RestActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
    }

    /// The rest is over, skipped or called off: a workout's card goes back to its set, a lone
    /// rest's card goes away.
    static func finishRest() async {
        guard let a = current else { return }
        var s = a.content.state
        if s.inWorkout {
            s.endRest()
            await a.update(ActivityContent(state: s, staleDate: nil))
        } else {
            await endAll()
        }
    }

    // ---- the workout card's buttons ----

    /// Ticks the set the card shows. The page moves the card on to the next set (and a rest);
    /// until it does, the card shows this one as done.
    static func markDone() async {
        guard let a = current else { return }
        var s = a.content.state
        // A rest that ran out shows the set (the widget's CardMode) before the app has taken the
        // rest down: Done there is a Done on the set, and ends the rest with it.
        let restOver = s.resting && !s.paused && s.endsAt <= Date()
        guard !s.resting || (restOver && s.inWorkout), !s.pendingDone, s.setIdx >= 0 else { return }
        if s.resting {
            RestEnd.cancel()
            s.endRest()
        }
        s.pendingDone = true
        await a.update(ActivityContent(state: s, staleDate: s.staleDate))
        RestEvents.emitSet("done", idx: s.setIdx, i: s.setI)
    }

    // ---- the rest's buttons ----

    static func togglePause() async {
        guard let a = current, a.content.state.resting else { return }
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
        await a.update(ActivityContent(state: s, staleDate: s.staleDate))
        RestEvents.emit("pause", endsAt: s.paused ? nil : s.endsAt, totalSec: s.totalSec, leftSec: s.left(at: now), paused: s.paused)
    }

    static func nudge(_ delta: Double) async {
        guard let a = current, a.content.state.resting else { return }
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
        await a.update(ActivityContent(state: s, staleDate: s.staleDate))
        RestEvents.emit("adjust", endsAt: s.paused ? nil : s.endsAt, totalSec: s.totalSec, leftSec: left, paused: s.paused)
    }

    static func skip() async {
        RestEnd.cancel()
        await finishRest()
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
struct SetDoneIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark the set done"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await RestLive.markDone()
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
