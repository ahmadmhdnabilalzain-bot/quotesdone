# ROW #3 — THE EXECUTIVE UI: 28 → 91 / 152 IN ONE SESSION

Measured on production 2026-08-09. Every number below is a scorer run, not an estimate.
Scorer: `scripts/staging/verify_os2_blueprint.mjs`, modules in `scripts/staging/os2_blueprint/`.

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

| source | coverage |
|---|---|
| `agent_runs` | **7 of 113** agent values match an `org_agents` key — the rest are cron job names |
| `agent_memory` | 22 of 66 wrote a thought in 30 days |
| `ai_cost_log` | **3 of 66** have ever been billed for a model call |
| exam results | 10 of 66 have any; **0 of 66 have two dated ones** |
| `kb_usage_log` | **0 rows** — nothing writes it |

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
