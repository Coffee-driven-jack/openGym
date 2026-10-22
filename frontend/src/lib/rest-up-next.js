// The set a rest is for, as the Live Activity on the iPhone Lock Screen shows it under the
// countdown: the exercise, which set it is, and what it asks for — "Bench Press · Set 3/4 · 60×8".
//
// A rest starts when a set is ticked (Workout.jsx toggle), and the set it leads into is not always
// the next row of the same exercise:
//   - more sets left on that exercise: its first undone row;
//   - a superset round just closed: the flow has already moved `cur` to the group's next member,
//     which the row after the last member's tick is not;
//   - that exercise is finished: the first unfinished unit after it, as the workout navigates.
// Read straight off the session, so it is a pure helper with its test beside it (CONTRIBUTING).
import { t } from './i18n-core.js'
import { exerciseNameText } from './format.js'
import { exOr } from './exercises.js'
import { setLabel, supersetUnits, unitOf } from './history.js'
import { nextUnfinishedUnit } from './supersetFlow.js'
import { isWarmupRow } from './workout-model.js'

const hasWork = (entries, i) => !!entries[i]?.sets?.some(s => !s.done)

export function restUpNextIndex(active, forIdx) {
  const entries = active?.entries
  if (!Array.isArray(entries) || !entries.length) return null
  const cur = Number.isInteger(active.cur) ? active.cur : null
  // No owner (a rest restarted from Ready without one): the marked exercise is the best guess.
  if (!Number.isInteger(forIdx) || !entries[forIdx]) return cur != null && hasWork(entries, cur) ? cur : null
  const units = supersetUnits(entries)
  const own = unitOf(units, forIdx)
  if (own.length > 1 && own.includes(cur) && hasWork(entries, cur)) return cur
  if (hasWork(entries, forIdx)) return forIdx
  const next = nextUnfinishedUnit(entries, units, forIdx)
  const idx = next?.find(i => hasWork(entries, i))
  return idx ?? null
}

// { name, set, detail } with every part a display string, or null when nothing is left — the
// last set of the workout, or no session at all. `nameOf` is injectable for tests.
export function restUpNext(active, forIdx, { speedUnit, nameOf = id => exerciseNameText(exOr(id)) } = {}) {
  const idx = restUpNextIndex(active, forIdx)
  if (idx == null) return null
  const e = active.entries[idx]
  const sets = e.sets || []
  const s = sets.find(x => !x.done)
  if (!s) return null
  const work = sets.filter(x => !isWarmupRow(x))
  const set = isWarmupRow(s) ? t('Warm-up') : t('Set {0}', `${work.indexOf(s) + 1}/${work.length}`)
  return { name: nameOf(e.id) || '', set, detail: setLabel(e.id, s, e.target, speedUnit) }
}
