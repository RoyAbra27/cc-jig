import type { Register } from 'claude-code'

// Cheap prefilter: only prompts that look like a correction reach the model call.
export const CORRECTION =
  /^\s*(no|nope|wrong)\b|\b(don'?t|do not|stop|again|wrong|never|i told you|i said|not what i|that'?s not|why did you)\b|תפסיק|שוב|אמרתי|לא נכון|אל תעשה/i

export const THRESHOLD = 3
export const NONE = 'none'

export type Store = { counts: Record<string, number> }

export const headingsOf = (md: string): string[] =>
  [...md.matchAll(/^## +(.+?)\s*$/gm)].map(m => m[1])

// Returns the new store and whether this bump just reached the threshold.
export const bump = (s: Store, heading: string): { store: Store; hit: boolean } => {
  const n = (s.counts[heading] ?? 0) + 1
  return { store: { counts: { ...s.counts, [heading]: n } }, hit: n === THRESHOLD }
}

export const list = (s: Store): string => {
  const rows = Object.entries(s.counts).sort((a, b) => b[1] - a[1])
  if (!rows.length) return 'Ratchet: no corrections counted yet.'
  return ['Ratchet counts (a heading at 3 should become a hook):', ...rows.map(([h, n]) => `  ${n >= THRESHOLD ? '!' : ' '} ${n}  ${h}`)].join('\n')
}

export const notice = (heading: string): string =>
  `Ratchet: "${heading}" has now been corrected ${THRESHOLD} times. Per the Ratchet rule, propose converting it into a hook (guard.sh) instead of another reminder.`

type Env = { env: { get: (n: 'USERPROFILE' | 'HOME') => Promise<string | undefined> } }
type Fs = Env & { fs: { read: (p: string) => Promise<string> } }

async function home($: Env): Promise<string> {
  return ((await $.env.get('USERPROFILE')) ?? (await $.env.get('HOME')) ?? '').replace(/\\/g, '/')
}

// Outside every git repo, under the user's home.
async function storePath($: Env): Promise<string> {
  return `${await home($)}/.claude-mods-data/ratchet.json`
}

async function load($: Fs): Promise<Store> {
  try {
    const j = JSON.parse(await $.fs.read(await storePath($)))
    return j && typeof j.counts === 'object' ? { counts: j.counts } : { counts: {} }
  } catch {
    return { counts: {} }
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'ratchet', description: 'Show how often each CLAUDE.md rule was corrected' })
    return next(e)
  })

  on('command.run', { command: 'ratchet' }, async $ => ({ text: list(await load($)) }))

  on('prompt.submit', async ($, e, next) => {
    // Skip slash commands, meta prompts and anything that does not look like a correction.
    if (!e.command && !e.isMeta && CORRECTION.test(e.text)) {
      void (async () => {
        try {
          const md = await $.fs.read(`${await home($)}/.claude/CLAUDE.md`)
          const headings = headingsOf(md)
          if (headings.length < 1) return
          const label = await $.model.classify(
            `A user corrected an AI coding assistant. Which rule section of its instructions does the correction belong to, or none if it is not a correction?\n\n${e.text.slice(0, 500)}`,
            [...headings, NONE],
          )
          if (label === undefined || label === NONE) return
          const { store, hit } = bump(await load($), label)
          await $.fs.write(await storePath($), JSON.stringify(store, null, 2))
          if (hit) {
            $.ui.log(notice(label))
            $.ui.toast(notice(label), { timeoutMs: 10000 })
          }
        } catch {
          // best effort: a failed classification must never disturb the prompt
        }
      })()
    }
    return next(e)
  })
}
