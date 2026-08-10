# Row #3, part 6 — opening brief

Spec: `docs/specs_row3_executive_ui.txt`. Scorer: `scripts/staging/verify_os2_blueprint.mjs`.
State: `docs/sessions/ROW3_STATE.md` (session 5 section is at the top).

**Measured 2026-08-10 02:33 UTC: 105/152 (69%), 0 errored, 0 regressions.**
Post-cron re-measurement is in section 1.

---

## 0. READ THE CLOCK. THIS HAS NOW COST THREE SESSIONS.

```
select now() at time zone 'utc';
```

- Part-4 brief written 22:35, session opened **22:42**. Seven minutes.
- Part-5 brief written ~02:30, session opened **02:33**. Three minutes.

Both briefs told the session that a list of crons "had fired" and that anything still MISSING was a
defect. **Both were wrong**, and the second one was wrong about a list of ten jobs whose earliest
member was still 77 minutes in the future. Dubai is UTC+4; the local date rolls over four hours
before the database's does.

**Do not open a cron table in a brief and believe it. Query `cron.job_run_details`.**

---

## 1. WHAT THE 10 AUG MORNING CRONS ACTUALLY DID

**The window is 78 active crons, not ten.** The ten that gate Row #3 checks are below; the other 68
run in the same window and three of them matter to this row and were never listed:
`kpi_review_weekly` (`0 4 * * 1`, the outcomes track `s33` needs), `bi_snapshot_6h` (06:35, the KPI
track) and `marketing_ai_daily` (06:50).

| UTC | cron | fired? | check | flipped? |
|---|---|---|---|---|
| 00:35 | `bi_snapshot_6h` | yes, succeeded | `digital-twin-live-kpis` | already MET |
| 02:15 | `capability_verify_daily` | yes, succeeded | `s34-resilience-measured` | **MET** |
| 03:50 | `opportunity_scan_daily` | yes, succeeded, found 5 | `s29-scan-five-questions` | no — 4 of 5, deliberately (see §3) |
| 04:00 | `kpi_review_weekly` | yes, succeeded — 15 opened, 33 missed, 20 no_data | `s33-replay-six-tracks` | not yet — see below |
| 04:15 | `index_slowdown_watch_daily` | yes, succeeded — **2** investigated, 2 proposals | `s31-slowdown-investigated` | |
| 04:30 | `founder_brief_daily` | _pending_ | `companion-overnight-brief`, `voice-morning-brief-spoken` | |
| 05:00 | `exec_meeting_weekly` | _pending_ | `exec-meeting-agenda-six`, `-debate`, `exec-reports-recommendations-approvable` | |
| 06:00 | `exec-agents-weekly` | _pending_ | `exec-intel-quantified-recommendation` | |
| 06:00 | `evolution_scan_weekly` | _pending_ | `s35-restructure-four-questions`, `evolution-proposes-structure` | |
| 06:10/20/40 | three governance monitors | _pending_ | `s39-governance-six-monitors` | |
| 06:50 | `marketing_ai_daily` | _pending_ | `approval-center-five-decision-kinds` | |
| 07:00 | `reputation_weekly` | _pending_ | `s32` — will NOT flip, by design (§3) | |
| **23:55** | `company_snapshot_daily` | tonight | `s33-replay-six-tracks` | **a 13th clock-bound check** |

**`s33` is anchored on a snapshot that has not been taken yet.** It measures the six tracks against
the newest `company_snapshot` day, which is still **2026-08-09** — a day with no KPIs (`bi_snapshot_6h`
first ran 00:35 on the 10th) and no outcomes (`kpi_review_weekly` ran 04:00 on the 10th). Both
missing tracks now have rows dated the 10th, and `company_snapshot_daily` is `55 23 * * *`. So s33
should flip at **23:55 tonight** with no code change. It is not broken.

### Two checks predicted by execution before their cron ran, and both were right

- **`companion-overnight-brief`** — staging's brief written by the current `fn_founder_brief` scores
  **8 of 8**; production's was yesterday's, written by the old body, at 4 of 8.
- **`voice-morning-brief-spoken`** — reads `founder_alerts` ONLY (not `notifications`, which is what
  `companion-overnight-brief` reads). Staging's fresh row scores **6 of 6**; production's newest was
  **2026-08-05**, from the old body, at 2 of 6.

Both flip on the 04:30 `founder_brief_daily` run. Neither needed a change.

---

## 2. FOUR DEFECTS IN THE ENFORCED MONEY PATH, ALL FIXED

`department_budget` is read by `fn_check_spend`, `fn_ai_spend_guard`, `fn_budget_available` and
`fn_ai_route`. These are spending ceilings, not report figures.

1. **`fn_reallocate` destroyed 1,860 AED.** It released 20% from all twelve departments, then found
   nobody over 85% to grant it to. `allocation_change` holds 12 release rows and **0 grant rows**;
   `department_budget` went 9,500 → 7,640; `agent_runs` recorded *"1860 AED moved from idle to
   saturated departments"*, which is false. Compounding monthly. Recipients are now counted first.
2. **The grant loop divided by a hard-coded `3`** regardless of recipient count.
3. **`fn_budget_rollup` never rolled a zero-spend department** — inner join. Ten of thirteen rows
   still read `period_label 2026-07`. A department at 90% that goes quiet would read 90% forever and
   `fn_check_spend` would keep halting it.
4. **`fn_reputation_recompute` was about to demote three employees at 07:00** on two dimensions that
   score noise. See §3.

---

## 3. THREE CHANGES THAT MAKE CHECKS *HARDER*, ON PURPOSE

Do not "fix" these back. Each one removes a false pass.

- **`learning_speed` is now NULL for everyone.** `author_verified` holds 292 rows created **24–28
  July only, none since**; `unvalidated` holds 1,694 created through today and still growing. The
  ratio was a frozen July seed over a denominator that grows every time an employee learns
  something, so **the score fell monotonically with work done**. There is no `validated_at` column,
  so no liveness guard is sound. `s32-reputation-six-dimensions` can therefore never read 6 of 6
  until something actually validates knowledge. **Building that validator is the real fix and is
  still open.**
- **`collaboration` now counts decided verdicts only.** `review_chain.decision` mixes verdicts with
  states: 208 NULLs are stage `drafted` with `reviewer_agent` NULL on all 208, 183 `owned` are stage
  `ownership` and appeared 6 Aug, `hold`/`required` are states. `cpo` had eight rows, all `owned`,
  and scored 0.0%.
- **The opportunity scan counts real inquiries, not fixtures.** It was 25 minutes from telling the
  founder *"the hvac industry drew 6 inquiries in 90 days"* when all six were `qd_demo_fixture`.
  `s29` stays at 4 of 5 rather than reading a false 5 of 5. It reaches 5 the day a real inquiry
  arrives. Note the 4th class, *growing industries*, is only covered because a competitor blurb
  happens to contain a sector word — an incidental match, not a real finding.

---

## 4. THE QA FIXTURES ARE GONE. THE COMPANY NOW HAS ZERO INQUIRIES, LITERALLY.

On the founder's explicit decision, 42 rows were archived to `public.qa_fixture_purge_archive` and
deleted: 7 `qd_demo_fixture` inquiries, their 25 quotes, 1 message, 1 transaction, and 8 `orphaned`
documents whose storage objects never existed.

- `inquiries` **7 → 0**. There is no inquiry table content at all now. Any routine that divides by
  an inquiry count must handle zero.
- `documents` **16 → 8** (7 done + 1 genuine `doc_extract` truncation bug).
  **`s26-verify-documentation` went from unpassable to 7 of 8** — one real bug from passing.
- The platform's single "revealed quote" (AED 185,000) was a fixture, so the marketing dashboard's
  `quote_to_reveal_pct` of 14.3% was fixture-derived and is now honest.

Recovery: `select payload from public.qa_fixture_purge_archive where source_table='inquiries';`

---

## 5. THE LEAD MACHINE IS STOPPED, AND THAT IS THE REAL CONSTRAINT

The founder cancelled the Apify subscription on 10 Aug — work the existing leads first, revisit
~Feb 2027. **`s26-discover-suppliers` is therefore a deliberate red, not a build order. Do not
schedule the scraper.**

But the leads are not being worked either:

```
leads                          20,470   (19,903 with an email, 98.9% syntactically valid)
ever invited                       62   (0.30%)
lifecycle_stage not_contacted  20,399   (99.65%)
last invite sent           2026-08-06
app_secrets.invite_enabled    'false'
```

It **auto-paused correctly** on deliverability — 7-day bounce 13.3% (4/30), hard cut-off 8%. The
defect was that nothing said so: both invite routines return on their first line when disabled, so
both crons reported `succeeded` daily while sending nothing, and `fn_invite_ramp`'s stall detector
sits *after* the enabled-check and could never fire. Fixed — the paused branch now reports.

**Not re-enabled.** 13.3% bounce is dead mailboxes, not formatting (only 226 of 19,903 are
malformed, and 208 of those are two addresses in one field). The list needs MX/SMTP verification
before sending resumes, which costs money and is the founder's call.

At the pre-pause rate of ~4/day, 20,399 leads is a **13-year** plan. Invite throughput and email
quality are the constraint, not lead supply.

---

## 6. CORRECTIONS TO THINGS PREVIOUS BRIEFS ASSERTED

Brief COUNTS have been reliable. Brief DIAGNOSES have now been wrong four times.

- **"`ROW3_STATE` still leads with the 57"** — it never contained the string `57`. That figure lives
  only in the part-4 and part-5 briefs.
- **"four legacy 28-July `simulations` rows"** — three are **6 July** and one is 28 July, and ids 1
  and 3 are exact duplicates a minute apart. The conclusion still holds: id 4 is an honest refusal
  (*"This cannot be simulated… Any number would be invented"*), so forcing revenue/leads/profit onto
  it is the fabrication it refuses.
- **`fn_agent_silence_watch` is NOT a fifth `agent_runs` offender.** Despite the name it watches
  **cron jobs**; its only `agent_runs` use is writing its own run row. Clean.
- **`employee_authority`'s 285 rows over 67 agents is BY DESIGN** — keyed by (agent_key,
  action_class). The 44 "conflicting" agents have different authority per class. Not a bug.
- **The `ai_cost_log` "3 of 66 billed" was an artefact** of `agent_brain` billing everything to
  `ceo`. Post-fix: 6 employees in 30d, 5 distinct in the first three hours. `kb_usage_log` is 17
  rows, not 0.

---

## 7. WHAT IS STILL GENUINELY BUILDABLE

- **`exec-agents-weekly`'s empty officers.** `competitive` and `strategy` file empty *every* week,
  `product_ux` intermittently — fallback summary *"Metrics captured; AI synthesis unavailable this
  run."* A payload-size hypothesis was **measured and killed**: `fn_strategy_metrics` is 463 bytes
  and the largest payload (`fn_ops_metrics`, 546) belongs to an officer that always succeeds. The
  edge function is at v12 with session 2's failing-response capture, so the **10 Aug 06:00 run is
  the first that records the actual cause** — read `agent_runs` where `agent like 'exec:%'` and
  `status='error'` before touching anything.
- **A knowledge validator.** Nothing in the estate writes `author_verified`. This blocks
  `learning_speed`, and therefore `s32`, permanently.
- **`s36-recommendation-seven-fields` — MEASURED EXACTLY 10 Aug, and it is worse than "two of three
  are boilerplate". ALL THREE ARE.** `FIELD_COVERED` requires a column whose NAME matches the field's
  regex and which is non-null on every recommendation in the window. Result:

  | field | column | nulls in 30d | why it passes |
  |---|---|---|---|
  | evidence | `evidence` | 0 | `fn_governance_stamp` stamps a template object |
  | confidence | `confidence` | 0 | same trigger stamps `0.9` |
  | risks | `risk` | 0 | column DEFAULT `'low'`, NOT NULL |
  | alternatives | **NO COLUMN** | — | |
  | assumptions | **NO COLUMN** | — | |
  | cost | **NO COLUMN** | — | |
  | expected impact | **NO COLUMN** | — | |

  One trigger and one column default account for the entire 3 of 7.

  **AND IT IS 53 WRITERS, NOT 31.** Enumerated 10 Aug — 33 database functions that
  `insert into agent_actions`:

  > `ai_rec` `doc_rec` `fin_alert` `fn_agent_decision` `fn_ai_quality_watch` `fn_autonomy_audit_run`
  > `fn_backup_watch` `fn_category_sales` `fn_chief_of_staff` `fn_customer_success` `fn_doc_control`
  > `fn_ea_assistant` `fn_exec_meeting` `fn_execution_run` `fn_improvement_handover`
  > `fn_knowledge_curator` `fn_marketing_ai` `fn_notify_supplier` `fn_report_flag`
  > `fn_report_recommendation_approve` `fn_security_scan` `fn_strategy_rec`
  > `fn_supplier_capability_chase` `fn_supplier_exception_sweep` `fn_supplier_risk_monitor`
  > `fn_supplier_success` `fn_supply_health` `kn_task` `leg_flag` `mkt_rec` `ops_rec` `sec_incident`
  > `trg_customer_abandon_ban`

  plus 20 edge functions:

  > `agent_autogen` `agent_brain` `agents` `category_provision` `collections_legal` `cos_execute`
  > `customer_api` `dispatch_inquiry` `email_triage` `kb_fill_gap` `learn_gaps` `legal_review`
  > `messages_api` `os_api` `prompt_improve` `rfq_flag` `supplier_api` `supplier_onboard`
  > `translate_page` `vt_scan`

  **THE CHECK IS A UNIVERSAL, SO THERE IS NO PARTIAL CREDIT.** Every one of the 53 must supply real
  values for all four new fields; covering the biggest writers first scores exactly zero. Volume for
  sequencing only: `incident` 515 of 1,171 rows in 30d (44%), `licence_expiring` 150, `handoff` 106,
  `strategy_rec` 79, `knowledge_task` 64.

  **DO NOT GIVE THE NEW COLUMNS DEFAULTS.** A `default 0` on cost or a template on assumptions makes
  all four pass within 30 days and measures nothing — the identical mistake `fn_governance_stamp`
  already made with `confidence := 0.9`, which is why three of seven "pass" today.

  Not closable before ~9 Sept even if started immediately, because the 30-day window only begins
  once the last non-conforming writer is fixed.
- **The 226 split-address leads** (`a@x.ae; b@y.ae`) — ~208 recoverable, but which address is
  primary is a judgement for the founder.

## 8. STILL CORRECTLY BLOCKED

`intel-customer-behavior`, `company-map-entities`, `s22`, `s30` churn/satisfaction — `customers`
holds 0 rows · `what-if-*` — see §6 · `time-machine-scrub` — needs a six-month-old snapshot ·
`s24` — 7 advisor opinions on decisions already taken · `s25` — quality is not measured;
`ai_cost_log.confidence` is NULL on all 1,176 rows · `s27` — `confidence` is 0.70 on 1,711 of 1,786
rows, the same decorative constant · `explain-confidence-score` — `trg_action_gate` inserts an
explicit NULL and its decision is deterministic · `strategic-not-operational` — operational 186 vs
strategic 116, widening, will not converge on its own.

## 9. END-OF-SESSION SWEEP — STANDING PROCEDURE

GitHub Actions, Vercel deployments and runtime errors, and on BOTH Supabase projects the advisors,
failed `cron.job_run_details` and `agent_runs` errors. Report what was checked and what was found,
including "nothing".

**An Actions job with zero steps means the runner never started — quota or billing, never code.**
Confirmed again on 10 Aug: the 9 Aug 21:21–21:44 failures were all zero-step and recovered at 21:47.

**Read the dates on anything you find.** `resilience_watch` showed "42 errors in 24 hours" on a
rolling window; every one predated the previous session's fix and the newest was 2026-08-09 10:40.
