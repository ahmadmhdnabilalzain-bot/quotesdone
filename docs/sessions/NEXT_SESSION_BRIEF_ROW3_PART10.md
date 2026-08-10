# Row #3, part 10 — opening brief: FINISH THE REST

Row #3 spec: `docs/specs_row3_executive_ui.txt`. Scorer: `scripts/staging/verify_os2_blueprint.mjs`.
State: `docs/sessions/ROW3_STATE.md` (session 8 block is at the top and carries the evidence).
Pack scorecard: `scripts/kb/pack_scorecard.mjs`.

**All numbers below were measured on production at 2026-08-10 ~20:45 UTC. Re-measure them before
acting on any of them.**

---

## 0. READ THE CLOCK FIRST

```sql
select now() at time zone 'utc';
```

Dubai is UTC+4. Query `cron.job_run_details` — never take a cron table in a brief on faith. A
PARTIAL scorer run is not a score: check for the `SPEC FILE #3 … : N/152` summary line, and if a
check reports ERROR rather than NOT MET, that is an infrastructure failure and not a finding —
**do not run a pack scorecard against the same project while the scorer is running**, it caused
exactly that in part 9.

---

## 1. HOW THIS SESSION IS WORKED

**Work continuously. The only thing that stops you is the founder typing "stop".**

- **Do NOT report progress.** No "I've finished X", no stage reports, no summaries between items,
  no asking whether to continue. He has said this four times.
- **Do NOT ask questions.** Make the call, do it, put the reasoning in the commit.
- **Do NOT wait.** Start slow things in the background and pick up different work immediately.
- **The ONE approval that exists is a refund.** Nothing else.
- **Speak once, at the end**, when the scorecard proves it is done.

---

## 2. THE PART-9 CLOSING STATE — DO NOT REBUILD ANY OF IT

```
                              production          staging
pack scorecard, every pack        100%             100%
artefacts IN USE             37 of 37         37 of 37     probe-measured, not asserted
OS_PORTALS gates             23 of 23         23 of 23     zero open
Row #3                        121/152                       0 errored, 0 regressions
```

Built and proved in part 9. Check before writing anything:

| already true | evidence |
|---|---|
| All twelve `ops_kb_stage` projections are read | `fn_ops_department_context` ← `fn_agent_context`, resolves live→target via `department_crosswalk` |
| One HTTP action invoker, risk-ordered | positive 200 on `ai_health`; refused=5 dispatched=0 on the five most dangerous classes, in an aborted transaction |
| `action_worker` drains the employee inbox | 123 items, 20 employees, 3,366 chars average, 3.00 AED |
| 344 route tests + 282 scenarios run hourly | `kb_route_tests_hourly`, `ops_scenarios_hourly` |
| Corpus integrity guard | `fn_kb_corpus_integrity`: staged = checkpointed = deployed = 115,148 |
| Mobile sign-in for the OS | `login_otp` resolves `admin_mfa_phone` → `admin_emails`; SMS sent, `known:true` |
| WhatsApp founder command channel | `fn_identify_contact` returns `founder`; answered "print me last month revenue" from real state |
| Release approval recorded | `founder_release_approval`, release `f756bcb`, expires 30 days |
| All 23 OS_PORTALS gates measured by `fn_os_portals_gates()` | not a literal in a JS file any more |

**`IN USE` is now a probe, not a sentence.** Every scorecard row executes a routine and counts what
comes back. If you add an artefact, add its probe.

---

## 3. WHAT IS PENDING — MEASURED, NOT GUESSED

### 3.1 THE SAME DEFECT, A THIRD TIME: ~47 ITEMS ADDRESSED TO IDENTITIES THAT DO NOT EXIST

82 `agent_actions` are still `pending`. Broken down by whether the addressee is an active
`org_agents` row:

```
knowledge_task           23   to_active 0
strategy_rec              8   to_active 0
objective_step            6   to_active 0
marketing_recommendation  4   to_active 0
ai_improvement            4   to_active 0
report_task               2   to_active 0
improvement_question      3   to_active 3   <- the sweep takes these
handoff                   3   to_active 3   <- the sweep takes these
```

Every one of those `to_active 0` kinds is on `action_worker`'s WORKABLE list. They are skipped
only because `fn_agent_action_work_sweep` joins `org_agents … and o.active`, and they are addressed
to `knowledge_curator`, `strategy_ai`, `marketing_ai`, `reporting_ai`, `document_controller` and
similar — **role names that are not employees**.

This is the third instance of one root cause. In part 9 it was the founder: `login_otp` and
`fn_identify_contact` both turned his own number into nobody. Here it is a work queue addressed to
roles the org does not model. Decide it properly — either those keys map to real employees, or
they become employees, or the writers stop inventing addressees — and fix it at the writer, not by
widening the sweep's join.

### 3.2 THE 24 FOUNDER-HELD ITEMS

`customer_escalation` 9, `legal_flag` 6, `security_incident` 3, `prompt_approval` 2, plus
`compliance_update`, `finance_alert`, `finance_marketing_budget`, `incident`. `action_worker`
refuses these BY NAME and always will. They are not a bug. They need either a human decision or a
narrower automation with its own gate — and mass-closing them is forbidden.

### 3.3 339 `analysis` TASKS WITH NO EXECUTOR

```
org_tasks open                 393
 … sweepable by the invoker     51   (recommend, knowledge_acquire, exec_review, compliance_check)
 … action_class = 'analysis'   339   no executor exists
```

`cos_execute` clears about three an hour with a model call each. The 51 drain themselves through
`org_task_execute_sweep_hourly`. The 339 do not, and that is the real backlog. Either `analysis`
gets an executor, or `cos_execute` gets throughput, or the tasks are wrong to exist. Measure which
before building.

### 3.4 TWELVE EDGE EXECUTORS THAT HAVE NEVER RUN

The invoker dispatches `low + advisory_safe + reversible` only — 27 of 39. The other 12 are 8
medium, 3 high and `escalate_founder`. Seven of them are irreversible with **no
`compensation_action_class`**, and the invoker refuses those by design, which is OS_PORTALS gate 19
being enforced rather than claimed. Widening is a real decision per class, not a predicate change:
declare a compensation, or leave it refused and say so.

### 3.5 ROW #3: 31 CHECKS STILL NOT MET

121/152. The full list is in `docs/sessions/ROW3_STATE.md`; the honestly-blocked ones are recorded
there with the reason and **must not be "fixed"**. Do not re-litigate those. The rest, grouped:

- **UI/explainability**: `explain-knowledge-used`, `explain-alternatives-considered`,
  `explain-confidence-score`, `s36-recommendation-seven-fields`, `s27-knowledge-seven-fields`
- **Employee workspace**: `employee-current-thoughts`, `employee-performance`,
  `employee-performance-trend`, `employee-knowledge-used`, `employee-learning-progress`
- **Simulation**: `what-if-projected-deltas`, `what-if-confidence-score`,
  `what-if-approve-from-simulation`, `s34-stress-six-scenarios`
- **Time machine**: `time-machine-scrub`, `time-machine-restores-six-dimensions` (the second
  completes on its own ~24 Aug — leave it)
- **Scoring/intel**: `s30-marketplace-eight-inputs`, `s25-quality-latency-cost`,
  `s29-scan-five-questions`, `intel-customer-behavior`, `s32-reputation-six-dimensions`
- **Structure**: `company-map-entities`, `s22-graph-navigation`, `s21-no-polling`,
  `s33-replay-six-tracks`, `s24-board-before-major-decisions`, `s23-reallocation-three-classes`
- **Blocked on real-world facts**: `s26-discover-suppliers` (**Apify is deliberately cancelled
  until ~Feb 2027 — do NOT "fix" this**), `s26-compare-capabilities`,
  `personalization-learns-founder-habits`, `exec-meeting-priorities-agreed`

`s24-board-before-major-decisions` is already scoped precisely in the state file: one guarded
`perform fn_board_review(...)` before `fn_decide`'s final return. It is a 30-day universal, so it
cannot flip before ~9 Sept whatever you do.

### 3.6 IN FLIGHT, FINISHES ON ITS OWN

- **Embedding backfill.** 14,589 of 115,148 pack rows embedded, ~31/min, ~2 days. It is FREE —
  in-region gte-small, not OpenRouter. **A batch above 5 returns HTTP 546 WORKER_RESOURCE_LIMIT**;
  add invocations, never batch size. Delete `kb_embed_backfill_boost` when nothing is unembedded.
- **Three daily crons have not had a scheduled run yet** — `kb_corpus_integrity_daily` 03:40,
  `model_catalog_drift_daily` 03:50, `tool_readiness_daily` 03:55. Each was executed by hand at
  build time. Confirm their first scheduled runs.

### 3.7 FOUR TRUE FINDINGS RECORDED AND NOT FIXED

- **`exec_agents` is at the edge runtime's ceiling.** Seven officers with a model call each ran
  ~130 s and one run hit `IDLE_TIMEOUT` at the platform's hard 150 s. `timeout_seconds` is 140 so
  the invoker records its own give-up rather than an unexplained kill. It needs to fan out or
  checkpoint before it can be relied on unattended.
- **`fn_p2c1_rollback_stage_b6` and `_b7` abort themselves** on "Stage B 13/14 after rollback": a
  Stage B selftest case depends on an object the partial rollbacks remove. The FULL Stage-B
  rollback passes. Do not relax the post-condition to make it green.
- **Staging cannot rehearse the rollback** — "brand_policy identities were not restored". Staging
  lacks the data the rollback restores.
- **`llm_calls` is a dead table**, frozen at 56 rows since 3 Aug. `fn_llm_log` writes
  `ai_cost_log`. Anything still reading `llm_calls` is reading a corpse.

---

## 4. THE TRAPS, EVERY ONE OF WHICH BIT IN PART 9

1. **Do not assert a blocker. Measure it.** Three items were reported as "the founder's" and all
   three were mine — every Twilio credential was provisioned and authenticating, Stripe is live
   keys, and WhatsApp had been answering messages the whole time.
2. **A branch guarded by a condition that cannot occur is not a feature.** Two were found in one
   afternoon: `fn_kb_route_activation_blocked` THREW instead of blocking (`text[] || 'literal'`,
   22P02) and a new `fn_ai_route` branch was unreachable. Both had been "working" for months
   because nothing reached them.
3. **grep does not prove a reader.** `fn_ops_department_context` looked like a reader of
   `kb_stage.decision_rules` and was matching a substring of `ops_kb_stage.decision_rules`.
4. **A 200 is not success.** `quote_compare` returned `{ok:false}` at HTTP 200 for weeks. Assert on
   the body too.
5. **`idempotency_key` is UNIQUE.** A not-exists guard that only excludes live statuses collides on
   a previously FAILED row. This bit twice, in two different sweeps.
6. **The guards in this estate are good — let them stop you.** A CHECK constraint, a CI credential
   test, a verify_jwt drift check and a root-cause trigger each caught a real mistake in part 9.
   Read what they say before working around them.
7. **Read the dates.** A 24-hour failure window keeps showing failures that were fixed hours ago.

---

## 5. FOUNDER RULES, UNCHANGED

Everything deploys to **BOTH** Supabase projects — production `htdblwldjkcgjvmqkbeh`, staging
`pglpqrhvozwepymcuunn`. Nothing is left on staging. Verified by **EXECUTION** in the same turn,
never by typecheck or by reading. Committed and merged via PR.

A MISSING verdict is a BUILD ORDER. Never fabricate, back-date or mass-close data to turn a gate
green, and never weaken a check — if a change makes a check HARDER because the old pass was false,
that is correct, and say so.

**Every SECURITY DEFINER function you CREATE is granted EXECUTE to PUBLIC.** Revoke it in the same
migration. `CREATE OR REPLACE` preserves the ACL, so do NOT revoke there — that removes a grant
someone already decided. Production sits at 56 anon-executable and did not move in part 9.

**The Supabase CLI bundles without typechecking.** `deno check` is the green build. And a function
importing `_shared/llm.ts` must be named in
`supabase/migrations_history/*_audit_95_llm_path_scoped_credentials.sql` or CI refuses the merge.

---

## 6. WHAT IS ACTUALLY HIS

Nothing is blocking. Everything below is a decision, not a credential:

1. **The 24 founder-held actions** — whether an AI employee may ever settle a customer escalation,
   legal flag or security incident without him seeing it. Part 9 said no and held them.
2. **The dormant workforce** — 47 of 66 employees do nothing on a given day, and ~47 pending items
   are addressed to roles that are not employees at all. Whether to staff those roles, retire them,
   or stop writing to them.
3. **Apify** — deliberately cancelled until ~Feb 2027. `s26-discover-suppliers` stays red on
   purpose.

OpenRouter: ~16 AED/day. Embedding is free. If the balance empties, say so in one line at the end
and keep working — most of what remains is model-free.

---

## 7. YOU ARE DONE WHEN

- `node scripts/kb/pack_scorecard.mjs` still reads **100% / 37 of 37** on both projects,
- `fn_os_portals_gates()` still reads **23 met, 0 open** on both,
- the pending `agent_actions` queue holds **only** items that genuinely need him, with the
  identity defect in 3.1 fixed at the writer,
- Row #3 is re-measured on a **COMPLETE** run and every check that moved is either a real gain or
  an explained true finding, with zero regressions against **121/152**,
- and the end-of-session sweep of GitHub Actions, Vercel and both Supabase projects reports what
  was checked and what was found, including "nothing", with the dates read.

Then one message.
