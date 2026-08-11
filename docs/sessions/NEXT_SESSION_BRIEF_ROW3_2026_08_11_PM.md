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

### Five need no work — they clear themselves. Re-measure, do not rebuild.

| check | why it is already fixed | goes MET |
|---|---|---|
| `explain-confidence-score` | writer + trigger order fixed today; needs 8 new gated decisions | within hours |
| `explain-knowledge-used` | all 55 failures are `action_gate` rows dated 4–6 Aug, before `action_gate_records_sources.sql` landed on 6 Aug; every row since carries sources | **13 Aug** |
| `s21-no-polling` | already known; per-day lag is 0s since the trigger landed | **~17 Aug** |
| `time-machine-restores-six-dimensions` | the missing dimension is **customers**, present on 2 of 13 snapshots. `fn_company_snapshot` already writes it — 9 and 10 Aug both carry it. The 11 older snapshots predate the fix and must NOT be back-filled: writing a customer count into a day nobody measured it is reconstructing a measurement that was never taken | **23 Aug**, when 8 Aug leaves the 14-day window |
| `s24-board-before-major-decisions` | 10 of 11; `decision_record` 42 is `executed` and is deliberately unreviewed | **5 Sept** |
| `exec-meeting-priorities-agreed` | writer already fixed — meeting #42 carries 12 `rank`/`owner` objects; the other four are pre-fix prose | **5 Oct** |
| `explain-alternatives-considered` | column, writer, all four surfaces and both components landed this session; two thirds of surfaced approvals predate `decision_log_id` | as the queue turns over |

### One can never pass as written

- **`what-if-projected-deltas`** and **`what-if-confidence-score`** are universals over the whole
  `simulations` table with **no time window** — `N('simulations')` is `count(*) … where true`. Five
  rows from 6–28 July lack the revenue+leads+profit triple. Fixing `fn_what_if` to emit the triple
  and a confidence is still correct spec work, but the checks stay red afterwards unless those five
  historical projections are deleted — and that is the founder's call, not a scorer's.

---

## WHAT IS ACTUALLY LEFT AND BUILDABLE

1. **`explain-alternatives-considered`** — 0 of 61. All four surfaces already deliver `confidence`;
   none delivers `alternatives`. Needs the four payloads to carry it and the two hand-picked
   components to render it:

   | surface | payload | reads |
   |---|---|---|
   | escalations | `fn_os_command().attention` | `decision_log` directly |
   | governance | `fn_ws_governance().recent_escalations` | `agent_actions where escalated` |
   | operations | `fn_ws_operations().approvals` | `agent_actions where status='pending'` |
   | assistant | `fn_ws_ea().approvals_top` | **`fn_ea_agenda(7)`**, not `fn_ws_ea` — edit that one |

   `<OperationsApp>` and `<AssistantApp>` hand their payload to `<ReadableObject>` and so show every
   key automatically; only `<Escalations>` and `<GovernanceApp>` name their fields by hand.

   The honest source is the verdict the gate actually rejected — the same shape `fn_decide` already
   builds as `v_alt`/`v_alt_why`. `decision_log` has no `alternatives` column yet.

   **MEASURE THIS BEFORE BUILDING IT.** The obvious implementation — put `alternatives` on
   `decision_log`, have `trg_action_gate` write it, and join the three `agent_actions` surfaces
   through `decision_log_id` — **does not close the check today**:

   ```
   operations (30 pending)   29 rows, 9 carry a decision_log_id
   assistant  (pending+needs_review)  42 rows, 22 carry one
   governance (escalated)    15 rows, 15 carry one
   ```

   The column was added on 6 Aug, so two thirds of the surfaced approvals predate it and have **no
   recorded evaluation to cite**. Emitting "approve / reject" for those would invent an evaluation
   that never happened — the same objection that keeps the reputation dimensions empty. Build the
   writer so every new gated action carries a real alternative, project it on all four surfaces, and
   let the check go MET as the older rows leave the queue. Do not synthesise a value for the rest.
2. **`s36-recommendation-seven-fields`** — 3 of 7 on every recommendation; missing alternatives,
   assumptions, cost. Shares its answer with #1.
3. **`s23-reallocation-three-classes`** — all 12 `allocation_change` rows in 62d carry
   `resource='ai_budget_aed'`, which does not match `\yai\y` because `_` is a word character. The
   real gap is that `fn_reallocate` only moves AI budget; the spec also names marketing spend and
   supplier onboarding capacity. Marketing budget is AED 0 on paused campaigns — check there is
   something real to move before moving it.
   *(The writer, all four surfaces and both components landed this session — see below. What is left
   is the queue turning over.)*

That is the whole list. Four items that were on it have since been measured off it:

- **`what-if-approve-from-simulation` — DONE this session.** `fn_what_if` now leaves an approval
  referencing the simulation, gated on the simulator's own confidence ≥ 0.5.
- **`exec-meeting-priorities-agreed` — SELF-CLEARING, not buildable.** The writer is already fixed:
  meeting #42 (10 Aug) carries 12 objects with `rank`, `owner`, `title`, `priority`, `why`. The
  other four in the window are arrays of prose strings from before the fix, and rewriting what a
  past meeting produced is not on. `exec_meeting_weekly` runs Mondays 05:00 UTC, so every meeting
  from here is compliant and the check goes MET on **5 October**, when the 6 Aug meeting leaves the
  60-day window.
- **`personalization-learns-founder-habits` — BLOCKED, same class as Group A.** There is no
  founder-behaviour stream to learn from. The founder has decided **12 actions ever** across three
  identities, the newest on **13 July**, and nothing records which modules he opens or when. A
  "habit" derived from twelve month-old rows is an invented pattern. The honest first step is the
  *capture* half — record founder interactions so that in some weeks there is something to learn —
  and the check will show nothing until then. Do not build the reader first.
- **`s36-recommendation-seven-fields` — weeks, not a session.** `FIELD_COVERED` requires a *column*
  on `agent_actions` whose name matches each of the seven, non-null on **every** recommendation in
  30 days. Three exist (`evidence`, `risk`, `confidence`); `assumptions`, `alternatives`,
  `expected_impact` and `cost` do not. `cost` and `alternatives` are honestly derivable, but
  assumptions and expected impact have to be *stated by the producing agents* — that is a change to
  dozens of routines, and stamping boilerplate into them is precisely the black box the section
  forbids. Then 30 days of turnover on top.

And on **`s23`**: `department_budget.marketing` is 400 AED/month, but that is the marketing
department's AI budget, not channel spend — Meta is the only paid channel and both campaigns sit
paused at AED 0. There is nothing real to move for "marketing budget to channels". Supplier
onboarding capacity (`invite_daily_cap`, currently 10 against a sendable pool of 16,238) **is** a
real movable resource. So s23 can be honestly advanced to 2 of 3 and not to 3 of 3.

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
- **`what-if-approve-from-simulation`**: the screen half already passed and nothing had ever created
  the action, so the approve control had nothing to bind to. `fn_what_if` now leaves an approval
  referencing the simulation, gated on its **own** confidence ≥ 0.5 — the branches whose text says
  "Any number would be invented" or "an assumption not an observation" produce a projection to read
  and no action to take. Run for real on the live question: simulation #8, `agent_action` #2679.
- **A hardcoded metric the founder was being shown as a fact.** `fn_what_if` told him "cache
  adoption is 0%, so caching is the first lever" — a string literal between three computed figures,
  true when the cache meter was broken and never updated when it was fixed. It now measures
  `cached_in_tokens` against `prompt_tokens` and prints the write volume beside the read, and says
  the opposite: 0.1% against a ~22% break-even, so caching is **not** currently the lever.
- **`explain-alternatives-considered`** built end to end: `decision_log.alternatives`, the gate
  writing the verdict it rejected, all four surfaces projecting it, both hand-picked components
  rendering it. Key present on 60 of 60 rows; values arrive as the queue turns over.

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
