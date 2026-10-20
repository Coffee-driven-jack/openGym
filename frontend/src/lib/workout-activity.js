// What the iOS Live Activity shows for the workout as a whole, from the moment it starts to its
// finish or discard: the routine, how long it has run, and the set to do now with what it asks
// for — "Bench Press · Set 1/4 · 60×8". Rests take the same Live Activity over with their
// countdown (lib/rest-alert.js); this is what it goes back to between them.
//
// The set to do now follows the exercise selected in the app (S.active.cur), rests included: its
// next undone set, or the next unfinished exercise once that one is done. Every way the app moves
// on — a swipe, the list, a chip, the superset flow after a round — sets `cur`, so the card is on
// the exercise the app shows. Read straight off the session, so it is a pure helper beside its test.
//
// The card's Done ticks that set from the Lock Screen. Each press names the set it was shown —
// entry and row — so one that reaches the page late, after the set moved on, never lands on
// another set (liveSetAction below).
import { t } from './i18n-core.js'
import { restUpNext, restUpNextIndex } from './rest-up-next.js'
import { speedUnitOf } from './speed.js'
import { isSideSet } from './workout-model.js'

// null when there is nothing to show: no session, an empty one, or the editor of a saved
// workout (it reuses S.active, but nobody is training).
export function workoutActivityOf(S, { nameOf } = {}) {
  const a = S?.active
  if (!a || a.editingWorkoutId || !Array.isArray(a.entries) || !a.entries.length) return null
  const forIdx = a.cur
  const speedUnit = speedUnitOf(S)
  const next = restUpNext(a, forIdx, { speedUnit, ...(nameOf ? { nameOf } : {}) })
  const idx = next ? restUpNextIndex(a, forIdx) : null
  const entry = idx == null ? null : a.entries[idx]
  const i = entry ? entry.sets.findIndex(s => !s.done) : -1
  return {
    title: a.name || t('Workout'),
    startedAt: Number.isFinite(a.start) ? a.start : 0,
    name: next?.name || '',
    set: next?.set || '',
    detail: next?.detail || '',
    // Where the set is, for Done; -1 when there is none.
    idx: idx ?? -1,
    i,
  }
}

// What a Done on the card asks of the session: { kind: 'tick', idx, i, side } to tick the set as
// the workout screen would, or null when the set it named is gone or already done — the press
// then does nothing.
export function liveSetAction(active, ev) {
  if (ev?.action !== 'done') return null
  const set = active?.entries?.[ev.idx]?.sets?.[ev.i]
  if (!set || set.done) return null
  // A unilateral row is ticked a side at a time, left first, as a key press ticks it.
  const side = isSideSet(set) ? (set.sides.L.done ? 'R' : 'L') : undefined
  return { kind: 'tick', idx: ev.idx, i: ev.i, side }
}
