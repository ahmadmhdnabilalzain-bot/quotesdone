# Row #3, part 2 — opening brief

Spec: `docs/specs_row3_executive_ui.txt`. Scorer: `scripts/staging/verify_os2_blueprint.mjs`.
State: `docs/sessions/ROW3_STATE.md`. Overlap decision: `docs/sessions/ROW3_ROW7_UI_OWNERSHIP.md`.

**Measured on production at the end of the previous session: see ROW3_STATE.md for the number.
Run the scorer before you read another line of this file.**

---

## 1. WHAT CHANGED, SO YOU DO NOT REBUILD IT

Eleven workspace routines were written or extended and every one is promoted to BOTH projects with
a digest match. Nine new screens or panels render them. Do not rebuild any of this:

`fn_ws_intelligence` · `fn_ws_exec_home` · `fn_ws_company_os` · `fn_ws_live_company` ·
`fn_ws_notifications` · `fn_os_memory` · `fn_owning_os` · `fn_report_drilldown` ·
`fn_report_recommendation_approve` — new.

`fn_ws_agent_ops` · `fn_os_search` · `fn_founder_brief` · `fn_entity_activity` ·
`fn_ws_supplier_360` · `fn_os_command` · `fn_ws_governance` · `fn_ws_operations` · `fn_ea_agenda` ·
`v_department_health` — extended.

Screens: Intelligence Centre (with What if?) · Executive Home · employee drawer · Operating System
& map · Company Memory · notification tiers · voice in the console · org chart · interactive
reports.

## 2. THE FOUR THINGS THAT COST TIME LAST SESSION

1. **The brief's defect diagnosis was wrong again.** It said four intel items had live data. Seven
   of nine DB legs already passed. **Measure the DB leg of every check in isolation before
   building.** It takes minutes and it changed the plan.
2. **A passing DB leg is not a populated panel.** Three items had passing DB legs and no payload
   carrying them. Measure both halves separately or you ship an empty screen.
3. **A default parameter creates an overload, it does not replace a routine.** `fn_os_search` kept
   its signature for exactly this reason; anything reading `pg_get_functiondef ... limit 1` could
   otherwise pick either body.
4. **Extend large plpgsql by reading the deployed definition back and injecting into it.** Six
   routines between 5.8k and 11k characters were changed this way. Retyping one is a silent bug.

## 3. WHAT IS LEFT, HONESTLY SORTED

### A. Blocked by business reality — do not spend time here

| what | why |
|---|---|
| `intel-customer-behavior`, `company-map-entities`, part of `s22` | **`public.customers` holds 0 rows** and all 7 inquiries carry a null `customer_id`. Checked directly — not a broken key. |
| `employee-current-thoughts`, `-performance`, `-performance-trend`, `-learning-progress`, `-knowledge-used` | The 66 employees barely execute: **7 of 113 `agent_runs` values match an employee key**, 3 of 66 appear in `ai_cost_log`, 0 of 66 have two dated exam results, `kb_usage_log` has no writer. |
| `strategic-not-operational` | 115 strategic items against **316** pending `agent_actions`. True about the company, not the screen. |
| `explain-confidence-score` | `decision_log.confidence` is NULL on every `action_gate` row. |
| `explain-alternatives-considered` | `challenge_record`'s 31 alternatives are challenges to founder proposals and join to none of the 35 surfaced actions. |
| `what-if-projected-deltas`, `-confidence-score` | Per-row universals over four simulation rows written on 28 July with different keys. Rewriting them is fabrication. |

### B. Waiting on a clock, not a change

- `companion-overnight-brief` and `voice-morning-brief-spoken` — `fn_founder_brief` was extended and
  **verified on staging at 8 of 8 figures**, up from 4. Both checks read the newest *stored* brief;
  the 04:30 cron regenerates it. **Re-run the scorer after 04:30 before touching either.**
- `exec-reports-recommendations-approvable` and `what-if-approve-from-simulation` — both UI halves
  are done. Each needs an `agent_actions` row that only exists once the founder approves something.
  They flip on first real use.

### B2. Looks cheap and is a trap — `twin-realtime-updates`

It reads *"0 of 13 twin classes are in the supabase_realtime publication (which holds 0)"*, so the
obvious move is `alter publication supabase_realtime add table …` for the thirteen and a
subscription in the shell. **Do not.**

All thirteen have **RLS enabled with zero policies** — deny-all. The OS console never selects them
directly; it goes through `os_api` with the service role. A browser subscription would therefore
**never fire**, and the check would go green over a feature that does nothing. Verified 9 Aug: RLS
true, policies 0, on every one of `customers`, `leads`, `org_agents`, `kb_chunks`, `inquiries`,
`transactions`, `gl_journal`, `ai_cost_log`, `workflow`, `edge_health_probe`, `risk_register`,
`expenses`, `vision_horizon`.

Making it real means admin-scoped RLS policies on those thirteen — including `customers`,
`transactions` and `gl_journal` — so that the founder's authenticated role can read them and
suppliers and customers cannot. **That is a security change and it needs its own review**, not a
line in a UI session.

### C. Genuinely buildable

- **`s38-manual-always-current`** — `cron_registry` has 138 rows against 147 active jobs. **28
  running jobs are undocumented** (`ai_spend_guard_hourly`, `knowledge_exam_loop`,
  `supplier_risk_*`, `model_benchmark_daily`, … full list in the check's evidence) and **2
  documented jobs no longer exist** (`wa_templates_watch`, `invite_campaign_start`). Registering the
  28 goes through `promote_rows_to_production.mjs`. Removing the 2 stale rows has **no sanctioned
  promotion path** — `apply_sql --ddl` explicitly forbids carrying row data — so that needs a
  decision about whether those two automations were retired deliberately.
- **`s27-knowledge-seven-fields`** — 1 of 7 metadata fields present on every one of 1,985
  `agent_knowledge` rows. This is a backfill; only do it if the values are derivable, never invented.
- **`s32-reputation-six-dimensions`** — `agent_reputation` has 66 rows and only `score` and
  `learning_speed` populated. The other four dimensions need the reputation job to compute them.
- **`s39-governance-six-monitors`** — 3 of 6 monitors need an active cron that has succeeded in 14d.
- **`exec-meeting-*` (4)** — the weekly meeting runs and succeeds; its agenda carries 0 of 6 named
  sections on all 12 contributions, no challenge is recorded, and no ranked priority list is
  produced. This is a change to `fn_exec_meeting`, and it is the largest coherent cluster left.
- **`time-machine-*`, `genome-*`, `s33-replay-six-tracks`** — snapshot coverage and attribute
  coverage; all measurable, all a matter of extending what already runs nightly.

## 4. THE RULE THAT KEPT THE SCORE HONEST

Every screen shipped last session had **its key paths resolved against the live production payload
before it shipped** — 33, then 24, then 38, then 71 paths, not one empty cell. Two figures were
corrected *before* shipping because measuring them showed they were wrong:

- a per-OS `staff` count that read 0 for Leadership, because only 4 of 72 `os_responsibility` rows
  named a department;
- `risk_register.probability` and `impact` are **text**, not numbers, so they cannot be multiplied
  into a score — the panel shows both values instead.

Do the same. The scorer cannot tell an empty panel from a full one; you can.
