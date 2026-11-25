export const meta = {
  name: 'branch-audit',
  description: 'Branch audit: parallel Opus lanes, then one Opus consolidator (skills/branch-audit)',
  whenToUse: 'Step 3-4 of the branch-audit skill, after the package, shared brief and lane scopes exist',
  phases: [
    { title: 'Lanes', detail: 'one Opus reviewer per lane, read-only', model: 'opus' },
    { title: 'Consolidate', detail: 'merge, re-verify, bucket, fix-wave draft', model: 'opus' },
  ],
}

// args: {
//   brief: absolute path of the frozen shared brief,
//   workspace: absolute dir that holds the package and audit-*.md files,
//   repo, branch, head: for the consolidator,
//   rulings: where binding user rulings live (path or 'none'),
//   lanes: [{ name, scope }]  scope = the lanes.md text adapted to this repo, naming concrete files
// }
const a = args || {}
if (!a.brief || !a.workspace || !Array.isArray(a.lanes) || !a.lanes.length) {
  throw new Error('branch-audit needs args {brief, workspace, repo, branch, head, rulings, lanes:[{name, scope}]}')
}

phase('Lanes')
// Barrier on purpose: the consolidator needs every lane file.
const laneReplies = await parallel(a.lanes.map(l => () =>
  agent(
    `You are the ${l.name} lane of a multi-lane final audit. Read ${a.brief} first; it is your contract. ` +
    `Lane name for IDs and file: \`${l.name}\`. Write your findings to ${a.workspace}/audit-${l.name}.md.\n\n` +
    `Scope:\n${l.scope}`,
    { label: `lane:${l.name}`, phase: 'Lanes', model: 'opus', agentType: 'general-purpose' },
  ).then(r => ({ lane: l.name, reply: r }))
))

const done = laneReplies.filter(Boolean)
const missing = a.lanes.map(l => l.name).filter(n => !done.some(d => d.lane === n))
if (missing.length) log(`lanes with no reply (consolidator told to skip): ${missing.join(', ')}`)

phase('Consolidate')
const laneFiles = done.map(d => `${a.workspace}/audit-${d.lane}.md`).join(', ')
const merged = await agent(
  `You consolidate a multi-lane code audit. Repo ${a.repo}, branch ${a.branch} at HEAD ${a.head}. ` +
  `Read ${a.brief} for context and hard rules (read-only; no state-resetting tests; no subagents; no secrets or real data). ` +
  `Then read every lane file: ${laneFiles}. Binding user rulings: ${a.rulings || 'none'}.` +
  (missing.length ? ` Lanes that did not report: ${missing.join(', ')}; note the gap in Lane statistics.` : '') +
  `\n\nFollow ~/.claude/skills/branch-audit/references/consolidator.md from "Write ONE file" to the end, ` +
  `writing ${a.workspace}/audit-merged.md, and reply with ONLY what it asks for.`,
  { label: 'consolidator', phase: 'Consolidate', model: 'opus', agentType: 'general-purpose' },
)

return { lanes: done, missing, consolidator: merged }
