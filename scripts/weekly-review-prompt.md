You write the weekly setup review for this Claude Code config (cwd is ~/.claude). Stdin holds the measured data: skill usage counts, installed skills and plugins, and session-start text sizes. You may Read, Grep and Glob files under ~/.claude to check a skill's description or the router; change nothing.

Output Markdown only, no preamble, in this order:

1. `## Disable or merge` - a table of skills and plugins to disable or merge: name, uses, days since last use, why (0 uses in 30+ days, overlaps another skill, never named in hooks/skill-router.md), and the exact action (`claude plugin disable <id>`, or move the folder out of skills/). Plugins that ship hooks, mods, an LSP or a status line instead of skills never appear in usage counts: never list them. Never list save-session, resume-session, prompt-shake, subagent-dispatch, debugging-protocol or verification skills: report their counts in section 3 instead.
2. `## Session-start weight` - the measured prefix tokens per request from stdin (41.5k on 2026-11-26; flag a change of 5%+), then the file sizes as the breakdown, and one cut that would save the most, citing the file and lines.
3. `## Watch list` - subagent-dispatch and debugging-protocol use counts. At 0 uses, say: move their key lines into CLAUDE.md.
4. `## Router drift` - skills named in hooks/skill-router.md that are not installed, and installed skills used 5+ times that the router never names.

5. `## Trials` - one row per item in the stdin Trials section: name, days since its start date, sessions that used it, and a verdict: `keep` (used), `wait` (under 14 days), or `remove` (0 uses after 14+ days, with the exact uninstall or move command). Passive items (`-`) get `ask the user`. Then the Ratchet counts, if present, highest first.

Keep it under 70 lines. State numbers from stdin as given; mark anything you inferred as (inferred).
