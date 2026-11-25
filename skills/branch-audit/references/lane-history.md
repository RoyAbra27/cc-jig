# Lane history

One block per audit. Cut or merge a lane with no unique Important+ across three audits.

Entries use project codenames and finding classes only: never product names, branch names, SHAs, ticket IDs or bug specifics.

Codenames: **Project A** = API + worker backend with a data-ingestion pipeline; **Project A client** = its Android app; **Project B** = TS/Hono web app with Docker; **Project C** = a public agent-config repo (hooks, prompt files, bootstrap, CI).

## 2026-10-27 Project A, feature branch (41 commits; 11 lanes, pre-skill layout)

123 raw findings -> 60 merged, 13 Important, 0 Critical.

| Lane (old) | Raw | Duplicates | Unique verified | Unique Important+ | Maps to |
|---|---|---|---|---|---|
| security | 10 | 7 | 1 | 0 | api-surface |
| api | 11 | 6 | 5 | 0 | api-surface |
| pipeline | 9 | 7 | 2 | 0 | data-path |
| db | 12 | 7 | 5 | 0 | data-path |
| arch | 11 | 8 | 3 | 0 | conformance |
| docs | 17 | 9 | 8 | 0 | conformance + client-contract |
| ponytail | 14 | 4 | 10 | 0 | section in code lanes |
| deploy | 10 | 3 | 7 | 2 | deploy |
| mobile | 13 | 1 | 12 | 2 | client-contract |
| privacy | 9 | 3 | 6 | 1 | privacy |
| omissions | 7 | 1 | 6 | 1 | omissions |

Most duplicated: a hardening decision not yet implemented (3+ lanes), a missing storage bucket silently reading as empty (5 lanes), a credential-revocation gap (6 lanes). All three were already known open items, hence the known-open list in the brief.

## 2026-10-28 Project A, whole repo (post-merge, 8 lanes, skill layout + data-path split into uploads/core)

57 raw findings -> 50 merged, 6 Important + 3 Important decisions, 0 Critical.

| Lane | Raw | Duplicates | Unique verified | Unique Important+ |
|---|---|---|---|---|
| api-surface | 4 | 0 | 3 | 0 |
| data-path-uploads | 7 | 2 | 4 | 1 |
| data-path-core | 6 | 0 | 6 | 0 |
| conformance | 11 | 3 | 8 | 0 |
| deploy | 4 | 3 | 0 | 0 |
| client-contract | 10 | 1 | 9 | 3 |
| privacy | 6 | 1 | 5 | 1 |
| omissions | 9 | 1 | 7 | 1 |

Notes: known-open list worked (no lane re-reported a known item as new). A lock-vs-temp-file-write race was found by 3 lanes (top dup). api-surface and deploy 0 unique Important+ on a second pass over an already-audited surface: first strike for each. data-path-core (never-audited code) found only Minors.

## 2026-10-29 Project A, 10 commits (parser and ingestion changes; already red-teamed and code-reviewed)
| Lane | Raw | Duplicates | Unique verified | Unique Important+ |
|---|---|---|---|---|
| data-path | 5 | 1 | 4 | 0 |
| conformance | 5 | 1 | 4 | 0 |
| privacy | 8 (4 + 4 test gaps) | 0 | 8 | 0 |
| omissions | 10 | 0 | 10 | 0 |

Notes: 0 Important+ in every lane; the branch had already had a red team and a code review. Omissions found the only data-loss path (a revoked third-party account read as "no data" instead of an error) and both user decisions. Conformance: low yield on a small, plan-driven branch (a checklist pass by the controller would do). Strikes on zero unique Important+: data-path 1, conformance 1, privacy 1, omissions 1 (count toward the three-audit cut rule). Lesson: on a branch already red-teamed and code-reviewed, 2 lanes (omissions + privacy) may be enough.

## 2026-11-02 Project A, 21 commits (parser v2, views, docs, client guide section; already red-teamed and code-reviewed; user chose all 7 lanes)
| Lane | Raw | Duplicates | Unique verified | Unique Important+ |
|---|---|---|---|---|
| data-path | 5 | 1 | 4 | 0 |
| conformance | 7 | 2 | 6 | 0 |
| client-contract | 9 | 3 | 9 | 2 |
| privacy | 1 | 0 | 1 | 0 |
| api-surface | 4 | 2 | 2 | 0 |
| deploy | 7 | 2 | 6 | 1 (shared) |
| omissions | 6 | 1 | 6 | 1 (shared) |

Notes: client-contract earned most (traced the client code path for a quarantine bug and found a client-side upload queue wipe). A missing old-version signal was found by both omissions and deploy. data-path rated the quarantine bug Minor; the client-contract lane's code trace made it Important. Strikes on zero unique Important+: data-path 2, conformance 2, privacy 2, api-surface 2 (api-surface: range did not touch the API). Lesson: when the range reads another team's code, client-contract is the top lane; on an already-reviewed range, api-surface and privacy mostly return negative evidence.

## 2026-11-03 Project B, phase branch (Docker; 6 lanes + controller items)
| Lane | Raw | Duplicates | Unique verified | Unique Important+ | Dropped |
|---|---|---|---|---|---|
| data-path | 6 | 1 | 5 | 2 (incl. the only Critical) | 0 |
| omissions | 12 | 2 | 10 | 3 | 1 |
| conformance | 11 | 2 | 9 | 2 (+1 shared) | 1 |
| api-surface | 6 | 1 | 5 | 1 | 1 |
| deploy | 8 | 5 | 3 | 0 (1 shared with conformance) | 2 |
| privacy | 6 | 3 | 4 | 0 | 2 |
Note: privacy (0 unique Important+, headline fix ineffective) and deploy (mostly duplicated conformance) were the low-yield lanes this run; consider folding privacy into deploy for single-household apps.

## 2026-11-05 Project A client, auto-upload PR (Android client, 18 commits, +4.5k)
Lanes: data-path, conformance, deploy, client-contract, privacy, omissions (api-surface skipped: client only). 36 raw -> 28 merged (13 FIX-CODE, 3 USER-DECISION, 5 FIX-DOCS, 7 DEFER, 0 DROP). Only Important: omissions (a "delete all" action that missed not-yet-processed local data).
| Lane | Raw | Dup | Unique verified | Unique Important+ |
|---|---|---|---|---|
| data-path | 6 | 3 | 3 | 0 |
| conformance | 7 | 3 | 4 | 0 |
| deploy | 6 | 2 | 4 | 0 |
| client-contract | 4 | 2 | 2 | 0 |
| privacy | 4 | 1 | 3 | 0 |
| omissions | 9 | 4 | 5 | 1 |
Notes: branch already had a final review + fix wave, so code lanes found Minors only. Privacy and omissions cited package.diff line numbers instead of worktree lines; tell lanes to cite worktree lines.

## 2026-11-10 Project B web UI, summary verdict branch (web UI + bot text + deploy docs, 33 commits)
Lanes (lean, user choice): conformance, data-path (adapted to the trust path from stored data to every displayed number), omissions. 27 raw -> 21 unique (8 FIX-CODE, 4 USER-DECISION, 10 FIX-DOCS, 3 DEFER, 2 DROP).
| Lane | Raw | Dup | Unique verified | Unique Important+ |
|---|---|---|---|---|
| conformance | 9 | 3 | 6 | 0 |
| data-path | 9 | 3 | 6 | 2 |
| omissions | 9 | 0 | 9 | 0 |
Notes: a read-only probe script in the data-path lane found two invented-number paths the per-task reviews missed; for display-of-numbers branches, tell data-path to probe every figure shown. Omissions caught a deploy runbook that fails when followed literally.

## 2026-11-10 Project B, whole product before first deploy (6 lanes adapted to the product: money-trust, background, conformance, deploy, omissions, ux; plus controller items; security out of scope)
85 raw -> 82 merged (31 FIX-CODE, 23 FIX-DOCS, 5 USER-DECISION, 17 DEFER, 6 DROP), 1 Critical.
| Lane | Raw | Dup | Unique verified | Unique Important+ | Dropped |
|---|---|---|---|---|---|
| money-trust (data-path, adapted) | 10 | 2 | 10 | 6 | 0 |
| background (jobs, locks, outages) | 10 | 2 | 10 | 3 | 0 |
| conformance | 18 | 2 | 17 | 3 | 2 |
| deploy | 15 | 2 | 15 | 1 | 3 |
| omissions | 11 | 3 | 11 | 2 | 0 |
| ux | 20 | 2 | 20 (most partial: screenshots) | 4 | 1 |
| controller | 1 | 1 | 1 | 0 | 0 |
Notes: the adapted data-path lane earned most again, with runnable probes that made re-verification cheap (wrong-amount and wrong-number paths). A background lane found the only lock-starvation and provider-outage paths; a ux lane found trust-wording and recovery-flow problems no code lane looks at: both are worth adding for a product with scheduled jobs and a phone UI. Conformance and deploy were mostly doc hygiene on a whole-product pass (two findings changed what ships). All six lanes missed that a second pass through the main flow reset the user's earlier choices; the user found it by asking (the omissions axis for it was added the same day). One fix unit came back blocked because the controller had changed code after consolidation and its Done-when no longer matched.

## 2026-11-15 Project B, learning branch (30 commits, +4.6k; every task already reviewed plus a final 2-lane review)
Lanes: api-surface, data-path, conformance, ui (conditional, replaced deploy: no infra or dependency change), omissions; then a separate two-agent UX critique (design review + style detector) at the user's request. 41 raw -> 35 merged (15 FIX-CODE, 3 USER-DECISION, 7 FIX-DOCS, 3 DEFER, 7 DROP), 0 Critical.
| Lane | Raw | Dup | Unique verified | Unique Important+ | Dropped |
|---|---|---|---|---|---|
| api-surface | 5 | 1 | 4 | 0 | 1 |
| data-path | 8 | 3 | 5 | 0 | 3 |
| conformance | 8 | 0 | 8 | 0 | 0 |
| ui | 10 | 2 | 8 | 1 | 3 |
| omissions | 10 | 3 | 7 | 2 | 0 |
Notes: omissions found both unique Important decisions (learned state that only grows, no backup of the store holding it). The one merge-blocking bug (a flow dead end after its first use) was found by ui, api-surface and data-path, and again by the UX critique. The UX critique (design review) found 3 issues no lane rated Important: learned state invisible and not undoable, a verdict headline on a near-tie estimate, an overloaded choice row; the style detector found only cosmetic flags. Zero unique Important+ this run: api-surface, data-path, conformance (none has three in a row yet: each found an Important in an audit since its earlier zeros; api-surface's value here was the clean auth/CSRF evidence). Lesson: for a UI-heavy branch with a learning or explanation layer, a design-review UX lane belongs in the default set; consider merging conformance into the consolidator's pass.

## 2026-11-17 Project A client, UI polish branch (8 commits, +3.0k; no API, infra or dependency change)
Lanes: data-path, ui-ux, performance (measured baseline given), simplification (user asked), conformance, omissions; api-surface and deploy skipped (nothing exposed, no deps). 49 raw -> 48 merged (23 FIX-CODE, 5 FIX-DOCS, 3 USER-DECISION, 16 DEFER, 1 DROP), 0 Critical.
| Lane | Raw | Dup | Unique verified | Unique Important+ | Dropped |
|---|---|---|---|---|---|
| data-path | 7 | 0 | 7 | 0 | 0 |
| ui-ux | 11 | 0 | 9 | 1 | 0 |
| performance | 7 | 1 | 6 | 0 | 0 |
| simplification | 13 | 0 | 12 | 0 | 0 |
| conformance | 5 | 0 | 4 | 0 | 1 |
| omissions | 6 | 1 | 5 | 2 | 0 |
Notes: ui-ux found the only merge-blocking bug (a state reset missing on a second pass through a screen, reachable two ways) by walking view states, which no other lane does; the second-pass axis paid off again. Omissions found a rollback rule made unsafe by a schema bump and a missing crash-report channel. Simplification and performance were precise but Minor-only, as predicted for a ponytail-style lane; performance with a measured baseline mostly confirmed it. The consolidator moved two "decision" candidates to FIX-DOCS because one option was already ruled out by a standing rule or decision: give the consolidator the standing rules. Zero unique Important+ this run: data-path, performance, simplification, conformance.

## 2026-11-18 Project A client, tester-feedback fix branch (7 commits, +0.8k; no API, infra or dependency change)
Lanes: data-path, ui-ux, conformance, omissions, then cleanup added on request (dead code, stale comments, simplification, performance in touched files); api-surface and deploy skipped (nothing exposed, no deps). 36 raw -> 32 merged (5 FIX-CODE, 2 USER-DECISION, 5 FIX-DOCS, 18 DEFER, 2 DROP), 1 Critical.
| Lane | Raw | Dup | Unique verified | Unique Important+ | Dropped |
|---|---|---|---|---|---|
| data-path | 5 | 2 | 3 | 0 (shared the Critical) | 1 |
| ui-ux | 10 | 2 | 8 | 1 | 1 |
| conformance | 7 | 4 | 3 | 0 | 0 |
| omissions | 7 | 3 | 4 | 0 (shared the Critical) | 0 |
| cleanup | 7 | 0 | 6 | 0 | 0 |
Notes: the only Critical was pre-existing code reachable from a new angle (an entry point that stays open while a long-running mode is active), found independently by data-path and omissions; data-path had the right mechanism. ui-ux again found the unique Important by walking the second pass through a control (an action repeated in the same burst). A copy rule enforced by a test was broken in a resource type the test did not read (plurals); two lanes caught it, so ask lanes to check what each guard test actually parses. Cleanup was Nit-only, as predicted for a ponytail-style lane: fold it into the code lanes' closing section unless the user asks. Zero unique Important+ this run: data-path, conformance, omissions, cleanup (conformance: second run in a row; consider merging it into the consolidator per the earlier note).

## 2026-11-24 Project C, one day of commits (27 commits, +1.7k; no feature branch, range = the day's commits)
Lanes adapted to a config repo: hooks (data-path/api-surface analogue for hook scripts), public-leak (privacy analogue: private details in a public repo), deploy (bootstrap, CI, supply chain), conformance (consistency between rules, plans, prompt files and hooks), omissions. 37 raw -> 25 merged (13 FIX-CODE, 4 USER-DECISION, 4 FIX-DOCS, 3 DEFER, 2 DROP), 1 Critical.
| Lane | Raw | Dup | Unique verified | Unique Important+ | Dropped |
|---|---|---|---|---|---|
| hooks | 11 | 3 | 8 | 0 (shared the Critical) | 1 |
| public-leak | 2 | 0 | 2 | 0 | 0 |
| deploy | 10 | 2 | 8 | 3 (+ shared the Critical) | 0 |
| conformance | 5 | 3 | 2 | 0 (shared the Critical) | 0 |
| omissions | 9 | 2 | 7 | 1 | 0 |
Notes: the Critical (hook scripts without the executable bit, run by path, plus a same-day "block on hook failure" setting, so every tool call blocks on the other OSes) was found by three lanes; tests and CI called the scripts through the interpreter and never exercised the real invocation. Ask lanes to run every configured command exactly as written. Deploy earned most (installer clash, unpinned executors, an author-only absolute path). The consolidator found a product name the leak lane missed because the leak lane was scoped to the range: scope a leak lane to HEAD plus the range. The consolidator also caught a lane fix that would have disabled a hook on the author's machine (an interpreter lookup order hitting an OS stub). Zero unique Important+ this run: hooks, public-leak, conformance (conformance: third zero in a row, so fold it into the consolidator per the earlier notes).

## 2026-11-25 Project C, pre-push range (30 commits, +1.5k)
Lanes: hook-surface (attacker view of hook entry points), deploy (install/update path plus supply chain), privacy (public-repo leaks, HEAD plus range), omissions; conformance done by the consolidator. 41 raw -> 32 merged (22 FIX-CODE, 5 USER-DECISION, 5 FIX-DOCS, 3 DEFER, 2 DROP), 1 Critical.
| Lane | Raw | Dup | Unique verified | Unique Important+ | Dropped |
|---|---|---|---|---|---|
| hook-surface | 10 | 4 | 7 | 3 (incl. the Critical) + 1 shared | 0 |
| deploy | 13 | 4 | 13 | 4 + 1 shared | 0 |
| privacy | 7 | 1 | 5 | 1 | 2 |
| omissions | 11 | 3 | 11 | 1 | 0 |
Notes: the Critical was an allow-exception that exited early on a per-line match, so a second line rode along; only live exit-code probes with crafted input found it, so keep asking hook lanes to feed the real script. Deploy found the one data-loss bug by reproducing it in a throwaway repo. Fix-wave lesson: a fix brief that names a "remove X" ruling should ask whether to prompt instead; the user revised one mid-wave. Every lane produced a unique Important+ this run.
