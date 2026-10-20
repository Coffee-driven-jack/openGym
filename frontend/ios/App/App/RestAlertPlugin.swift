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
        // A button pressed while the app was not running: retained until the page listens.
        if let pending = UserDefaults.standard.dictionary(forKey: RestEvents.pendingKey) {
            UserDefaults.standard.removeObject(forKey: RestEvents.pendingKey)
            notifyListeners("rest", data: pending, retainUntilConsumed: true)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func onRestEvent(_ note: Notification) {
        UserDefaults.standard.removeObject(forKey: RestEvents.pendingKey)
        notifyListeners("rest", data: note.userInfo as? [String: Any] ?? [:], retainUntilConsumed: true)
    }

    @objc private func onActive() {
        RestEnd.appInFront = true
        RestEnd.withdraw()
        guard #available(iOS 16.2, *), let a = RestLive.current else { return }
        let s = a.content.state
        if s.paused { return }
        if s.endsAt <= Date() {
            Task { await RestLive.endAll() }
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
                    guard let s = RestLive.current?.content.state, !s.paused, s.endsAt <= Date().addingTimeInterval(0.5) else { return }
                    await RestLive.endAll()
                }
            }
            RunLoop.main.add(t, forMode: .common)
            self.endTimer = t
        }
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
        let attributes = RestActivityAttributes(
            title: call.getString("countdownTitle") ?? "Rest",
            doneTitle: title,
            pause: call.getString("pause") ?? "Pause",
            resume: call.getString("resume") ?? "Resume",
            minus: call.getString("minus") ?? "\u{2212} 15s",
            plus: call.getString("plus") ?? "+ 15s",
            skip: call.getString("skip") ?? "Skip",
            sound: sound
        )
        let state = RestActivityAttributes.ContentState(
            endsAt: at,
            totalSec: totalSec,
            leftSec: at.timeIntervalSinceNow,
            paused: false,
            accent: Self.color(call, "accent", 0xFF30D158),
            ink: Self.color(call, "ink", 0xFF000000),
            nextName: call.getString("nextName") ?? "",
            nextSet: call.getString("nextSet") ?? "",
            nextDetail: call.getString("nextDetail") ?? ""
        )
        Task {
            let live = await RestLive.show(attributes, state)
            call.resolve(["live": live])
        }
    }

    @objc func cancel(_ call: CAPPluginCall) {
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
