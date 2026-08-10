# Row #3, part 5 — opening brief

Spec: `docs/specs_row3_executive_ui.txt`. Scorer: `scripts/staging/verify_os2_blueprint.mjs`.
State: `docs/sessions/ROW3_STATE.md` (session 4 section is at the top and carries the evidence).

**Measured 2026-08-10 00:36 UTC: 103/152 (68%), 0 errored, 0 regressions.**

---

## 0. READ THE CLOCK BEFORE YOU READ ANYTHING ELSE

```
select now() at time zone 'utc';
```

The part-4 brief told the last session that twelve checks "flip on crons that have since fired" and
that anything still MISSING was a defect to debug. It was written at 22:35 UTC. The session opened
at **22:42 UTC — seven minutes later**. Not one of the twelve had reached its hour, and an hour
spent "debugging" them would have been an hour spent inventing faults in working routines.

**Dubai is UTC+4, so the local date rolls over four hours before the database's does.** "Today is
the 10th" on your screen can be 22:xx on the 9th in production. One query settles it.

The proof arrived on schedule: `bi_snapshot_6h` ran for the first time in its life at **00:35:00**,
wrote all 14 metrics, and `digital-twin-live-kpis` flipped to MET with no code change.

---

## 1. THE CLOCK TABLE, WITH REAL TIMES

**Today, 10 Aug, IS A MONDAY in UTC.** The weekly jobs fire this morning, not next week.

| UTC | check(s) | cron | state |
|---|---|---|---|
| ~~00:35~~ | ~~`digital-twin-live-kpis`~~ | `bi_snapshot_6h` | **MET — fired 00:35:00, 14/14 metrics** |
| 02:15 | `s34-resilience-measured` | `capability_verify_daily` | first firing ever |
| 03:50 | `s29-scan-five-questions` | `opportunity_scan_daily` | first run of the NEW body |
| 04:15 | `s31-slowdown-investigated` | `index_slowdown_watch_daily` | first firing ever |
| 04:30 | `companion-overnight-brief`, `voice-morning-brief-spoken` | `founder_brief_daily` | first run of the extended body |
| 05:00 Mon | `exec-meeting-agenda-six`, `-debate` | `exec_meeting_weekly` | **today** |
| 06:00 Mon | `exec-intel-quantified-recommendation` | `exec-agents-weekly` | **today** |
| 06:00 Mon | `s35-restructure-four-questions`, `evolution-proposes-structure` | `evolution_scan_weekly` | **today** |
| 06:10/20/40 Mon | `s39-governance-six-monitors` | three monitors, zero runs ever | **today** |
| ~13 Aug | `explain-knowledge-used` | none — ages out | already fixed 6 Aug |
| ~13–16 Aug | `s21-no-polling` | none — 7-day median | fixed this session |
| ~23 Aug | `time-machine-restores-six-dimensions` | `company_snapshot_daily` | 14-day universal |
| 1 Sept | `s37-benchmark-monthly-report` leg 2 | `monthly_report` | |

`s33-replay-six-tracks` needs one day carrying BOTH a KPI reading and an opened outcome. The KPI
half started flowing at 00:35 today; the outcome half is `fn_kpi_review`, Mondays.

**All seven of the routines behind these were verified present on production with their new
markers.** They will fire against new code, not old.

---

## 2. WHAT IS ACTUALLY TRUE ABOUT THIS BUSINESS

Three corrections that matter more than the score, all measured this session.

1. **THE SEVEN INQUIRIES ARE DEMO FIXTURES.** Every one carries
   `brief_source='qd_demo_fixture'` and a "ZZ DEMO" summary. `ROW3_STATE` and every brief before
   this one treat them as real demand waiting on a buyer. **The company has had ZERO real
   inquiries.** Live matching has never been exercised, and `match_eval`'s 100%/100% is a synthetic
   benchmark against its own seeded suppliers. Do not cite it as evidence that matching works.
2. **"3 of 66 employees have ever been billed for a model call" was an ARTEFACT.** `agent_brain`
   sent no agent to the model layer, so `ai_cost_log` resolved every call to the exec department
   head: 381 calls, AED 51.08 over four days, all stamped `ceo`. Fixed and deployed to both
   projects. **The dormancy case that five per-employee universals rest on must be re-argued from
   `agent_runs` and `agent_memory`, not from `ai_cost_log`.**
3. **`agent_brain` is 93% of all AI spend** — ~AED 383/month, 14,110 prompt tokens a call. Daily
   cost went from ~AED 0.5 to ~AED 13 on 6 Aug when it was switched on. That is a founder decision
   to review, not a defect.
4. **"57 of 66 EMPLOYEES ARE DORMANT" IS WRONG. IT IS 44 — MEASURED, NOT ESTIMATED.** That figure
   counts from `agent_runs`, which is the **cron and job log**: 111 distinct agent values in 30 days
   and only **nine** of them are `org_agents` keys at all. Employees record work in `agent_memory`
   (26 of 66 in 30d) and `agent_chats` (23 of 66). `fn_evolution_scan` used the wrong table and
   fired a founder-facing proposal every Monday naming each "dormant" role for retirement — **13 of
   them demonstrably working.** Fixed on both projects before the 10 Aug 06:00 run; it now requires
   silence in all three sources and reports 44. The five per-employee universals are 66-of-66 so
   they stay blocked either way, but **the gap is a third smaller than this estate believes**, and
   `ROW3_STATE` still leads with the 57.

---

## 3. DO NOT REBUILD ANY OF THIS

Sessions 1–3: see `ROW3_STATE.md`. Session 4 added, all promoted to both projects and each verified
by EXECUTION before promotion:

`fn_knowledge_provenance_stamp` + trigger + backfill · six `company_constitution` genome sections ·
the genome block injected into `fn_agent_context` · `trg_company_event_dispatch` lookback 1 → 20 ·
`fn_resilience_watch`'s unmatched-inquiry statement · `agent_brain`'s `llmFor` factory.

---

## 4. GENUINELY BLOCKED — AND FOUR MUST STAY RED

| what | why |
|---|---|
| `intel-customer-behavior`, `company-map-entities`, part of `s22`, `s30` churn/satisfaction | `public.customers` holds 0 rows, and now we know there have been no real inquiries either |
| `what-if-projected-deltas`, `-confidence-score` | universals over ALL `simulations`; four legacy 28-July rows block both. Back-filling or deleting them is fabrication |
| `time-machine-scrub` | needs a six-month-old snapshot; `company_snapshot_daily` has 12 runs. Only time |
| `s24-board-before-major-decisions` | leg 2 needs 7 advisor opinions on decisions already taken |
| `s34-stress-six-scenarios`, `future-simulator-forward-questions` | `scenario_library.last_run` has no writer. A real runner is the build |
| `s21-events-nine-classes` | `competitor.pricing_changed` has no observation mechanism at all |
| `s25-quality-latency-cost` | **QUALITY IS NOT MEASURED.** Latency and cost are, on 100% of rows for all 5 routed models over 30 days — but the check's quality axis is `ai_cost_log.confidence`, which is **NULL on all 1,176 rows**. `ok` exists and genuinely discriminates (gemini-3.5-flash 77.8% success, sonnet-5 94.8%, gemini-3.1-flash-lite 100%) but it is a success flag, not a confidence, and filling the column from it would be re-labelling a boolean to clear a null check. The check also wants a `fn_model_benchmark` that has RUN and the comparison on a surface. Scoring model output quality needs reference outputs — a real build, not a gap-fill |
| `exec-meeting-priorities-agreed` | 60-day universal; three meetings age out 27 Sept / 3 Oct / 6 Oct |
| the five per-employee universals, `s32-reputation-six-dimensions` | re-measure first — see §2.2 |
| `s26-verify-documentation` | **8 of the 16 documents point at storage objects that never existed.** See §2.4 |

### 2.5 — `agent_runs` IS THE CRON LOG. FOUR ROUTINES READ IT AS AN EMPLOYEE RECORD.

111 distinct `agent` values over 30 days and **only nine are `org_agents` keys**. Employees record
work in `agent_memory` (26 of 66 in 30d) and `agent_chats` (23 of 66). Every routine below was
swept; the result is recorded in full so nobody re-derives it:

| routine | verdict |
|---|---|
| `fn_ws_exec_home` | **WAS WRONG, FIXED.** `employees_working` was `count(distinct agent) from agent_runs` with no join at all — reported **54 of 66** on the landing screen when the truth was **13** |
| `fn_evolution_scan` | **WAS WRONG, FIXED.** "57 of 66 dormant", proposing retirement — real figure 44 |
| `fn_reputation_recompute` | `reliability` reads it. **Unsound but harmless** — every value present is >= 93, so it only ever raises a score. Do not "fix" it into something that lowers scores without first deciding what employee reliability means |
| `fn_agents_board` | per-agent `last_run` / `fails24` / `last_status` from `agent_runs`, joined to `org_agents`. Shows "never ran" for employees who reason via `agent_chats`. **Misleading display, no consequence attached** — left alone |
| `fn_self_review` | raises "failing repeatedly" from `agent_runs` errors in 7d. Same class. **Read it properly before changing it** |
| `fn_exec_meeting` | **CLEAN.** Its only use is writing its own run row |
| `fn_company_snapshot` | **CLEAN.** `agent_runs_7d` and `error_rate_7d` are platform metrics and are honestly named |
| `fn_os_review`, `fn_os_improve`, `fn_graph_rebuild`, `fn_ws_agent_ops`, `fn_ws_agents`, `fn_promote_memory_sweep` | not swept in detail; the last three already read `agent_memory` too |

**The estate was simultaneously telling the founder 54 of 66 were working and 57 of 66 were
dormant, from the same table read the same wrong way. The answer is 13 in 24h and 22 in 30d.**

### 2.4 — QA FIXTURES IN PRODUCTION ARE HOLDING CHECKS RED, IN AT LEAST THREE PLACES

This is the pattern, not three coincidences, and every scorer verdict that counts rows should be
read against it:

- **`inquiries`** — all 7 carry `brief_source='qd_demo_fixture'` and a "ZZ DEMO" summary. Zero real
  inquiries have ever arrived.
- **`documents`** — 9 of 16 are unextracted, and **8 of those are `status='orphaned'`** with the
  error written on the row: *"Storage object never existed. QA fixture or seed row with no
  object"* and *"Stale demo path; no object in storage."* They cannot be extracted because there is
  no file. Marking them verified is fabrication, so `s26-verify-documentation` is unpassable while
  they sit there. The 9th is a genuine `extraction_null` on a drawing — the `doc_extract`
  truncation defect `verify_prod_readiness` tracks — and fixing it alone reaches only 8 of 16.
- **`match_eval`'s own HARNESS_FIX sellers** are self-cleaning, so that one is handled.

**The decision is the founder's, not a session's**, because it means deleting rows from production:
either purge the orphaned fixture rows and the ZZ DEMO inquiries, or accept that the checks reading
them stay red until real traffic dilutes them. **Do not "fix" this by teaching the scorer to skip
fixtures** — that is weakening a check to make it pass, and the same argument would eventually
excuse skipping anything inconvenient. The one place fixture-exclusion WAS correct this session was
`fn_resilience_watch`, because that is an operational alert paging a human about demo data, not a
measurement of whether the company works.

---

## 5. BUILDABLE, WITH THE TRAPS NAMED

- **`s36-recommendation-seven-fields` is NOT "3 of 7 plus a writer change".** FOUR fields have no
  column (the part-4 brief omitted *expected impact*), and two of the three "covered" ones are
  trigger boilerplate: `fn_governance_stamp` stamps `confidence := 0.9` and a template `evidence`
  object, so **confidence is 0.9 on all 1,165 rows, one distinct value**. Filling four more columns
  from that trigger reads 7/7 in thirty days and means nothing. The honest build is per-writer:
  **31 writers across 32 recommendation kinds, none sharing a helper.** Plus a 30-day age-out.
- **`s27-knowledge-seven-fields` cannot be closed honestly.** Now 2 of 7. `confidence` is 0.70 on
  1,711 of 1,786 rows — the same decorative constant. `source_ref` reaches only 132 of 1,148; the
  other 1,016 are the 26–27 Jul category batch and the estate's own labels distinguish
  `expert_framework_v1` / `v2` / `authored`, which is not recoverable per row. `expiry` and
  `supporting evidence` have no column and no derivable content.
- **`s23-reallocation-three-classes` + `approval-center-five-decision-kinds` share one root cause:
  nothing in this company has ever proposed moving marketing budget.** Zero `agent_actions` rows
  match, ever. All 12 `allocation_change` rows are `ai_budget_aed` between departments on 1 Aug.
  A real reallocation engine is the build; channel-level data may only exist inside
  `marketing_snapshots.kpis` (32 rows) — check before designing.
- **`explain-confidence-score`** — escalations read 0/8 because `trg_action_gate` inserts
  `confidence` as an explicit NULL. The gate's decision is deterministic, so any number written
  there is boilerplate. Fix the meaning of confidence or leave it red.
- **`strategic-not-operational` is NOT converging — it widened.** `ROW3_STATE` records the hourly
  sweep taking operational 316 → 181 and implies it keeps draining. Re-measured 10 Aug: **operational
  186, strategic 116** — the gap went from 66 to 70. The sweep is holding a steady state against
  arrivals, not draining toward the threshold. Today's `opportunity_scan` and `evolution_scan` add
  strategic items, but tens, not seventy. It will not flip on its own.
- **`personalization-learns-founder-habits` has an honest seed, contrary to "0 candidate stores".**
  Real founder behaviour IS recorded: **11 `agent_chats` from two genuine founder accounts**
  (`ahmadalzain1993@admin.quotesdone.com`, `management@quotesdone.com`) — which agents the founder
  consults, when, how often. That is a legitimate basis to derive a profile from, not invented data.
  But it is a THREE-LAYER build (a store, a UI-reachable reader, and the shell genuinely adapting —
  and note the `adapts` leg is a source regex, so writing the word "habit" without behaviour would
  be an accidental pass), and **eleven data points do not make a habit**. What the habits should
  DRIVE — which module opens first, notification batching, prominence — is a founder product
  decision. Ask before building.
- **`s32-reputation-six-dimensions` — all six dimensions accounted for, and reputation gates spend.**
  `fn_reputation_recompute` weights correctness .30, reliability .30, cost_efficiency .15,
  learning_speed .15, collaboration .10, NULLs coalesce to 50, and `< 50` is probation — which
  `fn_check_spend` enforces. State of each:
  - **correctness** — NULL on all 66. All `outcome_record` rows sit at verdict `pending`; genuinely
    nothing to grade.
  - **reliability** — computed from `agent_runs`, which for employees is the wrong table (see §2.4).
    `onboarding` and `security` show exactly 720 runs/30d — 24/day, a cron heartbeat — while `brief`
    has 39 runs against 140 chats and `docs` 9 against 136. **Unsound but currently harmless**:
    every value present is >= 93, so it only ever raises a score. Do not "fix" it into something
    that starts lowering scores without deciding what employee reliability should mean.
  - **cost_efficiency** — was NULL for almost everyone because `agent_brain` billed all reasoning to
    `ceo`. That is fixed as of 10 Aug, so this dimension starts carrying real per-employee data.
  - **learning_speed** — **was actively demoting people. Fixed 10 Aug**, see the section above.
  - **collaboration** — from `review_chain`, NULL for the probation cohort.

  `agent_reputation` is also a week stale at any given moment: `reputation_weekly` is `0 7 * * 1`,
  so rows show NULL for dimensions whose underlying data arrived after the last Monday.
- **200 knowledge items have no `review_due`**, so `fn_knowledge_decay` can never mark them stale —
  permanently invisible to review. No single interval is derivable (`profession` uses 90, 365 AND
  396 days; `company` is a scattered 367–398). Setting one is a knowledge-director decision.

---

## 6. THE RULES THAT KEPT THIS HONEST

- **Read `now()` in UTC before calling an un-flipped check a defect.**
- **A check that passes by accident is worse than one that fails.** Found twice more this session:
  `confidence` 0.9 on every recommendation, and 0.70 on every knowledge row.
- **Execute on staging before promoting, and probe with the REAL shape.** The first provenance probe
  prefixed every fixture topic with `PROV_TEST_` and three of four derivations returned null,
  because the LIKE patterns anchor at the start of the topic. The bug was in the test.
- **A detector that trips on its own explanation is a false alarm.** The deployed `agent_brain`
  bundle matched `const llm = makeLlm` — in the comment explaining its removal. Strip comment lines.
- **Verify by execution, not by typecheck.** `agent_brain` was probed on staging as `account_mgr`,
  chosen precisely because it is not the exec head, so `ceo` could not be right by accident.
- **`qd_guard` refuses to apply a body carrying the production ref to a branch, and it is right.**
  `fn_resilience_watch` embeds its own project's URLs, so each project's own definition was read
  back and patched.
- **`internal_credential_audit` is a refusal log, not an access log** — `fn_internal_auth` records
  nothing on a successful non-legacy auth. Absence there is not absence of traffic.
- Deploys: `deploy-functions.yml` runs on `branches: ['**']` and **always targets staging**.
  Production needs `gh workflow run deploy-functions.yml -f target=<prod ref> -f slugs=<fn>`.

---

## 7. END-OF-SESSION SWEEP — STANDING PROCEDURE

GitHub Actions, Vercel deployments and runtime errors, and on BOTH Supabase projects the advisors,
failed `cron.job_run_details` and `agent_runs` errors. Report what was checked and what was found,
including "nothing".

Session 4's sweep found the `resilience_watch` band defect and the `agent_brain` attribution defect,
so it is not a formality — **it was the most productive twenty minutes of the session.**

**The diagnostic that will recur:** an Actions job with **zero steps** means the runner never
started — quota or billing, never code.
