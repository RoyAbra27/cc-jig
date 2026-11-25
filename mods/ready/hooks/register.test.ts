import { expect, test } from 'claude-code/testing'
import { CHECK, DOC, report } from './register'

const base = { branch: 'feat/x', upstream: 'origin/feat/x', commits: ['abc1 feat: a'], docs: [], dirty: 0, head: 'h1' }

test('report: unknown check, no docs, name-based protection', async () => {
  const t = report(base)
  expect(t).toContain('Unpushed: 1 commit(s) vs origin/feat/x')
  expect(t).toContain('Check at HEAD: unknown')
  expect(t).toContain('Docs touched: none')
  expect(t).toContain('Protected branch: no (by name only')
  expect(t).toContain('nothing was pushed')
})

test('report: no upstream, main branch, stale and fresh check', async () => {
  expect(report({ ...base, branch: 'main', upstream: undefined, commits: [] })).toContain('no upstream')
  expect(report({ ...base, branch: 'main' })).toContain('probably YES')
  expect(report({ ...base, check: { cmd: 'npm test', ok: true, head: 'old' } })).toContain('stale')
  expect(report({ ...base, check: { cmd: 'npm test', ok: false, head: 'h1' } })).toContain('FAILED')
  expect(report({ ...base, ghProtected: true })).toContain('YES (GitHub)')
})

test('docs and check matchers', async () => {
  expect(DOC.test('README.md') && DOC.test('docs/a.txt') && !DOC.test('src/a.ts')).toBe(true)
  expect(CHECK.test('npm test')).toBe(true)
  expect(CHECK.test('git push')).toBe(false)
})

test('/ready runs through the engine and only calls git read commands', async ($, on) => {
  const calls: string[][] = []
  on('command.register', () => ({ value: { command: 'ready' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('process.run', (_, e) => {
    calls.push([...e.argv])
    return { value: { exitCode: 1, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const r = await $.command.run({ command: 'ready', args: '', origin: { kind: 'composer' }, presentation: { layout: 'main', columns: 80 } } as never)
  expect(r.text).toContain('not a git repository')
  expect(calls.every(c => c[0] === 'git' && c[1] !== 'push')).toBe(true)
})
