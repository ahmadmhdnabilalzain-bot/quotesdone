# NEXT SESSION — ROW #3 (second pass, 11 Aug 2026 PM)

Measured on **2026-08-11 between 09:25 and 10:30 UTC**. This supersedes
`NEXT_SESSION_BRIEF_ROW3_UI.md`, which is left in place as the record of what the session was
handed. **That brief put four blocked items in its work list**; this one corrects them, with the
measurement in each case.

Read `FULL_SPEC_AUDIT_2026_08_11.md` alongside it for the standing verdicts. The conduct rules are
in the `quotesdone-session` skill and apply automatically.

---

## WHERE IT STANDS

| | |
|---|---|
| Row #3 at session start | **124/152**, 28 NOT MET |
| pack scorecard | 100% ingested, **37 of 37 IN USE**, both projects |
| OS_PORTALS gates | **23 met, 0 open**, both projects |
| project parity | **BOTH PROJECTS IN SYNC** |
| OpenRouter | **~$9.27** at 10:15 UTC, **~$0.27/h** → ~34h. Founder alerted twice; topping up is his call. |

---

## THE CORRECTION

The previous brief's Group C listed twelve "buildable now" items. **Four are not buildable**, blocked
by the same thing as Group A — the marketplace has no demand side:

```
customers 0   inquiries 0   quotes 0   transactions 0   approved suppliers 0
```

- **`s29-scan-five-questions`** — the missing class is *rising keywords*. There is no search-term
  stream: `inquiries` is 0 rows, and `category_keyword`/`subcategory_keyword` are static
  dictionaries, not time series. A "rising" keyword derived from a static list would be invented.
- **`s22-graph-navigation`** — `graph_nodes` holds category, responsibility, employee, goal,
  workflow, department, operating_system. Of the nine chain classes only **category** and
  **employee** exist. Five of the seven missing (customer, rfq, quote, revenue, supplier) are
  entities the company does not have.
- **`company-map-entities`** — same store, same gap. The UI reader is real work, but it would render
  a graph with five of nine classes empty.
- **`time-machine-scrub`** — needs a snapshot from last month and from six months ago.
  `company_snapshot` holds **14 days**. Blocked by time; back-dating snapshots would be fabrication.

### Two need no work — they clear themselves

- **`explain-knowledge-used`** — 367 of 423. All 55 failures are `action_gate` rows dated **4–6 Aug**,
  before `action_gate_records_sources.sql` landed on 6 Aug. Every row since carries sources.
  **Clears itself 13 August** when 6 Aug leaves the 7-day window.
- **`s21-no-polling`** — **clears ~17 August.** Do not touch it; re-measure.

### One can never pass as written

- **`what-if-projected-deltas`** and **`what-if-confidence-score`** are universals over the whole
  `simulations` table with **no time window** — `N('simulations')` is `count(*) … where true`. Five
  rows from 6–28 July lack the revenue+leads+profit triple. Fixing `fn_what_if` to emit the triple
  and a confidence is still correct spec work, but the checks stay red afterwards unless those five
  historical projections are deleted — and that is the founder's call, not a scorer's.

---

## WHAT IS ACTUALLY LEFT AND BUILDABLE

1. **`explain-alternatives-considered`** — 0 of 61. All four surfaces already deliver `confidence`;
   none delivers `alternatives`. Needs the four payloads (`fn_os_command().attention`,
   `fn_ws_governance().recent_escalations`, `fn_ws_operations().approvals`, `fn_ws_ea().approvals_top`)
   to carry it, and the two hand-picked components (`<Escalations>`, `<GovernanceApp>`) to render it
   — the other two use `<ReadableObject>` and show every key automatically. The honest source is the
   verdict the gate actually rejected, the same shape `fn_decide` already builds as `v_alt`/`v_alt_why`.
   `decision_log` has no `alternatives` column yet.
2. **`s36-recommendation-seven-fields`** — 3 of 7 on every recommendation; missing alternatives,
   assumptions, cost. Shares its answer with #1.
3. **`s23-reallocation-three-classes`** — all 12 `allocation_change` rows in 62d carry
   `resource='ai_budget_aed'`, which does not match `\yai\y` because `_` is a word character. The
   real gap is that `fn_reallocate` only moves AI budget; the spec also names marketing spend and
   supplier onboarding capacity. Marketing budget is AED 0 on paused campaigns — check there is
   something real to move before moving it.
4. **`what-if-approve-from-simulation`** — no approval row references a simulation.
5. **`personalization-learns-founder-habits`** — nothing yet. New store + reader + UI.
6. **`time-machine-restores-six-dimensions`** — 5 of 6 dimensions non-null on all 13 snapshots. One
   short; find which and why.
7. **`exec-meeting-priorities-agreed`** — 1 of 5 meetings in 60d end with ranked agreed priorities.
   `exec_meeting` runs weekly, so build the ranking and it fills over ~4 weeks.

Group B (employee track record) is unchanged and should still not be filled with a baseline.

---

## WHAT THIS SESSION CLOSED

- **`s34-stress-six-scenarios` 2 of 6 → 6 of 6, both projects.** Four scenarios authored **and** the
  thing that runs them built — nothing in the database had ever written `last_run`, and the 10 Aug
  file had correctly refused to stamp one. `fn_scenario_run` tests whether the organisation can
  answer the failure, and was made to fail three ways in an aborted transaction before being trusted.
- **`explain-confidence-score` data path fixed.** `trg_action_gate` wrote a literal `null` into
  `decision_log.confidence` while `NEW.confidence` sat in scope one line above. Probe:
  `dl_confidence=0.77`. `<Escalations>` now renders it. **Reads 52 of 60, escalations 0/8, until
  eight new gated actions arrive** (~2h of normal traffic). Not backfilled — the 1,378 historical
  rows keep their null.
- **`s24-board-before-major-decisions` 0 of 11 → 10 of 11.** The wiring was never missing; probe
  returned 7 opinions / 7 advisors / `subject_ref` set. It had never been exercised.
  `decision_record` 42 is `executed` and is deliberately left unreviewed, so this stays MISSING
  until **5 September**.
- **Edge function deploys were blocked on main** since 09:13 with 19 type errors — invisible because
  the PR typecheck is non-blocking by design while the deploy job hard-fails on the same errors. Two
  were real: `pdf_native` served every raw PDF as `application/json` (CORS spread overwrote the
  Content-Type), and `kb_research_test` imported a deleted `llmWeb` so it could not load at all.
  Fixed, deployed to both, `deploy edge functions` green on main.
- **`agent_silence_watch_daily`** was dying for a full day at a time. Not slow — measured 465 ms end
  to end; it sat blocked for its full 120 s timeout. Cadence, not code: now `40 */6 * * *`.

PRs: #173, #174, #175, #176 — all merged.

---

## STILL OPEN, NOT IN THE SCORER

- **OpenRouter ~$9.27, ~34h.** `agent_reasoning` on sonnet-5 is ~85% of spend — 592 calls / 82 AED
  in 7 days, average 11,727 input tokens.
- **Model cascading (open router.txt §4) is still not implemented, and the naive version costs MORE.**
  `agent_reasoning` reports a confidence on **0 of 592** calls, so a confidence-gated cascade
  escalates every time and you pay for both models. `agent_brain` returns prose plus an `@@ACTIONS@@`
  JSON tail, and `selfReportedConfidence()` only reads whole-JSON bodies. **The output contract has
  to carry a confidence before cascading can save anything.** The parked `routine_employee_reasoning`
  route caps output at 1,000 tokens against a measured 1,446 average — switching to it re-introduces
  the truncation that was fixed.
- **Prompt caching is marginal, not broken.** Measured over 10h on `agent_reasoning`: 45,652 tokens
  written, 9,851 read → R/W 0.216 against a 0.278 break-even. Roughly break-even. Not the lever.
- **55 of 63 active company goals carry no `measure_sql`.**
- **58 orphan routines**, baselined as a ratchet. Several are PostgREST RPCs named at runtime —
  verify before dropping any.
- **`cron_history_prune` (jobid 94) is OFF**, `cron.job_run_details` 144,198 rows / 80 MB. It was
  **not** the cause of the watchdog failure, and enabling it deletes nine days of history. Retention
  is the founder's call.
- **`meta_access_token`** absent by design. Leave it.

---

## THE ONE-LINE RULE

Say nothing until you can honestly say, and say **only**:

> all verified and fixed and merged and deployed 100%

If you cannot, keep working. If you hit a hard limit, hand over honestly and name exactly what is
unfinished.
