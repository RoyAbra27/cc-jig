import { expect, test } from 'claude-code/testing'
import { CORRECTION, bump, headingsOf, list, notice } from './register'

test('prefilter catches corrections and skips plain asks', async () => {
  for (const t of ["No, use the other file", "don't add a README", 'stop doing that', 'you did it again', 'I told you twice', 'that is wrong'])
    expect(CORRECTION.test(t)).toBe(true)
  for (const t of ['add a login page', 'what does this function do?', 'looks great, ship it'])
    expect(CORRECTION.test(t)).toBe(false)
})

test('headings come from ## lines only; the third bump hits', async () => {
  expect(headingsOf('# Top\n## Git Workflow\ntext\n### sub\n## Ratchet (added 2026-09-01)\n')).toEqual(['Git Workflow', 'Ratchet (added 2026-09-01)'])
  let s = { counts: {} as Record<string, number> }
  const hits: boolean[] = []
  for (let i = 0; i < 4; i++) {
    const r = bump(s, 'Git Workflow')
    s = r.store
    hits.push(r.hit)
  }
  expect(hits).toEqual([false, false, true, false])
  expect(list(s)).toContain('! 4  Git Workflow')
  expect(notice('X')).toContain('hook')
})

test('a correction prompt is classified, counted in the store, and notices at 3', async ($, on) => {
  let stored = ''
  const logs: string[] = []
  on('env.get', (_, e) => ({ value: e.name === 'USERPROFILE' ? '/home/t' : undefined }))
  on('fs.read', (_, e) => ({ value: e.path.endsWith('CLAUDE.md') ? '## Git Workflow\n## Verification\n' : stored || '{"counts":{}}' }))
  on('fs.write', (_, e) => {
    stored = e.text
    return { value: undefined }
  })
  on('model.classify', () => ({ value: 'Git Workflow' }))
  on('ui.log', (_, e) => {
    logs.push(e.text)
    return { value: undefined }
  })
  on('ui.toast', () => ({ value: undefined }))
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('command.register',() => ({ value: { command: 'ratchet' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  for (let i = 0; i < 3; i++) {
    await $.prompt.submit({ text: "no, don't commit that", origin: { kind: 'composer' } } as never)
    for (let k = 0; k < 500; k++) await Promise.resolve()
  }
  expect(JSON.parse(stored).counts['Git Workflow']).toBe(3)
  expect(logs.some(l => l.includes('Git Workflow'))).toBe(true)
})
