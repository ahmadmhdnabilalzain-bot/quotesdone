# Row #3, part 3 — opening brief

Spec: `docs/specs_row3_executive_ui.txt`. Scorer: `scripts/staging/verify_os2_blueprint.mjs`.
State: `docs/sessions/ROW3_STATE.md`. Overlap decision: `docs/sessions/ROW3_ROW7_UI_OWNERSHIP.md`.

**Measured on production at the end of the previous session: 95/152 (62%), 0 errored, 0
regressions. Run the scorer before you read another line — six checks were deployed and verified
but flip on clocks between 00:35 and 06:40 UTC, so the number should be materially higher.**

The last full run measured 94; `s28-blocks-repeat-failures` landed after it and was confirmed MET
by a targeted run. Production's clock was **2026-08-09 20:00 UTC** at handover — the local date had
rolled to the 10th but none of the six clock checks had reached its hour, so do not read their
still-MISSING verdicts as failures until you have compared `now()` against the table below.

---

## 1. RUN THE SCORER FIRST, AND EXPECT THESE SIX

Every one of these is deployed to both projects and verified by executing the routine. None needs
a change. If one of them is still MISSING after its hour, **that is a defect and it is yours** —
the routine did not do what execution said it would.

| flips at (UTC) | check | verified how |
|---|---|---|
| 00:35 | `digital-twin-live-kpis` | `bi_snapshot_6h` scheduled + registered; all 14 active metrics dry-run to a value on production; every other leg of the check already passes |
| 04:30 | `companion-overnight-brief`, `voice-morning-brief-spoken` | extended `fn_founder_brief` executed on staging: all four new figures land, `founder_alerts` row written. Digest-identical on both projects |
| 05:00 Mon | `exec-meeting-agenda-six`, `exec-meeting-debate` | `fn_exec_meeting` executed on staging: 6 of 6 sections on all 12 contributions, 2 challenges recorded between cfo and procurement |
| 06:40 Mon | `s39-governance-six-monitors` | the three unrun monitors executed on staging; all three succeed |
| 02:15 | `s34-resilience-measured` | `capability_verify_daily` scheduled + registered; the verdicts it will write were projected read-only over production's 16 rows — 4 passing, 1 failing, 11 mechanism_present, 0 absent |

`exec-meeting-priorities-agreed` will NOT flip with the others. It is a universal over every ceo
`exec_report` in 60 days and three of the four in the window were written on 28 Jul and 3 Aug with
string recommendations. The routine is fixed; **rewriting those three rows would be editing the
record to turn a gate green**, so they are left to age out — 27 Sept, 3 Oct, 6 Oct.

## 2. DO NOT REBUILD THIS

Session 1 built eleven workspace routines and nine screens (section 1 of
`NEXT_SESSION_BRIEF_ROW3_PART2.md` — still accurate). Session 2 added:

`fn_exec_meeting` (six agenda sections, ten participants, ranked priorities, `fn_challenge` on the
top three) · `fn_ws_reports` (the meeting transcript, priorities and challenges) · `fn_challenge`
(a prior-outcome refusal now states its basis) · `v_operating_manual` (+ governance_policy,
decision_policy, org_departments — 198 → 254 entries) · `bi_snapshot_6h` cron · `MeetingReplay` in
`OsxShell.tsx` · `fn_ws_company_os` (+ a `flow` key) and `OsFlowMap` · `fn_should_escalate`
(consults institutional_memory before deciding).

## 3. THE RULE THAT PAID FOR ITSELF TWICE THIS SESSION

**Measure the mechanism before you believe the brief about it.** Two of the previous brief's own
items were wrong:

- `s38-manual-always-current` was listed as the top buildable item with "28 undocumented jobs".
  It was already MET — 0 and 0. Ten minutes saved by running `--only=s38` first.
- The 04:30 founder-brief cron was described as something to wait for. It had already run today,
  successfully, for the 22nd time — and the extended routine was deployed *after* it, so waiting
  for "the 04:30 cron" without checking would have meant waiting a day to discover nothing had
  changed. The distinction only shows up if you read `cron.job_run_details` **and** compare the
  stored output against what the new body should produce.

And the one that was a real defect hiding as business reality: **`fn_bi_snapshot` had no cron at
all.** A writer with no schedule looks exactly like an empty table.

## 4. WHAT IS LEFT, RE-MEASURED

### A. Genuinely blocked by the company, not the code

| what | why |
|---|---|
| `intel-customer-behavior`, `company-map-entities`, part of `s22` | `public.customers` holds 0 rows. `inquiry_intake` v21 creates the row now — verified in the deployed source — so this fills on the first authenticated inquiry. |
| the five per-employee universals | 8 of 66 employees have ever produced an `agent_run`. `agent_brain` writes `agent_runs`, `agent_memory` and `kb_usage_log` per turn, but 66-of-66 coverage needs the employees to work. |
| `strategic-not-operational` | 115 strategic against **181** operational — the hourly sweep took it from 316. Still needs strategic to exceed operational. |
| `explain-confidence-score` | `decision_log.confidence` NULL on every `action_gate` row. |
| `explain-alternatives-considered` | `challenge_record`'s alternatives join to none of the 35 surfaced actions. **Re-measure this one** — the meeting now writes challenges whose proposal text names the agenda item, which may change the join. |
| `what-if-projected-deltas`, `-confidence-score` | four simulation rows from 28 July with different keys. Rewriting them is fabrication. |

### B. `twin-realtime-updates` is MET and must stay untouched

Section B2 of `NEXT_SESSION_BRIEF_ROW3_PART2.md` explains why the obvious version would have been
fraud: all thirteen twin classes have **RLS enabled with zero policies** — deny-all — and the
console reads them through `os_api` with the service role, so a browser subscription would never
fire. Making it real is a security change with its own review. **Nothing in session 2 touched RLS
or the realtime publication.**

### C2. The next three, already scoped

- **`explain-policies-applied`** — the biggest single remaining piece and fully understood. The
  check takes the ACTUAL rows of four action surfaces — `fn_os_command()->'attention'`,
  `fn_ws_governance()->'recent_escalations'`, `fn_ws_operations()->'approvals'`,
  `fn_ws_ea()->'approvals_top'` — and requires EVERY surfaced action to carry a key matching
  `policy|policies|policy_keys|policies_applied|rule|rules`, **and** the drawing component to show
  it (all keys count for a surface handed to `<ReadableObject>`, only rendered ones otherwise). The
  source is `decision_trace.policy_keys`. It is four payload changes and up to four component
  changes, which is why it was not started at the end of a session rather than because it is hard.
  `explain-alternatives-considered` has the identical shape over `challenge_record.alternatives`.
- **`s24-board-before-major-decisions`** — leg 1 is one line: one of `fn_decide`,
  `fn_decision_gate`, `fn_task_approve`, `fn_check_spend`, `fn_exec_meeting` must CALL
  `fn_board_review(`. Leg 2 needs every `decision_record` in 30 days to carry an opinion from all
  seven advisors, and the 11 already in the window have none. Building leg 1 makes future decisions
  advised and the check flips 30 days later — back-filling opinions onto past decisions would be
  fabrication.
- **`s21-events-nine-classes`** — 4 of 9. An emitter counts either as a recorded event OR as a
  routine passing the type to `fn_emit*(...)` as a literal, so three are honest code changes:
  `customer.registered` (trigger on `customers`), `supplier.approved` (on the `leads` approval
  transition), and an AI-confidence monitor over `ai_cost_log.confidence`. `campaign.launched` has
  a defensible analogue in `invite_schedule`. **`competitor.pricing_changed` has no mechanism at
  all** — `competitor` has no price column and `market_intel` has 0 rows — so the check cannot be
  closed honestly until the company observes competitor pricing.

### C. Buildable, closest first

- **`s33-replay-six-tracks`** — two legs. The KPI track is fixed by `bi_snapshot_6h` (from 00:35
  every snapshot day has metric rows). The **outcomes** track needs `outcome_record` rows on the
  replay day; `fn_outcome_open` is called only by `fn_kpi_review`, weekly on Monday 04:00. Decide
  honestly whether outcomes should open daily before scheduling anything — an outcome row created
  to fill a track is fabrication. The second leg is pure build: **no browser-reachable routine
  spans all six tables**, and one `fn_os_replay(p_day date)` wired into `os_api` closes it.
- **`time-machine-restores-six-dimensions`** — 5 of 6. The missing dimension is **customers**: the
  nightly `company_snapshot.state` carries 24 keys and not one matches `customer|buyer`. Adding a
  real count (0 today) is a true measurement, not a fabrication — but the check is a universal
  over the last 14 days, so it flips 14 days after the writer changes, not on deploy.
- **`s32-reputation-six-dimensions`** — re-measured, and it is mostly NOT buildable yet.
  `fn_reputation_recompute` already computes five of the six and writes NULL where there is no
  evidence. `correctness` is NULL on all 66 for a reason that is business reality, not a defect:
  it reads graded outcomes, and **all 51 `outcome_record` rows sit at `verdict='pending'` because
  0 of them have reached their measurement date** — the earliest is 11 Aug, then 19 Aug, then
  1 Sept. `fn_outcome_evaluate` runs daily at 03:30 and correctly has nothing to grade. The other
  four are thin because few employees execute. What IS buildable: **"decision quality" has no
  column at all** — `agent_reputation` carries correctness, reliability, cost_efficiency,
  learning_speed, collaboration, score, tier and nothing matching `decision|judg|quality`. Adding
  the column alone will not flip the check, so do it as part of the whole dimension, not before.
- **`s36-recommendation-seven-fields`** — 3 of 7 on every one of 1,157 recommendations/30d;
  missing alternatives, assumptions, cost and one more.
- **`s29-scan-five-questions`** (2 of 5), **`s35-restructure-four-questions`** (0 of 4) — the scan
  and the restructure prompts do not ask the named questions.
- **`s27-knowledge-seven-fields`** — 1 of 7 metadata fields on 1,985 rows. A backfill; only if the
  values are derivable, never invented.
- **`s25-routing-seven-task-classes`** — 3 of 7 task classes have an active `model_policy`;
  missing OCR, summarization, translation, vision. Config rows, promoted with
  `promote_rows_to_production.mjs`. Untouched because naming the model that serves OCR is a
  configuration decision, not a repair.

### E. Two architecture findings worth acting on outside the scorer

- **`os_interface` does not connect.** The ten systems declare 16 outputs and 17 inputs and the two
  sets are DISJOINT except `supply.gap`, which marketplace both emits and consumes. Joining
  outputs to inputs on `event_type` gives **zero** cross-OS edges, and `graph_edges` has none
  either. The flow map on the OS map screen is therefore drawn from what was actually delivered
  (`event_delivery` + `company_event.actor` resolved through the department), not from the
  contract table. Deciding which system consumes `decision.executive`, `policy.updated` and
  `task.assigned` is a founder call; writing those rows to make a picture connect would be
  inventing the company's contract table.
- **`matching` is failing and the founder has never been told.** `v_critical_capability_tests`
  grades all sixteen critical capabilities and nothing read it, so `critical_capability.last_verdict`
  was NULL on all sixteen. `matching` — "RFQs reach suppliers who can actually do the work" — has
  been **FAILING at 33% pass over fourteen days** since 5 Aug. `fn_capability_verify` now writes the
  verdict back and raises a founder alert on a failing capability, but **fixing the matching
  capability itself is untouched work** and it is the most consequential thing in this file.
- **Eleven of sixteen capabilities have never been behaviourally exercised.** Their declared test is
  `rpc_selftest`, which only establishes that the mechanism exists. They are written as
  `mechanism_present`, deliberately not `passing`. Turning those into real behavioural tests is the
  follow-on, and it is what `s34-resilience-measured` is really asking for.
- **`decision_log.ctx` nests the action text.** `trg_action_gate` passes `text` at the top level to
  `fn_should_escalate`, then RECORDS the decision as `{kind, risk, action, attrs}` with the text
  under `attrs`. Measuring anything about gated actions on `ctx->>'text'` returns 0 of 1,229; the
  path in the log is `ctx->'attrs'->>'text'`, and all 1,229 carry it.

### D. One softness worth knowing about

`s38-manual-self-documenting` is MET, and its delivery leg passes because `fn_ws_company_os`
carries the 81 runbooks into the payload. **`v_operating_manual` itself still has no real reader**
— the only routine naming it, `fn_agent_context`, names it in a comment. The founder cannot open
the operating manual on any screen. That is not what the check measures, and it is worth building
anyway.

## 5. THE RULE THAT KEEPS THE SCORE HONEST

Every screen shipped is resolved against the live production payload before it ships. `MeetingReplay`
was resolved twice: **10 of 21 paths** against production's 6 Aug meeting (the six agenda sections
and the challenge fields do not exist on it, and the component renders only what is present), and
**25 of 26** against the new-shape meeting on staging. The one empty path was
`challenge.reasoning` — which turned out to be a real defect in `fn_challenge`, found because the
path was measured rather than assumed, and fixed in the same session.

## 6. THE GITHUB ACTIONS ALLOWANCE (9 Aug 2026)

The plan's 2,000 minutes hit 100% on 9 August with 23 days left. Measured over the three days
GitHub still had runs for: **192 Actions-minutes, ~64 a day**, of which `checks` is 160 across 214
runs. 2,000 ÷ 64 = 31 days, so the burn rate and the allowance were the same number and the month
ran out exactly on schedule.

Fixed in `.github/workflows/checks.yml`, no coverage lost:

- **`paths-ignore`** on `docs/**`, `**/*.md`, `.claude-flow/**`, `graphify-out/**`. The three jobs
  are `deno check`, `tsc --noEmit` and three node scripts — none can be affected by a markdown
  file, and this repository writes a great deal of markdown plus two directories of run artefacts.
  A handover commit was paying for a full typecheck of the Next.js app twice.
- **`concurrency`** with `cancel-in-progress` on every ref **except main**. The project merges in
  bursts; superseded runs are cancelled instead of each running to completion. main is excluded on
  purpose — the run against what is actually deployed has to finish.

**Still the owner's call, and deliberately not done:** setting a $0 Actions budget stops the
overage immediately, but it also stops the daily **External resilience watchdog** — the only check
outside the database that would notice a total pg_cron outage. It costs 0.1 minutes a day. At
GitHub's $0.008/minute for Linux the overage for the rest of the cycle is single-digit dollars at
the pre-fix rate and less after it.

## 7. THE END-OF-SESSION SWEEP (standing procedure)

The founder's instruction, 9 Aug 2026: **check GitHub, Vercel and Supabase for failures at the end
of every session.** Not as a reaction to a report — as a procedure. Result of the first one:

| platform | checked | found |
|---|---|---|
| GitHub Actions | last 12 runs | 6 failures, ALL of them the quota block before the budget was set at ~21:47. Every run after it is green, including `checks` and `deploy edge functions` on main |
| Vercel | 20 deployments + runtime errors/24h | 19 READY, 1 CANCELED (superseded by a rapid follow-up push — normal). Latest production READY. **No runtime errors** |
| Supabase production | advisors, cron, agent_runs | 617 advisories, **0 ERROR** — 441 are the known `rls_enabled_no_policy` deny-all state from section B. **0 name any object touched this session.** No failed cron runs in 12h, no `agent_runs` errors in 6h |
| Supabase staging | cron, agent_runs | clean on both |

**The diagnostic that matters, because it will happen again:** an Actions job with **zero steps**
means the runner never started — that is quota or billing, never code. A broken workflow file
reports `startup_failure`; a failing test reports failing steps. The way to tell them apart in one
move is to dispatch a workflow you did not touch: `resilience-ping` costs 0.1 minutes and failed
identically, which proved the `checks.yml` change was innocent.
