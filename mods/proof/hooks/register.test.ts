import { expect, test } from 'claude-code/testing'
import { CHECK, CODE, SCRATCH, checkOf, line } from './register'

test('the shown command starts at the check, and scratch files are not edits', async () => {
  expect(checkOf('cd /work/proj && npm run verify:core')).toBe('npm run verify:core')
  expect(checkOf('git status')).toBeUndefined()
  expect(checkOf('claude plugin test "$D" 2>&1 | tail -3; claude plugin validate x')).toBe('claude plugin test "$D"')
  expect(checkOf('npm test && git commit -m x')).toBe('npm test')
  expect(SCRATCH.test('D:\\work\\Temp\\claude\\x\\scratchpad\\a.py')).toBe(true)
  expect(SCRATCH.test('D:\\work\\app\\src\\a.ts')).toBe(false)
})

test('check commands are recognised, everyday commands are not', async () => {
  for (const c of ['npm run verify:core', 'npx vitest run', './gradlew testDebugUnitTest', 'uv run pytest -q', 'bash hooks/guard.test.sh', 'cd app && ./gradlew assembleDebug', 'claude plugin validate .'])
    expect(CHECK.test(c)).toBe(true)
  for (const c of ['git status', 'ls -la', 'cat package.json', 'echo test', 'npm install'])
    expect(CHECK.test(c)).toBe(false)
})

test('only code files count as edits; docs and config do not', async () => {
  for (const f of ['src/a.ts', 'App.kt', 'build.gradle.kts', 'hooks/guard.sh', 'x.py', 'C:\\r\\main.go'])
    expect(CODE.test(f)).toBe(true)
  for (const f of ['README.md', 'settings.json', 'config.toml', 'SKILL.md', '.gitignore', 'notes.txt'])
    expect(CODE.test(f)).toBe(false)
})

test('the line says in plain words whether code was tested after it changed', async () => {
  const check = { cmd: 'npm test', ok: true, at: 1_000 }
  expect(line(61_000, 500, check)).toBeUndefined()
  expect(line(61_000, 2_000, check)).toBe('⚠ untested: code changed after the last test (npm test passed 1m ago)')
  expect(line(61_000, 500, { ...check, ok: false })).toBe('✘ test failed: npm test (1m ago)')
  expect(line(5_000, 1_000, undefined)).toBe('⚠ untested: code changed and no test has run this session')
  expect(line(5_000, 0, undefined)).toBeUndefined()
})

// Turn-driven: stub the engine services, drive tool.call and turn.complete, assert what proof emits.
let clock = 0
function setup(on: (...a: never[]) => unknown, bash: { isError: boolean }) {
  const o = on as unknown as (n: string, h: (_: unknown, e: never) => unknown) => void
  o('clock.now', () => ({ value: clock }))
  o('turn.complete', (_, e: never) => e)
  o('turn.start', (_, e: never) => e)
  o('tool.call', (_, e: never) => ((e as { tool: string }).tool === 'Bash' ? { result: { isError: bash.isError }, isError: bash.isError } : { result: {} }))
}
const done = (extra = {}) => ({ text: 'x', answer: 'done', reason: 'answer', durationMs: 1_000_000, turnId: 't', ...extra }) as never
const edit = (f: string) => ({ tool: 'Edit', file_path: f }) as never
const bash = (command: string) => ({ tool: 'Bash', command }) as never

async function run($: any, on: any, steps: Array<[number, () => Promise<unknown>]>, ok = true, ev = done()) {
  setup(on, { isError: !ok })
  await $.turn.start({ turnId: 't' })
  for (const [t, f] of steps) {
    clock = t
    await f()
  }
  clock = 120_000
  return (await $.turn.complete(ev)) as { text?: string }
}

test('edit then passing test: silent', async ($, on) => {
  const r = await run($, on, [[10_000, () => $.tool.call(edit('src/a.ts'))], [20_000, () => $.tool.call(bash('npm test'))]])
  expect(r.text).toBe('x')
})

test('same untested state on the next turn with no new edit is silent', async ($, on) => {
  const r1 = await run($, on, [[10_000, () => $.tool.call(bash('npm test'))], [20_000, () => $.tool.call(edit('src/b.ts'))]])
  expect(r1.text).toBe('⚠ untested: code changed after the last test (npm test passed 2m ago)')
  const r2 = (await $.turn.complete(done())) as { text?: string }
  expect(r2.text).toBe('x')
})

test('passing test then edit: untested', async ($, on) => {
  const r = await run($, on, [[10_000, () => $.tool.call(bash('npm test'))], [20_000, () => $.tool.call(edit('src/a.ts'))]])
  expect(r.text).toBe('⚠ untested: code changed after the last test (npm test passed 2m ago)')
})

test('failing test: test failed', async ($, on) => {
  const r = await run($, on, [[10_000, () => $.tool.call(bash('npm test'))]], false)
  expect(r.text).toBe('✘ test failed: npm test (2m ago)')
})

test('editing only a .md file is silent', async ($, on) => {
  const r = await run($, on, [[10_000, () => $.tool.call(edit('README.md'))]], true, done({ durationMs: 1 }))
  expect(r.text).toBe('x')
})

test('subagent turn is silent', async ($, on) => {
  const r = await run($, on, [[10_000, () => $.tool.call(edit('src/a.ts'))]], true, done({ agentId: 'sub' }))
  expect(r.text).toBe('x')
})
