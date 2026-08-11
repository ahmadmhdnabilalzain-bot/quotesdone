# FULL SPEC AUDIT — 11 August 2026

Every one of the eight spec files and the six v2026.07.31 packs, audited against the code and both
live databases. Clock at start: **2026-08-11 07:54 UTC / 11:54 Dubai**.

Everything below is a measurement or an execution. Everything applied went to **both** projects;
`scripts/checks/project_parity.mjs` prints BOTH PROJECTS IN SYNC.

---

## The twelve open items

| # | Item | Verdict | Evidence |
|---|---|---|---|
| 1 | Departments vs the spec's 22 | **BUILT** | 14 → **25** departments, 68 → **93** employees. 11 created, Data & Analytics restored, Supplier Success reactivated. Every one: ≥2 staff, a named manager, an objective, an authority grant, a budget, an OS. `rfq_intelligence` planned and assigned 3 tasks on its first run. |
| 2 | CEO reasoning stopped 9 Aug | **NOT WHAT IT LOOKED LIKE** | The Chief of Staff *is* thinking: `agent_brain` `task_class=agent_reasoning`, 193 calls in 48h, 2 tasks done every hour. `fn='cos_execute'` stopped appearing in `ai_cost_log` on 29 Jul because the reasoning moved into `agent_brain`. What genuinely stopped is the `agent='cos_execute'` **run row** on 10 Aug 11:50 — and nothing watched for that. Now `fn_runner_silence_watch` does, and flagged it on its first pass. |
| 3 | Prompt caching off (0.19%) | **THE METER WAS BROKEN, THEN FIXED** | OpenRouter reports cache under `usage.prompt_tokens_details.{cached_tokens,cache_write_tokens}`; `ai_gateway` read two top-level names that do not exist, so `cachedIn` was 0 on every call ever made. Worse, `cache_control` was stamped on a prompt whose tail says "captured just now" — a 1.25x write on every call and a read on none. Split, measured: **0.293 → 0.176 AED (write) → 0.087 AED (read)**. |
| 4 | 46 calls with NULL task_class | **CLOSED BEFORE THIS SESSION** | All 146 null rows are 27–28 Jul, before `fn_llm_log` derived the class. **Zero since 28 Jul.** Not a live defect. |
| 5 | 37 notifications never sent | **PART REAL, PART BY DESIGN** | `resilience_alert` rows are written already-`digested` as an audit copy — the alert itself goes out through `alert_founder`, so those 12 are not lost. The real defect: the founder brief listed digest rows as bare **counts by type** and then closed **every** digest row regardless of age, so anything outside its window was marked handled without ever appearing. Now prints subject + timestamp and closes only what it reported. |
| 6 | Recurring email figures | **FOUR DEFECTS FOUND AND FIXED** | See below. |
| 7 | Functions with zero tables | **THE RULE AS WRITTEN DOES NOT ISOLATE DEAD CODE** | 150 rows: ~120 are pgvector's own operators in `public`, the rest pure helpers that are correct to touch no table and *are* called (`fn_norm_text` 7 callers, `fn_term_matches` 7). `scripts/checks/no_orphan_routines.mjs` measures what the rule is for: **58 orphans**, baselined as a ratchet. Not deleted — several are PostgREST RPCs the console names at runtime. |
| 8 | agent_expectations merge | **NOT A MERGE — A CATEGORY ERROR** | Keyed on runner names, not employee keys. `chief_of_staff` and `brief` are two *runners* belonging to one *employee*, which is what the 23505 was saying. 36 stale rows, **zero readers**, 84 live runners unwatched. Now re-derived every pass (121 runners, 57 watched) with a `kind` column, and read by `fn_runner_silence_watch`. |
| 9 | Supplier categories | **RECONCILED EXACTLY** | All 84 spec entries present. 12 extras: **8 were the same trade under a shorter slug**, each with **zero** of the 14 required knowledge modules while its twin had all 14 — folded with aliases, 79 leads moved. 4 are real trades from the spec's own 66-group list and stay. `signage` was the one non-duplicate with no knowledge; its 14 modules were authored. **88 active, 88 with all 14.** |
| 10 | `meta_access_token` absent | **BY DESIGN, HANDLED CORRECTLY** | `meta_sync` logs `status='skipped'` with the exact key to add and why. It is an OAuth credential only the founder can mint from Meta Business. Not a code defect. |
| 11 | OpenRouter balance | **$10.70 at 05:00, burning ~$1.15/h** | Which is why item 3 was worked first. |
| 12 | Row #3 31 NOT MET | Re-scored — see the run at the foot of this file. |

---

## Item 6 in full — what the founder was being told

**"Monthly goal attainment: 97.7% against target"** on a morning with AED 0 recognised against an
AED 83,333 monthly target. Three compounding causes:

1. `least(100.0, NULL)` returns **100.0** — PostgreSQL's `least()` ignores nulls — so all 56 goals
   with no measured actual scored a perfect 100 and were averaged with the two real ones
   (revenue 0.0%, quote conversion 57.2%).
2. No period filter: it averaged the **2026-07** rows on 11 August.
3. Direction ignored: 19 `at_most` goals were scored as though bigger were better, because
   `fn_goal_period_refresh` tested `direction='down'` while the table stores `'at_most'` — that
   branch was unreachable on every row.

Now **50.0% across 2 of 61 goals that carry a measured actual for 2026-08**, via
`fn_goal_attainment`, which returns the denominator so no caller can quote the rate without its base.

**The goal ledger was stuck in July.** `fn_goal_period_refresh` only ever UPDATEd existing rows.
It now opens the current month, quarter and year (67 period rows opened on the first run) and says
in its own note how many active goals carry no `measure_sql` at all — **55 of 63**.

**"Approvals waiting: 40 (incl. 6 supplier KYC)"** — the 40 is `agent_actions`, the 6 is `leads`.
Disjoint sets. 46 decisions were waiting and the email said 40.

---

## Also found and fixed, unprompted

- **Both cron watchdogs had died.** `agent_silence_watch_daily` 06:40 and `exception_alerts_hourly`
  07:35, both a statement timeout. `cron.job_run_details` is 143,802 rows / 80 MB with one index,
  and both routines asked it a per-job question — 165 to 495 heap scans per run. The index that
  would fix it is refused (*must be owner of table job_run_details*), so both queries read the
  history once instead. `fn_agent_silence_watch` is the routine that would have reported its own
  absence.
- **64 of 93 employees had never done anything** — not idle, *unreachable*. `cos_execute` sent every
  task to one agent per department. It now routes on `employee_authority`, which already held 285
  per-employee grants and had no reader: **54 of 99 (dept, class) pairs now route elsewhere,
  23 employees reachable who never were.**
- **27 employees held no knowledge of their own** and were answering with a colleague's expertise.
- **`v_department_health` covered 15 of 25 departments** — a hand-written UNION. Now derived from
  `org_departments`, so coverage cannot fall behind the org again.
- **The knowledge confidence layer had 2 of its 7 fields.** Now 7 of 7 on all 2,040 rows, every
  value derived from a written rule, dated from each row's own `updated_at` rather than from today.

---

## Standing verdicts the next session should not re-litigate

- **`dept_key='knowledge'` is the Operations team under a legacy key.** Do not rename it: it is a
  primary key behind four foreign keys and many bare string literals. The display name is corrected.
- **`ttl:'1h'` prompt caching works and loses money here.** Write 2.0x vs 1.25x, and the hourly loop
  repeats at ~65 minutes — just outside a 1-hour window. 5-minute break-even is 22%; measured
  same-agent repeat within 5 minutes is 38%.
- **`dept_plan` stays on `chief_of_staff_decision`, not `department_planning`.** The latter caps
  output at 1,600 tokens and dept_plan measured 1,725 on 6 Aug — routing it there re-introduces the
  truncation that was fixed.
- **`s26-discover-suppliers` must not be "fixed".** Apify was deliberately cancelled until ~Feb 2027;
  work the existing 20,470 leads.
- **Reputation dimensions are NOT filled with a baseline.** 64 employees have no track record, and a
  number invented for them would be indistinguishable from a measured one the moment it landed in
  the column. `s32-reputation-six-dimensions` stays NOT MET, honestly.
