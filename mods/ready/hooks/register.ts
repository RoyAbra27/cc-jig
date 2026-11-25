import type { Register } from 'claude-code'

// Same idea as the proof mod: a "check" is a command whose pass/fail is evidence.
// Copied, not imported: a plugin folder must stand alone once installed.
export const CHECK =
  /(^|[;&|\s])(npm\s+(run\s+)?(test|verify[\w:-]*|lint|typecheck|build|check)\b|npx\s+(vitest|jest|tsc|eslint|playwright\s+test)\b|tsc\b|vitest\b|jest\b|pytest\b|uv\s+run\s+(pytest|ruff|mypy)\b|ruff\s+check\b|mypy\b|\.\/gradlew\s+\S*(test|check|lint)\w*|bash\s+\S*\.test\.sh\b|cargo\s+(test|check|build)\b|go\s+test\b|claude\s+plugin\s+(validate|test)\b)/

export const DOC = /(\.md$|^docs\/)/i
export const PROTECTED_NAMES = /^(main|master|trunk|production|prod|release\/.*)$/

type Check = { cmd: string; ok: boolean; head: string }

// ponytail: module memory, a mod reload forgets the last check ("unknown" until the next one).
let lastCheck: Check | undefined

export type Facts = {
  branch: string
  upstream?: string
  commits: string[]
  docs: string[]
  dirty: number
  head: string
  check?: Check
  // true/false when GitHub answered, undefined when only the name is known
  ghProtected?: boolean
}

export const report = (f: Facts): string => {
  const out: string[] = [`/ready on ${f.branch || '(detached HEAD)'}`]
  if (!f.upstream) out.push('Unpushed: no upstream, a first push would send every commit on this branch')
  else out.push(`Unpushed: ${f.commits.length} commit(s) vs ${f.upstream}`)
  out.push(...f.commits.slice(0, 15).map(c => `  ${c}`))
  if (f.commits.length > 15) out.push(`  ... and ${f.commits.length - 15} more`)
  if (f.dirty) out.push(`Working tree: ${f.dirty} uncommitted change(s), not part of the push`)
  if (!f.check) out.push('Check at HEAD: unknown (no check command seen this session)')
  else if (f.check.head !== f.head) out.push(`Check at HEAD: stale - ${f.check.ok ? 'passed' : 'failed'} \`${f.check.cmd}\` on an earlier commit`)
  else out.push(`Check at HEAD: ${f.check.ok ? 'passed' : 'FAILED'} \`${f.check.cmd}\``)
  out.push(f.upstream ? (f.docs.length ? `Docs touched: ${f.docs.join(', ')}` : 'Docs touched: none (if behavior changed, docs may be stale)') : 'Docs touched: unknown without an upstream range')
  const named = PROTECTED_NAMES.test(f.branch)
  if (f.ghProtected !== undefined) out.push(`Protected branch: ${f.ghProtected ? 'YES' : 'no'} (GitHub)`)
  else out.push(`Protected branch: ${named ? 'probably YES' : 'no'} (by name only, GitHub not checked)`)
  out.push('Read-only: nothing was pushed or changed.')
  return out.join('\n')
}

type Runner = { process: { run: (a: readonly string[], i?: { timeoutMs?: number }) => Promise<{ exitCode: number; stdout: string }> } }

// Read-only git only: callers pass log, diff, status, rev-parse, branch --show-current.
const git = async ($: Runner, args: string[]): Promise<string | undefined> => {
  try {
    const r = await $.process.run(['git', ...args], { timeoutMs: 10000 })
    return r.exitCode === 0 ? r.stdout.trim() : undefined
  } catch {
    return undefined
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'ready', description: 'Push checklist for this repo (read-only)' })
    return next(e)
  })

  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const r = await next(e)
    const first = e.command.trim().split('\n')[0]
    const m = CHECK.exec(first)
    if (r.deny === undefined && m) {
      const head = await git($, ['rev-parse', 'HEAD'])
      lastCheck = { cmd: first.slice(m.index + m[1].length).split(/\s*(?:\|\|?|;|&&)/)[0].trim(), ok: !r.isError, head: head ?? '' }
    }
    return r
  })

  on('command.run', { command: 'ready' }, async $ => {
    const head = await git($, ['rev-parse', 'HEAD'])
    if (head === undefined) return { text: '/ready: not a git repository here.' }
    const branch = (await git($, ['branch', '--show-current'])) ?? ''
    const upstream = await git($, ['rev-parse', '--abbrev-ref', '@{u}'])
    const range = upstream ? '@{u}..HEAD' : undefined
    const commits = range ? ((await git($, ['log', '--oneline', range])) ?? '').split('\n').filter(Boolean) : []
    const docs = range ? ((await git($, ['diff', '--name-only', range])) ?? '').split('\n').filter(l => DOC.test(l)) : []
    const dirty = ((await git($, ['status', '--porcelain'])) ?? '').split('\n').filter(Boolean).length
    let ghProtected: boolean | undefined
    if (branch && upstream) {
      try {
        const g = await $.process.run(['gh', 'api', `repos/{owner}/{repo}/branches/${branch}`, '--jq', '.protected'], { timeoutMs: 5000 })
        if (g.exitCode === 0 && /^(true|false)$/.test(g.stdout.trim())) ghProtected = g.stdout.trim() === 'true'
      } catch {
        // gh missing or offline: name-based
      }
    }
    return { text: report({ branch, upstream, commits, docs, dirty, head, check: lastCheck, ghProtected }) }
  })
}
