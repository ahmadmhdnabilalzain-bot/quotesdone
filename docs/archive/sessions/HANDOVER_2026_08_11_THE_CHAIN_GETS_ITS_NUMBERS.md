# HAND-OVER — 2026-08-11 evening · the chain got its numbers

Session ran 17:47 → 21:40 UTC (Dubai 21:47 → 01:40). **8 PRs, all merged to `main`.**

| PR | |
|---|---|
| [#199](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/199) | Two levels of the chain could not hold their own number |
| [#200](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/200) | The founder's WhatsApp could answer him; now it can obey him |
| [#201](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/201) | A requirements change left every quote answering the old question |
| [#202](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/202) | Spec #7 names 16 failures; thirteen had no scenario at all |
| [#203](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/203) | A ZIP of drawings got the same useless note as a corrupt file |
| [#204](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/204) | Five processes the company performs and had never written down |
| [#205](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/205) | Cost per OS, and it carries its own coverage |
| [#206](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/206) | The company spends 85% of its thinking on itself and nothing noticed |

---

## 1. THE ONE THING TO READ IF YOU READ NOTHING ELSE

`fn_cost_per_os(30)` — a routine that did not exist this morning — says the company spent **143.75 AED
on model calls in 30 days**, of which:

```
leadership      122.69 AED   85.4%    the OS that reasons about the company
(unattributed)   16.41 AED   11.4%
operations        4.59 AED    3.2%
marketplace       0.06 AED    0.0%    the OS meant to earn the AED 1,000,000
technology        0.003 AED   0.0%
```

Revenue over the same window: **0**.

This is not an assertion that the split is wrong — a company with no customers may rightly think
about itself. It is that **nothing in the company could see it.** `fn_spend_concentration_check()`
now runs weekly, and on its first execution filed **`org_tasks` 1309 to `ai_director`**, telling it
to shift capacity toward demand and quoting *or* record why the internal work is the faster route to
revenue, and not to close it without one or the other.

---

## 2. NINE BRIEF DIAGNOSES DIED ON MEASUREMENT

Every one would have been wasted work. **Re-measure before building what a brief proposes.**

| the brief said | measured |
|---|---|
| "Employee KPIs are effectively ZERO" | `employee_kpi` **124 rows**, 94 with `measure_sql`, 95 employees, **0 active employees without a KPI** |
| "NO LINK — management cannot translate goals into departmental objectives" | `department_objective` **66 rows covering 25 of 25 departments**, 38 with a `goal_key`, 0 orphans |
| "put your KPI + goal into `fn_agent_context`" | it **already emitted** `# YOUR KPIs`, with target, unit, cadence and *"serves company goal X"* |
| "`org_tasks.objective_id` is an unfinished writer — backfill it" | FK'd to `org_objectives`, **0 rows**, the founder's own objective intake. NULL because he has never entered one |
| "the 14 employees don't know what they are for" | all 14 had a role, title, seniority and manager. `onboarding` has **1,208 agent_runs**, `security` 1,178. One column was blank |
| "OCR + Drawing Intelligence — ABSENT" | `drawing_boq` is a full UAE quantity-surveyor vision pipeline wired into 5 functions. **UNEXERCISED, not absent** |
| "vision routing — no vision call has ever been made" | **12 vision calls** across 7 functions on `google/gemini-3.5-flash`; `drawing_boq` succeeded on 29 Jul with 1,812/1,028 tokens |
| "`fn_scenario_run` reports staffing as readiness" | already fixed by an earlier session — says `staffed` not `ready`, `is_rehearsal:false` |
| "zero-cost AI calls need fixing" | already fixed. Zero-cost-with-tokens runs 28 Jul→5 Aug and is **zero every day since 6 Aug across 1,673 calls** |

---

## 3. WHAT LANDED, WITH THE MEASUREMENT

| | before | after |
|---|---|---|
| `department_objective` measurable | **0 of 66** — no column existed | 20 measured, 0 failed |
| `employee_kpi` storing its actual | none — computed then discarded | 74 measured, 20 failed |
| `employee_kpi` performance **history** | none | `employee_kpi_history`, 123 rows/day, one per KPI per UTC day |
| `org_tasks` naming an employee | **0** — owner was prose in `detail` | 142 across 40 employees |
| active employees with no responsibilities | 14 | **0 of 93** |
| measurable company goals | 8 of 63 | **20 of 63** |
| exec's *"Reach AED 1M annual revenue"* | `goal_key=autonomous_decision_rate` | `revenue_annual` |
| `os_objective` #42 *"every goal carries a live actual"* | 7.94% | **23.81%** |
| spec #7 exception scenarios covered | 3 of 16 | **16 of 16** |
| workflows | 14 | **19** — Customer Registration, Payment, Complaint, Refund, Supplier Suspension |
| founder WhatsApp | could answer | **can dispatch** — verified, 2 real handoffs |
| `wa_inbound` `MessageSid` idempotency | none | `wa_inbound_seen`, claimed before any work |
| cost per OS | did not exist | `fn_cost_per_os`, with its own coverage attached |

**The AED 1M target now reaches an individual employee.** Inside the real 9,010-character context
`ap_specialist` receives: `# YOUR NUMBER RIGHT NOW` at offset 5,402, *"Reach AED 1,000,000 annual
revenue"* at 5,872, `LAYER 4 (EXTERNAL)` at 6,250 and not evicted.

### Three things caught only by measuring

- **A security defect I introduced and caught in the same turn.** `anon` could execute
  `fn_employee_scorecard`. **`apply_sql.mjs --promote` posts `pg_get_functiondef()`, which carries
  the CREATE and no GRANT/REVOKE** — so a revoke runs on staging and is silently absent on
  production, where a new signature is a fresh CREATE granted to PUBLIC. **This is a standing trap
  for every future routine promoted without `--ddl`.** Fixed; anon-executable SECURITY DEFINER back
  to 56.
- **A scale trap.** `leads.rv_response_rate` is a 0–1 fraction against an 85-*percent* target. Stored
  raw it would have marked a healthy 67% response rate as catastrophic. ×100.
- **`os_objective` #44 went 0 → 29** — a check got *harder* because its old pass was false. It now
  says the company has 29 employee KPIs nobody can measure.

### One place I overstated, and corrected in the same session

I wrote *"NO RECOVERY PATH EXISTS"* on `pdf_corrupted` and `zip_instead_of_pdf`, having verified only
that no MIME validation existed and **inferred** the failure mode. Reading the intake path showed a
graceful degrade — `{ok:true, boq:null, note:'no_readable_pages'}` — not a crash. Both rows corrected
in `scripts/sql/i_overstated_two_of_the_thirteen_correcting_it.sql`, and the real gap (a generic note
telling the customer nothing) fixed.

---

## 4. WHAT IS NOT DONE — named exactly

- **Maturity Index, delete-proposer, remaining spec #3 UI gaps** (AI side panel, interactive
  documents, drag & drop, workspace snapshots, live collaboration, visual workflow builder).
- **`model_policy_by_identity` → `routing_tier` on `org_agents`.** Sequenced behind §1–§4 by
  decision; §1–§4 plus Phase 8 items consumed the session.
- **Model cascading** — still correctly blocked. The output contract must carry a confidence first.
- **43 of 63 company goals still carry no measure.** Split in the file into *"no instrument exists"*
  (24 — not a SQL task) and *"the numerator and denominator are a business decision"* (19).
- **29 employee KPIs have no `measure_sql`**, all created 2026-08-11 08:00 UTC by something I did not
  trace. `os_objective` #44 now reports them honestly.
- **`employee-performance-trend` (Row #3) stays red, deliberately.** It needs >1 observation per
  employee *and* a UI series component in `AgentDrawer`. `employee_kpi_history` starts producing a
  second observation after tomorrow's 03:30 cron. **Its current source is
  `employee_kpi.created_at` — a KPI *definition's* authoring date, not a measurement.** Pointing it
  at `employee_kpi_history.measured_on` is the right fix and needs a UI reader to go with it. I did
  not do it tonight because adding my own new table to the scorer's source list, on the same night I
  created it, is indistinguishable from gaming the check.

---

## 5. THE ROW #3 NUMBER

**125/152, unchanged across two runs tonight, and the red set is identical between them** — so none
of tonight's work moved a check either way.

The 126 → 125 move happened before my first run. **It is not attributable and I am not going to
guess:** previous sessions recorded only the total, never the per-check list, and the scorer reads
live data on a database with 169 cron jobs. There was nothing to diff against.

**That is now fixed for good.** [`docs/sessions/ROW3_VERDICTS_2026_08_11.txt`](ROW3_VERDICTS_2026_08_11.txt)
is the first per-check verdict list this scorer has ever produced — 125 MET + 27 NOT MET = 152.
**Save the next run's list and a real diff becomes possible.**

---

## 6. END-OF-SESSION SWEEP

| check | result |
|---|---|
| `fn_os_portals_gates()` production | **23 / 23 met** |
| `fn_os_portals_gates()` staging | **23 / 23 met** |
| `project_parity.mjs` | **BOTH PROJECTS IN SYNC** — 197 edge fns, 420 tables, 852 functions, 155 triggers, **0 tables without RLS**, **56 anon-executable SECURITY DEFINER** (baseline) |
| Supabase advisors, production | **0 ERROR**, 448 INFO, 166 WARN |
| GitHub Actions | green on all 8 PRs |
| Vercel | production READY; one preview hit the documented `next/font/google` flake and passed on retrigger |
| Row #3 scorer | 125/152, run to completion twice |
| **Pack scorecard** | **NOT RUN — see below** |

**The pack scorecard was not run on either project.** It requires `--packs=<extracted dir>` — the six
`QuotesDone_*_v2026.07.31.zip` files from `~/Downloads` extracted to a directory — and that directory
is not in this working tree. It fails fast with `--ref and --packs are required`. The last recorded
values were INGESTED 100%, IN USE 37/37, RETRIEVABLE 46.6%. **I am not claiming those still hold.**

---

## 7. STATE AT HAND-OVER

```
clock                 2026-08-11 ~21:40 UTC (Dubai 01:40 on the 12th)
main                  b597716 · 8 PRs merged this session
Row #3                125/152 (verdict list committed for the first time)
gates                 23/23 on BOTH projects
parity                BOTH PROJECTS IN SYNC (420 tables, 852 functions, 56 anon-exec SECDEF)
advisors              0 ERROR
company_goals         63 · 20 measurable (was 8)
department_objective  66 · 20 measurable, 20 measured, 0 failed (was 0 measurable)
employee_kpi          124 · 94 measurable · 74 with a stored actual · history table live
org_tasks             840 · 143 with an owning employee (was 0) · newest is 1309, the spend finding
org_agents            93 active · 0 without responsibilities (was 14)
scenario_library      32 · all 16 of spec #7's named failures now covered
workflow              19 · 2 founder gates, both on money
demand side           customers 0 · inquiries 0 · quotes 0 · transactions 0 — unchanged, and the
                      new goal measures now say so out loud instead of being silent
```

New routines, all on cron, all revoked from PUBLIC: `fn_dept_objective_measure` (03:25 daily) ·
`fn_employee_kpi_measure` (03:30 daily) · `fn_goal_decompose` (03:10 Mon) ·
`fn_spend_concentration_check` (03:40 Mon) · plus `fn_employee_scorecard`, `fn_employee_kpi_trend`,
`fn_cost_per_os`, `fn_employee_responsibilities_backfill`.

`scripts/qsql.mjs` gained `--ref=` so staging can be read directly; it was production-only.
`scripts/checks/upload_kind_is_classified.test.mjs` reads its predicates out of the deployed source,
so editing the regex without updating the expectations fails the check.
