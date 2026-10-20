import { describe, expect, it } from 'vitest'
import { liveSetAction, workoutActivityOf } from './workout-activity.js'

const nameOf = id => ({ bench: 'Bench Press', row: 'Barbell Row' })[id]
const set = (w, r, done = false) => ({ w, r, done })
const session = (extra = {}) => ({
  id: 'w1', name: 'Push Day', start: 1_000, cur: 0,
  entries: [
    { id: 'bench', target: { reps: 8 }, sets: [set(60, 8), set(60, 8), set(60, 8)] },
    { id: 'row', target: { reps: 10 }, sets: [set(50, 10)] },
  ],
  ...extra,
})

describe('workoutActivityOf', () => {
  it('shows the first set with its reps as soon as the workout starts', () => {
    expect(workoutActivityOf({ unit: 'kg', active: session() }, null, { nameOf })).toEqual({
      title: 'Push Day', startedAt: 1_000, name: 'Bench Press', set: 'Set 1/3', detail: '60×8',
      idx: 0, i: 0,
    })
  })

  it('moves on with the sets ticked, and to the next exercise when one is done', () => {
    const a = session()
    a.entries[0].sets[0].done = true
    expect(workoutActivityOf({ active: a }, null, { nameOf })).toMatchObject({ name: 'Bench Press', set: 'Set 2/3' })
    a.entries[0].sets.forEach(s => { s.done = true })
    expect(workoutActivityOf({ active: a }, null, { nameOf })).toMatchObject({ name: 'Barbell Row', set: 'Set 1/1', detail: '50×10' })
  })

  // During a rest the set is the one the rest is for, which follows the exercise that started it.
  it('follows the rest’s owner rather than the marker while resting', () => {
    const a = session({ cur: 1 })
    a.entries[0].sets[0].done = true
    expect(workoutActivityOf({ active: a }, { forIdx: 0 }, { nameOf })).toMatchObject({ name: 'Bench Press', set: 'Set 2/3' })
    expect(workoutActivityOf({ active: a }, null, { nameOf })).toMatchObject({ name: 'Barbell Row' })
  })

  it('keeps the workout up with no set line once everything is ticked', () => {
    const a = session()
    a.entries.forEach(e => e.sets.forEach(s => { s.done = true }))
    expect(workoutActivityOf({ active: a }, null, { nameOf })).toMatchObject({ title: 'Push Day', startedAt: 1_000, name: '', set: '', detail: '', idx: -1 })
  })

  it('shows nothing outside a workout, for an empty one, or while editing a saved one', () => {
    expect(workoutActivityOf({ active: null }, null)).toBeNull()
    expect(workoutActivityOf({ active: session({ entries: [] }) }, null)).toBeNull()
    expect(workoutActivityOf({ active: session({ editingWorkoutId: 'w0' }) }, null, { nameOf })).toBeNull()
  })

  it('falls back to “Workout” for a session without a name', () => {
    expect(workoutActivityOf({ active: session({ name: '' }) }, null, { nameOf }).title).toBe('Workout')
  })
})

describe('the card’s Done', () => {
  it('ticks the set the card showed', () => {
    expect(liveSetAction(session(), { action: 'done', idx: 0, i: 0 })).toEqual({ kind: 'tick', idx: 0, i: 0, side: undefined })
  })

  // A press that reaches the page after the set was ticked in the app, or after the session
  // changed under it, must not land on whatever set sits there now.
  it('does nothing for a set already done or no longer there', () => {
    const a = session()
    a.entries[0].sets[0].done = true
    expect(liveSetAction(a, { action: 'done', idx: 0, i: 0 })).toBeNull()
    expect(liveSetAction(a, { action: 'done', idx: 5, i: 0 })).toBeNull()
    expect(liveSetAction(null, { action: 'done', idx: 0, i: 0 })).toBeNull()
  })

  it('ignores anything that is not a Done', () => {
    expect(liveSetAction(session(), { action: 'reps', idx: 0, i: 0, reps: 9 })).toBeNull()
  })

  it('ticks a unilateral row a side at a time, left first', () => {
    const a = { entries: [{ id: 'lunge', target: { reps: 8 }, sets: [{ w: 20, r: 8, done: false, sides: { L: { r: 8, done: true }, R: { r: 8, done: false } } }] }] }
    expect(liveSetAction(a, { action: 'done', idx: 0, i: 0 })).toMatchObject({ kind: 'tick', side: 'R' })
  })
})
