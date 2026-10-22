// The workout screen's own tick, lent to the iOS Live Activity's Done button (lib/workout-activity
// liveSetAction). Workout.jsx binds it while it is mounted, so a press on the Lock Screen goes
// through the same toggle() a tap does — the rest it starts, the beep, the next exercise, the
// end of the workout. Away from that screen nothing is bound, and the store is ticked directly.
let tick = null

export function bindLiveTick(fn) {
  tick = fn
  return () => { if (tick === fn) tick = null }
}

export const liveTick = () => tick
