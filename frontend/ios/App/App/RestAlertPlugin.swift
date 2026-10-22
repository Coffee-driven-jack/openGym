import Foundation
import Capacitor
import UIKit
import UserNotifications
#if canImport(ActivityKit)
import ActivityKit
#endif

/**
 * The rest timer outside the WebView, on iOS: the Live Activity on the Lock Screen and in the
 * Dynamic Island (RestActivity.swift, drawn by the RestWidget extension), and the "rest over"
 * notification for when the app is not in front. The same calls as the Android plugin
 * (RestAlertPlugin.java), so lib/rest-alert.js drives both alike.
 *
 * Usage from JS:
 *   import { registerPlugin } from '@capacitor/core';
 *   const RestAlert = registerPlugin('RestAlert');
 *   await RestAlert.schedule({ at, totalMs, title, countdownTitle, sound, accent, ink, pause, resume, minus, plus, skip,
 *                              nextName, nextSet, nextDetail });
 *   await RestAlert.hold({ leftMs, totalMs });
 *   await RestAlert.setAccent({ accent, ink });
 *   await RestAlert.cancel({});
 *   await RestAlert.showSet({ workoutTitle, startedAt, nextName, nextSet, nextDetail, accent, ink, …labels });
 *   await RestAlert.endWorkout({});
 *   RestAlert.addListener('rest', ev => …)   // what the Live Activity's buttons did
 */
@objc(RestAlertPlugin)
public class RestAlertPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "RestAlertPlugin"
    public let jsName = "RestAlert"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "schedule", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "cancel", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "hold", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setAccent", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "showSet", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "endWorkout", returnType: CAPPluginReturnPromise),
    ]

    /// With the app in front, the end of the rest takes the Live Activity down: the page plays
    /// the end and shows its own toast. Away, the activity stays up showing "rest over" until the
    /// app returns or the next rest replaces it.
    private var endTimer: Timer?

    override public func load() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(onRestEvent(_:)), name: RestEvents.name, object: nil)
        nc.addObserver(self, selector: #selector(onActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(onBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        DispatchQueue.main.async {
            RestEnd.appInFront = UIApplication.shared.applicationState == .active
            if RestEnd.appInFront { self.onActive() }
        }
        // Buttons pressed while the app was not running: retained until the page listens.
        for pending in RestEvents.takePending() {
            notifyListeners("rest", data: pending, retainUntilConsumed: true)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func onRestEvent(_ note: Notification) {
        // Up and listening: this event goes now, and the queue held for a later launch is not needed.
        _ = RestEvents.takePending()
        notifyListeners("rest", data: note.userInfo as? [String: Any] ?? [:], retainUntilConsumed: true)
    }

    @objc private func onActive() {
        RestEnd.appInFront = true
        RestEnd.withdraw()
        guard #available(iOS 16.2, *), let a = RestLive.current else { return }
        let s = a.content.state
        if !s.resting || s.paused { return }
        if s.endsAt <= Date() {
            Task { await RestLive.finishRest() }
        } else {
            armEndTimer(s.endsAt)
        }
    }

    @objc private func onBackground() {
        RestEnd.appInFront = false
        endTimer?.invalidate()
        endTimer = nil
        RestEnd.postIfBooked()
    }

    private func armEndTimer(_ at: Date?) {
        DispatchQueue.main.async {
            self.endTimer?.invalidate()
            self.endTimer = nil
            guard let at = at, RestEnd.appInFront else { return }
            let t = Timer(fire: at, interval: 0, repeats: false) { _ in
                guard #available(iOS 16.2, *) else { return }
                Task {
                    // Only if this is still the rest that was running: a pause or ±15 s moved it.
                    guard let s = RestLive.current?.content.state, s.resting, !s.paused, s.endsAt <= Date().addingTimeInterval(0.5) else { return }
                    await RestLive.finishRest()
                }
            }
            RunLoop.main.add(t, forMode: .common)
            self.endTimer = t
        }
    }

    @available(iOS 16.2, *)
    private static func attributes(_ call: CAPPluginCall) -> RestActivityAttributes {
        RestActivityAttributes(
            title: call.getString("countdownTitle") ?? "Rest",
            doneTitle: call.getString("title") ?? "Rest over",
            pause: call.getString("pause") ?? "Pause",
            resume: call.getString("resume") ?? "Resume",
            minus: call.getString("minus") ?? "\u{2212} 15s",
            plus: call.getString("plus") ?? "+ 15s",
            skip: call.getString("skip") ?? "Skip",
            done: call.getString("done") ?? "Done",
            sound: call.getBool("sound") ?? true
        )
    }

    @objc func schedule(_ call: CAPPluginCall) {
        let atMs = call.getDouble("at") ?? -1
        let at = Date(timeIntervalSince1970: atMs / 1000)
        if at <= Date() {
            call.reject("at must be in the future")
            return
        }
        let title = call.getString("title") ?? "Rest over"
        let sound = call.getBool("sound") ?? true
        let totalSec = max(1, (call.getDouble("totalMs") ?? at.timeIntervalSinceNow * 1000) / 1000)
        RestEnd.book(at: at, title: title, sound: sound)
        armEndTimer(at)

        guard #available(iOS 16.2, *) else {
            call.resolve(["live": false])
            return
        }
        // A rest inside a workout keeps the workout's card: its title and clock come back after.
        let workout = RestLive.current?.content.state
        let inWorkout = workout?.inWorkout ?? false
        let state = RestActivityAttributes.ContentState(
            resting: true,
            inWorkout: inWorkout,
            workoutTitle: inWorkout ? workout?.workoutTitle ?? "" : "",
            startedAt: inWorkout ? workout?.startedAt : nil,
            endsAt: at,
            totalSec: totalSec,
            leftSec: at.timeIntervalSinceNow,
            paused: false,
            accent: Self.color(call, "accent", 0xFF30D158),
            ink: Self.color(call, "ink", 0xFF000000),
            nextName: call.getString("nextName") ?? "",
            nextSet: call.getString("nextSet") ?? "",
            nextDetail: call.getString("nextDetail") ?? "",
            // The set the rest is for is the one the workout card already shows (the page brings it
            // just before the rest starts): its place carries over, so Done is there again when
            // the rest is over.
            setIdx: inWorkout ? workout?.setIdx ?? -1 : -1,
            setI: inWorkout ? workout?.setI ?? -1 : -1,
            pendingDone: false
        )
        Task {
            let live = await RestLive.show(Self.attributes(call), state)
            call.resolve(["live": live])
        }
    }

    /// Skip, Dismiss, a rest replaced or switched off. A workout's card goes back to its set.
    @objc func cancel(_ call: CAPPluginCall) {
        RestEnd.cancel()
        armEndTimer(nil)
        guard #available(iOS 16.2, *) else { call.resolve(); return }
        Task {
            await RestLive.finishRest()
            call.resolve()
        }
    }

    /// The workout (lib/workout-activity.js): its title, start and the set to do now. Put up when
    /// a session starts; during a rest only the set and the title are brought up to date, and the
    /// countdown stays.
    @objc func showSet(_ call: CAPPluginCall) {
        guard #available(iOS 16.2, *) else { call.resolve(["live": false]); return }
        let title = call.getString("workoutTitle") ?? ""
        let startedMs = call.getDouble("startedAt") ?? 0
        let startedAt = startedMs > 0 ? Date(timeIntervalSince1970: startedMs / 1000) : nil
        let name = call.getString("nextName") ?? ""
        let set = call.getString("nextSet") ?? ""
        let detail = call.getString("nextDetail") ?? ""
        let setIdx = call.getInt("setIdx") ?? -1
        let setI = call.getInt("setI") ?? -1
        let accent = Self.color(call, "accent", 0xFF30D158)
        let ink = Self.color(call, "ink", 0xFF000000)
        Task {
            if let a = RestLive.current, a.activityState == .active, a.content.state.resting {
                await RestLive.update { s in
                    s.inWorkout = true
                    s.workoutTitle = title
                    s.startedAt = startedAt
                    s.nextName = name
                    s.nextSet = set
                    s.nextDetail = detail
                    s.setIdx = setIdx
                    s.setI = setI
                    s.pendingDone = false
                }
                call.resolve(["live": true])
                return
            }
            let state = RestActivityAttributes.ContentState(
                resting: false,
                inWorkout: true,
                workoutTitle: title,
                startedAt: startedAt,
                endsAt: Date(),
                totalSec: 1,
                leftSec: 0,
                paused: false,
                accent: accent,
                ink: ink,
                nextName: name,
                nextSet: set,
                nextDetail: detail,
                setIdx: setIdx,
                setI: setI,
                pendingDone: false
            )
            let live = await RestLive.show(Self.attributes(call), state)
            call.resolve(["live": live])
        }
    }

    /// The workout finished or was discarded: its card goes, with any rest still on it.
    @objc func endWorkout(_ call: CAPPluginCall) {
        RestEnd.cancel()
        armEndTimer(nil)
        guard #available(iOS 16.2, *) else { call.resolve(); return }
        Task {
            await RestLive.endAll()
            call.resolve()
        }
    }

    /// Paused in the app (#193): the end is called off and the clock holds at the time the app
    /// shows. Resuming in the app schedules the new end, which restarts it.
    @objc func hold(_ call: CAPPluginCall) {
        RestEnd.cancel()
        armEndTimer(nil)
        let leftSec = max(1, (call.getDouble("leftMs") ?? 0) / 1000)
        let totalSec = max(leftSec, (call.getDouble("totalMs") ?? 0) / 1000)
        guard #available(iOS 16.2, *) else { call.resolve(); return }
        Task {
            await RestLive.update { s in
                guard s.resting else { return }
                s.paused = true
                s.leftSec = leftSec
                s.totalSec = totalSec
            }
            call.resolve()
        }
    }

    @objc func setAccent(_ call: CAPPluginCall) {
        let accent = Self.color(call, "accent", 0xFF30D158)
        let ink = Self.color(call, "ink", 0xFF000000)
        guard #available(iOS 16.2, *) else { call.resolve(); return }
        Task {
            await RestLive.update { s in
                s.accent = accent
                s.ink = ink
            }
            call.resolve()
        }
    }

    // ARGB from the page; a JS number arrives as a Double.
    private static func color(_ call: CAPPluginCall, _ name: String, _ fallback: UInt32) -> UInt32 {
        guard let d = call.getDouble(name) else { return fallback }
        return UInt32(truncatingIfNeeded: Int64(d))
    }
}
