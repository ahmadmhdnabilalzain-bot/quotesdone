# PROMPT — next session

Copy everything below the line into the new session.

---

Read `docs/sessions/HANDOVER_2026_08_11_THE_CHAIN_GETS_ITS_NUMBERS.md` first — it carries the
measurement and the decisions already made, so you do not re-derive them. The `quotesdone-session`
skill applies automatically.

The specs are the contract, all eight:

```
C:\Users\Opera\OneDrive\Desktop\quotesdone archeticture.txt
C:\Users\Opera\OneDrive\Desktop\OS.txt
C:\Users\Opera\OneDrive\Desktop\OS 2.txt
C:\Users\Opera\OneDrive\Desktop\customer portal.txt
C:\Users\Opera\OneDrive\Desktop\supplier portal.txt
C:\Users\Opera\OneDrive\Desktop\suppliers categories.txt
C:\Users\Opera\OneDrive\Desktop\quotesdone agents and knowledge.txt
C:\Users\Opera\OneDrive\Desktop\open router.txt
C:\Users\Opera\Downloads\QuotesDone_*_v2026.07.31.zip   (all six)
```

Start with the clock: `select now() at time zone 'utc';` — Dubai is UTC+4. Do not report the
OpenRouter balance; I top it up and it does not gate your work.

**THE STANDARD — the only definition of done.** THE COMPANY CAN OPERATE, LEARN, MANAGE ITSELF,
IDENTIFY PROBLEMS, MAKE PROFESSIONAL DECISIONS, IMPROVE ITS PERFORMANCE, AND ACTIVELY WORK TOWARD
AED 1,000,000 IN REVENUE BY AUGUST 2027 WITH MINIMAL FOUNDER INVOLVEMENT. Not "the agent exists".
Not "the workflow runs". Not "the table was created."

The one business objective is AED 1,000,000 by August 2027, and it must flow downward: management
decides what departments must achieve, departments decide what employees must achieve, employees
decide how to execute. I do not define the method. The system derives it.

Every AI employee belongs to a department, has defined responsibilities, develops real expertise,
knows its department's objectives, receives tasks and priorities from management, reports results
back, has measurable KPIs, is monitored against them, learns from outcomes and failures, improves
its methods, coordinates with other employees, and owns the operational decisions in its scope.
Management operates the same way. A failure is traced up the chain to the employee, workflow,
knowledge source, prompt or rule that caused it, corrected, and the KPI re-checked. A knowledge gap
is never answered with a weak guess: retrieve company knowledge, consult a specialist, research
through an approved tool, request what is missing, raise a knowledge-gap task, escalate to a
manager, then learn from the outcome.

**YOUR AUTHORITY.** Technical architecture, agent design, role allocation, org structure, workflow
design, KPI implementation, learning mechanisms, management hierarchy, observability and
orchestration are yours to decide and do. If an agent is missing, if two should be one, if one
should be several, if a department is wrong, if responsibilities sit with the wrong agent, if KPIs
are meaningless, if management cannot supervise, if agents cannot learn or communicate, if decisions
are untraceable, if knowledge does not reach the employee that needs it, or if a workflow blocks
autonomy — correct it. Build on good work, repair bad work, connect disconnected work, replace what
fundamentally prevents the intended behaviour. Do not preserve bad architecture because it exists;
do not rebuild working components for tidiness. Escalate only what cannot be inferred from the
AED 1M objective, existing policies, commercial rules, the business model, the specs, or the
operating model above. Stripe refunds still need me.

---

## THE FIRST THING — the workflow engine has finished five runs in its lifetime

Measured on production 2026-08-12 and instrumented so it now says so itself:

```
workflow_run          195 running · 7 failed · 5 done
workflow_step_run   2,655 total · 2,310 queued · 195 ready and unfinished · 143 done · 7 failed
of the 195 ready:       0 executable
                      132 carry NO action_class at all
                       63 carry one that matches no eligible executor
                       71 name an actor that DOES resolve to an active employee
                        5 distinct actors in total across all 195
eligible executors     22 (edge, active, low risk, advisory-safe, reversible, no human notice)
```

**Every in-flight workflow run is parked on a step nothing can pick up.** `fn_workflow_step_sweep`
runs every ten minutes and queues work **only** for a registered low-risk reversible edge executor.
Most workflow steps name an `actor_role` — an **employee** — and **nothing routes a ready step to
the employee who owns it.** That is the missing half of the engine.

`failed_workflows` measures 58.33% over runs that reached a terminal state (7 of 12). The company
now reports this: the sweep writes an `agent_runs` row at `status='error'` naming the parked count,
and `error` reaches my brief since #211.

**Build the employee-side dispatcher.** 71 of 195 are dispatchable today across only 5 distinct
actors, so it is well bounded. `org_tasks.assigned_agent` exists now and is the natural landing
place. Decide the completion path — a dispatched step has to be able to reach
`fn_workflow_step_done` — and cap the batch, because 195 tasks at once is a flood, not a fix.
The 124 steps whose actor does not resolve (`owner` and friends) are the fifth identity vocabulary
in this database; fix the vocabulary rather than special-casing it.

## THEN, in order

2. **The 39 company goals and 19 employee KPIs still without a measure.** Both are named with the
   reason for each in `scripts/sql/twelve_of_the_fifty_five_decorative_goals_can_be_measured.sql`
   and `scripts/sql/ten_employee_kpis_that_could_always_have_been_measured.sql`. Five need a fixture
   or holdout set that does not exist — building the fixture IS the work. Ten need demand that does
   not exist. Do not write SQL for a goal you cannot honestly measure; a decorative number in front
   of an employee is the defect, not the fix.
3. **Model cascading**, which is still correctly blocked. Measured 12 Aug: 1,729 calls in 7 days,
   **7 carry a confidence, and 647 sonnet-5 calls carry none**. The two functions that do emit one
   always emit exactly 1.000, which carries no information. The prerequisite is the output contract:
   `agent_brain`'s `@@ACTIONS@@` JSON is the place, but confidence is logged by `_shared/llm.ts`
   BEFORE the response is parsed, so the gateway must return the `ai_cost_log` row id for the
   confidence to attach to the right call. Attaching it to "the most recent row" under concurrency
   would produce exactly the wrong-subject number this codebase keeps producing. `fn_ai_route`
   already downgrades at ≥0.95 and escalates below the floor, so a real confidence activates routing
   that already exists.
4. **The remaining spec #3 UI gaps** — AI side panel, interactive documents, drag & drop, workspace
   snapshots, live collaboration, visual workflow builder. Also `employee-performance-trend` in the
   Row #3 scorer: it needs >1 observation per employee AND a series component in `AgentDrawer`.
   `employee_kpi_history` began producing a second observation from 12 Aug, so the data side is
   solved; the UI reader is not. Its current source is `employee_kpi.created_at` — a KPI
   *definition's* authoring date, not a measurement — and pointing it at
   `employee_kpi_history.measured_on` is the right fix, with a UI reader to go with it.
5. **The five delete proposals now open as `agent_actions`** (`kind='delete_proposal'`). Each wants
   remove / retire / keep-with-a-reason. The 96 `model_policy_by_identity` rows are the interesting
   one: they are no longer merely inert, they are **superseded** by `org_agents.routing_tier`.

## WHAT I DECIDE, NOT YOU

- **Resuming supplier invites.** `invite_enabled` is `false`, cap 10/day, 7-day bounce 13.3%,
  5 of 62 lifetime invites bounced. **19,841 leads with an email have never been invited; at 10/day
  that is 5.4 years against 355 days to target.** Sending into that bounce rate risks the sending
  domain. The ramp defect that let it accelerate into a bad rate is fixed (#209). The list needs
  verification before volume, and buying verification is money.
- **The spend split.** 85.4% of 30 days of model spend went to `leadership`, 0.04% to `marketplace`,
  against revenue of 0. Filed weekly to `ai_director` as `org_tasks` 1309. It asks for a decision:
  shift capacity toward demand, or record why the internal work is the faster route.

## WHAT MUST NOT BE REBUILT

`os_objective` (50 of 50 measurable). `org_agents.manager_key` (93 of 94, acyclic). The review chain
(1,557 rows, 7 stages). `fn_agent_context` — 34,892 characters with a documented history of one bug
per rewrite; extend it through `fn_agent_context_capped`, never edit it. `kb_search` (hybrid,
probed). `fn_scenario_run` (already honest — says `staffed`, not `ready`). `fn_kpi_review` (turns a
MISSED KPI into a task and an outcome record, weekly). `drawing_boq` (a full UAE quantity-surveyor
vision pipeline, wired into five functions, proven by a successful call on 29 Jul). The rehearsal
harness in `scripts/rehearsal/`.

## HOW TO WORK

Verify by execution in the same turn, on a non-zero effect, never on an HTTP 200. Use the
aborted-transaction probe for writes. Deploy to both Supabase projects. Merge via PR, never straight
to main. Never weaken a check; if a fix makes one harder because the old pass was false, say so in
the commit. **Never state anything you are not 100% sure of — a narrow check never licenses a broad
claim.**

**Nine brief diagnoses died on measurement last session and each would have been wasted work.**
Re-measure before building what a brief proposes. Two of my own findings were wrong and I corrected
them in the same session — do that, out loud, rather than quietly.

## TRAPS — the new ones are at the top

- **`apply_sql.mjs --promote` cannot carry a `REVOKE`.** It promotes by posting
  `pg_get_functiondef()` read back from staging, and that emits the CREATE and nothing else. A new
  routine promoted **without `--ddl`** reaches production **granted to PUBLIC**. This is how
  `fn_employee_scorecard` became anon-executable for twenty minutes on 11 Aug.
- **`pg_get_functiondef` emits no trailing semicolon** — valid for one definition, a syntax error
  for several concatenated.
- **`jsonb_array_elements(x) c` names the FROM item, not the column.** You get `r.value`, not `r.c`.
  Use `as t(c)`.
- **`scripts/checks/sql_files_match_live.test.mjs` ranks files by COMMIT order, not mtime.** An
  uncommitted file is invisible to it. Its baseline is now **0** — any drift fails. Raising it is
  not how you fix a failure there.
- **`ai_gateway` defaults its wall to 55,000 ms** when the caller does not send `client_timeout_ms`.
  `_shared/llm.ts` now sends `dTo + 5000`; anything calling the gateway directly must declare it.
- **Reading a table in the same statement that refreshes it** returns the pre-update snapshot. I
  nearly reported `os_objective` #44 as lying because of this.
- `least(100.0, NULL)` = 100.0. BEFORE triggers fire in name order. `revoke … from anon` is a silent
  no-op under PUBLIC; revoke from PUBLIC. `fn_agent_context` ignores any `p_max_chars` below 22,000
  — always call `fn_agent_context_capped`. PostgREST runs as `authenticator` with
  `statement_timeout=8s`. A PARTIAL scorer run is not a score — look for `N/152`. Do not run the
  pack scorecard against a project while the Row #3 scorer runs. Vercel builds fail
  non-deterministically on a `next/font/google` module; a redeploy clears it, mechanism unknown, do
  not assert one. Signature parity is not behaviour parity.

## END-OF-SESSION SWEEP, EVERY TIME

GitHub Actions (a zero-step job means quota, not code), Vercel, both Supabase projects, Row #3
scorer to completion, pack scorecard on both, `fn_os_portals_gates()` on both,
`project_parity.mjs` → BOTH PROJECTS IN SYNC, and `sql_files_match_live.test.mjs` → drift 0.

**Save the Row #3 per-check verdict list every run.**
`docs/sessions/ROW3_VERDICTS_2026_08_11.txt` is the first one that has ever existed; before it, a
126 → 125 move was unattributable because only the total was recorded.

## STATE AS OF 2026-08-12 ~21:20 UTC — do not re-derive

```
main 59fe58e · 20 PRs merged this session (#199–#218) · production READY on quotesdone.com
Row #3 125/152, identical red set across three runs · gates 23/23 both
parity BOTH PROJECTS IN SYNC — 197 edge fns · 420 tables · 855 functions · 155 triggers ·
  0 tables without RLS · 56 anon-executable SECURITY DEFINER
advisors 0 ERROR (security and performance) · scripts/sql drift 0, ratchet at the floor

company_goals         63 · 24 measurable (was 8)
department_objective  66 · 24 measurable · 24 measured · 0 failed (was 0 measurable)
employee_kpi         124 · 104 measurable · 84 with a stored actual (was 0)
employee_kpi_history  live — one row per KPI per UTC day, unique index prevents fabricating a trend
org_tasks            840 · 143 with an owning employee (was 0) · newest is 1309, the spend finding
org_agents            93 active · 0 without responsibilities (was 14) · routing_tier on all 93
scenario_library      32 · all 16 of spec #7's named failures covered
workflow              19 · 2 founder gates, both on money
demand side           customers 0 · inquiries 0 · quotes 0 · transactions 0

Pack scorecard NOT RUN — it needs --packs=<extracted dir>, the six zips extracted, which are not in
the working tree. Last recorded: INGESTED 100%, IN USE 37/37, RETRIEVABLE 46.6%. Not claimed current.
```

New routines, all on cron, all revoked from PUBLIC: `fn_dept_objective_measure` (03:25 daily) ·
`fn_employee_kpi_measure` (03:30) · `fn_goal_decompose` (03:10 Mon) ·
`fn_spend_concentration_check` (03:40 Mon) · `fn_delete_proposer` (03:50 Mon) · plus
`fn_employee_scorecard`, `fn_employee_kpi_trend`, `fn_cost_per_os`, `fn_alert_severe`,
`fn_routing_tier_model`, `fn_employee_responsibilities_backfill`.

Do not stop and do not check in. Take the next item. Keep going until I say stop. If you hit a hard
limit that makes further work unreliable, hand over honestly and name exactly what is unfinished —
a truthful hand-over is worth more to me than a green tick.
