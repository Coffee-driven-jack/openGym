// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({ nav: vi.fn() }))
vi.mock('./nav.js', () => ({ navToWorkout: h.nav }))

import { openWorkoutLink, workoutLinkOf } from './workout-link.js'
import { useStore } from '../store/useStore.js'

describe('workoutLinkOf', () => {
  it('reads the entry from the Live Activity’s link, whatever the bundle id', () => {
    expect(workoutLinkOf('ch.duartesantos.opengym://workout?idx=2')).toEqual({ idx: 2 })
    expect(workoutLinkOf('org.example.opengym://workout?idx=0')).toEqual({ idx: 0 })
  })

  it('opens the workout without choosing an exercise when the link names none', () => {
    expect(workoutLinkOf('ch.duartesantos.opengym://workout')).toEqual({ idx: null })
    expect(workoutLinkOf('ch.duartesantos.opengym://workout?idx=-1')).toEqual({ idx: null })
  })

  it('is not a workout link otherwise', () => {
    expect(workoutLinkOf('ch.duartesantos.opengym://pair?code=1')).toBeNull()
    expect(workoutLinkOf('not a url')).toBeNull()
    expect(workoutLinkOf(undefined)).toBeNull()
  })
})

describe('openWorkoutLink', () => {
  const session = () => ({ id: 'w', cur: 0, entries: [
    { id: 'a', sets: [{ w: 60, r: 8, done: false }] },
    { id: 'b', sets: [{ w: 40, r: 10, done: false }] },
  ] })
  beforeEach(() => { h.nav.mockClear() })

  it('selects the exercise the card showed and opens the workout', () => {
    useStore.setState({ S: { ...useStore.getState().S, active: session() } })
    expect(openWorkoutLink('x.opengym://workout?idx=1')).toBe(true)
    expect(useStore.getState().S.active.cur).toBe(1)
    expect(h.nav).toHaveBeenCalled()
  })

  it('leaves the selection alone for an entry that is gone', () => {
    useStore.setState({ S: { ...useStore.getState().S, active: session() } })
    openWorkoutLink('x.opengym://workout?idx=7')
    expect(useStore.getState().S.active.cur).toBe(0)
    expect(h.nav).toHaveBeenCalled()
  })

  it('does nothing without a session, or while a saved workout is being edited', () => {
    useStore.setState({ S: { ...useStore.getState().S, active: null } })
    expect(openWorkoutLink('x.opengym://workout?idx=1')).toBe(false)
    useStore.setState({ S: { ...useStore.getState().S, active: { ...session(), editingWorkoutId: 'w0' } } })
    expect(openWorkoutLink('x.opengym://workout?idx=1')).toBe(false)
    expect(h.nav).not.toHaveBeenCalled()
  })
})
