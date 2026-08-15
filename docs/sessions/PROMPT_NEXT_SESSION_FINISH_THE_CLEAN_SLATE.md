# Finish the clean slate — prompt for the next session

Copy the block below into a new session. It is self-contained.

---

Read `docs/sessions/HANDOVER.md` and `.claude/skills/quotesdone-session/SKILL.md` first, then finish
the clean-slate work started 15 Aug 2026 on branch `repair/v3-certification-remediation-1`.

**The founder needs exactly this sentence at the end, and will accept nothing else:**

> both projects are 100% identical word by word and exporting from either wont make any difference.
> also, there is not a single staging data in either, both of the are updated to the latest upgrades
> we did till this moment

Say it only when every clause is true and measured. "Both projects" means **Supabase and GitHub**.
If a clause is not true, say plainly which one and why — never soften the sentence.

## Standing rules that apply from the first minute

- **No OpenRouter calls.** Every provider route is held open-circuit in `llm_route_health`. Do not
  release it. Before anything that would spend, quote the estimated cost and WAIT for his answer.
  Release only on his explicit instruction:
  `update llm_route_health set open_until = null, opened_reason = null;`
- **He is not a coder.** Never ask him a technical question. Decide it yourself and say what you
  decided. Escalate only money, destructive production changes, and facts only he holds.
- **No step-by-step progress updates.** Work until done, then reply once.
- There is **ONE Supabase project**: production `htdblwldjkcgjvmqkbeh`. Staging
  (`pglpqrhvozwepymcuunn`) was DELETED on 15 Aug 2026 and does not exist.

## What is already true — verified, do not redo

| | |
|---|---|
| routines: repo `scripts/sql` ↔ database | **349 / 349 identical**, 0 drifted, 0 missing |
| full schema export ↔ `supabase/schema/full_schema.sql` | **byte-identical**, 53,224 lines, 2,836,943 chars |
| staging Supabase branch | deleted; `list_projects` returns one project |
| staging/demo data in production | inquiries 0 · customers 0 · quotes 0 · matches 0 · transactions 0 · projects 0 · claimed leads 0 · orphaned scores 0 · our test contacts 0 |
| production leads kept | **20,465 real leads**, 20,465 scores, 15,306 capabilities |
| OpenRouter since the hold | 0 calls, AED 0 (last spend 02:51:33, hold landed 02:51:36) |
| 13 checks retargeted to production | assertion counts identical before/after in every file |

Verify identity at any time with:
```
node scripts/checks/sql_files_match_live.test.mjs
node scripts/checks/export_from_either_source_is_identical.mjs
```

## What is left — four things

### 1. Merge PR #387 into main

`main` does not yet contain the work. The branch is merged-ready (conflicts already resolved).
**Both content conflicts, if resolved the wrong way, reintroduce fixed defects** — main's
`ai_gateway/index.ts` predates the attempt-level cost capture, and main's `_shared/llm.ts` still
returns a truncated model answer as if complete. HEAD is correct on both; it is what is deployed.

### 2. Rehome the homeless tests — DO NOT DELETE THEM

`scripts/staging/` is built around `assertNotProduction()`, which refuses production by design, so
these cannot simply be retargeted. **The decision is already made: rehome, do not delete.** They are
real coverage.

- `scripts/staging/journey_test.mjs` — 739-line end-to-end journey
- `scripts/staging/smoke_staging.mjs` — the capped smoke `workflow_ownership_alignment.test.mjs`
  defers to for the paid half of its claim
- `scripts/staging/verify_intake_routing.mjs` — pins two real live defects
- `scripts/staging/apply_missing_objects.mjs`
- `scripts/staging/demo_factory.mjs` — 1,448-line fixture factory, **49 files import `REF as STAGE`
  from it** and therefore target the dead project without containing its name

**How:** run them against production inside an **aborted transaction** — do the write, count the
effect, then `raise exception` with the counts so it rolls back and the numbers still come out.
That technique is used throughout this repo and is what made every guard in this session provable
without leaving a row behind. Keep `assertNotProduction` as a guard for anything that cannot be
made rollback-safe; do not weaken it.

### 3. Retire the five that compare two projects

Their whole purpose was diffing production against staging. With one project they measure nothing,
and a check that passes while measuring nothing is worse than no check. Preserve the reasoning in
their headers somewhere before deleting — especially `staging_grant_parity.mjs` (records 464
anon-executable holes) and `staging_monitor_cron_parity.mjs` (records which crons are safe to
replicate).

- `scripts/checks/project_parity.mjs` (+ its dead companion `staging_cron_exclusions.json`)
- `scripts/sql/staging_grant_parity.mjs`
- `scripts/sql/staging_monitor_cron_parity.mjs`
- `scripts/kb/sync_executor_classification.mjs`
- `scripts/kb/sync_ops_projections.mjs`

### 4. Fix the rest, then re-verify

- `scripts/apply_sql.mjs` — the mandated deploy path. It imports from `demo_factory.mjs` and fails
  with `management API 400: {"message":"Resource has been removed"}`. **Fix this first** — nothing
  else can be applied cleanly until it works.
- `scripts/verify_deploy_parity.mjs` — remove the `--staging-only` flag along with the target, or it
  becomes a flag that prints a vacuous "DEPLOY PARITY OK" measuring nothing. Then run
  `--all` against production: **all 202 edge functions must carry the repo's code.**
- `scripts/checks/runtime_connection_gate_b.mjs`, `scripts/checks/v3_remediation_regression.mjs` —
  staging is only a default `--ref`; both make live agent calls, so they stay held while OpenRouter
  is held.
- `scripts/checks/a_phone_cannot_select_an_account.test.mjs` — has a deliberately staging-only test
  ("two accounts on one number are refused, not guessed") that inserts two demo customers. Preserve
  the assertion; make it rollback-safe.
- `scripts/checks/export_from_either_source_is_identical.mjs` — **leave alone.** It names the dead
  ref only inside a portability *detector*, not as a target. Editing it weakens the detector.

## Two real production defects found and deliberately left failing

Do not paper over these; they are genuine findings, not merge damage.

1. A decided agent action writes a `decision_trace`, but `knowledge_refs->>'knowledge_count'` is
   null, so the trace does not carry the knowledge ids `fn_record_context_retrieval` recorded
   moments earlier.
2. `v3_runtime_behaviour.test.mjs` asserts the self-review refusal matches
   `/cannot be its only reviewer/`. The guard fires correctly, but `org_align_01` rewrote its
   wording. Reconcile the message or the regex — do not just relax the regex.

## Lessons from 15 Aug that will cost you time if ignored

- **Check what a pattern actually matched before acting on its count.** A demo scan over the leads
  returned 28 hits; 26 were real UAE companies — soil **TEST**ing labs, INTER**TEK**, "BRIGH**TEST**
  TRADING", six **DEMO**LITION contractors, "Amazon At**test**ation".
- **A grep for a literal misses indirection.** 39 files named the dead project; 87 targeted it.
- **`scripts/sql` is append-only.** A file is the record of a change that was applied and is never
  edited. To change a routine, add a new file.
- **Verify direction before reconciling drift.** One "drift" was live carrying an
  `insufficient_credit` branch the repo never had — the rule that stops the company retrying into
  an out-of-credit wall. Applying the repo file would have deleted it.

## Finish line

When 1–4 are done, re-run all of these and only then give him his sentence:

```
node scripts/checks/sql_files_match_live.test.mjs
node scripts/checks/export_from_either_source_is_identical.mjs
node scripts/verify_deploy_parity.mjs --all
npm test
```
