---
name: checkpoint-9-sep-the-phase-removal-landed
description: "State after PR #541 merged 9 Sep 2026 — Phases A-D gone from repo and database, local suite 0 red for the first time, next agent is the signed-in customer/supplier seat"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-08T23:28:09.684Z
---

**READ THIS FIRST ON RESUME.** Supersedes
[[checkpoint-8-sep-the-sweep-is-prepared-not-run]].

Four PRs merged to `main`: **#541** (repo catches up with the database), **#542** (rescues an
untracked file), **#543** (366 phase SQL files + 315 docs), **#544** (the last 142 artifacts).
`main` is at `c441409`.

**The phase names are gone.** What still carries one, and why each is deliberate:
- `scripts/checks/*.RETIRED.mjs` (17) — their names ARE the record; each header says what was
  removed and why it was retired rather than edited until it passed.
- `supabase/migrations/` + `migrations_history/` (23) — append-only, never edited.
- `scripts/sql` files with the word inside a SENTENCE name (e.g.
  `the_phase_programme_is_removed_entirely.sql`) — the record of the removal work. No `phase_` prefix.
- **The founder's own inputs, NOT ours to delete** — `QuotesDone_PHASE_D_DETERMINISTIC_.../` and
  `docs/sessions/PROMPT_PHASE_B|C_*.md`. Flagged to him in #544; a spec he shared is his to retire.

## Where the estate stands, all measured 9 Sep 2026

| | |
|---|---|
| local check suite | **97 tests, 97 pass, 0 fail** — first time at zero |
| support acceptance | 103/103, 0 critical, 0 groups unrun |
| canonical routine manifest | 0 findings |
| schema mirror | identical: YES, 0 project refs embedded |
| edge function deploy parity | 54/54 carry the repo's code |
| phase objects / routines | 0 / 1 (down from 80 / 125) |
| cron | 1 job (`wa_flush`), 0 active, 0 failures in 24h |
| org | `org_agents` 2 rows — `ceo`, `customer_support`; `org_departments` 0 rows |

## What this session did

- Deleted the four phase script trees (90 files) plus `scripts/tmp_diag`. Safe only because the
  shared SQL client moved from `scripts/phase_b/lib/db.mjs` to **`scripts/lib/db.mjs`** first — it
  is imported by `deploy_functions.mjs`, all of `scripts/kb/` and a dozen checks.
- Retired 18 checks with their subjects, repaired 4 others. Details in
  [[checks-retired-with-their-subject]].
- Cleared the 61 local reds — see [[ci-green-does-not-mean-npm-test-green]].
- Fixed a live customer-facing defect: the notification gate was DROPPING customer messages.
  See [[an-fk-to-an-emptied-table-fails-every-writer]].

## Open, named, not fixed — each is his call or the next agent's

1. **Automation is stalled and the alarm is right.** 0 active cron jobs; `founder_alerts` holds 9
   "SCHEDULER DOWN — automation stalled" rows. This is the intended consequence of deleting the
   machinery, not a regression. It comes back when the right agents are built.
2. **Stale-instruction supersession is unimplemented.** The old founder path enforced it;
   `fn_ceo_command_submit` has no supersession branch. A gap in the company, not in a check.
3. **`org_tasks.dept_key` is a label with no referent.** The FK was dropped; the column stays
   because 33 live routine bodies read or write it and an index hangs off its attnum.
4. **`agent_actions.decision_log_id` has no writer on insert** since the gate was dropped. Harmless
   only because the filler was made null-tolerant on 3 Sep.
5. **`kb_stage.scenario_tests` (3,324 rows) carries a guard whose hint names a dropped routine.** The
   guard still fires and its session-variable escape hatch still opens; what was lost is the
   LEDGERED path — expectations can now be changed with no audit entry.
6. **Recommended check, not built:** no `agent_knowledge` row written by the `knowledge_exam` loop
   may carry its own question's `reference_answer`, and no row already marked `unsourced` may be
   re-promoted to `author_verified`. That guards the loop he KEPT.

## Next

The founder's stated next agent: **the signed-in customer/supplier seat** — the one that handles
inquiries and suppliers. The CEO runtime (`ceo_agent`, `fn_ceo_classify`, `fn_ceo_command_submit`,
9 intents, 34 classifier rules) is live but its end-to-end testing is still queued behind finishing
the customer_support agent's. See [[the-org-is-two-agents-and-no-departments]].
