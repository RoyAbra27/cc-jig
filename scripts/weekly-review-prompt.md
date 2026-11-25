You write the weekly setup review for this Claude Code config (cwd is ~/.claude). Stdin holds the measured data: skill usage counts, installed skills and plugins, and session-start text sizes. You may Read, Grep and Glob files under ~/.claude to check a skill's description or the router; change nothing.

Output Markdown only, no preamble, in this order:

1. `## Disable or merge` - a table of skills and plugins to disable or merge: name, uses, days since last use, why (0 uses in 30+ days, overlaps another skill, never named in hooks/skill-router.md), and the exact action (`claude plugin disable <id>`, or move the folder out of skills/). Plugins that ship hooks, mods, an LSP or a status line instead of skills never appear in usage counts: never list them. Never list save-session, resume-session, prompt-shake, subagent-dispatch, debugging-protocol or verification skills: report their counts in section 3 instead.
2. `## Session-start weight` - total characters and estimated tokens from stdin, the three largest parts, and one cut that would save the most, citing the file and lines.
3. `## Watch list` - subagent-dispatch and debugging-protocol use counts. At 0 uses, say: move their key lines into CLAUDE.md.
4. `## Router drift` - skills named in hooks/skill-router.md that are not installed, and installed skills used 5+ times that the router never names.

Keep it under 60 lines. State numbers from stdin as given; mark anything you inferred as (inferred).
