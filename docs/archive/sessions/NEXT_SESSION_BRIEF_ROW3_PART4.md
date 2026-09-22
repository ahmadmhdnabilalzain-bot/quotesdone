# Row #3, part 4 — opening brief

Spec: `docs/specs_row3_executive_ui.txt`. Scorer: `scripts/staging/verify_os2_blueprint.mjs`.
State: `docs/sessions/ROW3_STATE.md`. Overlap decision: `docs/sessions/ROW3_ROW7_UI_OWNERSHIP.md`.
Previous brief (still accurate on the blocked list): `NEXT_SESSION_BRIEF_ROW3_PART3.md`.

**Measured on production at the end of the previous session: 100/152 (66%), 0 errored, 0
regressions across six full runs. Run the scorer before you read another line — twelve checks were
deployed and verified and flip on crons that have since fired, so the number should be materially
higher.**

---

## 1. RUN THE SCORER, THEN READ THIS TABLE BEFORE CONCLUDING ANYTHING

Every row below is deployed to BOTH projects and was verified either by executing the routine or by
projecting its output over production read-only. **A check still MISSING after its hour is a defect
and it is yours** — the routine did not do what execution said it would. Do not rebuild it; debug it.

| UTC | check(s) | written by |
|---|---|---|
| 00:35 | `digital-twin-live-kpis` | `bi_snapshot_6h` |
| 02:15 | `s34-resilience-measured` | `capability_verify_daily` |
| 03:50 | `s29-scan-five-questions` | `opportunity_scan_daily` |
| 04:15 | `s31-slowdown-investigated` | `index_slowdown_watch_daily` |
| 04:30 | `companion-overnight-brief`, `voice-morning-brief-spoken` | `founder_brief_daily` |
| 05:00 Mon | `exec-meeting-agenda-six`, `exec-meeting-debate` | `exec_meeting_weekly` |
| 06:00 Mon | `exec-intel-quantified-recommendation` | `exec-agents-weekly` |
| 06:00 Mon | `s35-restructure-four-questions`, `evolution-proposes-structure` | `evolution_scan_weekly` |
| 06:40 Mon | `s39-governance-six-monitors` | three monitors that had never run |
| ~23 Aug | `time-machine-restores-six-dimensions` | `company_snapshot_daily` — a 14-day universal |
| 1 Sept | `s37-benchmark-monthly-report` leg 2 | `monthly_report` |

`s33-replay-six-tracks` needs a snapshot day carrying BOTH a KPI reading (from 00:35) and an
outcome opened (from `fn_kpi_review`, Mondays).

**`exec-meeting-priorities-agreed` flips on no clock at all.** It is a universal over 60 days and
three of the four meetings in the window carry string recommendations written on 28 Jul and 3 Aug.
They age out 27 Sept, 3 Oct, 6 Oct. Rewriting them would be editing the record.

## 2. THE THREE THINGS THAT MATTER MORE THAN THE SCORE

1. **`matching` was never failing — CORRECTED 9 Aug.** The benchmark returns precision 100% and
   recall 100% on every run it has made (3 Aug, 27, 20, 13 Jul). `match_eval`'s logRun hardcoded
   `agent: 'match_eval'` and was called from the AUTH GUARD as well as the benchmark, so a caller
   refused at the secret check was filed under the benchmark's own identity — and
   `v_critical_capability_tests` reads the LATEST run for a suite. One unauthenticated probe on
   5 Aug marked the capability FAILING and dragged the 14-day pass rate to 33%. Refusals now go to
   `match_eval_auth`; the capability reads PASSING again after the next weekly benchmark.
   **Open, and not fixed:** something has called `match_eval` with a wrong or missing `__secret`
   four times since 27 July. The guard is right to refuse it; nobody has established what it is.
2. **`strategic_execution` fell 65.3 → 46.8**, taking `company_maturity` 44.1 → 42.4 on 6 Aug, and
   nothing looked for three days. `fn_index_slowdown_watch` now raises it. The cause is still unknown
   — the routine names the dimension that moved and says plainly that the reason is not in the data.
3. **57 of 66 employees are dormant** — no run in 30 days. That single fact sits behind five blocked
   checks, and `fn_evolution_scan` now says so monthly instead of proposing router tweaks around it.

## 3. DO NOT REBUILD ANY OF THIS

Sessions 1–2 built eleven workspace routines and nine screens (section 1 of PART2, still accurate).
Session 3 added, all promoted with a digest match:

`fn_exec_meeting` · `fn_ws_reports` · `fn_challenge` · `v_operating_manual` · `bi_snapshot_6h` ·
`fn_capability_verify` + `capability_verify_daily` · `fn_period_report` · four `model_policy` rows ·
`fn_ws_company_os` (flow + tracks) · `trg_company_event_dispatch` · `fn_check_spend` ·
`fn_ws_exec_home` · `fn_action_policies` + four action payloads · `fn_health_index` ·
`exec_agents` (edge) · `fn_evolution_scan` · `fn_opportunity_scan` · `fn_index_slowdown_watch` +
`index_slowdown_watch_daily` · `fn_company_snapshot`.

Screens: `MeetingReplay`, `OsFlowMap`, the six-board Console strip, the replay track row, policies on
the escalation and governance surfaces.

## 4. GENUINELY BLOCKED, WITH THE REASON

| what | why |
|---|---|
| `intel-customer-behavior`, `company-map-entities`, part of `s22`, `s30` churn/satisfaction | `public.customers` holds 0 rows. `inquiry_intake` v21 creates one — verified in the deployed source — so this fills on the first authenticated inquiry. |
| the five per-employee universals, `s32-reputation-six-dimensions` | 8 of 66 employees have ever produced a run. `correctness` is NULL on all 66 because all 51 `outcome_record` rows sit at verdict `pending` — the earliest measurement date is 11 Aug. Not a defect: `fn_outcome_evaluate` runs daily and has nothing to grade. |
| `explain-confidence-score` | NOT a rendering gap. All 8 escalation elements carry `confidence` NULL because `fn_os_command` reads `decision_log`, where it is null on every `action_gate` row. |
| `explain-alternatives-considered` | `challenge_record`'s alternatives join to none of the 34 surfaced actions. **Re-measure** — the meeting now writes challenges naming agenda items. |
| `strategic-not-operational` | 115 strategic against 181 operational. The sweep took it from 316. |
| `s21-events-nine-classes` | 3 of the 5 missing emitters are honest code changes; **`competitor.pricing_changed` has no mechanism at all** — `competitor` has no price column and `market_intel` has 0 rows. |
| `s24-board-before-major-decisions` | leg 1 is one line (a call to `fn_board_review`); leg 2 needs every `decision_record` in 30d to carry all 7 advisor opinions, and the 11 in the window have none. Back-filling them is fabrication. |
| `s34-stress-six-scenarios`, `future-simulator-forward-questions` | Both read `scenario_library.last_run` and **nothing writes it**. Stamping it is the same fraud as writing `passing` for an untested capability. A real scenario runner is the build. |
| `what-if-projected-deltas`, `-confidence-score` | four simulation rows from 28 July with different keys. |

## 5. BUILDABLE, CLOSEST FIRST

- **`s36-recommendation-seven-fields`** — 3 of 7 on every one of 1,161 recommendations/30d; missing
  alternatives, assumptions, cost. Writer change plus a 30-day wait for the old rows to age out.
- **`s27-knowledge-seven-fields`** — 1 of 7 metadata fields on 1,985 `agent_knowledge` rows. A
  backfill; only if the values are derivable, never invented.
- **`s23-reallocation-three-classes`** — 0 of 3 resource classes moved in 62d. `allocation_change` is
  the table; something has to actually reallocate.
- **`s22-graph-navigation`** — 2 of 9 node kinds. supplier, rfq, quote, knowledge and revenue all
  have populated sources; **customer does not**, so this cannot fully close yet.
- **`s26-discover-suppliers` / `-compare-capabilities` / `-verify-documentation`** — 0 scrape runs in
  30d, 0 capability records, 7 of 16 documents verified.
- **`personalization-learns-founder-habits`** — 0 candidate behaviour stores among 411 tables. Needs
  a new table plus a reachable reader.
- **`genome-eleven-attributes-stored`** — 5 of 11. The absent ones are risk appetite, hiring
  philosophy, brand positioning. **These are founder doctrine, not derivable facts — ask, do not
  author them.**

## 6. THE RULES THAT KEPT THIS HONEST

- **Measure the DB leg and the UI leg separately, before building.** A passing DB leg is not a
  populated panel.
- **Execute on staging before promoting.** It caught three real bugs this session, including two
  CHECK constraints on `evolution_proposal` that would have failed silently at the weekly run.
- **Project the output over production read-only when staging's data cannot exercise it.** That is
  how the `review_chain` false-absence and the empty competitor roster were caught.
- **Resolve every rendered path against the live payload before shipping a screen.** `MeetingReplay`
  was 10 of 21 on production's old meeting and 25 of 26 on the new shape — and the one empty path was
  a real defect in `fn_challenge`.
- **Never back-fill, back-date or re-shape history to turn a gate green.** Four checks in section 4
  are red for exactly this reason and should stay red until time or traffic moves them.
- **A check that passes by accident is worse than one that fails.** `s31`'s first leg read 1 because
  a read-only screen routine matched a regex. Look at what the number is actually counting.

## 7. END-OF-SESSION SWEEP — STANDING PROCEDURE, NOT A REACTION

The founder's instruction of 9 Aug: **check GitHub, Vercel and Supabase for failures before ending
every session.** GitHub Actions runs, Vercel deployments and runtime errors, and on BOTH Supabase
projects the advisors, failed `cron.job_run_details` and `agent_runs` errors. Report what was
checked and what was found, including "nothing".

**The diagnostic that will recur:** an Actions job with **zero steps** means the runner never
started — that is quota or billing, never code. A broken workflow reports `startup_failure`; a
failing test reports failing steps. Dispatch a workflow you did not touch (`resilience-ping`, 0.1
minutes) to settle it in one move.

**GitHub Actions state:** the 2,000-minute plan was being consumed at exactly the rate it renewed
(~64 min/day). `paths-ignore` and `concurrency` are in `checks.yml`, the founder set a $10 Actions
budget on 9 Aug, and CI was confirmed green afterwards. `scripts/checks/run.mjs` now also runs
locally (`vendor` joined SKIP_DIRS), so the gate is not Actions-dependent: `node
scripts/checks/run.mjs` gives 21 node check files + 16 deno tests, EXIT=0.
