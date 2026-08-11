# NEXT SESSION — FINISH ROW #3

Everything in this file was measured on **2026-08-11**. Read `FULL_SPEC_AUDIT_2026_08_11.md`
alongside it: that is what the last session closed and, more importantly, the **standing verdicts
you must not re-litigate**.

The conduct rules are in the `quotesdone-session` skill and apply automatically.

---

## WHERE IT STANDS — measured, do not re-derive, DO re-verify at the end

| | |
|---|---|
| Row #3 | **124/152**, complete run, 0 errored, **28 NOT MET** |
| pack scorecard | 100% ingested, **37 of 37 IN USE**, both projects |
| OS_PORTALS gates | **23 met, 0 open**, both projects |
| project parity | `scripts/checks/project_parity.mjs` → **BOTH PROJECTS IN SYNC** |
| org | **25 departments, 93 employees**, none empty, none single-staffed, all managed |
| categories | **88 active, 88 with all 14 knowledge modules** |
| security | 56 anon-executable SECURITY DEFINER, both projects |
| agent_knowledge | 2,040 rows, **7 of 7 metadata fields** non-null |

**124/152 is a SECOND complete run**, taken after every change of the session had landed. The first
run read 123/152 because `s27-knowledge-seven-fields` was scored MISSING at 09:20 and closed at
09:35, mid-run; the re-run confirms it MET with 7 of 7 metadata fields on all 2,040 rows. Two
complete runs, no check errored in either.

---

## THE 29 STILL NOT MET, grouped by what actually blocks them

### A. Genuinely blocked — the marketplace has a supply side and no demand side
Do **not** manufacture the data. State the verdict and move on.

- `s30-marketplace-eight-inputs` — churn and customer satisfaction need customers
- `intel-customer-behavior` — same
- `s26-discover-suppliers` — **Apify is deliberately cancelled until ~Feb 2027.** Work the existing
  20,470 leads. This must NOT be "fixed".
- `s26-compare-capabilities` — 0 approved suppliers to compare

### B. Blocked on employees having a track record — do NOT fill with a baseline
64 of 93 employees had never acted before yesterday's routing change. `cos_execute` now routes on
`employee_authority`, so **23 employees became reachable**. These should improve on their own as the
loop runs; re-measure before building anything.

- `employee-current-thoughts` — every active employee needs an `agent_memory` row in 30d
- `employee-performance` / `employee-performance-trend` — every employee needs an `agent_runs` row
- `employee-learning-progress` — every employee needs ≥2 dated `knowledge_exam_results`
- `s32-reputation-six-dimensions` — 66 rows, `correctness` and `learning_speed` null on all of them
- `employee-knowledge-used` — `kb_usage_log` per employee

**A reputation number invented for an employee with no track record is indistinguishable from a
measured one the moment it lands in the column.** The last session left these NOT MET on purpose.

### C. Buildable now — this is the real work list
Roughly in value order.

1. **`explain-knowledge-used`, `explain-alternatives-considered`, `explain-confidence-score`** —
   OS 2.txt §15 "Explainability Everywhere". Click any action and see why, who, which OS, what
   knowledge, which policies, what alternatives, what confidence, what happened after.
   `agent_actions` already carries confidence on 1,245 of 1,245 rows; alternatives and
   knowledge-used are the gap. Closes `s36-recommendation-seven-fields` too (3 of 7 fields present
   on 1,247 recommendations; missing alternatives, assumptions, cost).
2. **`time-machine-scrub` + `time-machine-restores-six-dimensions`** — OS 2.txt §7. `company_snapshot`
   has 14 days on file and six tracks already carry rows; what is missing is a reader that takes a
   date and returns all six, and a control that scrubs.
3. **`what-if-projected-deltas`, `what-if-confidence-score`, `what-if-approve-from-simulation`** —
   `fn_what_if` and `fn_simulate` exist and run. They emit `net_revenue` and
   `projected_annual_revenue_aed` but not the revenue+**leads**+**profit** triple the spec names,
   3 of 5 carry a confidence, and no approval row references a simulation.
4. **`company-map-entities`** — OS 2.txt §15/§22. `graph_nodes` has 323 nodes rebuilt daily by an
   active cron and **zero readers**. Departments, processes, employees, customers, suppliers and
   knowledge on one connected canvas.
5. **`s22-graph-navigation`** — the spec chain walked through relationships, same store.
6. **`exec-meeting-priorities-agreed`** — the Monday meeting must end with agreed, **ranked**
   priorities. `exec_meeting` runs weekly and produces opinions, not a ranking.
7. **`s24-board-before-major-decisions`** — `fn_board_review` was wired into `fn_decide` last
   session and the check still reads MISSING. **Find out why before rebuilding it.**
8. **`s23-reallocation-three-classes`** — reallocation across all three named classes
   (marketing spend, AI compute, supplier onboarding). `reallocate_monthly` runs.
9. **`s34-stress-six-scenarios`** — 2 of 6 exercised in 180d. Missing: campaign failure, cash-flow
   reduction, OpenRouter outage, and one more. `scenario_library` exists.
10. **`s29-scan-five-questions`** — 4 of 5 question classes present in `opportunity`; missing
    **rising keywords**.
11. **`personalization-learns-founder-habits`** — OS 2.txt §14. Nothing yet.
12. **`s21-no-polling`** — the 7-day median is straddling a fix. Per day it is already 0s since the
    trigger landed. **It clears itself around 17 August.** Do not touch it; re-measure.

---

## OPEN, NOT IN THE SCORER

- **OpenRouter balance.** $10.70 at 05:00 on 11 Aug, burning ~$1.15/hour. Check it FIRST. The
  founder has been told; if it is still low, cutting spend is more urgent than any check.
- **AI level distribution.** `select * from v_ai_level_distribution;` — the spec's target is
  20/55/20/5 and the last measurement was 27/29/35/1.7 with the large tier at 35%. The view is new;
  use it. `routine_employee_reasoning` exists in `model_policy` as a deliberately parked cheaper
  route for the reasoning loop — **that decision is yours to make**, and the reason it was parked is
  in the row's own rationale.
- **Model cascading** (open router.txt §4) is still not implemented: cheap model → confidence check
  → escalate. `fn_ai_route` has `p_escalate` and `selfReportedConfidence()` exists in the gateway;
  nothing joins them.
- **55 of 63 active company goals carry no `measure_sql`** and therefore can never produce an
  actual. `fn_goal_period_refresh` now says so in its own run note. The Data & Analytics department
  was created with exactly this as its quarterly objective.
- **58 orphan routines.** `node scripts/checks/no_orphan_routines.mjs` — baselined at 58 as a
  ratchet. They were NOT deleted: several are reachable over PostgREST as RPCs the console names at
  runtime, so "named nowhere in the repository" is evidence, not proof. Verify before dropping any.
- **`cron_history_prune` (jobid 94) is OFF** and `cron.job_run_details` is 143,802 rows / 80 MB,
  growing ~6k/day. Both watchdogs were rewritten to read it in one pass so this is no longer urgent,
  but it will matter again.
- **`meta_access_token`** is absent by design and handled correctly. It is an OAuth credential only
  the founder can mint. Leave it.

---

## THE ONE-LINE RULE

Say nothing until you can honestly say, and say **only**:

> all verified and fixed and merged and deployed 100%

If you cannot, keep working. If you hit a hard limit, hand over honestly and name exactly what is
unfinished.
