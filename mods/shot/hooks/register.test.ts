import { expect, test } from 'claude-code/testing'
import { parseArgs } from './register'

test('args: url and label are validated and sanitised', async () => {
  expect(parseArgs('https://example.com/a')).toEqual({ url: 'https://example.com/a', label: 'example.com' })
  expect(parseArgs('http://localhost:3000 home page')).toEqual({ url: 'http://localhost:3000', label: 'home-page' })
  expect('error' in parseArgs('--evil')).toBe(true)
  expect('error' in parseArgs('')).toBe(true)
  expect(parseArgs('https://x.io ../../etc')).toEqual({ url: 'https://x.io', label: '.._.._etc' })
})

test('first /shot stores before, second compares, browser is closed each time', async ($, on) => {
  const calls: string[] = []
  let hasBefore = false
  on('command.register', () => ({ value: { command: 'shot' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('fs.exists', (_, e) => ({ value: e.path.endsWith('before.png') && hasBefore }))
  on('process.run', (_, e) => {
    const [bin, ...rest] = e.argv
    calls.push(bin === 'uv' ? `uv ${rest.at(-2) === 'dir' ? 'dir' : rest.at(-2)}` : `${bin} ${rest[0]}`)
    const stdout = bin === 'uv' ? (rest.includes('compare') ? '12.50' : '/tmp/claude-shot/home') : ''
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const run = () => $.command.run({ command: 'shot', args: 'https://example.com home', origin: { kind: 'composer' }, presentation: { layout: 'main', columns: 80 } } as never)

  const first = await run()
  expect(first.text).toContain('stored "before"')
  expect(calls.filter(c => c === 'agent-browser close').length).toBe(1)

  hasBefore = true
  const second = await run()
  expect(second.text).toContain('12.50% of pixels changed')
  expect(second.text).toContain('compare.html')
  expect(calls.filter(c => c === 'agent-browser close').length).toBe(2)
})
