# ROW #3 — THE EXECUTIVE UI: 28 → 112 / 152 and rising

Measured on production. Every number below is a scorer run, not an estimate.
Scorer: `scripts/staging/verify_os2_blueprint.mjs`, modules in `scripts/staging/os2_blueprint/`.

---

## Session 6 (10 Aug 2026, opened 05:47 UTC) — THE CLOCK WAS READ FIRST, AND IT PAID

```
select now() at time zone 'utc'  ->  2026-08-10 05:47:29   (Monday)
```

**Opening measurement 112/152 (74%), 0 errored, 0 regressions — up 7 from 105 at 02:33.**
Not one of those seven came from a session. `cron.job_run_details` was queried before anything
else: `opportunity_scan_daily` 03:50, `kpi_review_weekly` 04:00, `index_slowdown_watch_daily`
04:15, `founder_brief_daily` 04:30, `exec_meeting_weekly` and `match_eval_weekly` 05:00 had all
fired; `exec-agents-weekly`, `evolution_scan_weekly`, the three governance monitors,
`marketing_ai_daily` and `reputation_weekly` had not. The 06:00–07:00 window was watched by a
background poller while other work continued, so no minute was spent idling against it.

`match_eval` is green again and it was the previous session's fix, proved by its own run:
05:00 cron `error`, 5 of 5 seeds refused by `leads_approved_implies_verified`; 05:16 manual run
after the fix `ok`, 5 fixtures seeded, precision 100% / recall 100%. The daily
*"CRITICAL: matching is failing"* founder alert therefore stops on its own.

### Built and verified by execution

| change | what it closed |
|---|---|
| Five event emitters — `customer.registered`, `supplier.approved`, `campaign.launched`, `ai.confidence_dropped`, `competitor.pricing_changed` | **`s21-events-nine-classes` 4 of 9 → 9 of 9.** Each fires where the fact becomes true, in the database, so every caller is covered. Verified inside an aborted transaction: customer=1 supplier=1 competitor=1 campaign=1, and ai=1 on a second probe. Nothing persisted |
| `prompt_unmeasured` trigger in `fn_evolution_scan`, and both `evolution_proposal` allow-lists widened to accept `prompting` | **`evolution-proposes-structure` 5 of 8 → 8 of 8 domains.** Prompting was the one domain the schema itself refused |
| three `scenario_library` rows — reveal fee change, paid channel failure, expansion to another emirate | **`future-simulator-forward-questions` 1 of 4 → 4 of 4 classes.** No `last_run`, no `last_result`: none has been exercised |
| `fn_period_report('monthly')` executed | **`s37-benchmark-monthly-report`** — report 142, 18,545 bytes, **16 of 27 competitors named**. 141 reports in 40 days had named none |
| `knowledge_exam` v13 stamps the grader's real confidence, `author_verified`, `source_ref` and a 90-day `review_due` on every fill | **The knowledge validator §7 called open already existed and was mislabelling its own output.** Executed on production: HTTP 200, 3 examined, `knowledge_exam_results` 492 → 495 |

### Two checks flipped on code that had shipped and never run

- **`s35-restructure-four-questions` 0 of 4 → 4 of 4, with no code change.** The four structural
  questions were already inside `fn_evolution_scan`; `evolution_scan_weekly` last fired **3 Aug**,
  before they were added. Today's 06:00 run was their first execution and produced **12 `audit_gap`
  proposals** off real numbers: 44 of 66 employees dormant, six operating systems over 5 open tasks
  per head (Operations 19.0, Leadership 14.4), four departments holding ≥5 open tasks with nobody
  running (`evolution` 27, `legal` 25, `knowledge_eng` 14, `hr` 8), 13 departments with two or more
  wholly dormant employees. **Session 5 nearly rebuilt this. Read section 3 before building.**
- **`exec-intel-quantified-recommendation` 4 of 7 → 7 of 7.** `competitive` filed its first
  non-empty report ever at 06:02:57 (3 recommendations), `strategy` 3 after **2 attempts**,
  `procurement_quality` 3 after 2. The retry session 2 added is what fixed it; the payload-size
  hypothesis was already dead and the officers were never broken in the way four sessions assumed.

### Measured and found HONESTLY BLOCKED — do not "fix" these

| check | why, measured 10 Aug |
|---|---|
| `s32-reputation-six-dimensions` | needs six dimensions non-null on **all 66** employees. Today: correctness **0** of 66, reliability 7, cost_efficiency 3, collaboration 5, learning_speed 15 and falling to 0 at 07:00. **There is no decision-quality column at all.** Filling these is fabrication, not a build |
| `s27-knowledge-seven-fields` | needs two columns that do not exist (expiry, supporting evidence) plus `source_ref` on all 1,990 rows — 1,022 have no source and inventing one is fabrication |
| `explain-confidence-score` | the `confidence` key **is** on all 8 escalation elements and is **NULL on all 8**. A UI change cannot help; stamping a constant is the `fn_governance_stamp` mistake again |
| `explain-alternatives-considered` | 0 of 34 across all four surfaces, and no per-action alternatives data exists anywhere. Same 53-writer shape as `s36` |
| `s23-reallocation-three-classes` | only one of the three resource classes can move at all. `allocation_change` holds 12 rows, every one `ai_budget_aed`, all from the 1 Aug run that destroyed 1,860 AED. Marketing budget needs a media budget that does not exist; onboarding capacity needs invites unpaused. Both are founder money decisions |
| `s29-scan-five-questions` | 4 of 5. "Rising keywords" has **no data source**: `seo_categories` holds 24 search terms with no volume and no time series, `category_keyword` is a 1,839-row routing dictionary. A keyword-volume feed costs money |
| `personalization-learns-founder-habits` | the founder has decided **12 things ever** — 7 of them `os-preview@quotesdone.com` rejecting in a 53-second burst on 13 July, newest decision **2026-07-13**. A habit store over that measures nothing. Blocked on usage, not on code |
| `employee-learning-progress` | **0 of 83 examined agents have exam results on two different days.** Not a defect: `fn_exam_pick_agent` walks 207 distinct `agent_knowledge.agent_key` values at ~6 exams a day and started 26 July, so it is still on its first pass. Only 66 of those 207 keys are employees; the rest are `cat:` specialists with no workspace |
| `time-machine-restores-six-dimensions` | 5 of 6 on all 13 snapshots; `customers` first appears on the **2026-08-09** snapshot and is written nightly now, so the 14-day universal completes ~**24 Aug**. Nothing to build |
| `s39-governance-six-monitors` | 5 of 6 at 06:22; the sixth (`regulatory changes`) fires at 06:40 |

### The four new emitters raised the public-exposure number, and it was put back

Postgres grants EXECUTE to PUBLIC on every new function, so the four SECURITY DEFINER trigger
functions took production's `anon_security_definer_function_executable` from **63 to 67** — the one
figure in the daily security alert that is genuinely about public exposure, and the one left for the
founder to work through caller by caller. Caught in the advisor sweep in the same session and
revoked from `public, anon, authenticated` on both projects; `has_function_privilege` now returns
false for all four, and the emitters were **re-probed after the revoke** and still fire
(customer=1 competitor=1 campaign=1), because a trigger function runs as the table owner.
**Any new SECURITY DEFINER function adds one to that count unless the grant is revoked.**

### The 63 anon-executable SECURITY DEFINER functions, triaged instead of counted

Every one of the 63 was checked against the Next.js source and the edge functions rather than
revoked blind, because revoking blind is what breaks product surfaces:

| bucket | n | what the evidence says |
|---|---|---|
| **BROWSER** | 7 | named in `src/` — `fn_customer_preference_learn`, `fn_os_memory`, `fn_supplier_document_impact`, `fn_supplier_knowledge_graph`, `fn_supplier_opportunities`, `fn_supplier_quote_recommend`, `fn_supplier_twin`. Real supplier-portal and OS-shell surfaces. **Left alone** |
| **TRIGGER** | 5 | return type `trigger`; nothing calls them by name in any language — `fn_approval_raise_on_award`, `fn_org_task_cross_os_guard`, `fn_po_orders_link`, `trg_company_event_dispatch`, `trg_learn_customer_preference`. **Revoked on both projects** |
| **INTERNAL** | 51 | not named anywhere in `src/`. The ones with edge references are called with the service role; the rest are cron- and database-only. Each still needs one look, so they were not touched |

**Production `anon_security_definer_function_executable` 63 → 58**, verified by
`has_function_privilege`, with `trg_company_event_dispatch` re-probed afterwards: an insert into
`company_event` still runs the dispatch trigger without error. The remaining 51 are a reviewable
list now rather than a bare number.

### The IT employee's URGENT incident is a misreading, five escalations deep

`agent_actions` holds **82 `needs_review` handoffs**, oldest 24 July, **none completed since 25
June** (7 done, all 25 June). All 82 titles are distinct, so this is not the `licence_expiring`
duplicate storm — it is the same question re-asked with a louder title because nobody answers.
`it` alone holds 28 and escalated one incident five times in three days:

> *"URGENT: event-bus retry loop is unbounded"* · *"Systemic Ingress Failure — review.step
> duplicate storm on timestamp 01:41:05.615334"* · *"(2nd escalation) … 18 duplicate review.step
> rows, hard-stop not applied"*

**Measured: there is no duplicate storm.** The two clusters it names are
`2026-08-06 03:59:05.598967` with 150 rows and **150 distinct `entity_id`s**, and
`2026-07-27 01:41:05.615334` with 20 rows and **20 distinct `entity_id`s** — batch inserts sharing
one transaction timestamp, not duplicates. Over 7 days every `company_event` type has
`count(distinct (entity_type, entity_id, occurred_at)) = count(*)`. The bug is the handoff queue
having no consumer, which is what turned one wrong reading into five founder-facing escalations.

**Root cause located, deliberately NOT fixed today.** `agent_brain` writes the handoff
(`agent_actions`, `kind:'handoff'`, `status:'pending'`, which `trg_action_gate` rewrites to
`needs_review`) and **`fn_agent_context` never mentions `handoff`** — measured, not read. So the
receiving employee's own context contains no trace of what was handed to it: a handoff is a message
with no inbox. The fix is an inbox — the agent's open handoffs, capped, inside the context every
employee reasons from. It was not made in this session on purpose: `fn_agent_context` is 31 KB and
feeds every AI call in the company, `agent_brain` is **93% of the OpenRouter spend** with about
three days of balance left, and there were twenty-five minutes before the closing measurement.
Changing the most central and most expensive routine on production without room to verify it is how
a session breaks the company. **This is the first build order for the next session.**

---

## Session 5 (10 Aug 2026, opened 02:33 UTC) — THE CLOCK, AGAIN, AND FOUR DEFECTS IN THE MONEY PATH

```
select now() at time zone 'utc'  ->  2026-08-10 02:33:05   (Monday)
```

**The previous session ended at 02:30 UTC. This one opened at 02:33 — three minutes later.** The
part-5 brief listed ten crons "due between 03:50 and 07:00 that morning" and asked which had fired.
At session open, **none had**; the earliest was 77 minutes away. This is the third consecutive
session opened inside the previous one's shadow. Opening score **105/152 (69%), 0 errored, 0
regressions** — identical to 02:30, exactly as the clock predicts.

One cron HAD fired in the gap: `capability_verify_daily` at 02:15, first run ever, and
`s34-resilience-measured` was already MET in the opening run.

**The window is not ten crons. It is 78.** Every active job with a fixed hour between 03:16 and
07:00 today: 78 of them, weekday-or-Monday. The ten in the brief are the subset that gate Row #3
checks. Three more that matter and were not listed: `kpi_review_weekly` (`0 4 * * 1`, the outcomes
track `s33` needs), `bi_snapshot_6h` (06:35, the KPI track), and `marketing_ai_daily` (06:50).

### Four defects, all found by reading rows under a verdict rather than taking it

| defect | consequence | state |
|---|---|---|
| `fn_reallocate` released 20% of the AI budget from all twelve departments and granted it to **nobody** — no department was over 85% | **1,860 AED destroyed**, `department_budget` 9,500 → 7,640, run note claimed "moved from idle to saturated departments". Compounding, monthly, and `department_budget` is enforced by `fn_check_spend` / `fn_ai_spend_guard` / `fn_budget_available` / `fn_ai_route` | FIXED, both projects |
| `fn_reallocate`'s grant loop divided the pool by a hard-coded `3` regardless of recipient count | latent leak; with one recipient two-thirds of the pool vanished | FIXED |
| `fn_budget_rollup` inner-joined its spend subquery, so a department with zero spend was never rolled | ten of thirteen rows still read `period_label 2026-07`; a department at 90% that goes quiet reads 90% forever and stays halted | FIXED |
| `fn_reputation_recompute` was about to demote **three employees at 07:00** on two dimensions that score noise | see below | FIXED |

### The two reputation dimensions, and why nobody should have been on probation

Predicted read-only at 03:15, before the 07:00 run: five employees under 50 — `legal` 43.8, `cpo`
45.0, `learning_dev_mgr` 45.2, `analytics` 46.3, `ops_director` 49.5, three of them newly demoted.
Every one was below the line because of these two and nothing else; correctness, reliability and
cost_efficiency are NULL for all five.

- **`learning_speed` still measured a frozen seed.** Session 4 nulled it at zero validated rows —
  half the fix. `author_verified`: **292 rows, created 24–28 July only, 4 owners, none since**.
  `unvalidated`: **1,694 rows, 23 Jun → today, 23 owners, still growing**. A frozen July seed over a
  denominator that grows every time an employee learns anything, so the score **falls monotonically
  with work done**. There is no `validated_at` column, so no liveness guard is sound. Now NULL for
  everyone. **This makes `s32` harder, not easier** — it can never read 6 of 6 until a validator
  exists. Building that validator is the real fix and is still open.
- **`collaboration` counted undecided drafts and ownership markers as failed reviews.**
  `review_chain.decision` mixes verdicts with states and `stage` proves it: 208 NULLs are stage
  `drafted` with `reviewer_agent` NULL on **all 208**; 183 `owned` are stage `ownership` and first
  appeared 6 Aug; `hold` and `required` are states. `cpo` has **eight rows, all `owned`**, and
  scored 0.0% for having taken ownership of eight things. Now `approve / (approve + reject +
  request_revision)`.

After both: 60 standard, 6 trusted, **zero probation, zero demotions** — verified by execution on
staging, `employee_authority` byte-identical before and after.

### The opportunity scan was 25 minutes from reporting demo fixtures as market demand

`marketing_category_demand.inquiries_90d` counts inquiries with **no fixture filter**, and hvac's 6
and aluminium's 1 are **7 of 7 `qd_demo_fixture`**. Today was the new body's first run. At 03:50 it
would have written *"the hvac industry drew 6 inquir(y/ies) in 90 days… demand is running ahead of
the supply able to answer it"* and put it in front of the founder as detected demand. Fixed in the
two demand-driven blocks only; the shared view is untouched because four routines read it.
**This also makes `s29` harder** — it stays at 3 of 5 rather than reading a false 5 of 5, and
reaches 5 of 5 the day a real inquiry arrives.

### The marketing budget decision now reaches the founder

Two paused QuotesDone Meta campaigns, AED 0 spend, and `fn_marketing_ai` has said *"launch and fund
it"* daily since 30 July **without ever naming the money** — because no media budget exists anywhere
(`budgets` and `budget_lines` empty; `department_budget` is AI model spend and does not cover media)
and the amount is a founder decision. Filed as kind `finance_marketing_budget` so
`fn_governance_stamp`'s existing sensitive-domain rule escalates it.

Probed rather than reasoned about: `mkt_rec` inserts `pending` and `trg_action_gate` immediately
rewrites it to `needs_review`, because **`fn_authorize` resolves `marketing_ai` to role `"guest"`**
— `role "guest" lacks permission "run_agent_action"`. That is why all 161 `needs_review` rows sit
where they do. **Granting that role would push the paused share from 2.6% to ~15% and regress
`approval-center-everything-else-automatic`**, so the 159 are left alone.

### Checked and found clean — recorded so nobody re-derives it

- **`fn_agent_silence_watch` is NOT a fifth `agent_runs` offender.** Despite the name it watches
  **cron jobs**, not employees; its only `agent_runs` use is writing its own run row. Clean.
- **`employee_authority`'s 285 rows over 67 agents is BY DESIGN** — keyed by (agent_key,
  action_class), ~4.25 classes each. The 44 agents with "conflicting" `max_tier` simply have
  different authority per action class. Not a duplication bug.
- All eight morning routines are **md5-identical across both projects**, as are the three governance
  monitors, and all three dry-run clean. `fn_regulation_watch` returns `sources: 0` — it succeeds
  while watching nothing, which satisfies `s39`'s scheduling question but governs nothing.
- **`fn_exec_meeting` will flip `exec-meeting-agenda-six` at 05:00**: executed on staging, all six
  sections present on **all 12** contributions, 2 challenges in the window.
- **`fn_founder_brief` will flip `companion-overnight-brief` at 04:30**: staging's brief written by
  the current body scores **8 of 8**; production's is yesterday's, written by the old body, at 4 of 8.
- **`fn_index_slowdown_watch` will find exactly one fall at 04:15** — `company_maturity` 44.1 → 42.4
  on 6 Aug, −1.70 — and raise a proposal, which should flip `s31`.
- **`s26-discover-suppliers` is a FOUNDER SPEND DECISION, not a defect.** The scraper is an Apify
  actor (`compass/crawler-google-places`), 22 runs, **all manual, none since 19 June, and there is
  no cron for it at all**. Restarting it commits money to a third party. Not scheduled unilaterally.
- **The part-5 brief's claim that "`ROW3_STATE` still leads with the 57" is itself wrong** — the
  string `57` has never appeared in this file. It lives only in the part-4 and part-5 briefs. That
  is the third brief misdiagnosis in three sessions; brief COUNTS are reliable, brief DIAGNOSES are
  not.

---

| run | score | what changed |
|---|---|---|
| opening | **28/152 (18%)** | inherited, re-measured, unmoved |
| after Intelligence | 38/152 | `fn_ws_intelligence` + the Intelligence Centre |
| after Executive Home | ~50/152 | `fn_ws_exec_home` + the landing screen |
| after the employee workspace | ~57/152 | `fn_ws_agent_ops` extended |
| after the Operating System | **66/152 (43%)** | `fn_ws_company_os` + the map |
| after Memory, notifications, voice | **76/152 (50%)** | `fn_os_search`/`fn_os_memory`, `fn_ws_notifications` |
| after explainability | **80/152 (53%)** | `fn_owning_os` + the four action surfaces |
| after live company, reports, what-if | 88/152 (58%) | `fn_ws_live_company`, `fn_report_drilldown`, the org chart, 5 more departments in `v_department_health` |

| after root-cause fixes + realtime + manual | **91/152 (60%)** | customer creation at intake, agent_brain instrumentation, action-queue sweep, twin realtime, cron registry |

152 verdicts every run. **0 errored, denominator verified, every run.**

Eight scorer runs. The row nearly tripled its score in a single session.

### Session 2 (9 Aug 2026, evening)

| run | score | what changed |
|---|---|---|
| opening | **91/152 (60%)** | re-measured, unmoved — see below for why |
| after the exec meeting + the manual | **93/152 (61%)** | `exec-meeting-replayable`, `s38-manual-self-documenting` |
| after the flow map | **94/152 (62%)** | `mission-control-flow-animation` |
| after the memory reaches the gate | **95/152 (62%)** | `s28-blocks-repeat-failures` |
| after routing, replay reader, reactive bus | **96/152 (63%)** | `s25-routing-seven-task-classes` |
| after reputation reaches authority | 97/152 | `s32-reputation-drives-authority` |
| after the command centre | **98/152 (64%)** | `command-center-six-boards` |
| after policies and the prose insight | **100/152 (66%)** | `explain-policies-applied`, `exec-intel-narrative-insight` |

**0 errored, 0 regressions**, every run.

The three fixes the previous session expected to accrue moved the score by zero, and measuring
each one separately says why — one is genuinely waiting on traffic, one is working and will never
reach its threshold on its own, one worked and its check needs a different number:

| fix | before | now | verdict |
|---|---|---|---|
| customer created at intake | 0 customers, 7 inquiries all null | **unchanged** | deployed and correct — `inquiry_intake` v21 (18:25 UTC) creates the row. No inquiry has arrived since. Waiting on a buyer, not on code. |
| agent_brain instrumentation | 7 of 66 employees had ever run | **8 of 66** | writing. `kb_usage_log` 0 → 2 rows, `agent_memory` 22 → 26 distinct in 30d. The checks are 66-of-66 universals; one employee an hour does not reach them. |
| hourly action-queue sweep | 316 pending/needs-review | **181** | working, −135. `strategic-not-operational` needs strategic (115) to exceed operational (181), so it is still short by 66. |

Four things the previous brief called clocks or blockers were re-measured, and one of them was
neither:

- **`fn_bi_snapshot` had no cron at all.** It walks `metric_definition`, executes each metric's
  own `measure_sql` and writes `metric_snapshot`. The only thing that ever called it was
  `fn_emit_metric_alerts`, weekly on a Monday, as a side effect of an alerting job — so fourteen
  KPIs were computed once a week by accident and presented as a live digital twin.
  `metric_snapshot` had rows on exactly two days ever. Now scheduled `35 */6 * * *` on both
  projects and registered in `cron_registry`. All 14 metrics dry-run to a value on production.
- **the 04:30 founder-brief cron is fine.** 22 runs, 22 successes, last 2026-08-09 04:30:01. The
  extended `fn_founder_brief` was deployed *after* that run, so it has never executed on
  production — today's brief carries none of the four new figures. Verified by executing the
  deployed definition on staging: all four figures land and the `founder_alerts` row is written.
  First real run 04:30 UTC on 10 Aug.
- **the three governance monitors are new, not broken.** `approval_trace_audit_weekly`,
  `decision_conflict_scan_weekly` and `regulation_watch_weekly` are active with Monday 06:10 /
  06:20 / 06:40 schedules and **zero runs ever** — they were created after the last Monday. All
  three were executed on staging and all three succeed, so their first firing will not fail.
- **`s38-manual-always-current` was already MET.** 0 undocumented, 0 ghosts, against 151 active
  jobs. The previous brief's "28 undocumented, 2 stale" was fixed at the end of that session.

### What was built

| change | what it closed |
|---|---|
| `fn_exec_meeting` — six agenda sections, all ten participants, ranked/owned priorities, `fn_challenge` on the top three | `exec-meeting-agenda-six`, `-debate`, `-priorities-agreed` (all verified on staging; production flips on the Monday cron) |
| `fn_ws_reports` + `MeetingReplay` in the shell | **`exec-meeting-replayable` — MET** |
| `fn_challenge` — a refusal driven only by prior outcomes now says so | a `recommend_against` with an empty `reasoning`, which the meeting would have produced weekly |
| `v_operating_manual` + governance_policy, decision_policy, org_departments | **`s38-manual-self-documenting` — MET**, 198 → 254 entries |
| `bi_snapshot_6h` cron + registry row | `digital-twin-live-kpis`, and the KPI track of `s33-replay-six-tracks` |
| `fn_ws_company_os` + a `flow` key, and `OsFlowMap` | **`mission-control-flow-animation` — MET.** 932 deliveries in 7d, 738 attributed to a sending system, 37 cross-OS edges drawn. The declared `os_interface` graph joins to ZERO cross-OS edges, so the map is drawn from what was delivered rather than from the contract |
| `fn_should_escalate` consults `institutional_memory` | **`s28-blocks-repeat-failures` — MET.** 287 lessons on file and 1,229 gated actions a month that had never met. Three-token match, set by measuring: it fires on 4 of 1,229 (0.3%), three of them precise |
| `fn_capability_verify` + `capability_verify_daily` | `s34-resilience-measured`. 16 capabilities graded by a view nothing read. **`matching` has been FAILING at 33% since 5 Aug and no surface said so** |
| `fn_period_report` + a Competitive Position section, `monthly_report` repointed | `s37-benchmark-monthly-report` leg 1 MET. 27 competitors, none ever named in a board report. **0 of 27 offer supplier anonymity** — the differentiator this marketplace is built on |
| four `model_policy` rows | **`s25-routing-seven-task-classes` — MET.** vision, OCR, translation and summarization were running with no tier, no fallback and no cost ceiling |
| `fn_ws_company_os` + a `tracks` key | `s33-replay-six-tracks` spanner leg: 0 → 1 routine spanning all six track tables |
| `trg_company_event_dispatch` | `s21-no-polling` trigger leg MET. Delivery went from a 15-minute scan to **0s measured**; the 7-day median converges |
| `fn_check_spend` consults `agent_reputation` | **`s32-reputation-drives-authority` — MET.** Seven probation employees kept their nominal spend ceiling while `max_tier` already said 'gated' |
| `fn_ws_exec_home` + four figures, and the Console strip | **`command-center-six-boards` — MET**, 2 of 6 → 6 of 6 |
| `fn_action_policies` + four action payloads + two components | **`explain-policies-applied` — MET**, 34 of 34. decision_trace holds 4 rows and could never have answered for 34 actions; decision_policy could |
| `fn_health_index` fills its own `note` | **`exec-intel-narrative-insight` — MET.** The lobby had a prose slot filled only when there was almost no data |
| `exec_agents` retries once and logs the truth | **A silent failure, not a check.** Three of six officers filed empty reports for a week, each recorded as `status: ok` |

### Session 4 (9 Aug 2026, late — opened 22:42 UTC)

**The opening measurement was 100/152, unchanged, and the reason is the clock, not twelve broken
routines.** The part-4 brief said twelve checks "flip on crons that have since fired" and instructed
that anything still MISSING was a defect to debug. The brief was written at ~22:35 UTC and this
session opened at **22:42 UTC — seven minutes later**. Its table lists the hour each cron NEXT
fires. Not one of the twelve had reached its hour.

```
select now() at time zone 'utc'  ->  2026-08-09 22:42:08   (Sunday)
```

The local date rolls over four hours before UTC does, so "today is the 10th" in Dubai was 22:42 on
the 9th in the database. **Read `now()` before calling an un-flipped check a defect.** Corroborated
without relying on arithmetic: `bi_snapshot_6h` (`35 */6 * * *`), `capability_verify_daily`
(`15 2 * * *`), `index_slowdown_watch_daily` (`15 4 * * *`) and the three governance monitors all
have **zero runs ever** — impossible unless they were created after their most recent slot.

| run | score | what changed |
|---|---|---|
| opening | **100/152 (66%)** | re-measured, 0 errored — no cron had fired |
| after the knowledge provenance fix | 100/152 | s27 1 of 7 → 2 of 7, no flip |
| after the genome | **102/152 (67%)** | `genome-eleven-attributes-stored` + `genome-inherited-by-every-employee` both MET |
| after the 00:35 cron | **103/152 (68%)** | `digital-twin-live-kpis` MET — the first of the twelve, watched rather than predicted |

**THE FIRST OF THE TWELVE FIRED AND WAS MEASURED, NOT ASSUMED.** `bi_snapshot_6h` ran for the first
time in its life at **2026-08-10 00:35:00**, status succeeded. `metric_snapshot` went 42 → **56
rows** and all **14** active metrics carry a reading inside the window. The check now reads "0 of 14
active metric(s) have no snapshot inside 24h ... newest 2026-08-10 00:35:00" — **MET**. Everything
the opening section says about the clock is confirmed by the clock itself.

#### What was built

| change | what it closed |
|---|---|
| `fn_knowledge_provenance_stamp` + trigger + backfill | `owner_agent` 1,148 null → **0 of 1,986**; `source_ref` → 1,016. **s27 1/7 → 2/7.** Five DB functions and fourteen edge functions write `agent_knowledge` and not one set either field; the newest cohort was still growing, so a backfill alone would have been undone by the next cron |
| six `company_constitution` sections | **`genome-eleven-attributes-stored` — MET**, 5 of 11 → 11 of 11 |
| genome block injected into `fn_agent_context` | **`genome-inherited-by-every-employee` — MET**, 2 of 11 → 11 of 11 across all 66 |

#### Four of the six genome attributes were missing LABELS, not missing facts

The check is label-anchored on purpose. `brand-quick-reference.md` (a real Dropbox asset already in
`agent_knowledge`) carried the brand voice; `vision_horizon` carried the growth strategy;
`career_level`'s seven levels carried the hiring bar; the constitution already carried the ethical
commitments under other names. **Two were founder doctrine and were ASKED, not authored** — risk
appetite (aggressive growth) and leadership style ("the executives should always make sure targets
are achieved, and accordingly push the team for that").

#### The `match_eval` caller, answered

Nothing calls it with a *wrong* secret — it is called with **no secret at all**. `requireInternal`
returns early on an empty credential without consulting `fn_internal_auth`, and
`internal_credential_audit` (live since 3 Aug) holds **zero `match_eval` rows**, including for the
5 Aug 18:49 refusal; a wrong secret is always recorded as `unknown_credential`. It is never called
alone either — 5 Aug is strictly alphabetical (`dispatch_inquiry` :07, `doc_extract` :10,
`match_eval` :24, `quote_extract` :34, `route_inquiry` :37). A sweep posting an empty body over a
sorted slug list. Not `verify_prod_readiness.mjs` (GET-only) and not `deploy_functions.ps1`.

**The same pattern elsewhere, and much larger: `send_whatsapp` was refused 823 times**,
`unknown_credential`, every two minutes from 3 Aug 05:06 to 8 Aug 21:38. The 4 Aug identity capture
names it: `pg_net/0.20.4` from `3.1.231.113` then `47.131.52.147`, presenting a real 64-char secret.
Production's own `wa_flush` is fine — `cred_cron_notifications` hashes to credential 13, active and
scoped. So it was another Postgres: a branch database carrying production's `wa_flush` cron with
production's URL baked in and its own regenerated secret, the same class of incident `qd_guard.mjs`
records for 3–4 Aug. It stopped when that database went away. Neither surviving non-prod project can
do it now — `staging-batch0` has zero crons naming the production ref, and the
`fix/row3-root-causes` preview branch has no `cron` schema at all.

**`fn_internal_auth` records nothing on a successful non-legacy auth.** `internal_credential_audit`
is a refusal log, not an access log; absence there is not absence of traffic.

#### Two traps found, and NOT walked into

- **`s36-recommendation-seven-fields` is not "3 of 7 needing a writer change".** Four fields have no
  column at all (the brief named three and omitted *expected impact*). Worse, two of the three
  "covered" fields are trigger boilerplate: `fn_governance_stamp` stamps `confidence := 0.9` and a
  template `evidence` object whenever the caller omits them, so `confidence` is **0.9 on all 1,165
  rows, one distinct value**. Filling four more columns from that trigger would read 7/7 in thirty
  days and mean nothing. The honest build is per-writer, and there are **31 writers across 32
  recommendation kinds**, none sharing a helper.
- **`s27` cannot be closed honestly.** `agent_knowledge.confidence` is 0.70 on 1,711 of its 1,786
  non-null rows — the same decorative constant — so the 200 nulls were left alone. `source_ref`
  reaches only 132 of the 1,148: the other 1,016 are the 26–27 Jul category batch, and the estate's
  own labels distinguish `expert_framework_v1` from `v2` from `authored`, which is not recoverable
  per row. `expiry` and `supporting evidence` have no column and no derivable content.

#### Open, and deliberately not invented

- **200 knowledge items have no `review_due` at all**, so `fn_knowledge_decay` can never mark them
  stale — they are permanently invisible to review. No single interval is derivable: `profession`
  uses 90, 365 **and** 396 days and `company` is scattered 367–398 (a fixed target date, not an
  interval). Setting one is a knowledge-director decision, not a derivation.
- **`what-if-projected-deltas` and `what-if-confidence-score`** are universals over *all*
  `simulations` rows, so the four legacy 28-July rows block both. Back-filling or deleting them
  would be fabrication.
- **`time-machine-scrub`** needs a six-month-old snapshot and `company_snapshot_daily` has 12 runs.
  Only time closes it.

#### Found after the first three PRs, mostly by the end-of-session sweep

- **`s21-no-polling` was a real defect, not a converging clock — FIXED.** This document said delivery
  went "to 0s measured" and "the 7-day median converges". The median was 543 / 553 / 557 / **561s**
  across 6–9 Aug: flat. Only **21 of 508 deliveries (4%)** were sub-5s. Two suspects were cleared by
  experiment rather than by reading — `FOR EACH STATEMENT` is fine, because `fn_event_dispatch`
  sweeps instead of reading `NEW` (two rows in one statement both delivered). The defect was the
  argument: `fn_event_dispatch(1)` is **`p_lookback_minutes`**, so any event whose `occurred_at` was
  more than sixty seconds old was invisible inline and waited for the 15-minute cron. Probe on
  staging: `now()` → delivered, `now() - 5 min` → **zero**. Now 20 minutes, which exceeds the
  poller's own interval. Flips ~13–16 Aug when instant deliveries are the majority of the window.
- **`explain-knowledge-used` is a THIRTEENTH clock-bound check the brief never listed.** The
  `sources` fix landed on 6 Aug: gate decisions are 100% cited since 7 Aug (29/29, 61/61, 70/70) and
  0% before. It flips ~13 Aug on its own. Every one of the 108 uncited rows is `kind='action_gate'`.
- **The unmatched-inquiry watchdog forgot after 24 hours — FIXED.** `resilience_watch` was the only
  agent erroring on production, 65 times, and stopped dead at 09-08 10:40. Nothing was fixed: the
  check read `between now()-24h and now()-6h`, a BAND, and the inquiries created 08-08 10:40 simply
  crossed the far edge. It also counted fixtures. Both corrected, in opposite directions.
- **THE SEVEN INQUIRIES ARE DEMO FIXTURES.** All 7 carry `brief_source='qd_demo_fixture'` and are
  seeded "ZZ DEMO" briefs. This document and the part-4 brief both treat them as real demand waiting
  on a buyer. **The company has had ZERO real inquiries, not seven**, and live matching has never
  been exercised — `match_eval`'s 100%/100% is a synthetic benchmark against its own seeded
  suppliers.
- **`agent_brain` is 93% of all AI spend, and its cost attribution does not survive scrutiny.** 381
  calls over 4 days, **AED 51.08 (~AED 383/month)**, 14,110 prompt tokens each. Daily AI cost went
  from ~AED 0.5 to ~AED 13 on 6 Aug when this started. **Every one of the 381 `ai_cost_log` rows
  carries `agent_key='ceo'`** — yet `agent_chats` over the same window shows `agent_brain` replying
  as knowledge_director (38), procurement (35), docs (27) and brief (25), dispatched by
  `internal@quotesdone.com`, i.e. `cos_execute`. Both cannot be true of the same calls.
  `agent_key` is not a hardcoded default — six distinct values appear across `ai_cost_log` in 7 days
  (ceo 408, ai_trainer 129, knowledge_curator 85, NULL 39, brief 23, onboarding 5) — and
  `_shared/llm` does forward `agent: def.agent ?? null`.

  **RESOLVED — it is a mis-attribution defect.** `cos_execute` never writes `agent_chats` (zero
  occurrences); `agent_brain` is the only function that writes a conversational one. So those
  department chats WERE `agent_brain` calls. And `agent_brain` passes `agent: key` in exactly two
  places — line 102 (`kb_usage_log`) and line 225 (`agent_runs`) — **neither of which is an LLM
  call**. Nothing hands the employee to the model layer, so `ai_cost_log` resolves it to the exec
  department head. **Every model call `agent_brain` makes on behalf of any of the 66 employees is
  billed to `ceo`.**

  Two things follow. Per-employee AI spend is not measured, it is a single bucket. And this
  document's "`ai_cost_log` — **3 of 66** have ever been billed for a model call" is an ARTEFACT of
  that bucket, not evidence of dormancy — so the dormancy case, which five per-employee universals
  rest on, is weaker than it reads here and must be re-argued from `agent_runs` and `agent_memory`
  instead.

  **FIXED AND DEPLOYED TO BOTH PROJECTS.** And it was NOT the one-line change it first looked like:
  `const llm = makeLlm(...)` sat at MODULE SCOPE, built at boot before any request, and `makeLlm`
  binds `def.agent` at CONSTRUCTION while the function it returns takes `(sys, input, max)` with no
  per-call override. There was no argument to pass the agent in. The constant became a factory —
  `const llmFor = (agent) => makeLlm(OPUS_FIRST, {..., agent})`, called as `llmFor(key)(...)`. Same
  models, ceiling, timeout and prompt; only the stamp changes.

  **Verified by execution, not by typecheck.** Staging's `agent_brain` was invoked as `account_mgr`
  — chosen precisely because it is not the exec head, so `ceo` could not be right by accident — and
  the resulting `ai_cost_log` row reads `agent_key='account_mgr'`, 14,332 prompt tokens, AED 0.1086.
  A second row, `agent_key` NULL at 317 tokens and AED 0.0003, is `llmFast`: left unattributed on
  purpose and noted in the code, because it is 0.3% of the bill and its callers take no key.
  Production is v29 as of 00:34:50; its first post-deploy call is pending the next hourly
  `cos_execute`. staging had zero prior `agent_brain` cost rows, so those two are clean evidence.
- Two other routines use a `between now()-x and now()-y` band (`fn_founder_brief` 60→30d,
  `fn_ceo_questions` 14→7d) and both are legitimate prior-period comparisons, not alerts. No active
  daily cron has failed to run in 30 hours.
- The genome block costs ~425 prompt tokens per `fn_agent_context` call, about **+4% of prompt
  tokens, ~AED 0.5/day**. Measured, not assumed.

---

## 1. THE SHAPE OF THE WHOLE ROW, IN ONE SENTENCE

Almost every one of the 124 gaps read:

```
ui: no rendered component names it  |  db: <real, live, populated data>
```

The company computes itself every night and showed the founder almost none of it. The fix was
never a database one. **Seven new or extended workspace routines and six new screens** carried
what already existed to a surface the founder opens.

### What was built

| routine | what it exposed that reached nothing before |
|---|---|
| `fn_ws_intelligence` | `opportunity` (9), `competitor` (27), `ai_cost_log` (1,094 calls / AED 85), `company_index` (39) |
| `fn_ws_exec_home` | health, revenue, goal attainment, active customers/suppliers, employees working, bottlenecks, per-department run counts |
| `fn_ws_agent_ops` | per-employee goal, tasks, decisions, confidence, workload, plans |
| `fn_ws_company_os` | the 10 operating systems, 324 graph nodes + 608 edges, the board, the indices, 12 replay days, 66 reputations, 32 proposals, 47 challenges, 269 lessons, 16 capabilities, 81 runbooks |
| `fn_os_search` | widened from 3 corpora to **9 of 9** |
| `fn_os_memory` | subject-and-period reader over decisions, rejections, changes and lessons — did not exist |
| `fn_ws_notifications` | the four tiers, and the share the AI cleared alone (98% of 1,186 over 30d) |
| `fn_founder_brief` | the four figures the overnight brief never carried |
| `fn_entity_activity` | a configuration object now has a change history (33 real events for `model_policy`) |
| `fn_ws_supplier_360` | rejection rationale from `decision_record` + policies from `decision_trace` |

Screens: Intelligence Centre · Executive Home (Overview + Console strip) · employee drawer ·
Operating System & map (six tabs) · Company Memory · notification tiers · voice in the console.

---

## 2. THE TRAP, AND HOW IT WAS HANDLED

The nine `intel-*` checks scan a component body for nine regexes and require **four co-located**.
A component that merely *names* all nine scores nine and shows four empty panels.

So the DB leg of each was measured in isolation **before a line of UI was written**, and the
result contradicted the brief: **seven of nine DB legs already passed, not four.** The brief read
"no data" for competitors, customer behaviour and AI spending; the truth was that their DB legs
passed and **no workspace payload carried them**. Same conclusion, different cause — and the cause
is what made three of them cheap.

The screen was then built in two stages and measured at each: **4/9, then 8/9.** The ninth was
left out on purpose.

**Every screen shipped this session had its key paths resolved against the live production payload
before it shipped.** 33, then 24, then 38, then 71 paths. Not one empty cell.

---

## 3. WHAT IS BLOCKED, AND BY WHAT

This is the part that matters most, because none of it is closable by writing code.

### The company has no customers

`public.customers` holds **0 rows**, and all 7 inquiries carry a **null `customer_id`** — checked
directly, so this is not a broken foreign key. It is a marketplace with 20,470 supplier leads and
no buyers registered yet.

That single fact blocks: `intel-customer-behavior` · `company-map-entities` (customer is one of
six required node classes) · one of `s22`'s nine chain classes · the churn and satisfaction inputs
of `s30-marketplace-eight-inputs`.

### The 66 employees barely execute

The org chart lists 66 active employees. The estate has almost no record of them working:

**RE-MEASURED 2026-08-10 03:45 UTC. Three of these five rows were wrong or are now stale — the
corrected figures are in the right-hand column, and the dormancy case rests on the middle three
rows, never on `ai_cost_log`.**

| source | as written 9 Aug | measured 10 Aug |
|---|---|---|
| `agent_runs` | **7 of 113** agent values match an `org_agents` key | **10 of 113.** Still the wrong table for employees — it is the CRON log; 103 of its 113 values are job names |
| `agent_memory` | 22 of 66 wrote a thought in 30 days | **22 of 66** — unchanged, and one of the three sources that actually evidences employee work |
| `ai_cost_log` | **3 of 66** have ever been billed for a model call | **AN ARTEFACT, NOT A FACT.** `agent_brain` never passed the employee to the model layer, so every call resolved to `ceo`. Fixed 10 Aug 00:34; **6 employees billed in 30d and 5 distinct in the first three hours after the fix alone** |
| exam results | 10 of 66 have any; **0 of 66 have two dated ones** | unchanged — still blocks `employee-learning-progress` |
| `kb_usage_log` | **0 rows** — nothing writes it | **17 rows.** `agent_brain` writes it now |

**The dormancy figure is 44 of 66, measured across all three real sources** (`agent_memory` 22,
`agent_chats` 19, `agent_runs` 10 — silent in all three). Not 57, and not the `ai_cost_log` 3.
`fn_evolution_scan` was proposing 57 for retirement every Monday until it was fixed on 9 Aug; the
10 Aug 06:00 run reports 44.

That blocks five per-employee universals: `employee-current-thoughts`, `-performance`,
`-performance-trend`, `-learning-progress`, `-knowledge-used`. **No UI change can close them**, and
`employee-learning-progress` deliberately has no key on the drawer — a learning panel with no curve
behind it is an empty panel.

### Three explanations have no source to draw from

`explain-confidence-score` reads 27 of 35: the eight escalations come from `decision_log` and **every
`action_gate` row has `confidence` NULL**. `explain-alternatives-considered` reads 0 of 35 because
`challenge_record`'s 31 recorded alternatives are challenges to *founder proposals* and join to none
of these actions. `explain-knowledge-used` needs `kb_usage_log`, which has 0 rows and no writer.

### The console is operationally overloaded

`strategic-not-operational` now names **4 of 4** strategic queues and still reads MISSING. Its last
leg asks that strategic work outnumber operational, and production is **115 strategic against 316**
pending-or-needs-review `agent_actions`. A true statement about the company, not the screen.

### Two are waiting on a clock, not a change

`companion-overnight-brief` and `voice-morning-brief-spoken` both read the newest **stored** brief.
`fn_founder_brief` was extended and verified on staging at **8 of 8 figures**, up from 4 — and
production's newest brief predates the change. The 04:30 cron regenerates it. Running it by hand
would have been a production write outside the promotion path, to turn a gate green a few hours
early.

---

## 4. THE ROW #3 / ROW #7 OVERLAP IS SETTLED

`docs/sessions/ROW3_ROW7_UI_OWNERSHIP.md`. The rule is mechanical: **a requirement belongs to
row #3 if and only if one of its 152 check IDs already scores it**, because the row with a working
measurement holds the ground.

Row #3 keeps all 152. Row #7's Part B3 loses 10 UI features to row #3 and 1 to rows #4/#5, taking
its proposed denominator from **231 to 220**.

---

## 5. WHAT THE NEXT SESSION SHOULD NOT REPEAT

- **The brief's own defect diagnosis was wrong again.** It said four intel items had data. Seven
  did. Measure the DB leg of every check in isolation before building; it takes minutes and it
  changed the plan.
- **A passing DB leg is not a populated panel.** Three items had passing DB legs and no payload
  carrying them. Both halves have to be measured separately or the screen ships empty.
- **Check what a figure means before rendering it.** A per-OS `staff` count read 0 for Leadership
  because only 4 of 72 `os_responsibility` rows name a department. It was corrected to
  `owned_departments` before shipping rather than after.
- **Adding a default parameter creates an overload, it does not replace a routine.** `fn_os_search`
  kept its signature for exactly this reason; the period-scoped reader became `fn_os_memory`.
- **Extend large plpgsql by reading the deployed definition back and injecting into it.** Three
  routines of 5.8k, 6.9k and 11k characters were changed this way, so the working code around each
  change is byte-identical to what was already running.
