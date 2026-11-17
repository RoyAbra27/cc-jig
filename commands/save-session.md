# /save-session

Save the current session state for continuation in a future session.

1. Create a file at `~/.claude/sessions/YYYY-MM-DD-<topic>.md` where `<topic>` is a short slug describing what we worked on
2. Include these sections:
   - **Goal**: What we were trying to accomplish
   - **Completed**: What was done (with file paths changed)
   - **What worked**: Verified approaches with evidence
   - **What failed**: Attempted approaches that didn't work and why
   - **Could not run**: steps that were blocked from running at all, with the reason (tool or credential absent, suite already red, dependency unavailable). If there were none, write "none" explicitly
   - **Remaining**: What's left to do
   - **Key context**: Important decisions, constraints, or discoveries that the next session needs to know
   - **Suggested skills**: skills or agents the next session should invoke first, with one line on why
   Reference specs, plans, ADRs, commits and PRs by path or URL instead of copying their content. Never write secrets or tokens into the file
3. Nothing goes under **Completed** on the strength of intent. If it was not verified, it belongs under **Could not run** or **Remaining**
4. Write this file when stopping work that continues in a later session. If it already exists, update it merge-style: touch only the sections that changed, never rewrite the file wholesale
5. **Reflect (added 2026-11-09):** run the procedure in `~/.claude/commands/reflect.md` and record its outcome in the session file
6. Show the user the file path so they can provide it to the next session via `@` or `/resume-session`
