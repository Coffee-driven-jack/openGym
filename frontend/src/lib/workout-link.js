// A tap on the iOS Live Activity (RestWidget's widgetURL) opens the app on the exercise the card
// shows: `<bundle id>://workout?idx=2`. The scheme is the app's own bundle id, so a test build
// and the store app side by side never answer each other's links. `idx` is the entry the card
// named (lib/workout-activity.js); without one — a rest outside a workout — the link only opens
// the workout screen.
import { useStore } from '../store/useStore.js'
import { navToWorkout } from './nav.js'

// { idx } with idx an entry index or null, or null when the link is not a workout link.
export function workoutLinkOf(url) {
  let u
  try { u = new URL(String(url)) } catch { return null }
  const where = (u.host || u.pathname.replace(/^\/+/, '')).toLowerCase()
  if (where !== 'workout') return null
  const raw = u.searchParams.get('idx')
  const idx = raw != null && /^\d+$/.test(raw) ? Number(raw) : null
  return { idx }
}

// Selects the exercise the link names and shows the workout. Nothing without a session to show,
// and the selection stays as it is when the entry is gone (the session changed since).
export function openWorkoutLink(url) {
  const link = workoutLinkOf(url)
  if (!link) return false
  const { S, update } = useStore.getState()
  const a = S.active
  if (!a || a.editingWorkoutId) return false
  if (link.idx != null && a.entries?.[link.idx] && a.cur !== link.idx) {
    update(s => { if (s.active) s.active.cur = link.idx })
  }
  navToWorkout()
  return true
}

// The app opened by a link (a cold start: the launch URL), or brought back by one (appUrlOpen).
let started = false
export function initWorkoutLinks() {
  if (started) return
  started = true
  import('@capacitor/app').then(({ App }) => {
    App.addListener('appUrlOpen', ev => { openWorkoutLink(ev?.url) })
    App.getLaunchUrl().then(r => {
      if (!r?.url || openWorkoutLink(r.url)) return
      // A cold start can reach here before the session is read back: try again once it is.
      const stop = useStore.subscribe(st => { if (st.S?.active && openWorkoutLink(r.url)) stop() })
      setTimeout(stop, 10_000)
    }).catch(() => {})
  }).catch(() => {})
}
