import type { Register } from 'claude-code'

export const THRESHOLD = 65

export type Todo = { content: string; status: string }
export type State = { todos: Todo[]; lastAsk: string; lastReply: string; date: string }

const clip = (s: string, n: number) => (s.length > n ? `${s.slice(0, n - 1)}...` : s).replace(/\s+/g, ' ').trim()

// The block appended to TASKS.md. Only what the API shows: the last TodoWrite list and the last exchange.
export const section = (st: State): string[] => {
  const open = st.todos.filter(t => t.status !== 'completed')
  return [
    `## Session state (${st.date}, context at ${THRESHOLD}%+)`,
    ...(open.length ? open.map(t => `- [ ] ${clip(t.content, 120)}${t.status === 'in_progress' ? ' (in progress)' : ''}`) : ['- [ ] (no open todos were visible; fill in the next step)']),
    ...(st.lastAsk ? [`- Last request: ${clip(st.lastAsk, 160)}`] : []),
    ...(st.lastReply ? [`- Last reply: ${clip(st.lastReply, 200)}`] : []),
  ]
}

export const propose = (existing: string, st: State): { content: string; diff: string } => {
  const add = section(st)
  const base = existing === '' || existing.endsWith('\n') ? existing : `${existing}\n`
  const content = `${base}${base === '' ? '' : '\n'}${add.join('\n')}\n`
  const head = existing === '' ? ['--- /dev/null (new file)', '+++ TASKS.md'] : ['--- TASKS.md', '+++ TASKS.md (proposed)', `@@ append after line ${existing.split('\n').length} @@`]
  return { content, diff: [...head, ...(existing === '' ? [] : ['+']), ...add.map(l => `+${l}`)].join('\n') }
}

type Msg = { role: string; text: string; toolUses: { tool: string; input: Record<string, unknown> }[] }

export const stateOf = (msgs: readonly Msg[], date: string): State => {
  let todos: Todo[] = []
  for (const m of [...msgs].reverse()) {
    const tu = m.toolUses.find(t => t.tool === 'TodoWrite' && Array.isArray(t.input.todos))
    if (tu) {
      todos = (tu.input.todos as Todo[]).map(t => ({ content: String(t.content), status: String(t.status) }))
      break
    }
  }
  const last = (role: string) => [...msgs].reverse().find(m => m.role === role && m.text.trim())?.text ?? ''
  return { todos, lastAsk: last('user'), lastReply: last('assistant'), date }
}

// Once per session: module memory, so a mod reload may offer once more.
let offered = false

export const register: Register = on => {
  on('turn.complete', async ($, e, next) => {
    const r = await next(e)
    if (e.agentId || offered) return r
    const { context } = await $.session.usage()
    if ((context.percent ?? 0) < THRESHOLD) return r
    offered = true
    void (async () => {
      try {
        const root = await $.session.root()
        const path = `${root.replace(/\\/g, '/')}/TASKS.md`
        const existing = (await $.fs.exists(path)) ? await $.fs.read(path) : ''
        const msgs = await $.session.messages({ last: 30 })
        const st = stateOf('deny' in msgs ? [] : msgs, new Date(await $.clock.now()).toISOString().slice(0, 10))
        const { content, diff } = propose(existing, st)
        $.ui.log(`Compaction insurance: context passed ${THRESHOLD}%. Proposed TASKS.md change:\n${diff}`)
        const choice = await $.ui.ask('Write this update to TASKS.md before the context compacts?', ['Write', 'Skip'])
        if (choice === 'Write') {
          await $.fs.write(path, content)
          $.ui.log(`Compaction insurance: wrote ${path}`)
        }
      } catch {
        // dismissed dialog or a failed read: nothing is written
      }
    })()
    return r
  })
}
