import type { Register } from 'claude-code'

// A "check" is a command whose pass/fail is evidence: tests, type checks, lints, builds, validators.
export const CHECK =
  /(^|[;&|\s])(npm\s+(run\s+)?(test|verify[\w:-]*|lint|typecheck|build|check)\b|npx\s+(vitest|jest|tsc|eslint|playwright\s+test)\b|tsc\b|vitest\b|jest\b|pytest\b|uv\s+run\s+(pytest|ruff|mypy)\b|ruff\s+check\b|mypy\b|\.\/gradlew\s+\S*(test|assemble|build|check|lint)\w*|gradlew(\.bat)?\s+\S*(test|assemble|build|check|lint)\w*|bash\s+\S*\.test\.sh\b|cargo\s+(test|check|build)\b|go\s+test\b|claude\s+plugin\s+(validate|test)\b)/

// Only code needs a test after it changes; docs and config edits are not tracked.
export const CODE = /\.(tsx?|[cm]?jsx?|py|kts?|java|gradle|sh|rs|go|swift|cs|rb|php|c|cc|cpp|h|sql)$/i

export const ago = (ms: number): string =>
  ms < 60_000 ? `${Math.max(1, Math.round(ms / 1000))}s ago` : ms < 3_600_000 ? `${Math.round(ms / 60_000)}m ago` : `${Math.round(ms / 3_600_000)}h ago`

// Throwaway files (session scratchpad, temp) are not edits that need a check.
export const SCRATCH = /[\\/](Temp|tmp)[\\/]|scratchpad/i

// The check part of a command, from where the check starts (drops a leading `cd x &&`).
export const checkOf = (command: string): string | undefined => {
  const first = command.trim().split('\n')[0]
  const m = CHECK.exec(first)
  // Keep only the check itself: stop at the next pipe, `;`, `&&`, `||` or redirect.
  return m ? first.slice(m.index + m[1].length).split(/\s*(?:\|\|?|;|&&|\d?>)/)[0].trim() : undefined
}

type Check = { cmd: string; ok: boolean; at: number }

// ponytail: module memory, so a mod reload forgets the last check; move to $.state if that bites.
let lastEdit = 0
let lastCheck: Check | undefined
let editedThisTurn = false
// Edit/check timestamps at the last emitted line; the same state is not warned about twice.
let spokeAt = ''

export const line = (now: number, edit: number, check: Check | undefined): string | undefined => {
  if (!check) return edit ? '⚠ untested: code changed and no test has run this session' : undefined
  const cmd = check.cmd.length > 48 ? `${check.cmd.slice(0, 47)}…` : check.cmd
  const when = ago(now - check.at)
  if (edit > check.at) return `⚠ untested: code changed after the last test (${cmd} ${check.ok ? 'passed' : 'failed'} ${when})`
  // Alarm-only: a passing test after the last edit is silent.
  return check.ok ? undefined : `✘ test failed: ${cmd} (${when})`
}

export const register: Register = on => {
  on('turn.start', ($, e, next) => {
    if (!e.agentId) editedThisTurn = false
    return next(e)
  })

  on('tool.call', { tool: ['Edit', 'Write', 'NotebookEdit'] }, async ($, e, next) => {
    const r = await next(e)
    const file = String(e.file_path ?? e.notebook_path ?? '')
    if (r.deny === undefined && !r.isError && CODE.test(file) && !SCRATCH.test(file)) {
      lastEdit = await $.clock.now()
      editedThisTurn = true
    }
    return r
  })

  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const r = await next(e)
    const cmd = checkOf(e.command)
    if (r.deny === undefined && cmd) lastCheck = { cmd, ok: !r.isError, at: await $.clock.now() }
    return r
  })

  on('turn.complete', async ($, e, next) => {
    const r = await next(e)
    if (e.agentId || e.reason !== 'answer') return r
    const now = await $.clock.now()
    // Speak only on turns that changed code or ran a test.
    const ranCheck = lastCheck !== undefined && lastCheck.at >= now - e.durationMs
    if (!editedThisTurn && !ranCheck) return r
    const text = line(now, lastEdit, lastCheck)
    const state = `${lastEdit}|${lastCheck?.at}`
    if (!text || state === spokeAt) return r
    spokeAt = state
    return { ...r, text }
  })
}
