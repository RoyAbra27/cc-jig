import { expect, test } from 'claude-code/testing'
import { propose, stateOf } from './register'

const msgs = [
  { role: 'user', text: 'finish the migration', toolUses: [] },
  { role: 'assistant', text: 'Working on it', toolUses: [{ tool: 'TodoWrite', input: { todos: [{ content: 'a', status: 'completed' }, { content: 'b', status: 'in_progress' }] } }] },
]

test('state: open todos from the last TodoWrite, last exchange', async () => {
  const st = stateOf(msgs, '2026-11-25')
  expect(st.todos.length).toBe(2)
  const { content, diff } = propose('# Tasks\n- [x] old\n', st)
  expect(content.startsWith('# Tasks\n- [x] old\n')).toBe(true)
  expect(diff).toContain('+- [ ] b (in progress)')
  expect(diff).not.toContain('+- [ ] a')
  expect(propose('', stateOf([], 'd')).diff).toContain('(new file)')
})

function setup(on: (...a: never[]) => unknown, stub: { percent: number; choice: string; writes: string[] }) {
  const o = on as unknown as (n: string, h: (_: unknown, e: never) => unknown) => void
  o('turn.complete', (_, e: never) => e)
  o('session.usage', () => ({ value: { context: { window: 1000, percent: stub.percent }, startedAt: 0 } }))
  o('session.root', () => ({ value: 'C:/repo' }))
  o('fs.exists', () => ({ value: false }))
  o('session.messages', () => ({ value: msgs }))
  o('clock.now', () => ({ value: 0 }))
  o('ui.log', () => ({ value: undefined }))
  o('tool.call', () => ({ result: { questions: [], answers: { 'Write this update to TASKS.md before the context compacts?': stub.choice } } }))
  o('fs.write', (_, e: never) => {
    stub.writes.push((e as { path: string }).path)
    return { value: undefined }
  })
}

const turn = { text: 'x', answer: 'done', reason: 'answer', durationMs: 1, turnId: 't' } as never

test('at 65% and Write: TASKS.md is written once, never again that session', async ($, on) => {
  const stub = { percent: 70, choice: 'Write', writes: [] as string[] }
  setup(on as never, stub)
  await $.turn.complete(turn)
  for (let k = 0; k < 500; k++) await Promise.resolve()
  await $.turn.complete(turn)
  for (let k = 0; k < 500; k++) await Promise.resolve()
  expect(stub.writes.map(w => w.split('\\').join('/'))).toEqual(['C:/repo/TASKS.md'])
})

test('Skip, or under 65%, writes nothing', async ($, on) => {
  const stub = { percent: 70, choice: 'Skip', writes: [] as string[] }
  setup(on as never, stub)
  await $.turn.complete(turn)
  for (let k = 0; k < 500; k++) await Promise.resolve()
  expect(stub.writes).toEqual([])
})
