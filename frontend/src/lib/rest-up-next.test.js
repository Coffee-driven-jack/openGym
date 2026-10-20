import { describe, expect, it } from 'vitest'
import { restUpNext, restUpNextIndex } from './rest-up-next.js'

const set = (w, r, done = false, extra = {}) => ({ w, r, done, ...extra })
const ex = (id, sets, extra = {}) => ({ id, target: { reps: 8 }, sets, ...extra })
const nameOf = id => ({ bench: 'Bench Press', row: 'Barbell Row', curl: 'Curl', press: 'Overhead Press' })[id]

describe('restUpNextIndex', () => {
  it('stays on the exercise while it has sets left', () => {
    const active = { cur: 0, entries: [ex('bench', [set(60, 8, true), set(60, 8)]), ex('row', [set(50, 8)])] }
    expect(restUpNextIndex(active, 0)).toBe(0)
  })

  it('moves on to the next unfinished exercise once this one is done', () => {
    const active = { cur: 0, entries: [ex('bench', [set(60, 8, true)]), ex('row', [set(50, 8)])] }
    expect(restUpNextIndex(active, 0)).toBe(1)
  })

  // The rest after a superset round is for the group's first member again, where the flow has put
  // `cur` — not for more sets of the member whose tick closed the round.
  it('follows the superset to the member the flow moved to', () => {
    const active = { cur: 0, entries: [
      ex('bench', [set(60, 8, true), set(60, 8)], { sg: 'a' }),
      ex('row', [set(50, 8, true), set(50, 8)], { sg: 'a' }),
    ] }
    expect(restUpNextIndex(active, 1)).toBe(0)
  })

  it('wraps to earlier unfinished work, as the workout does', () => {
    const active = { cur: 2, entries: [ex('bench', [set(60, 8)]), ex('row', [set(50, 8, true)]), ex('curl', [set(12, 10, true)])] }
    expect(restUpNextIndex(active, 2)).toBe(0)
  })

  it('has nothing to show after the last set, or without a session', () => {
    expect(restUpNextIndex({ cur: 0, entries: [ex('bench', [set(60, 8, true)])] }, 0)).toBeNull()
    expect(restUpNextIndex(null, 0)).toBeNull()
    expect(restUpNextIndex({ entries: [] }, 0)).toBeNull()
  })

  it('falls back to the marked exercise when the rest has no owner', () => {
    const active = { cur: 1, entries: [ex('bench', [set(60, 8, true)]), ex('row', [set(50, 8)])] }
    expect(restUpNextIndex(active, undefined)).toBe(1)
  })
})

describe('restUpNext', () => {
  it('names the exercise, counts work sets only, and says what the set asks for', () => {
    const active = { cur: 0, entries: [ex('bench', [set(40, 8, true, { phase: 'warmup' }), set(60, 8, true), set(60, 8), set(60, 8)])] }
    expect(restUpNext(active, 0, { nameOf })).toEqual({ name: 'Bench Press', set: 'Set 2/3', detail: '60×8' })
  })

  it('calls a warm-up row a warm-up', () => {
    const active = { cur: 1, entries: [ex('bench', [set(60, 8, true)]), ex('press', [set(20, 10, false, { phase: 'warmup' }), set(40, 8)])] }
    expect(restUpNext(active, 0, { nameOf })).toEqual({ name: 'Overhead Press', set: 'Warm-up', detail: '20×10' })
  })

  it('shows a timed hold as its duration', () => {
    const active = { cur: 0, entries: [{ id: 'plank', target: { mode: 'time', sec: 60 }, sets: [{ sec: 60, w: 0, done: true }, { sec: 45, w: 0, done: false }] }] }
    expect(restUpNext(active, 0, { nameOf: () => 'Plank' })).toEqual({ name: 'Plank', set: 'Set 2/2', detail: '0:45' })
  })

  it('is null when the workout has nothing left', () => {
    expect(restUpNext({ cur: 0, entries: [ex('bench', [set(60, 8, true)])] }, 0, { nameOf })).toBeNull()
  })
})
