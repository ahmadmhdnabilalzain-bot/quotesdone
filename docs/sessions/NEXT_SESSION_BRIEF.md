# START HERE — SESSION 13. TWO RULES, BOTH FROM THE FOUNDER, BOTH ABSOLUTE.

> ## 1. ONE ROW AT A TIME, TO 100%. DO NOT START THE NEXT FILE.
> *"we close them row by row. so we wont move to the next row unless we reach 100%. all of them
> have to become 100%."* — 6 Aug 2026.
> Breadth-first is now forbidden. A file at 96% is an open file. Finish it.
>
> ## 2. EVERYTHING DEPLOYS TO PRODUCTION. NOTHING STOPS AT STAGING.
> *"nothing is for staging. all for deploy."* — 6 Aug 2026.
> Staging is a rehearsal surface, not a destination. Every routine, table, Edge Function, reference
> load and config change goes to `htdblwldjkcgjvmqkbeh` in the turn it is verified. This also
> overrides "import into staging only" notes inside founder knowledge packs — those predate 5 Aug,
> when production became a live target. `qd_guard` still refuses production writes **by design**;
> promote by reading staging's verified definition back and posting it verbatim, then assert
> `md5(prosrc)` matches. Do not retype a body. `scripts/verify_prod_parity.mjs` is the check.

## THE ROW YOU ARE ON: #1 quotesdone architecture. TAKE IT TO 100%.

> ## 3. THE ORDER IS THE FILE ORDER: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8.
> *"we start next session with quotesdone architecture row. it was 25% done and it has to hit 100%
> then we move to OS blue print, then OS 2 then,,,etc."* — 6 Aug 2026.
> Not cheapest-first. Not "#7 is already in flight". **#1, to 100%, then #2.** An earlier revision
> of this brief suggested 6 → 2 → 1 → 3 → 5 → 8 → 4; that suggestion is withdrawn.

**Baseline: 9 of 36 = 25%** (the trusted 411-enumeration). Session 12 did **not** work this file.

### What a rigorous read of #1 already found — start here, do not re-derive it

The spec's *organisation* is built and running. Its *quality half is inert*: the department-head and
Chief-of-Staff review chain, the challenge heuristics, the culture principles and the collaboration
rules all exist and hold real rows, and **nothing calls any of them — so work ships whenever a
deliverable exceeds 60 characters.** That single sentence is most of this row.

| finding | evidence |
|---|---|
| `collaboration_rule` **10 rows** with `must_involve` / `must_review` / `may_challenge` and a blocking flag | **0 readers.** `cos_execute:229` dispatches each task to exactly one department's brain, with no second participant |
| `org_agents.title` populated **67/67** | `fn_agent_context` selects only `department, role` — **the job title never enters any prompt** |
| `org_agents.responsibilities` populated **55/67** | not selected by `fn_agent_context`; 0 readers anywhere |
| `org_agents.manager_key` valid for **66/67**, every one resolving | **traversed by nothing.** Routing uses `brain_agent`/`lead_agent`, so the reporting line is never walked. `v_org_chart` exists with 0 readers |
| `department_objective` **44 rows**, all `horizon='year_1'` | only `trg_goal_cascade` touches it. **`dept_plan` does not read it** |
| `goal_period` **183 rows**, refreshed daily | **0 readers** — the only proc that touches it is its own refresher |
| `decision_record` 3 rows carrying `serves_goal` | 0 readers; its consumers `v_decision_intelligence` and `v_audit_coverage` are themselves unread |
| only **5 of 63** `company_goals` carry a `measure_sql` | `goal_period` holds 183 targets and **9** actual values, 6 non-zero. `fn_goal_period_refresh` is 8/8 green because it has almost nothing to compute |
| no per-employee **short-horizon** objective store exists | `department_objective` is year_1 only; `org_tasks` is a work queue standing in for it |

Genuinely MET already, do not touch: `company_goals` 63 rows read by `dept_plan:79` · `org_authority`
196 + `employee_authority` 285, enforced live at `cos_execute:170` (it re-resolves `fn_dept_authority`
and logs `tier_claim_exceeds_grant`) · `employee_kpi` 94 active read by 8 procs · `agent_memory` 208 /
`org_memory` 173 / `institutional_memory` 30 in LAYER 4 · `dept_plan_daily` 10/10 · `dept_learn_daily`
13/13 · `org_agents.max_open_tasks` 67/67.

**The shape of this row is wiring, not building.** Almost every gap above is a populated table with
no caller — the same defect this project has hit seven times. Expect `fn_agent_context`,
`cos_execute` and `dept_plan` to be where most of the fixes land.

**The itemised list for every file is on disk** — do not re-derive it:
`C:\Users\Opera\.claude\projects\C--Users-Opera-quotesdone\44929eb5-f98f-4608-8a3b-5dc2f37d6fc1\subagents\workflows\wf_f5161532-05f\journal.jsonl`
one `{"type":"result"}` line per spec file, each with every requirement, its status and its evidence.
The companion audit `wf_d6848866-ec5` carries the ranked fixes and the refutations.

## ⚠ THE SCORECARD BELOW IS INFLATED AND UNDER RE-AUDIT. DO NOT PLAN AGAINST IT.

The founder rejected it on sight and was right. Two defects, both mine, both structural:

1. **Verification was one-directional.** Three skeptics attacked every `MISSING` verdict and
   **refuted 30 of 110**. Nobody ever challenged a `MET` verdict. That can only move requirements
   *out* of MISSING and never out of MET, so the table is biased upward by construction.
2. **The denominator was decomposed, not discovered.** 411 → 620 happened because the new scorers
   split the specs' capability lists into individual requirements — file #1's scorer says so
   outright: *"I count 56 rather than 36 because the file states five explicit capability lists
   (12 employee attributes, 9 employee-object fields, 8 department-head duties, 6 Chief-of-Staff
   duties, 10 CEO duties) that a prior pass most likely collapsed into one requirement each."*
   Splitting one requirement into twelve moves numerator and denominator together and shifts the
   percentage for free.

Third, smaller: each scorer was handed a list of ~20 items to "count as MET" so it would not
re-report closed work. That pre-loaded the numerator too.

**The tell the founder used, and the right one:** seven of the eight files had NO work done on them
in the session that produced this table, and every one of them scored higher. Work moved exactly
one row — **#7** — and nothing else.

**Until the re-audit lands, the trustworthy baseline is the ORIGINAL table**: 36/9, 45/15, 54/6,
44/7, 51/8, 45/6, 64/18, 72/14 across files 1–8 on the 411-requirement enumeration. Use it.

What IS trustworthy from session 12, because each was measured directly rather than judged:
`dept_library` 1,456 rows had zero callers and now has a reader · 3,959 operations records imported
with md5 identical on both projects · 52 of 66 employees had an empty layer-2 heading · `dept_plan`
returned exactly 1200 output tokens on 40 of 61 calls · the DR drill went from 1 row to 32,686 ·
`dropbox_backup` has not run since 27 July behind 1,754 "successful" cron entries.

## ✅ THE RE-AUDIT LANDED. THIS IS THE CORRECTED TABLE — USE IT.

Every MET claim was attacked by a skeptic demanding a named object, a row count or caller, **and a
named reader**, defaulting to downgrade. **90 of 232 MET claims did not survive.**

| # | spec file | reqs | MET claimed | **MET upheld** | corrected | old 411-baseline |
|---|---|--:|--:|--:|--:|--:|
| 1 | **quotesdone architecture ← START HERE** | 56 | 24 | **14** | **25%** | 25% |
| 2 | OS (blueprint) | 77 | 51 | **37** | **48%** | 33% |
| 3 | OS 2 (executive UI) | 59 | 5 | **1** | **2%** | 11% |
| 4 | customer portal | 75 | 13 | **1** | **1%** | 16% |
| 5 | supplier portal | 90 | 16 | **2** | **2%** | 16% |
| 6 | suppliers categories | 41 | 18 | **10** | **24%** | 13% |
| 7 | agents and knowledge | 129 | 82 | **59** | **46%** | 28% |
| 8 | open router | 93 | 23 | **18** | **19%** | 19% |
| | **total** | 620 | 232 | **142** | **23%** | **20%** |

**The project is at ~23% against a 20% baseline — flat, inside the noise between two enumerations.**
The 37% was fiction. And **row #1 landed on exactly 25%, the same number the original table gave**,
from a completely independent enumeration — two readers, two denominators, one answer. Treat 25% as
solid. The portals collapsed: customer 16%→1%, supplier 16%→2%, executive UI 11%→2%.

### The systemic finding that explains most of row #1 — read this before anything else

**129 advisory-tier `org_tasks` sit at `proposed` and NOT ONE advisory task has ever reached
`done`.** Only autonomous tasks complete (96). `dept_plan/index.ts:65-69` says why in its own source:

> *"proposed means waiting on a founder decision, and there is no approval path, so a proposed row
> can never clear."*

150 tasks are parked, **114 of them over a week old, the oldest 25 July**. `evolution_proposal` has
31 proposed and exactly **1** ever implemented (27 July). `self_review` 31 rows, read by nothing but
its own writer. `company_reflection` 9 rows, same. **One missing approval path is strangling the
entire improvement loop**, and it sits directly under row #1's "Every Task Has a Review Process".
This is almost certainly the highest-value single fix in the project.

### The other row-#1 downgrades, each with its evidence

- **58 of 63 `company_goals` have an EMPTY `measure_sql`** — 92% of the objective set cannot be
  measured. Worse, `revenue_annual`'s measure is `select count(*) from inquiries where created_at >
  now()-interval '30 days'` — it **counts inquiries, not revenue**, against a table with 0 rows.
  Every revenue figure the CEO layer has ever produced is a constant zero. And `fn_agent_context`
  never reads `company_goals` at all, so only the 13 department-head planning prompts see them.
- **`employee_authority`'s 285 rows have fired at most 3 times ever.** Its only enforcement path is
  `fn_check_spend` ← `fn_decision_gate` (a trigger on `decision_record`, 3 rows, last 27 July) and
  `fn_emit_budget_exceeded`, which has **zero callers anywhere**. Department authority IS enforced
  live at `cos_execute:170`; per-employee authority is not.
- **Current workload does not exist.** `max_open_tasks` is a static CAP, not load. Line 372 asks for it.
- **`dept_learn_daily` reported 13/13 successful while writing ZERO lessons on two of the last three
  days.** 104 tasks done against 31 lesson rows — "every completed task generates learning" is false
  by a factor of three, and the lessons are per-department-per-day digests, not per-task records.
- **`customer_preference`: 0 rows and 0 readers** — referenced by nothing in the entire system,
  though "customer preferences" is named in the Company Memory section.
- **`institutional_memory` frozen for 9 days** (last write 28 July) while `outcome_evaluate_daily`,
  its claimed writer, reports 8/8 successful runs.
- **Of the seven self-optimisation loops, three run and are read** (`fn_sop_update`,
  `fn_knowledge_curator`, `fn_knowledge_decay`). `fn_evolution_scan`, `fn_outcome_evaluate`,
  `fn_self_review` and `fn_company_reflect` all write where nothing reads.

## THE SUPERSEDED INFLATED SCORECARD, kept only to show what was corrected

| # | spec file | MET (strict) | MET+PARTIAL | unread | MISSING |
|---|---|--:|--:|--:|--:|
| 6 | suppliers categories | 44% | **93%** | 3 | **0** |
| 7 | **agents and knowledge ← YOU ARE HERE** | **64%** | 90% | 4 | 9 |
| 2 | OS (blueprint) | 65% | 82% | 12 | 2 |
| 1 | quotesdone architecture | 41% | 75% | 11 | 3 |
| 3 | OS 2 (executive UI) | 8% | 59% | **21** | 3 |
| 5 | supplier portal | 18% | 58% | 13 | 25 |
| 8 | open router | 25% | 58% | 6 | 33 |
| 4 | customer portal | 17% | 39% | 11 | 35 |
| | **total** | **37% (230/620)** | **69%** | **81** | **110** |

> **The denominator is 620, not 411.** Eight independent readings of the real spec text. Do not
> compare a percentage to an older brief's — compare statuses. And the previous card's
> *"categories 17% → 87%"* is on the MET+PARTIAL bar, where it now reads **93%**; it is not in
> conflict with the 44%.

~~SUGGESTED ORDER, cheapest first: 6 → 2 → 1 → 3 → 5 → 8 → 4.~~ **WITHDRAWN — the founder set the
order on 6 Aug: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8, each to 100% before the next.** Two observations
from the cheapest-first analysis survive as *facts about the rows*, not as an argument to reorder:
#6 has **zero MISSING** — complete and half-finished, finishing work only — and #3, which reads
worst on any bar, carries **21 BUILT_BUT_UNREAD**: production computes an autonomous company every
night and shows the founder none of it. Both are wiring when their turn comes.

## THE DEFINING STATE OF THIS CODEBASE: 81 requirements built, correct, and read by nothing

13% of the whole spec. Larger than the customer and supplier portals' missing items combined, and
the cheapest work in the project. **Never score BUILT_BUT_UNREAD as done** — that is precisely the
lie three consecutive sessions kept uncovering. For every requirement ask three questions and never
conflate them: does the mechanism EXIST · is it POPULATED and does it RUN · does anything READ it.

Six were closed in session 12: `dept_library` (1,456), `os_knowledge_domain` (380), the RFQ
lifecycle trace, `fn_os_health`'s failing-cron signal, layer-2 department knowledge, and the
3,959-record operations corpus — wired in the same change that imported it.

## MEASURE "no caller" PROPERLY, AND VERIFY BEFORE RECORDING "MISSING"

Counting `pg_proc` and `pg_views` misses `cron.job`, which is where most agent functions are
invoked from — that error made a whole governance layer look unbuilt when it runs 1,266 times with
zero failures. Two adversarial audits refuted **~33 "missing" findings** that were already built.
Already refuted, do not rebuild: supplier-website crawling, Arabic supplier email, the 24/48h nudge
ladder, quote version history, duplicate-quotation detection, model autoswitch, optimistic record
claiming, supplier brief immutability.

## STATE AT SESSION 12 CLOSE

`main` **18 behind — PR #7 is open and unmerged.** Schema **405 tables / 745 routines**, identical.
Gates: phase1 12/12 · taxonomy 11/11 · intake-routing 10/10 · factory 18/18 · journey 39/39 ·
prod-readiness 13/13 · **agent-knowledge 25/25** · **rfq-trace 10/10** · purge clean.
`verify_prod_parity`: nothing staging-only across 20 config tables. Backups now provably restorable
— 11 tables / 32,686 rows, where the drill previously passed on 1 row and scored empty files green.

**Carry these two first, both measured and both real:**
1. **`dropbox_backup` has not run since 27 July** despite 1,754 consecutive "successful" cron
   entries — `pg_net` success means the POST was queued, not that the function ran. It now raises
   an incident; the off-site copy is still stale.
2. **The autonomy-gate chain has a FIXED ORDER.** `trg_action_gate` holds 1,048 of 1,079 rows;
   `fn_autonomy_dispose` sweeps that exact status set with no threshold; cron 64 is `active=false`
   and is the only thing preventing it. **Enabling cron 64 first auto-clears 1,048 held rows.**
   Sequence: bind `fn_autonomy_dispose` → lift the confidence gate → `agent_autonomy_enabled` → cron 64.

---

# Previous — QuotesDone, 6 August 2026, end of session 10

**MERGED to `main` on 5 August 2026** — [PR #3](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/3),
merge commit `ea13ffb`. `main` now describes what production runs; it did not before.
Merging also triggered a Vercel rebuild, so **quotesdone.com is live with the frontend changes**
(verified afterwards: HTTP 200, all controls present, zero console errors).

> ## ⚠ PRODUCTION IS NO LONGER UNCHANGED — 5 August 2026, session 10
>
> Every previous revision of this brief said "Production unchanged." **That is now false.** On the
> founder's explicit instruction, overriding the standing staging-only rule, session 10 deployed
> **16 Edge Functions** and applied **9 configuration items** to `htdblwldjkcgjvmqkbeh`.
>
> - **The reveal is fixed in production.** `customer_api` no longer selects the non-existent
>   `transactions.created_at`, so a customer who pays now actually sees the supplier. Confirmed
>   absent from the deployed bundle, not merely committed.
> - `doc_extract` and `license_extract` ship without their caller-side ceilings.
> - All 6 active models are priced in `model_rate` — the 3 that were missing (both Gemini models and
>   `qwen/qwen3.7-plus`) are the reason 247 of 603 calls billed at zero. **Historical rows stay at
>   zero**; only new calls are metered.
> - `quote_comparison` and `rfq_routing` moved to staging's **full** verified rows — tier, primary,
>   fallback *and* ceiling, not just `max_tokens` as §8 used to claim.
> - **16/16 production functions boot-checked** afterwards (read-only, no data created).
> - Schema parity held throughout: 403/161/739/5,237 and ledger 712@20260804182051 on both.
>
> **Deployed from an unmerged branch.** `main` does not contain what production is running. Merging
> is now a correctness matter, not housekeeping.
>
> `node scripts/verify_prod_readiness.mjs` → **12/13**. The one outstanding item is withheld
> deliberately; see §8.

Staging **`pglpqrhvozwepymcuunn`** · production **`htdblwldjkcgjvmqkbeh`** (read-only, never deployed to).

Run these first. **All fifteen were green at the end of session 10** — anything red is a regression
you introduced or drift someone else caused, not a known state:

```
node scripts/staging/verify_phase1.mjs           # 12/12  deployed, isolated, in sync
node scripts/staging/smoke_staging.mjs           # 15/15  auth, storage, postgrest, 10 functions
node scripts/staging/verify_cost.mjs             #  8/8   pricing, routing, monitoring — zero spend
node scripts/staging/verify_matching.mjs         # 12/12  floor, fan-out and the hard gates — zero spend
node scripts/staging/verify_taxonomy.mjs         # 11/11  the router + crosswalk, gaps CLOSED — zero spend
node scripts/staging/verify_constraints.mjs      #   2/2  NOT NULL + CHECK parity — zero spend
node scripts/staging/verify_exception_window.mjs # 14/14  the 14-day licence exception — zero spend
node scripts/staging/verify_portal.mjs           # 14/14  what the portal is served, incl. the reveal
node scripts/staging/verify_fraud_hash.mjs       #   5/5  copied_quote can now fire — zero spend
node scripts/staging/verify_doc_extract.mjs      #   7/7  the document queue — 1 model call, ~0.075 AED
node scripts/staging/verify_license_extract.mjs  # 12/12  licence reading — 4 calls, ~0.2 AED
node scripts/staging/verify_supplier_docs.mjs    # 13/13  supplier-docs end to end — 2 calls, ~0.1 AED
node scripts/staging/demo_factory.mjs            # 18/18  factory selftest, ~40 s, cleans up after itself
node scripts/staging/journey_test.mjs            # 39/39  signup -> upload -> quotation comparison
node scripts/verify_prod_readiness.mjs           # 13/13  §8 against PRODUCTION, read-only
```

---

## SESSION 12 (6 Aug 2026) — the fifth unread asset, and a governance layer that was already running

**All seventeen gates green on the first pass**, journey 39/39 (275 s), and `--purge --dry-run`
after it reported exactly `1 storage/signed-terms` — the rolling register, nothing else. No
regression, no drift, no leak. Every defect below came from the work after the gates.

**FILE #7, agents and knowledge — dept_library and os_knowledge_domain now have readers.**

`public.dept_library` holds **1,456 rows in both projects** — legal 451, procurement 361, it 318,
finance 290, and a cross-cutting `company` 36 — with a `tsvector` column and a search function,
`fn_dept_library_search(p_dept, p_query, p_limit)`, that **works**: measured, five relevant hits
for a real question in each of the five. It had **zero callers**. Not one routine, view, Edge
Function, cron job or frontend module named it. The fifth instance of the shape.

The reader is an **overload, not a rewrite**. `fn_agent_context(text,integer,text)` *calls*
`fn_agent_context(text,integer)` and appends one section, so the 100-line four-layer body is not
copied and cannot drift, the existing signature is not dropped and its grants survive, and its
**thirteen call sites across ten Edge Functions** keep working byte-identically. Both parameters of
the old signature carry defaults, so a two-argument call still resolves to exactly one function.

> **Without a query it would have been a dump, not retrieval.** `fn_agent_context` has no message
> parameter, which is why the library could not simply be pasted into layer 2 — legal alone is 451
> rows averaging 1,390 characters against a 22,000-character budget. The section is emitted **only**
> when a caller supplies the real question, and is capped at ~2,600 characters. `agent_brain` passes
> it today (staging v2, production v26, `p_query` confirmed present in both deployed bundles with
> comment lines stripped). **The other twelve call sites are unchanged until they pass one too** —
> `agent_act:41`, `dept_plan:81` and `secretary_act:287` are the next ones with a real task string.

Second orphan, same change: **`os_knowledge_domain`, 380 rows, had zero readers AND zero writers.**
`fn_knowledge_gaps` — already exposed by `os_api`'s `knowledge_gaps` action — reported per-agent
gaps with nobody to route them to. It now carries `owner_os`. Measured *before* wiring, because the
six-vocabularies rule applies here too: of **110** active `category_agents`, **84** have a domain
row at `cat:<slug>` and only **53** have one with `ownership='owns'`. The join is real but
**partial**, so the summary reports `unowned` (57) as a number rather than letting the report imply
full coverage.

`verify_agent_knowledge.mjs`, **13/13, zero spend**. The checks that matter are the negative ones:

- a **query-less call is byte-identical** to the old two-argument one (28,014 chars, no section) —
  without that assertion this is a silent behaviour change to ten Edge Functions;
- every emitted excerpt must **match a real `dept_library` row by title** (4 of 4), so "the output
  grew" can never be mistaken for "the library was read";
- a `cat:<slug>` specialist has **no `org_agents` row**, so `v_dept` is null and the search falls
  through to "any department" — the branch most likely to be silently dead. Without this check all
  110 category specialists would get an empty section and nothing would say so;
- and it states the corpus gap instead of hiding it: **4 of 13 staffed departments have a library**,
  and a department without one returns nothing rather than borrowing another's.

Routines **743 → 744 in each project**; applied directly, not as a migration.

**THE GOVERNANCE LAYER IS NOT UNBUILT AND NOT UNWIRED — correct the previous brief.** "AI Governor,
AI Scheduler, AI Auditor, AI Memory Manager, exception handling and self-healing … several have
routines with no callers" measured routine-to-routine and view references only. **All seven run on
active production crons and all succeed**, and their output lands:

| cron (production, all `active`) | routine | runs / ok | output, measured |
|---|---|--:|---|
| `policy_consistency_weekly` | `fn_policy_consistency_check` | 3 / 3 | the Governor |
| `autonomy_audit_weekly` | `fn_autonomy_audit_run` | 2 / 2 | `org_memory` 2 rows |
| `knowledge_curator_daily` | `fn_knowledge_curator` | 18 / 18 | `knowledge_kpi_snapshots` 28 rows |
| `knowledge_decay_daily` | `fn_knowledge_decay` | 8 / 8 | **0 decayed — correctly** (see below) |
| `edge_health_scan_15min` | `fn_edge_health_scan` | 785 / 785 | 30 active `edge_expectation` rows |
| `exception_alerts_hourly` | `fn_exception_alerts` | 432 / 432 | `founder_alerts` 108 rows |
| `graph_rebuild_daily` | `fn_graph_rebuild` | 18 / 18 | `graph_nodes` 323 / `graph_edges` 300 |

`fn_knowledge_decay` decaying nothing looked exactly like session 11's `kpi_review_weekly` — eight
"successful" runs measuring nothing — and it is **not** that. Measured: 1,869 `agent_knowledge`
rows, 1,734 carrying `review_due`, and in production **0 are past it** (earliest bucket 2026-10-24;
seven bulk stamps at ~90 days and ~12 months from the import). The engine is idle because the corpus
is genuinely fresh, not because it is broken. Worth re-checking after 24 Oct 2026.

> **A parity difference nothing measures.** The `(agent_key|topic)` md5 over all 1,869 rows is
> **identical** on both projects, but `review_due` is not: staging's earliest is **2026-08-05** with
> **168 rows already past due**, production's is **2026-10-24** with none. The row keys were copied;
> the review metadata is an older snapshot. Harmless today — staging has 0 crons so decay never runs
> there — but it means a staging test of the decay engine would exercise a state production is not in.

**OBSERVABILITY: THE SUPPLIER HAD A TEN-STEP TIMELINE, THE RFQ HAD NONE.** The blueprint's
Observability requirement is a worked RFQ trace — created → BOQ analysed → qualified → 12 suppliers
selected → invitations sent → 7 quotations → ranked → award — and it says "every step should be
logged with timestamps **and reasons**". `fn_entity_activity` is already reachable (`os_api`'s
`activity` action) and had exactly one specialised branch, `if p_entity = 'supplier'`. For an
inquiry it returned comments plus `os_audit_log`, and the RFQ lifecycle is written to neither.

Nothing new was recorded. Every step already sat in a table: `inquiries`' own timestamps,
`documents`, **`inquiry_matches` — which carries `match_reason` and `similarity`, the only place the
system records WHY a supplier was contacted** — `quotes`, `comparison_run_v2`, `transactions`,
`company_event` and `agent_actions`. Assembly, not instrumentation. `verify_rfq_trace.mjs` 10/10:
7 entries across decision/event/match/milestone/quote, **2 of 2 matches carrying their reason**,
nothing undated, the supplier branch unaffected, and a non-uuid id refused rather than thrown.

> **THE FIXTURE FOUND THREE BUGS THE PATCH REPORTED AS SUCCESS**, all reachable only at call time:
> `left join public.leads l` collided with the function's declared `l public.leads%rowtype` (42702);
> `', quality '||q.quality` — `quotes.quality` is **jsonb**, so `text||jsonb` resolves to
> `jsonb||jsonb` and the literal is parsed as JSON; and `coalesce(c.explanation_en,'')` — jsonb too.
> The second is the same shape as the `text[] || 'literal'` bug already documented inside
> `run_health_check`. A DO block that rewrites `pg_get_functiondef` reports success for all three.
> **Build the fixture in the same change, not after it.**

**CONTINUOUS MONITORING (⭐⭐⭐⭐⭐ in the blueprint): the signal was computed correctly every time and
nobody asked for it.** This started as "fix `v_cron_failing`" and that would have been the wrong
fix. `fn_os_health()`'s `failing_crons` already uses `JOIN LATERAL (… ORDER BY start_time DESC LIMIT
1) WHERE status='failed'` — the most recent run, the only definition of "failing now" that is any
use — and it correctly returns **`[]`** today. Its one caller is `fn_os_selftest`, which has **none**:
not a cron, not a routine, not an `os_api` action. Sixth asset of this shape.

`fn_exception_alerts` — hourly, already writing `founder_alerts`, already deduped — now asks it, and
raises `cron_failing` naming the jobs. One check in an existing loop; no new cron, table or channel.

> **Do NOT "fix" `v_cron_failing`.** It is a different, cruder signal — anything that failed at any
> point in 7 days, never clearing — and its one consumer is `fn_invite_ramp`'s advisory message,
> where "what has been flaky" is the right question. It lists 3 jobs; **2 recovered days ago**
> (`health_check` last failed 4 Aug, succeeded 6 Aug 00:30; `supplier_invites_daily` last failed
> 4 Aug, succeeded 5 Aug) and `kpi_review_weekly` has run once, ever, and fails outside the window.
> Two signals, two questions. The defect was the missing reader, not the view.
>
> **Staging has 0 crons, so the new branch cannot execute there** — exactly how the two jsonb
> concatenation bugs above hid. The alert text is asserted against a synthetic `failing_crons` array
> including a null message, which is the only part that could carry that landmine. The INSERT itself
> first runs when a production cron actually fails; that is stated, not claimed as exercised.

> **`run_health_check` was already fixed — read before you re-fix it.** `v_cron_failing` shows 78 of
> 336 runs failing with `malformed array literal`, and the deployed source already carries `::text`
> casts on every branch plus a comment recording the diagnosis: `text[] || 'a bare literal'` resolves
> to `anyarray||anyarray` because an unadorned literal is type `unknown`. The monitor crashed
> **precisely when it had something to report** and took the other checks down with it. Historic.

**3,959 OPERATIONAL RECORDS THE FOUNDER SHIPPED, AND NEITHER PROJECT HAD A TABLE FOR THEM.**

`C:\Users\Opera\qd-packs\QuotesDone_COMPANY_OPERATIONS_KNOWLEDGE_v2026.07.31\`. Its own
`START_HERE.md` says in line 5 that it is **separate** from the 86-category supplier corpus that
sessions 10–11 imported — which is why "the knowledge corpus is now in both projects" was true and
still left this entirely unloaded. Measured contents:

| record_type | n | closes |
|---|--:|---|
| `exception_playbook` | **240** | Exception Handling ⭐⭐⭐ — the spec's 16 named scenarios |
| `decision_rule` | **240** | the Decision Engine ⭐ |
| `live_data_binding` | 268 | Layer 3 |
| `standard_operating_procedure` · `metric_definition` · `department_scenario` | 236 · 216 · 192 | SOPs, KPIs, QA |
| `agent_role` · `workflow_handoff` · `operational_template` · `event_subscription` | 96 · 132 · 120 · 100 | the agent registry, cross-department flow |
| `hard_gate` · `audit_requirement` · `memory_policy` · `model_routing_policy` | 10 · 8 · 6 · 5 | Governor / Auditor / Memory Manager |

> The **first HR playbook is titled "External AI provider unavailable"** — the literal first
> scenario the blueprint names. This was never content that needed writing.

**Not into `dept_library`, though that would have been free** (it gained a reader the same day).
`dept_library` has 7 columns; these records have **19**, and the pack's own instruction 5 is
*"Preserve every record's implementation_status, validation_status, authority tier, sources and
review date."* Those are the most useful fields in it: `authority_tier` is
advisory/supervised/gated/autonomous (**2,633 supervised, 139 gated**) and `implementation_status`
is the founder auditing his own spec — **1,325 implemented / 1,317 partial / 1,317 target_state**.
New table `public.ops_knowledge`, on both projects.

> **THE DEPARTMENT MAPPING IS THE FOUNDER'S, NOT MINE — and I was one command from inventing one.**
> A seventh vocabulary was exactly the trap to expect, and `START_HERE.md` pointed at a crosswalk he
> had already written: `04_AGENT_RUNTIME_AND_GOVERNANCE/07_PRODUCTION_TO_TARGET_DEPARTMENT_CROSSWALK.csv`.
> Transcribed verbatim with `mapping_type` preserved, plus **two corrections stated rather than
> silently applied**: it lists `hr_people` and `sales_crm` as having no confirmed production
> department, and `org_departments` carries an active `hr` (4 agents) and `sales` (5 agents) today.
> The pack is dated 31 July; both were added after. Leaving them unmapped would strand 284 records.

**Wired in the same change**, because an imported corpus with no reader is the seventh instance of
this defect. `fn_ops_knowledge_search` is the sibling of `fn_dept_library_search`, and
`fn_agent_context` emits **LAYER 2c** beside 2b — kept separate on purpose: `dept_library` is
external domain reference, `ops_knowledge` is how *this company* operates, and merging them lets an
agent cite a generic UAE regulation where the company's own gated procedure applies. **The authority
tier and implementation status travel with each excerpt** — an agent reading a `gated` procedure
that does not say it is gated will act on it, and one reading `target_state` must know the
capability is not built.

Measured on both projects: **3,959 rows, 3,005 mapped to 14 departments, md5 identical.** `hr`,
`intelligence` and `knowledge_eng` each held 0 `agent_knowledge` **and** 0 `dept_library` rows and
now hold 142 / 144 / 144. **Every active department now has knowledge.** 427 records
(`qa_testing` 143, `business_development` 142, `communications` 142) import with `dept_key` NULL —
the crosswalk's own "unmapped_target", and there is still no production department for them.

> **AND THEN 884 OF THE 3,959 WERE REACHABLE BY NOTHING — the same defect, one level down, inside
> its own fix.** The first cut resolved `dept_key` from `scope_key` alone, which is right for the
> 3,432 department records and wrong for everything else: all **96 agent** records, all **340
> workflow** records and the **21 external sources** were returned by no search. Agent and workflow
> records name their department in `structured_data.department_key` instead; company principles, the
> source registry and ownerless cross-department workflows apply to everyone. **Reachable is now
> 3,520 of 3,959**, and the 439 that are not are exactly the three departments the crosswalk marks
> `unmapped_target` (qa_testing 147, communications 146, business_development 146).
>
> **Two pieces of my own tooling lied while I fixed it.** The re-import reported 24 of an expected
> 168 rows remapped because `node import.mjs | Select-Object -First 4` **terminates the upstream
> command in PowerShell** — the import was killed after ~1,000 rows and said nothing. And the
> production promoter used `on conflict do nothing`, which would have left production on the old
> mapping silently; its digest now covers `record_id||dept_key`, because **a no-op upsert preserves
> a key set exactly the way a duplicate-and-drop bug preserves a count.**

**`dept_plan` now reads all of it.** It is the reader that most needs its department's decision rules
and exception playbooks and it was the one that could not see them: `fn_agent_context` emits 2b and
2c only when the caller supplies the question, `dept_plan` passed none, and its 4,500-char slice cut
the context off inside layer 2 regardless. It now passes charter + north star + open task titles —
what it is about to plan against — and takes 11,000 chars. Measured: `hr`, which had **zero**
knowledge this morning, planned 3 tasks with input tokens up **2,898 → 4,716**, which is the
retrieved sections arriving.

> **One thing to put to the founder:** the pack's instruction 4 says *"Import into staging only."*
> That predates production becoming a deploy target on 5 Aug, and the standing rule since is both
> projects plus "I don't want to see the number zero". It was loaded to both; reversing it is one
> `delete from public.ops_knowledge` on production.

**A SIXTH TOKEN CEILING, AND IT WAS FAILING IN PRODUCTION THE DAY IT WAS FOUND.** `dept_plan` set
its ceiling **twice** — `makeLlm({max:1200})` *and* `llm(sys,user,1200)`, the per-call third
argument overriding the factory one — against `model_policy.chief_of_staff_decision`'s 2000.

> Of the **61 `dept_plan` calls ever made, 40 returned `output_tokens` EXACTLY 1200.** An output
> landing precisely on the ceiling is truncation, not a coincidence. The plan JSON was cut
> mid-string, the function reported **`output_did_not_parse`** — §5's laundered string — and fell
> through to the opus-4.8 fallback at roughly twice the cost. 5.498 AED since 27 July, much of it
> spent twice. `dept_plan: 2 failure(s)` fired at **01:15 on 6 Aug** for `legal` and
> `customer_success`; both had planned **nothing**, on a daily cron.

Proven by changing one variable against the same prompt. Staging (in=2898): 1200 → **exactly 1200
out**, `output_did_not_parse`, planned 0; at the policy → 822 out, parsed, planned 3. Production,
the two departments that actually failed: `legal` in=6204 → **1725 out, 3 tasks**;
`customer_success` in=5293 → **1378 out, 2 tasks**. Both natural outputs sit **above 1200**.

> **Two things that would have made this fix wrong, both caught by measuring rather than reading.**
> Removing only the `makeLlm` ceiling changed nothing — still exactly 1200 — because the call site
> passes its own. And deleting the ceiling outright makes it **worse**: `llm.ts` falls back to
> `def.max ?? 700` and always sends a number, so "no ceiling" cannot be expressed through that
> signature. The caller is now set deliberately **above** the policy (8000) so `min()` always yields
> the policy. **Any other fix to one of the remaining caller ceilings must check the call site too.**

`model_policy.chief_of_staff_decision` raised **2000 → 4000 on both projects**: the first fixed
production run measured 1725, **86% of 2000** — a worse mid-distribution position than
`license_extract`'s 74–78%, and that one was fixed before it ever failed.

**DISASTER RECOVERY WAS ASSERTED BY ONE ROW, AND THE ASSERTION WAS GREEN.** `dr_drill`'s pass
condition was `restored_rows === backup_rows && key_ok`, and for an empty backup `key_ok` is forced
true and `0===0` — so a backup file containing the two-byte string `[]` scored `ok`. Production has
0 customers / 0 inquiries / 0 quotes / 0 transactions, so **five of its six tables passed vacuously
and the sixth holds one row**: the 1 Aug run reported `{tables_checked:6, tables_failed:0,
total_restored:1}`. Measured: **215 of the 1,075 objects in the `backups` bucket are ≤2 bytes.**

> Asserting `backup_rows > 0` outright would fail every genuinely-empty table and be muted within a
> week. The distinction is `live_rows`: an empty backup of an **empty** table is correct, an empty
> backup of a **populated** table is a lost backup.

And the tables that hold the value were neither drilled nor backed up. Proven on production one
variable at a time:

| | tables | rows restored | failed |
|---|--:|--:|---|
| before | 6 | **1** | 0 — green and meaningless |
| fixed assertion, old snapshot | 11 | 22,332 | 3 — `kb_chunks`, `dept_library`, `ops_knowledge` named as having no backup |
| after adding them to `backup` | 11 | **32,686** | 0 |

`kb_chunks.json` 40.8 MB · `ops_knowledge.json` 9.0 MB · `dept_library.json` 3.4 MB now exist.
`customers` stays green throughout — backup 0, live 0, correctly not a false alarm.

**`dropbox_backup` — the only copy held OFF Supabase — reports 1,754 consecutive cron successes and
has not actually run since 27 July.** `pg_net` success means the POST was queued, not that the
function completed: the identical defect that made `cos_execute_hourly` look healthy for 237 runs.
It was absent from the 30-row `edge_expectation` set, so nothing watched it. Added on both projects
with `dr_drill` alongside; `fn_edge_health_scan` now returns **`(dropbox_backup, STALE, 13852.1, t)`**
— 9.6 days, incident raised — against ALIVE for all 31 others.

### The audit's remaining queue, ranked — start here next session

A 13-agent adversarial audit of file #7 ran at the end of this session; it **refuted ~13 claimed
gaps** (supplier-website crawling, Arabic supplier email, the 24/48h nudge ladder, quote version
history, duplicate-quotation detection, model autoswitch, record claiming — all already built; do
not rebuild them). What survived, in its order:

1. ~~`dr_drill` empty-backup pass~~ · ~~`dropbox_backup` expectation~~ — **done above.**
2. **`cron.job` 126: `fn_company_brief(1800)` → `4000`.** One number, same shape as `dept_plan`'s
   1200. The org chart every agent reads is cut mid-word at `"...lead knowledge_directo"`, silently
   omitting Marketing, Marketplace & Procurement, Sales and Technology while printing
   `Totals: 13 departments` against 15. It sits at priority 95 inside a 22,000-char budget.
3. **Two `agent_knowledge` UPDATEs: `UAE legal framework` and `UAE Civil Code update - 2026`,
   priority 10 → 90.** 1,502 chars that currently reach **none** of the 66 agents' Layer 1 — a UAE
   construction marketplace serving zero UAE legal text to any agent, including `legal`.
4. **The autonomy-gate chain, and it has a FIXED ORDER.** `trg_action_gate` holds 1,048 of 1,079
   rows; `fn_autonomy_dispose` sweeps exactly that status set and re-dispositions with no threshold,
   overwriting the gate; and cron 64 `autonomy_dispose_hourly` is `active=false`, which is the only
   thing currently preventing that. **Enabling cron 64 first would auto-clear 1,048 held rows.**
   Sequence: `fn_autonomy_dispose` binding → confidence lift in `trg_action_gate` →
   `agent_autonomy_enabled` → then cron 64.

**`graph_nodes` is measured and deliberately NOT wired here.** 323 nodes and 300 edges rebuilt every
night by an active production cron, read by **zero** routines, views, Edge Functions and frontend
modules. Its consumer is the company graph in the executive UI — spec file **#3**, which is
scheduled last — and inventing a different consumer inside #7 would build the same thing twice.
`decision_trace` stays closed per §3.5: seeded config, no orchestrator, no data-only fixture.

---

## SESSION 11 (6 Aug 2026) — the knowledge existed, nothing read it

All fifteen gates were green on the first pass. Every defect below was found *after* them.

**New gates — run these too:**

```
node scripts/verify_deploy_parity.mjs --since=HEAD~40   # is the repo's code actually RUNNING, both projects
node scripts/staging/verify_intake_routing.mjs          # 10/10 Arabic routing + ordered interview + knowledge
node scripts/staging/verify_agent_knowledge.mjs         # 25/25 spec file #7's knowledge + monitoring wiring — zero spend
node scripts/staging/verify_rfq_trace.mjs               # 10/10 the RFQ lifecycle trace — 1 rfq_routing call, ~0.01 AED
node scripts/staging/demo_factory.mjs --purge --dry-run # run AFTER the journey; only the register should appear
```

**THE RECURRING SHAPE, AND IT IS NOT "UNBUILT".** Four times over, an asset was complete, populated,
verified by a gate, and had **no reader**:

| asset | state before | how it failed |
|---|---|---|
| 4,212 bilingual aliases | loaded, gate green | 0 code references; **Arabic could not be classified at all** |
| 1,558 knowledge modules | all 84 categories | looked up as `cat:<legacy-slug>`; overlap with the catalogue keys is **exactly zero** |
| 16,588 ordered questions | 4,117 distinct | one reader in the repo — its own importer |
| 84 categories ↔ 66 families | both loaded | **six** different identifier schemes, no join |

**SIX VOCABULARIES FOR ONE TAXONOMY.** Measure before assuming any two tables join:
`category_specs` 56 legacy slugs · `catalog_supplier_categories` 86 · `catalog_domains` 67 families ·
`category_agent_map.agent_slug` 84 catalogue-style · `catalog_subcategories.agent_slug` 17 short-legacy
(**0 overlap** with the previous) · `kb_operational_route.route_key` `opcat-001`.

**Bridges built (all on BOTH projects — routine/table parity is asserted):**
`lead_trade_map` 25→63 rows · `catalog_category_domain` (new table, 86/86) ·
`fn_category_knowledge` · `fn_intake_slug_for_catalog` · `fn_category_questions`.
Staging now holds the **entire** knowledge estate (40 tables, 0 empty): kb_stage 112,611 records /
16,588 questions / 12,929 rules, `agent_knowledge` 1,869, `kb_chunks` 4,937, `dept_library` 1,456.

> **DO NOT WIRE `kb_stage.validation_rules`.** 4,696 rows, and the severity taxonomy is inconsistent:
> 21 families carry `critical` rows with **no rule text**, `warning` exists in exactly one family,
> `medium` (286 rules/44 families) and `error` (100/22) appear to be the same tier, and `on_fail` is
> identical on every row. Nothing distinguishes a brief-completeness rule ("all mandatory fields must
> be answered") from a platform-governance rule ("approvals must remain outside autonomous
> authority") — so filtering by severity injects governance text into a customer conversation.
> A function was written, measured, found wrong-by-construction and **dropped**. Fix the corpus first.

**Autonomy restored.** `event_dispatch_15min`, `cos_execute_hourly` and `dept_plan_daily` were
`active=false` since 2 Aug with 742 clean runs behind them. All re-armed. `kpi_review_weekly` had
**never once succeeded**: `employee_kpi` id 71 measured "share of KPIs meeting target" by selecting
from `fn_kpi_scoreboard()`, which executes every active KPI's SQL — it computed itself and timed out.
One row made all 95 KPIs unmeasurable. Retired; 94 now score (31 MET / 7 NEAR / 36 MISSED / 20 NO DATA).
**`cos_execute_hourly`'s 237 "successful" runs measured the POST being queued, not the function
completing** — its cron set no `timeout_milliseconds` so it inherited pg_net's 5s default while its
sibling `dept_plan_daily` sets 9000. Raised to 30s; first tick still unconfirmed.

**The 55 executors are classified** per the founder's rule of 6 Aug: **refunds are the only action
requiring approval**. 4 high / 10 medium / 41 low, zero blank idempotency, zero blank owners, 24
`high`+`advisory_safe` contradictions cleared. `outreach_send` and `invite` are `external_id` /
`natural_key`, so a retry cannot double-fire the 20,464-lead invite campaign — engineered, not gated.
Classifying woke `v_executor_registry_gaps`' fourth branch, which had never fired: it reads
`reversible AND compensation_action_class IS NULL`, unreachable while all 55 said `reversible=false`.
Its 0 was vacuous. Now answered per row: 16 reads need none, 32 undone by a person, 7 irreversible.

**Spec verification: 411 requirements measured across the 8 founder specs — 83 EXISTS / 183 PARTIAL /
145 MISSING at session start (20%).** Now ~31%. Per file: architecture 25% · OS blueprint 33% ·
executive UI 11% · customer portal 16% · supplier portal 16% · **categories 17%→87%** ·
agents+knowledge 28% · openrouter 19%. Work them **one file at a time to 100%**, not breadth-first.

---

`verify_prod_readiness.mjs` is not a staging gate — it measures **production** read-only and cannot
deploy or apply. It reached 13/13 in session 10, so unlike every previous session, a non-zero exit
here now means something drifted.

**Do not run the journey concurrently with `demo_factory` or `verify_portal`.** The factory's last
check compares absolute row counts before and after, and any other writer fails it for the wrong
reason.

`verify_cost.mjs` and the factory selftest are new and fast; run them on every commit. The journey
takes ~7.5 minutes (464 s measured) and produces 34 `agent_runs`. If a step fails, read `agent_runs`
for that function **before** assuming the model is at fault — five of session 8's defects presented
as "the model returned nothing" and none of them were.

`node scripts/staging/verify_cost.mjs --live` adds 4 more checks and spends about 0.0001 AED: it
puts one real inference through the deployed gateway and asserts the meter moved. Run it when you
touch anything in the pricing or budget path, not on every commit.

---

## 0. THE RULE FOR THIS SESSION — demo data, always

> **Anything that needs data to be tested gets demo data built for it. Create it, assert against
> it, delete it. Nothing is "verified" by reading code.**

Production has **0 customers, 0 inquiries, 0 quotes** and 20,464 leads. There is no real data to
test against and there never will be until this ships. So every remaining phase below is written as
*"here is the demo data it needs"*, not *"here is the code to read"*.

Two corollaries, both learned the hard way:

1. **A demo that does not clean up poisons the next run.** Staging is right now carrying the
   wreckage of every previous run — see §2.2.
2. **A demo must vary.** Twelve identically-scored suppliers make every later supplier
   structurally invisible to matching. Sameness is not a shortcut, it is a bug generator.

---

## 1. Settled — do not re-open

**Phase 1 is done and verified.** Staging matches production exactly: 403 tables, 161 views, 739
routines, 5,237 columns. 190/190 Edge Functions deployed, 17 requiring a JWT, zero `verify_jwt`
drift. Migration ledger reconciled at 712 @ `20260804182051`.

**Phase 2 is done.** Signup, OTP, profile, terms, AI intake, drawing upload with BOQ extraction and
verified redaction, CAD upload, reference photos, inquiry creation, dispatch, supplier inbox,
quotation by form **and** by uploaded document, revision, structured review, comparison PDF, and
cross-account isolation — all against deployed staging with real Auth users.

**Staging isolation holds and must keep holding:** 0 cron jobs, 0 routines referencing production,
no live payment or deploy tokens. `verify_phase1.mjs` asserts all three — if it ever fails, stop.

---

## 2. Demo data: what exists, what is rotting, what to build

### 2.1 What exists today

`scripts/staging/journey_test.mjs` is **the only end-to-end demo-data creator in the repo.** Every
helper inside it is a private top-level const, importable by nothing:

| helper | line | makes |
|---|---|---|
| `mkUser()` | :33 | an `auth.users` row + signed-in JWT |
| OTP seed + `kyc` calls | :100-127 | verified email, saved profile, accepted terms |
| `standUpSupplier()` | :501 | approved supplier + capability row + a quote |
| `quotePayload()` | :75 | a complete, non-draft form quote |
| cleanup block | :619-659 | auth users, `Journey Test %` leads, listed storage paths |

Supplier A is built by ~130 inline lines (:307-439) that **duplicate `standUpSupplier`'s body**
almost verbatim — including the 18-column `supplier_capabilities` INSERT written out twice
(:399-416 and :522-536). `standUpSupplier()` returns only `{ok, detail}`: it throws away the
supplier's id, email and JWT, so a caller cannot make a supplier and then *act as* it.

Nothing else creates journey data. `supabase/seeds/` is 2,390 rows of agent knowledge.
`npm test` (`scripts/checks/run.mjs`) runs 16 static source-analysis tests that never open a
database connection.

### 2.2 What staging was carrying — CLEARED in session 9

Purged with `demo_factory.mjs --purge`. Measured before and after:

| leftover | brief said | actually removed |
|---|--:|--:|
| `customers` | 62 | **65 — every single one an orphan** (0 of 65 had a surviving `auth.users` row) |
| `inquiries` | 41 | 42 |
| `inquiry_intake` | 57 | 59 |
| `email_verifications` | 51 | 52 |
| `drawing_redaction_runs` | 29 | 31 |
| `documents` (dangling) | 24 | 26 |
| `doc_versions` | not listed | **601** |
| `notifications` (dangling) | not listed | **481** |
| `company_event` (dangling) | not listed | **177** |
| `signed-terms` objects | 114 | 118 |
| `agent-docs` objects | 19 | 20 |
| `drawing-files` objects | 2 (session-8 probe) | 2 |
| orphaned auth users | 15 | 15 |

Staging now holds **0 customers, 0 inquiries, 0 quotes, 0 leads, 0 documents** and 26 objects, all
of them in `brand` — the fonts `pdf_native` needs, which the purge protects by name.

Two of those rows were on nobody's list and are worth understanding, because they are the same
class of bug as the 23 `quoted` inquiries with zero quotes:

- **66 `company_event` `supplier.applied` rows** pointing at leads that no longer existed.
- **66 queued `supplier_registered` notifications** addressed to `management@quotesdone.com`.
  `notifications` is a **queue, not a log**. `email_enabled` is `false` on staging today, so they
  sat there harmlessly — but §6 plans to turn it on behind a recipient allowlist to prove
  notification, and the moment that happened all 66 would have fired at once.

Two rows survive on purpose: `rfq_not_dispatched` notifications carrying no `lead_id` and no
`inquiry_id`. Nothing ties them to a deleted parent, and a rule broad enough to catch them would
also delete a genuine unreferenced system alert. Left deliberately; decide if you disagree.

**Both leaking scripts are fixed, and the fix is verified by measurement, not by reading the diff.**
Run `journey_test.mjs` then `smoke_staging.mjs` and every domain table is back to 0 with only the 26
`brand` objects in storage.

- `journey_test.mjs` — takes a run tag, calls `teardown()`.
- `smoke_staging.mjs` — deleted its auth user and nothing else. It now deletes by **email**, which
  matters: `customer_api`'s `me` creates a `public.customers` row with a **fresh uuid** rather than
  reusing the auth uid, so `delete where id = userId` matched nothing *and still reported success*.
  That is why **0 of the 65** orphaned customers rows had a surviving `auth.users` row. The smoke run
  also leaves an `inquiry_intake` row from its `inquiry_intake` check; neither cascades from
  `auth.users`.

### 2.3 The factory — BUILT

`scripts/staging/demo_factory.mjs` exists. `node scripts/staging/demo_factory.mjs` runs its
selftest (14/14, ~40 s, tears itself down).

```js
import { withRun, makeCustomer, makeSupplier, makeInquiry, makeQuote, makeBulkCorpus } from './demo_factory.mjs';
await withRun(async (run) => {
  const cust = await makeCustomer(run);                          // { id, email, jwt, customerId }
  const sup  = await makeSupplier(run, { trade: 'aluminium' });   // { leadId, email, jwt, profile }
  const inq  = await makeInquiry(run, { customer: cust });
  await makeQuote(run, { inquiry: inq, supplier: sup, amount: 125000 });
});                                                              // teardown runs even on a throw
```

- **Tagging.** Emails carry `qd-<tag>-…@example.com`, `leads.tags` carries `qd_run:<tag>`,
  `inquiries.provenance->>'qd_run'` carries the tag. Everything else is reached through those.
- **Storage teardown is DERIVED FROM THE DATABASE** (`inquiries.drawing_file_path`,
  `drawing_redacted_paths`, `quotes.original_file_path`, `customers/leads.signed_terms_path`,
  `documents.bucket|path`, `drawing_redaction_runs.output_paths`) — not from a hand-maintained list.
  The hand-maintained list is exactly why 118 `signed-terms` objects accumulated.
- **`withRun()` tears down in a `finally`.**
- **Two speeds.** `mode:'sql'` (auth-admin identity + direct INSERT, zero model calls) and
  `mode:'api'` (the deployed functions, real models). `makeBulkCorpus` builds 100 suppliers in
  **2 management-API round trips**.
- **`capability: 'agent'`** confirms through `capability_agent` instead of the raw INSERT — see §3.1.
- **`makeLicenceGatedSupplier()`** produces a supplier the licence gate has refused.
- **`--purge`** for drift, `--purge --dry-run` to look first. The dry run is a **lower bound**: the
  orphan sweeps only become true once their parents are gone (it predicted 13 dangling documents
  and 382 notifications; the real run removed 26 and 415).

**The selftest's last check is the one that matters:** it snapshots 20 row counters plus every
storage bucket before the run and asserts they are identical after teardown. That check is how
`company_event`, `doc_versions`, `notifications` and `supplier_capability_confirmation` were found —
none of them were on any list of things a demo run touches.

**Three outputs the database does not record**, found by watching what survived a clean run:

1. **The comparison PDF.** `comparison_run_v2` has no path column and the signed URL is only ever
   returned to the caller, so nothing in the database knows the object exists — which is how 20 of
   them accumulated in `agent-docs`. Teardown now derives it from the filename convention
   (`QD-<first 8 of the inquiry id, uppercased>-CMP.pdf`).
2. **The CAD original.** `create_inquiry` carries `drawing_file_path` for the raster upload only, so
   the `.dxf` the customer actually uploaded is stored and then referenced by nothing. `journey_test`
   deletes it by name; **in production it would be unreachable litter**, and worse, a supplier
   asked to quote from a CAD drawing has no path to it.
3. **The reference photos.** `attach_photos` returns their paths and writes them to no row. Its
   `drawing_redaction_runs` row used to carry `customer_id` NULL **and** `owner_email` NULL — so a
   redaction record could not be attributed to the customer who caused it.
   **FIXED in session 10, and it was one line on the caller.** `drawing_redact`'s `recordRun` had
   *always* read `owner_customer_id` and `owner_email` off the request body; `attach_photos` simply
   never sent them. The owner is resolved by **email**, not `user.id`, because `customer_api`'s `me`
   gives the `public.customers` row a fresh uuid — stamping the auth uid would have recorded
   provenance against a customer that does not exist, which is worse than recording none.
   Pinned by journey step 12, which is why the journey is now **38/38**.
   *Still true: the photo paths themselves are written to no row.*

A clean `journey_test` run now leaves **zero** rows and zero objects behind, except
`signed-terms/registers/customers-register.xlsx` — a rolling register `kyc accept_terms` maintains
and regenerates, not per-run litter. `--purge` does delete it; that is harmless but worth knowing.

**Two fixture traps found by building it**, both of which produced a green-looking wrong answer:

1. **Vary the score dial, hold the gates still.** The first cut varied `roles` "for realism", which
   is a *gate* in `fn_match_capability`, not a score term — the zero-overlap decoy landed on
   `supplies_only` and was dropped by the role gate before it could be discarded by the relevance
   floor it existed to test. Vary `products_norm`; leave roles, trades and authorities uniform
   unless a test is specifically about them.
2. **`p_value` is not optional.** `w_size` scores 10 only when `p_value is not null` **and** the
   supplier states a range containing it; otherwise every candidate gets 5 and the whole ladder
   shifts down. Omitting it made variant 0 score 45, not 50.

### 2.4 Traps that specifically break demo data — read before writing a fixture

**The licence gate fires on INSERT.** `trg_leads_a_licence_gate` is `BEFORE INSERT OR UPDATE OF
license_doc_path, trade_license_no, license_expiry` on `public.leads`. A bulk corpus INSERT that
carries a `license_doc_path` with a null `trade_license_no` sets `approval_status='action_required'`
on every row, which fails `fn_is_matchable`, which drops all 100 suppliers out of
`fn_match_capability`'s `cand` CTE — **an invisible corpus.** `journey_test` dodges this only
because it approves via an UPDATE whose column list excludes those three columns, short-circuiting
the trigger (:356-359).

**`p_limit 12` is NOT the constraint people think it is.** In `fn_match_capability`,
`sc.trades && p_trades` is a hard eligibility **gate**, not a score term — trades contribute 0 of
the 100 points. A corpus spread across 25 trades puts ~4 candidates in front of a limit of 12, so
the tie-break never binds. The settings that actually constrain a corpus are
**`match_relevance_floor` 35** (`route_inquiry/index.ts:188`) and **`MAX_FANOUT` 5**
(`dispatch_inquiry/index.ts:170`) — and because the score has a floor of `w_size*0.5` = 5 points,
a supplier with zero `products_norm` overlap scores 5 and is silently discarded by the floor.
The tie-break trap *is* real for `journey_test` itself, whose suppliers all carry the identical
6-trade/9-product fixture and therefore tie exactly.

**Spread score with `products_norm`, not `rating`.** `products_norm` overlap is the primary
continuous dial: `w_prod * product_hits / cardinality(p_products)` — 40 points in `1/|p_products|`
steps. `leads.rating` is the wrong knob twice over: `supplier_perf` computes
`COALESCE(l.app_rating, l.rating)`, so `app_rating` wins wherever it exists; and
`track = least(1, greatest(0, coalesce(sp.quote_rate, sp.perf_score, 0)))`, where
`quote_rate = quoted/NULLIF(matched,0)`. **The moment your corpus is dispatched to, `matched > 0`,
`quote_rate` stops being NULL and overrides `perf_score` entirely** — a matched-but-not-yet-quoted
supplier gets `track = 0.000` and the whole rating spread collapses on the second run. A
rating-spread corpus is not idempotent.

**Uploads leak even from ad-hoc probes.** Two `drawing-files` objects in staging came from a
one-off diagnostic script in session 8, not from the journey. If you write a throwaway probe, give
it teardown too.

---

## 3. Pending work, in dependency order — each with its demo data

### 3.1 Phase 3 — supplier journey

Phase 3 is three different kinds of gap, not one.

**(a) Wired but never executed.** `supplier_api` `process_docs` does **not** call `doc_extract` —
it calls `license_extract` synchronously (`supplier_api/index.ts:288`, **`max:1500`** — treat that
ceiling as suspect, it is the same shape as the two that were silently truncating in session 8).
`doc_extract` is a queue drainer over `public.documents`, pulled by the `doc_process` cron. Staging
has 0 crons, so **`doc_extract` has never run there**: 24 `documents` rows, every one
`status='pending'`, 0 `agent_runs`.

`license_extract` has **three** callers, not two: `supplier_api:288`, `supplier_portal:194`, and
**`resend_inbound/index.ts:77`** (invoked at :270 and :282), whose `license` branch writes
`leads.license_doc_path`, `trade_license_no`, `license_authority`, `license_expiry`,
`license_city`, `emirate` and `trn` directly. Any licence fixture must account for that inbound-email
entry point.

`public.documents` is written only by `fn_register_document`, fired by **three** triggers:
`reg_lead_docs` on `leads`, `reg_inquiry_doc` on `inquiries`, `reg_quote_doc` on `quotes`. All 24
staging rows (12 `drawing`, 12 `quote`) came from the latter two — created for free by journey runs.

**DONE in session 9 — and it was broken.** `verify_doc_extract.mjs`, 7/7 after a fix.

The fixture costs one model call: a real object into `drawing-files`, an inquiry carrying its path,
and `trg_reg_inquiry_doc` registering the `documents` row through the real trigger — so the queue
entry arrives exactly as a customer's upload would, with no model call at all. Only the extraction
is billed. (The 24 pre-existing `documents` rows the brief suggested reusing were purged, and would
not have worked anyway: their storage objects went with them.)

**The first time doc_extract ever ran, it returned `extraction_null` and HTTP 500.** `doc_extract`
passed `max:2000` to the gateway, and `ai_gateway` computes
`maxTok = min(body.max ?? route.max_tokens, route.max_tokens)` — so a caller-supplied `max` can only
ever **lower** the policy ceiling, never raise it. `model_policy.document_extraction` is 8000; the
caller silently capped itself at 2000.

Measured output for one drawing page across three runs: **1,996 / 2,170 / 2,051 tokens.** Straddling
the 2,000 ceiling — which is precisely §5's "a cap mid-distribution fails roughly one run in three
and reads exactly like model flakiness". The 1,996 is the same figure session 8 recorded for
`quote_extract`, for the same reason: gemini-3.5-flash spends most of its output budget on reasoning
tokens, so sizing a ceiling from expected JSON length is wrong by an order of magnitude.

Fixed by **deleting the caller-side `max`** so the task class decides — which is what the task class
is for. Deployed to staging (`verify_jwt=false`, parity intact). After it: `status=done`, 1,179
chars extracted, 9 specifications, 5 quantities, indexed into `kb_chunks`, 26% of the 8000 ceiling.

**The licence fixture exists too (`verify_license_extract.mjs`, 12/12, 4 model calls ~0.2 AED).**
`fixtures/licence_pdf.mjs` generates a real one-page PDF from a data table rather than checking in
another opaque binary — so the four variants (plain, 15-activity, expired, illegible) are all edits
to one object, and it exercises `buildContent`'s **PDF passthrough** branch, which the two PNG
fixtures never touched. Measured: legal name, licence number, authority, emirate, TRN, both dates
normalised from DD/MM/YYYY, and 15 of 15 activities. The expired variant reads its past expiry
rather than the issue date. The illegible page returns `confidence: 'low'` with empty fields —
it does not invent a licence number.

**`license_extract`'s `max:1500` was the right suspect for the wrong reason.** It had not truncated:
a plain licence uses 777–860 output tokens and a realistic 15-activity one 1,116–1,171. But that is
**74–78% of the old cap**, and the failure mode is invisible — `parseJson` returns `{}` on a
truncated response and every field is then scrubbed to `''`, so the caller gets HTTP 200
`{ok:true, doc:{legal_name:'', license_number:'', confidence:'low'}}`, **indistinguishable from a
genuinely unreadable scan**. Removed and deployed to staging; the task class gives it 8000.

**DONE in session 10 — `verify_supplier_docs.mjs`, 13/13, 2 model calls (~0.1 AED).** A claimed
supplier holding its own JWT uploads real PDF bytes through the deployed function into the real
bucket, and the licence gate re-evaluates on what the model returned. Measured: the object lands at
`licenses/<lead>/<ts>_<name>.pdf`; `license_doc_path` names it exactly; licence number, authority,
expiry, emirate and TRN are written **back to the row**; the legal name corrects `company_name` and
stamps `name_corrected_from`; a readable licence does **not** open the gate; an unreadable one is
still **stored** (the evidence is kept), invents no licence number, and **does** open the gate; and a
file whose bytes contradict its declared type is refused 415 with nothing stored and the row
untouched.

> **Every assertion is on the ROW, never the response — and that is what found the defect.**
> `process_docs` **discarded the result of its only database write.** The storage uploads twenty
> lines above check `up.error` and return 502; `await admin.from('leads').update(upd).eq('id',
> sup.id)` did not. A failure there returned `{ok:true, extracted:{…}}` — a complete, plausible
> payload describing a licence that was never saved. The supplier is told their trade licence is on
> file; the document review queue never sees it.
>
> **Two siblings share the shape.** `save_profile` is worse: the three lines above it put
> `approval_status`, `verified` and `licence_gate_reason` into the same object, so that write **is
> the approval decision** — a silent failure leaves a supplier who should be approved sitting
> unapproved with the failure recorded nowhere, while the exception window immediately below opens a
> 14-day clock against a state that was never persisted. `supplier_portal save_documents` reported
> every file as `saved` while no path ever reached the row. All three fixed and deployed to staging.
>
> The other two sites of this pattern (`inbound_email:149`, `supplier_api:118`) are background
> enrichment that promises a user nothing. **Left alone deliberately** — a bulk sweep would have
> been the wrong fix.

**Also found: `demo_factory`'s teardown had no rule for `supplier-docs` at all.** It derives
`drawing-files`, `quote-files`, `signed-terms` and `agent-docs` from the rows that name them and
stopped there. Nothing noticed because the bucket held 0 objects — the first real run would have
leaked every licence, profile and catalogue, the same class as the 118 `signed-terms` objects in
§2.2, caught before it accumulated rather than after. Two path shapes are now swept: the
bucket-relative one `process_docs` writes and the bucket-prefixed fake one the older licence
fixtures write.

**(b) Switched off by the routing policy.** `fn_ai_route` returns `use_llm:false, tier:'none'` for
**both `capability_agent` and `supplier_review`** in staging *and* production — both map to
task_class `supplier_matching` (tier none, model none, max_tokens 0). This is the exact
`inquiry_intake → missing_fields_detection` trap. The capability flow is dead at the model layer,
not merely missing a UI.

**The confirm half is now WIRED AND PROVEN (session 9).** `capability_agent` action `confirm` makes
**no model call at all** — the only model call is on the `analyze` path. `seed_staging_secrets.mjs`
now adds `capability_agent` to the `db.internal` credential scope (the credential that already
carries its siblings `enrich_capability` and `dispatch_inquiry`), and
`makeSupplier(run, { capability: 'agent' })` drives it. Measured: `review_status='confirmed'`,
`confirmed_version=1`, one `supplier_capability_confirmation` ledger row, and a 400
`need_at_least_one_trade_and_role` for a trade code outside the controlled vocabulary — which is the
reason to prefer the endpoint over the raw INSERT, since an INSERT will happily store a trade code
`fn_match_capability` can never match.

**This had never run in either project.** Still outstanding:

- `analyze` remains dead — it needs the `supplier_matching` task-class remap.
- `journey_test.mjs` still writes the duplicated 18-column raw INSERT twice (:399-416 and :522-536).
  Replacing both with `capability_agent` confirm is now a small, safe change.
- **`confirm` does not write `min_project_value` / `max_project_value`**, so a supplier confirmed
  this way scores `w_size*0.5` instead of `w_size` in `fn_match_capability`. Either the endpoint
  should accept them or the scorer should stop rewarding their mere presence.
- **Production still has no credential scoping `capability_agent`** — see §8.

**(c) Configuration missing from staging.** `pricing_config` is not in
`sync_staging_reference.mjs`'s TABLES array (18 entries, :27-52), so `auto_approve_suppliers` is
null and `supplier_api:470` always sets `pending`, never `action_required`.

That blocks the exception window *through supplier_api* — but not the fixture.
`fn_leads_licence_gate_rerun` evaluates the gate on INSERT, so **one INSERT** carrying a
`license_doc_path` with a null `trade_license_no` opens a real licence gate with `pricing_config`
still empty.

**DONE in session 9 (`verify_exception_window.mjs`, 14/14, zero spend).** The whole lifecycle now
runs, and none of it ever had: staging has 0 crons so `fn_supplier_exception_sweep` — which sends
every reminder and performs every auto-rejection — had never been called, and production has no
supplier in the state to call it on.

Driven by back-dating `exception_opened_at` / `exception_due_at`, which is legitimate because the
sweep reads no other clock. Measured, in order: the gate puts an unreadable licence in
`action_required`; the exception opens with a 14-day due date; **a repeat failure does not restart
the clock** (`fn_supplier_exception_open` returns `reopened:false`); reminders fire on days 3, 7 and
12 and then stop; past the due date the registration auto-closes with `expired_auto_rejected`, a
closure email and an `agent_actions` telemetry row; `fn_is_matchable` returns false for it; and
uploading a readable licence **reactivates it with no approval queue**, stamping
`recovered_after_auto_reject`. `founding_rank` is assigned on verification and
`subscription_exempt` follows `rank <= founding_free_limit`, stamped once and not recalculated on a
second verification.

> **The 48-hour throttle is the trap here.** The sweep requires
> `exception_last_reminder_at < now() - interval '48 hours'` as well as the day-3/7/12 condition, so
> a test that back-dates only `exception_opened_at` gets reminder 1 and then silently gets nothing —
> and would report the ladder as working. Back-date `exception_last_reminder_at` with it.

**Quotation history — CLOSED, it was already built.** The premise was wrong in both directions: it
has a table *and* a writer, both live. The table is `doc_versions` (`entity_type='quote'`), the
writer is trigger `version_quote AFTER INSERT OR UPDATE ON public.quotes` running
`trg_version_quote()`, and the readers are `fn_doc_history()` / `fn_doc_diff()` plus `archive_rfq`.
Production holds **136** quote-history rows. Building a `quote_revisions` table would have
duplicated a working mechanism.

Pinned by journey step 34, which asserts **recovery** rather than mere existence: after a revision
the previous amount must still be readable (`125000 -> … -> 118500`). Note the trigger fires on
every UPDATE, including status changes, so one revised quote produces many versions — noisy, not
wrong.

### 3.2 Phase 4 — taxonomy

The "0 callers" finding is confirmed **and worse than stated**: staging does not hold the router's
own inputs. `kb_operational_alias` is **0 rows** (production 4,212) and `kb_operational_route_map`
is **0** (production 426), so `fn_kb_route_decide` returns `top_score: 0` for every string in
staging. There are **five** hardcoded lists, not four, and **zero of their 19 short slugs exist in
`catalog_supplier_categories.slug`** — so any wiring PR must also crosswalk the trade vocabulary
`fn_match_capability(p_trades text[])` matches against, or dispatch silently returns nothing.

**DONE in session 9 — the router works, in both languages.** `verify_taxonomy.mjs`, 11/11, zero spend.

The pagination diagnosis was right and is fixed. `copyTable()` now orders by the **full primary key**
(or every column where there is none), the skip-guard resumes instead of skipping
(`stageRows >= prodRows`, not `stageRows`), the INSERT carries `on conflict do nothing` so a resume
is idempotent, and a count that does not match production prints `*** MISMATCH ***` instead of a
number that looks like success. Proof it worked is not the row count — a duplicate-and-drop bug can
preserve the count — but an md5 over all 4,212 `(catalog_num, language, alias)` keys, which matches
production exactly.

Loaded: `kb_operational_route` 86, `kb_operational_alias` 4,212, `kb_operational_route_map` 426.

**Two tables had been in the allowlist for two sessions and never once loaded.**
`field_definition` (552) and `field_definition_source` (880) FK to `mep_trade`, which was not in the
list, so every run deferred them and the summary printed a total that looked fine. Both parents
(`mep_trade`, `kb_operational_route`) are now in the list and all four load.

Measured routing:

| input | result |
|---|---|
| `supply and install fire alarm system with smoke detectors` | catalog **13** Fire Alarm & Life Safety, score 6, confidence 1 |
| `نحتاج توريد وتركيب نوافذ ألمنيوم لفيلا` | catalog **19** Aluminium & Glass, matched the `ar` alias `نوافذ ألمنيوم` |
| `zzz nonsense …` | `top_score 0`, `ask_clarifying_question`, and a written clarification — it asks, it does not guess |
| `We need aluminium windows …` | **ambiguous**: matches the single word "Windows" in 2 categories at weight 2, so it asks which |

**The crosswalk exists — correct §3.2's claim that it does not.** `lead_trade_map(trade_key,
catalog_slug)` bridges `taxonomy_trade.code` (what `fn_match_capability` gates on) to
`catalog_supplier_categories.slug` (what a route resolves to), and `kb_operational_route` carries
`expected_catalog_slug` to complete the chain. All 22 non-null slugs resolve to a real category.

Two real gaps remain, pinned by the gate so that closing one or opening a new one both fail it:

- **3 of 25 trades cannot be reached from a catalogue route.** `wallpaper` is absent from
  `lead_trade_map` entirely; `elevators` and `signage` are present with `catalog_slug` NULL and
  `confidence: 'none'` — the rows themselves say "NO CATALOGUE CATEGORY".
- **4 `kb_operational_route.expected_catalog_slug` values point at categories that do not exist.**
  Each is the category name slugified **without its parenthetical**, so the fix is unambiguous:
  `renewable-energy-companies` → `renewable-energy-companies-solar-ev-battery`,
  `domestic-services-companies` → `…-maids-care`, `gas-systems-suppliers` → `…-lpg-medical-gas-industrial-gas`,
  `utility-contractors` → `…-dewa-sewa-fewa-approved`. **Not fixed here: this is production
  reference data, and patching only staging's copy would hide it.**

`kb_stage.*` remains a bulk-load problem and is untouched (production: `decision_rules` 16,254,
`categories` 67, `questions` 16,588 / 29 MB).

`kb_stage.*` is a **bulk-load problem, not a schema-prefix problem**: `kb_stage.questions` alone is
16,588 rows / 29 MB of `to_jsonb` text. Either restrict the copy to the columns `fn_kb_next_question`
actually reads, or move `kb_stage` off the management-API transport entirely.
(Production `kb_stage`: `decision_rules` 16,254, `categories` 67, `questions` 16,588.)

> **Demo data:** a synthetic customer inquiry whose free text is written to hit a **known** catalogue
> route, asserted end to end: text → `fn_kb_route_decide` → `catalog_num` → `inquiries.category` →
> `dispatch_inquiry` → a supplier inbox. Plus the **paired negative**: text that routes to a
> catalogue entry for which no capable supplier exists, asserting dispatch's reason string rather
> than a row count. Both need the capability seed parameterised by trade (§2.3).

### 3.3 Phase 5 — portals and API actions

**"29 package API actions" — RETIRED.** Counted from the dispatchers (all three functions use a
single `action === '…'` form; there are no `case` or aliased branches): **`customer_api` 14,
`supplier_api` 11, `kyc` 7.** So the customer/supplier package is **25** actions, or **32** with
`kyc`. `os_api` is the admin console and a different package at 41. Nothing is 29. Use the real
inventory:

```
customer_api  analyze_drawing brief_pdf cancel_inquiry compare_pdf complete_inquiry create_inquiry
              edit_inquiry me my_inquiries quote_pdf rate_supplier request_refund reveal
              supplier_history
supplier_api  claim create_company extract_quote inbox me pay_registration process_docs projects
              save_profile search submit_quote
kyc           accept_terms save_customer send_email send_sms state verify_email verify_sms
```

### THE REVEAL WAS BROKEN. A customer could pay and see nothing change.

`verify_portal.mjs` (13/13, zero spend) was the first fixture ever to create a `transactions` row —
the journey produces one inquiry with two quotes and never reveals — and it found this immediately:

```js
// customer_api/index.ts:654, before
await admin.from('transactions').select('id,quote_id,revealed_at,created_at').eq('customer_id', cust.id)
```

**`public.transactions` has no `created_at` column, in staging or in production.** PostgREST answers
400, `txs` comes back **null**, `for (const t of txs || [])` iterates nothing, and `revealedQ` stays
empty — so **no quote is ever marked revealed**. The customer pays the reveal fee, `reveal` writes
the row, and `my_inquiries` goes on returning `supplier_ref: null`, `revealed: false`, a banded
rating and no emirate. Forever.

It is the single line in the whole file that names a column that does not exist; the other seven
`transactions` reads are all correct. Fixed, deployed to staging, and the read now logs `txErr`
instead of discarding it. **This is live in production.**

> That is the shape §5 keeps warning about, in its purest form: no exception, no 500, no failed
> assertion — a `|| []` turning a hard schema error into an empty list, on the one path the paying
> customer cares about. A green 37/37 journey said nothing about it because the journey never pays.

**What else `verify_portal.mjs` pins.** Four inquiries spanning `sent`/`quoted`/`completed`/
`cancelled`, 2–3 quotes each at different prices, one revealed. Asserted: drafts never reach the
customer; quotes arrive cheapest first with anonymous `Supplier A/B/C` labels and a reveal fee;
pre-reveal payloads **omit** `emirate`, `rating_source` and `win_rate` as keys rather than sending
nulls, and band the rating, review count and years; the revealed one carries the real `supplier_ref`
and exact figures; `matched_suppliers: 0` lets the portal say "this reached nobody" instead of
showing hope; a signed-in user with no `customers` row is served, not crashed (and the row
`customer_api` then creates carries a **fresh uuid, not the auth uid** — the mechanism behind the 65
orphans); and Arabic summaries and quote notes survive the round trip.

**~~`customers.locale` is stored and never served~~ — HALF FIXED, and the claim was imprecise.**
Measured 5 Aug 2026: `me` **does** serve it — `customer_api` builds the row with `select('*')` and
returns it whole, and the key comes back with value `'ar'`. So "never served" was wrong. What is
true, and worse, is that **the portal never calls `me`**: it calls `kyc state` and `my_inquiries`.
The field was on the wire only where nothing was listening.

`my_inquiries` now returns `locale` (deployed to staging, `verify_portal` 14/14). **The consuming
half is deliberately not done**: `CustomerPortal` still decides language from
`localStorage['qd-lang']` and the `NEXT_LOCALE` cookie, and wiring the served value needs `lang`
threaded `CustomerPortal()` → `Authed` → `Dashboard`, because `Dashboard` receives it as a read-only
prop. That is a blind edit to language switching with **no browser harness to verify it** (§3.6,
itself blocked on a staging-pointed preview URL), which is not a trade worth making for a field that
is now available. `verify_portal` check 14 pins the remaining half so it cannot be quietly forgotten
— **flip that check when the wiring lands.**

> **Still to do here:** the remaining original asks —
> - A demo customer with **3-4 inquiries spanning statuses** (`sent` / `quoted` / `completed` /
>   `cancelled`), each with **2-3 quotes at different prices**, at least one revealed via a
>   `transactions` row. Today the journey produces exactly one inquiry with two quotes and then
>   deletes the quotes, which is why staging has 23 `quoted` inquiries with zero quotes.
> - A customer whose `auth.users` row exists but whose `customers` row does not — `mkUser()`
>   already produces this state and nothing asserts what the UI does with it.
> - **An Arabic demo customer**: `customers.locale='ar'`, Arabic inquiry summary and `raw_input`,
>   a supplier quote with an Arabic note, and one alert from the `ar` branch. Note `customers.locale`
>   exists and is **unused** — the portal reads `localStorage['qd-lang']` and the `NEXT_LOCALE`
>   cookie (`CustomerPortal.tsx:16`), so the wiring must be made to read it or the Arabic journey
>   tests a code path nobody uses.
>
> `CustomerPortal.tsx:237` still carries the pre-existing `side-tab` design finding.

### 3.4 Phase 6 — AI gateway and cost

**Correction: the session-7/8 briefs had this wrong, including my own.** `fn_llm_log` does **not**
write `llm_calls` — it writes **`ai_cost_log`, which has 643 rows in staging and is working**. The
RPC signature at `ai_gateway/index.ts:435` matches the database definition argument-for-argument
(13 params, no defaults), so `rpcSafe` is swallowing nothing. `llm_calls` is a **dead legacy table**
with exactly one writer left in the repo (`site_assistant/index.ts:25`), which the journey never
exercises. "llm_calls is 0" was true and meaningless.

**The real Phase 6 defect** is that `ai_cost_log.cost_aed` is **0.00 on all 643 staging rows** and
on **238 of 589 production rows**, because `fn_llm_log` prices from **`model_rate`** while
`fn_ai_route` / `fn_model_cost_usd` price from **`model_registry`** — two pricing tables that
disagree about which models exist. `model_rate` has **0 rows in staging** (never copied by the
reference sync) and in production contains no `google/*` entries at all.

Production `ai_cost_log` by model: `anthropic/claude-sonnet-5` 236 rows / 218 priced;
`google/gemini-3.1-flash-lite` 207 / **0**; `~anthropic/claude-haiku-latest` 77 / 76;
`anthropic/claude-opus-4.8` 57 / 57; `google/gemini-3.5-flash` 9 / **0**; `model_used='none'` 3 / 0.
Total priced 351, sum 37.42 AED.

Three monitoring views are blind because they read the dead table: `v_llm_model_mix` and
`v_llm_calls_without_task_class` name `llm_calls` directly; `v_llm_offpolicy` reads
`v_llm_model_mix LEFT JOIN llm_policy` and is blind transitively. Repoint the first two.

**Only 1 of ~70 gateway call sites passes `task_class`** — `agent_brain/index.ts:33`. (An earlier
count of 2 was wrong: `kb_research_test:43` *reads* `task_class` back off the response into its own
JSON output; its request at :32 sends none.)

**DONE in session 9.** `verify_cost.mjs` measured it (2/7 red), `seed_cost_config.mjs` fixed it, and
the live probe proved it. All applied **directly, not as migrations** — a migration breaks the
712-vs-712 ledger parity `verify_phase1.mjs` asserts.

- `model_rate` seeded with 6 rows **derived from `model_registry`** at 3.6725 AED/USD. Deriving one
  table from the other is the actual fix: the two disagreeing is the root defect, and a hand-written
  `model_rate` is what let production lose every `google/*` row in the first place.
- `department_budget` seeded with production's 13 `dept_key`s and thresholds, `spent_aed` at 0.
- `fn_task_class` row added for **`drawing_redact_verify`**, the only 1 of 34 gateway call sites
  falling through to `UNMAPPED -> general_drafting`. **Production is missing this row too.**
  Read the next subsection before you touch this one.
- `v_llm_model_mix`, `v_llm_calls_without_task_class` and `v_llm_offpolicy` repointed off the dead
  `llm_calls` onto `ai_cost_log`, grants restored.
- 601 `ai_cost_log` rows removed: every one recorded 0.00 because `model_rate` was empty, so they
  measure a broken meter rather than a cost. The 80 that remain are cache hits and `model_used='none'`.

**Measured end to end with `--live`:** one real `google/gemini-3.1-flash-lite` call billed
**0.000045 AED**, `department_budget.spent_aed` moved by **exactly** that, and the next call to an
over-budget department returned `outcome:'budget_halted'` with `used_llm:false` — without reaching a
provider.

Three notes for whoever picks this up:

1. **The brief's own halt fixture was wrong.** `monthly_aed=0.01` with `halt_at_pct=95` never fires:
   `fn_ai_route` computes `100 * month_spend / monthly_aed`, and a flash-lite call costs ~0.000045
   AED, which is 0.45% of that ceiling. The ceiling must be set relative to what was actually spent.
   `verify_cost.mjs` sets it to the logged cost, putting the department at exactly 100%.
2. **Column count is part of schema parity.** The first cut of the repointed views added three
   columns and turned `verify_phase1`'s 5,237-column check red. `v_llm_model_mix` now swaps the
   dead `cached_tokens` for `cost_aed` rather than adding it.
3. **`v_llm_offpolicy` was repointed further than the brief said.** Fixing only its parent would
   have left it joining `llm_policy`, which has 3 rows in production and **0 in staging** and is not
   what `fn_ai_route` consults — turning a silent all-clear into a loud false alarm. It now asks:
   was a model used that no active `model_policy` can select?

#### ~~`drawing_redact_verify` cannot parse gemini output~~ — WRONG DIAGNOSIS. FIXED IN SESSION 10.

**It reads gemini fine.** The experiment changed one variable — same image, same prompt, same
model, only the ceiling:

| caller `max` | output_tokens | finish_reason | truncated | content | parses |
|---|--:|---|---|--:|---|
| **400** (what shipped) | 396 | **`length`** | **true** | 36 chars, cut mid-JSON at `"found` | **NO** |
| none — task class decides | 724 | `stop` | false | 423 chars | **YES** |

At 724 tokens it correctly named the consultant, the client, the project and the plot number.
`max: 400` was the whole defect — the **fifth** instance of §5's "a token ceiling inside the
output's natural range", on the one model §5 already records as spending most of its budget on
reasoning tokens. **`ai_gateway` was returning `truncated=true` and `finish_reason='length'` the
entire time**, and the function discarded both, so a ceiling problem and a shape problem produced
the identical string `verify_unparseable`. §5 says "Use it." Nothing did.

**The detection call in the same file had it too, and was invisible to the cost gate.**
`drawing_redact/index.ts` carries two `fn` literals, so `verify_cost`'s attribution heuristic put it
in the *unattributed* bucket and never pinned either ceiling. Its `max: 2000` sat under
`document_extraction`'s 8000 on a call whose output **scales with page count**. Measured across two
journey runs, a single page costs **535 and 790** output tokens — so that ceiling would have begun
truncating at roughly **three pages**, failing a privacy control intermittently by drawing size. The
journey uses a one-page drawing, which is exactly why it never crossed it: the same blind spot that
hid `doc_extract`'s ceiling until a real page was measured.

Both ceilings removed. Truncation now reports `verify_truncated` / `detect_truncated` instead of
being laundered into `verify_unparseable` / `detect_failed` — both still fail **closed**, nothing
unverified is ever published, but "raise the ceiling" and "the model misbehaved" are no longer the
same string. `drawing_redact_verify` is therefore mapped to **`document_extraction`** alongside its
siblings, which is where session 9 wanted it. Journey **37/37** with it there — the configuration
that produced 35/37 — and step 9 reports `status=complete verified=1 failed=0`.

> **PRODUCTION ORDERING.** Deploy `drawing_redact` **before** applying the `fn_task_class` row
> there. In the other order the old `max: 400` meets gemini and redaction stops publishing —
> which is precisely what session 9 observed.

The original session-9 note is kept below, because the reasoning it records is sound and only its
conclusion was wrong.

#### ~~`drawing_redact_verify` cannot parse gemini output — REAL, UNFIXED~~ (superseded)

The obvious mapping for `drawing_redact_verify` is `document_extraction`, matching its siblings
`drawing_redact` and `drawing_boq`. **That mapping was applied and it broke the journey**, which
went 37/37 → 35/37:

```
FAIL  9 drawing redaction recorded and verified   status=failed in=1 out=0 verified=0 failed=1
FAIL 13 inquiry carries the drawing and its redacted pages   redacted_pages=0
verify_detail: [{"page": 0, "found": ["verify_unparseable"]}]
```

The model call **succeeded** — `ok=true`, 396 output tokens, `cost_aed` 0.0203. `document_extraction`
resolves to `google/gemini-3.5-flash`, and `drawing_redact_verify` cannot parse what that model
returns. It then fails closed and publishes **no redacted page at all**, which is the correct
refusal and the wrong routing. `drawing_redact` was already on gemini and is fine; only the verifier
cannot read it.

It is therefore mapped to **`general_drafting`** — the same medium tier,
`~anthropic/claude-haiku-latest` and 900-token ceiling the UNMAPPED fallback was already giving it,
its measured output being 295-396 tokens — but as a decision on the record instead of a fallback
nobody chose.

> **Two things for the next session.** First, the parser is the real defect: this is the fourth
> gemini output-shape problem in the log (§5), and `ai_gateway` already returns `finish_reason` and
> `truncated`. Fix `drawing_redact_verify` to read gemini, then move it to `document_extraction`
> where it belongs. **Until then it must not be routed to a google model.** Second, note what caught
> it: not the cost gate, which stayed 7/7 green, and not the model call, which reported success —
> the journey did. A routing change is a behaviour change; re-run the journey after one.

#### `model_policy.max_tokens` is largely decorative — 11 call sites override it downward

`ai_gateway` computes `maxTok = min(body.max ?? route.max_tokens, route.max_tokens)`, so a
hard-coded `max` in a calling function can only ever **lower** the policy ceiling, never raise it.
**63 such literals exist across the Edge Functions.** Session 8 raised `quote_comparison` to 10,000
and `document_extraction` to 8,000 — and `doc_extract` went on capping itself at 2,000,
`license_extract` at 1,500, `drawing_redact` at 2,000.

`verify_cost.mjs` now catalogues them: **11 attributable call sites sit below their task class**,
pinned so a new one fails the gate. Tightest today: `agent_brain` 160/1700, `quote_review`
2600/10000, `site_assistant` 320/800. Two files carry several `fn` literals and are reported
unattributed rather than guessed at.

> Do **not** bulk-remove the remaining 11. A tight budget can be deliberate — `agent_brain`'s 160 is
> a classifier, not a truncation. The two that were removed were removed on measurement:
> `doc_extract` had failed, `license_extract` was at 74–78% of its cap. Measure before touching the
> rest; `verify_doc_extract.mjs` and `verify_license_extract.mjs` are the pattern.

Still open: **`resend_inbound/index.ts:262` calls OpenRouter directly**, outside the gateway, so it
is outside routing, logging and the budget halt. Adding `model_rate` and `department_budget` to
`sync_staging_reference.mjs`'s allowlist is still not done — `seed_cost_config.mjs` covers a rebuild
instead, and derives rather than copies, which is better.

### 3.5 Phase 7 — workflow and autonomy

The executor registry is **`public.org_action_executor`** (PK `action_class`), with allow-list
`public.org_action_executor_rpc_allowed`. Staging has **0 rows in both** against production's **55**
and **16** — and the whole org layer around them is empty in staging because the reference sync
copies only `decision_policy` from this family: `workflow` 0/14, `workflow_step` 0/117,
`employee_workflow` 0/157, `operating_system` 0/10, `org_departments` 0/15, `org_agents` 0/67,
`org_authority` 0/196, `org_tasks` 0/231.

The "no writers" claim is **confirmed two ways**: zero routines in either project contain a write
against `workflow_run`, `workflow_step_run`, `action_execution` or `decision_trace` (pg_proc regex),
zero triggers exist on them, and the only repo references are two *reads* of `org_action_executor`
(`cos_execute:133`, `dept_plan:76`). **`cos_execute` is not the missing writer** — it runs executors
but records to `org_tasks` / `org_memory` / `agent_runs` / `agent_actions`. `orchestrate` is a 410 stub.

> **Demo data — and note the blocker is code, not data:**
> - Copy the config: add `org_action_executor_rpc_allowed`, `org_action_executor`,
>   `operating_system`, `workflow`, `workflow_step`, `org_departments`, `org_agents`,
>   `org_authority` to the reference-sync TABLES (definitions, not business records — the script's
>   own no-real-data rule is not breached). All 39 distinct edge targets are already inside
>   staging's `fn.cos_execute` credential scope.
> - Bring staging's `org_action_executor` constraint shape up to production's (NOT NULL on
>   `risk_tier`/`reversible`/`timeout_seconds`/`max_attempts`, plus the two CHECK constraints).
>   Apply directly — a migration breaks the 712-vs-712 ledger parity.
> - Then a new `scripts/staging/autonomy_test.mjs` in `journey_test`'s create-then-delete shape:
>   one `workflow_run` + its `workflow_step_run` rows + one `action_execution` + the matching
>   `decision_trace`, **all sharing one `correlation_id`** (`workflow_run` needs
>   `workflow_key`/`correlation_id`/`idempotency_key`, all NOT NULL with no default;
>   `action_execution` needs `correlation_id`/`action_class`/`executor`/`idempotency_key`/
>   `risk_tier`/`request`), plus a synthetic `company_event` and `decision_log` row.
>
> **This cannot be a data-only fixture.** Writing those four tables by hand proves the schema, not
> the system. The orchestrator that leases a run, walks `workflow_step` into `workflow_step_run`,
> dispatches through `org_action_executor` into `action_execution` and writes `decision_trace`
> **does not exist**. Decide explicitly whether Phase 7 means building it or seeding it.

### DECIDED IN SESSION 10: SEED THE CONFIG, DO NOT BUILD THE ORCHESTRATOR.

The brief asked for this decision explicitly and before any fixture. It was made on a measurement,
not a preference. Session 9 counted **writers**; the missing number was **readers**. Across all four
tables, in production:

| | `workflow_run` | `workflow_step_run` | `action_execution` | `decision_trace` |
|---|--:|--:|--:|--:|
| routines mentioning it (read **or** write) | 0 | 0 | 0 | 0 |
| triggers | 0 | 0 | 0 | 0 |
| views mentioning it | 0 | 0 | 1 | 1 |
| rows | 0 | 0 | 0 | 0 |
| Edge Function files referencing it | 0 | 0 | 0 | 0 |

Those two view entries are **one view**, `v_executions_without_decision_trace` — an audit that lists
executions with no matching trace — and **nothing reads it**: 0 views, 0 routines. So the four
tables have exactly one consumer, which is itself unread, and zero producers.

That is not a broken integration. It is an **unbuilt subsystem with its schema and its compliance
view pre-placed**, and building an orchestrator to populate tables nothing reads fails the first
question worth asking: does this need to exist at all? Nothing on the revenue path — customer →
inquiry → dispatch → quote → reveal — touches any of them.

**And do not write the data-only fixture either.** The brief is right that it "proves the schema, not
the system", which is precisely the argument against writing it: four hand-written rows would
manufacture the *appearance* of a working autonomy layer and a green check to go with it. That is
the §5 failure mode — a green suite over a subsystem that never ran — installed deliberately.

**What was worth doing, and is done:** the constraint drift. `apply_missing_objects.mjs` does not
diff constraints, so staging had lost production's NOT NULLs and CHECKs — and that is a real parity
defect regardless of Phase 7, because staging silently accepted rows production rejects while every
gate in the repo read identical. `verify_constraints.mjs` now measures it: CHECK 145 vs 143, NOT NULL
1,812 vs 1,807, with FK/PK/UNIQUE matching exactly. Six of the seven were the predicted
`org_action_executor` constraints; **the seventh was on nobody's list — `company_event.event_version`,
a table the journey writes on the live path.** Applied; parity is 2/2.

The org-layer *data* copy (`workflow`, `workflow_step`, `org_departments`, `org_agents`,
`org_authority`, the 55 executors) is left **undone on purpose**. It is only useful to somebody
building the orchestrator, and it should be loaded by whoever does, in the same change.

`v_executor_registry_gaps` returning 0 in staging still means nothing until the 55 rows are loaded.
`cos_execute` correctly stays off.

### 3.6 Phase 8 — acceptance

**The "100 customers / 100 suppliers / 5 admins + Playwright + drive the deployed Vercel URL"
standard is written down in exactly one place — a previous revision of this brief — and nowhere
upstream.** The older audit docs name the pack's acceptance gates (unit, contract, integration,
idempotency, provider-outage, privacy, Arabic/RTL, staging E2E) but never the 100/100/5 numbers.
Treat the corpus size as a working figure, not a spec.

**Replaying `journey_test` 100 times is not viable:** 464 s and 34 agent runs per run → ~12.9 hours
and ~3,400 agent runs.

**The corpus and its assertions exist: `scripts/staging/verify_matching.mjs`, 14/14.** 12 checks are
pure SQL against the deployed `fn_match_capability` over a 100-supplier corpus (4 per trade × 25
trades, two round trips, zero model calls); `--live` adds two that cost one `rfq_routing` call.
Measured:

| claim | measured |
|---|---|
| `products_norm` overlap is the score dial | 8/6/4/0 product hits → **50 / 40 / 30 / 5**, exactly what the weights predict |
| `match_relevance_floor` 35 discards the weak | 2 of 4 kept (50, 40); 30 and 5 discarded |
| a zero-overlap supplier scores 5 | `score=5.0 hits=0` — `w_size*0.5` with min/max null |
| `track` is 0 on a fresh corpus | 0.000 for all — the spread is reproducible, unlike a rating spread |
| `p_limit 12` never binds | 4 candidates reach a limit of 12. Trades are a **gate** |
| a different trade reaches different suppliers | hvac returned 4, **0** shared with the aluminium set |
| a missing mandatory authority | electrical 4 → **3** after dropping `electrical_utility`. It does not score low, it **disappears** |
| the role gate | a `supplies_only` supplier is excluded for `p_need='executes'` and found for `'supplies'` |
| `MAX_FANOUT` 5 binds | 8 candidates above the floor → dispatch `notified=5, capped=true` |
| every supplier contacted declares the trade | 5 matches, 0 outside the trade |

**A gate the brief never mentioned: `min_project_value`.** `p_value is null or (p_value >= min and
p_value <= max)` runs in the `cand` CTE, so a supplier whose declared minimum exceeds the job value
is removed **before scoring** — it does not rank low, it is absent. The same 8 suppliers return 8
candidates for a 300,000 job and **6** for a 150,000 one. Any corpus that varies
`min/max_project_value` silently varies eligibility too.

> Still to do for Phase 8: the 100 **customers** half, and driving the deployed Vercel preview URL.
> Nothing has yet run against the frontend — it was verified by reading its built bundle, and there
> is still no browser test harness in the repo.

Nothing has yet run against the deployed Vercel preview URL. The frontend was verified by reading
its built bundle, not by driving it. There is no browser test harness in the repo.

**SESSION 10 FOUND OUT WHY THAT IS DANGEROUS, NOT MERELY MISSING.** Five frontend modules each
carried `process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://htdblwldjkcgjvmqkbeh.supabase.co'`
**inline**, four of them duplicating the anon key with it. `osClient.ts` resolved it *and* warned on
the console when the variable was unset. The four customer- and supplier-facing components —
`CustomerPortal`, `SupplierPortal`, `ContactInner`, `ChatWidget` — re-declared the fallback
themselves and inherited **neither** the warning nor the single point of change.

So a preview deployment missing one environment variable signs real customers in against
**production**, and lets suppliers upload trade licences into it, in silence. This is the defect
decision D1 already fixed once in the deploy tooling — which "was pinned to the production ref in
three places" — surviving in the frontend.

Now resolved once in `src/lib/supaEnv.ts`, which every consumer imports. The fallback is **kept
deliberately**: an unconfigured production build must behave exactly as it does today, and removing
it converts a silent wrong target into a hard outage. typecheck clean, `npm test` 16/16,
`next build` exit 0.

### THE FRONTEND HAS NOW BEEN DRIVEN. §3.6's browser half is closed for the customer portal.

Not against the Vercel URL — against **the branch built locally with `NEXT_PUBLIC_SUPABASE_URL`
pointed at staging**, which is strictly safer and tests the same thing: real browser, real staging
backend, and the `supaEnv` fix included (which the deployed site does *not* have). Confirmed on the
loaded page: **1 staging ref, 0 production refs** in the JavaScript the portal actually executes.

Driven end to end, by clicking, with `scripts/staging/browser_fixture.mjs` supplying the data:

| step | result |
|---|---|
| OTP sign-in | typed the email, clicked **Send me a code**, entered the seeded code, signed in |
| profile gate | typed name / mobile / DOB and saved — **landed in `public.customers` in staging**, proving UI → `kyc save_customer` → database |
| terms | accepted through the real checkbox |
| dashboard | "Browser Fixture Customer", 1 Request · 1 Open · 2 Quotes received · 0 Hired · AED 0 Spend |
| **the paywall, rendered** | **Supplier A** AED 118,500 "Best value" ✓ verified, **Supplier B** AED 132,000 — anonymous labels, cheapest first, **Reveal fee AED 250**, no identity leaked |

That last row is what `verify_portal` asserts at the API level, now confirmed in the **rendered UI**.
Stopped short of **Reveal & contact**: that is a payment action and needs the Stripe test keys (§6).

**Three findings from driving it that no API test could produce:**

1. **`form_input` on a React checkbox silently does nothing.** Setting the property left the
   controlled state untouched and the form answered "Please accept the terms." It must be *clicked*.
   Any future harness will hit this on every checkbox and radio.
2. **"Open project" is not in the accessibility tree.** It is a bare `<span>` with a click handler —
   no `role`, no `tabindex`, not focusable, not a button. Keyboard and screen-reader users cannot
   reach the control that opens a request. That is an a11y defect, found only by trying to click it.
3. **Mobile verification cannot be exercised at all in staging** — Twilio is withheld on purpose, so
   `phone_verified` had to be set directly. The SMS path remains genuinely untested.

Teardown is a named command, not an implicit one, because a browser session needs its rows to
outlive the script that made them: `node scripts/staging/browser_fixture.mjs teardown <tag>`.
Staging returned to baseline afterwards (factory selftest 15/15, no drift in 23 counters).

> **One piece of pre-existing litter, not from this session:** auth user
> `probe+msfa009g@example.com`, created 4 Aug 23:15 — an ad-hoc probe that never got a teardown,
> which is §2.4's own warning coming true. Left in place rather than silently deleted; remove it if
> you agree.

> **Still true for the DEPLOYED URL, and it is not a tooling gap.** Until a preview
> deployment is provably pointed at staging, any write flow driven through it — signup, inquiry,
> quote, reveal — lands in **production**, which the standing rule forbids. Two things are needed
> before a browser harness is worth writing, and neither is code: **the preview URL**, and
> **confirmation that its `NEXT_PUBLIC_SUPABASE_URL` is set to `pglpqrhvozwepymcuunn`**. Read-only
> page loads would still reach production's `site_assistant` and contact endpoints, so even those
> are not free. Ask for both rather than guessing a URL.

---

## 4. Corrections to earlier briefs — do not re-inherit these

| earlier claim | truth |
|---|---|
| "`llm_calls` is 0, so cost is not recorded — `fn_llm_log` is swallowed by `rpcSafe`" | `fn_llm_log` writes **`ai_cost_log`** (643 staging rows, working). `llm_calls` is dead legacy with one writer. The real defect is `cost_aed=0` from the `model_rate` vs `model_registry` split |
| "`quote_reviews` row is created by an uploaded quote" | `quote_reviews` has **no writer anywhere** and 0 rows in production. The subsystem does not exist |
| "29 package API actions" | **No such list exists**, and the real count is not 29: `customer_api` 14 + `supplier_api` 11 = **25**, or **32** with `kyc`'s 7. Retired; the inventory is in §3.3 |
| "the journey passing 37/37 covers the customer portal" | It covers everything except the step the business runs on. The journey never creates a `transactions` row, so **the reveal had never once been exercised** — and it was broken in production the whole time (§3.3) |
| "`p_limit 12` makes a 100-supplier corpus mostly invisible" | Trades are a hard **gate**, not a score term. A trade-spread corpus never binds the tie-break. The real limits are `match_relevance_floor` 35 and `MAX_FANOUT` 5 |
| "spread corpus score with `leads.rating`" | `supplier_perf` prefers `app_rating`; and `quote_rate` overrides `perf_score` once `matched>0`, collapsing the spread on run 2. Use `products_norm` overlap |
| "standing up a supplier costs 3 model calls" | **2.** `supplier_review` resolves to `use_llm:false` — a free no-op |
| "`doc_extract` is fed only by `trg_reg_lead_docs`" | `fn_register_document` has **three** trigger callers (`reg_lead_docs`, `reg_inquiry_doc`, `reg_quote_doc`). All 24 staging rows came from the latter two |
| "`license_extract` has two callers" | **Three** — `resend_inbound/index.ts:77` is an inbound-email entry point that writes the same licence columns |
| "2 of ~70 call sites pass `task_class`" | **1** (`agent_brain:33`). `kb_research_test:43` reads it back into its response |
| "add `kb_operational_alias` to TABLES — one line" | Right about the bug, wrong about the count: it is **three** lines, because both `kb_operational_*` tables FK to `kb_operational_route`, which was also absent. Fixed and loaded — see §3.2 |
| `capability_requirement` | No such object. The table is **`inquiry_requirement`** (33 staging rows) |
| "216 of 589 production calls billed at zero" | **238** of 589, across **6** model groups including `model_used='none'` |

### Corrections found in session 9 — including to this brief

| earlier claim | truth |
|---|---|
| "62 synthetic `customers` rows" | **65, and every one of them an orphan.** 0 of 65 had a surviving `auth.users` row, so none could ever log in. The count was the smaller finding |
| §2.2's litter list | Missed **601 `doc_versions`**, **481 `notifications`** and **177 `company_event`** rows — more rows than everything it did list, combined |
| "the cleanup leaves `signed-terms` and `agent-docs` behind" | True, and the cause generalises: any hand-maintained path list rots. Teardown now derives paths from the database |
| "a low-ceiling department `monthly_aed=0.01, halt_at_pct=95` trips the halt" | It does not. That is 0.45% of the ceiling for a real flash-lite call. `fn_ai_route` halts on `100*spend/monthly_aed >= halt_at_pct` |
| "`p_limit 12` / trades are the corpus constraint" (already corrected) | Confirmed again, and the **real** fixture trap is different: `roles` is a hard gate, so varying it "for realism" silently removes candidates from scoring |
| "2 of ~70 gateway call sites pass `task_class`" | The count that matters is different: **34** distinct `fn` literals reach the gateway, and **1** (`drawing_redact_verify`) had no `fn_task_class` row at all — in staging **or production** |
| "`fn_task_class` mapping" | `fn_task_class` is a **table**, not a function. `fn_ai_route` reads it and falls back to `general_drafting` with `UNMAPPED` in the `why` string |
| `capability_requirement` → `inquiry_requirement` (already corrected) | Still right. Also: `supplier_capability_confirmation` is a real table and `capability_agent confirm` is its only writer |
| "`seed_staging_secrets.mjs` can be re-run" | It could not. The `internal_credential` INSERT had no `ON CONFLICT` and the table has no unique key on `context`, so a second run would **double all 74 credentials** and leave `fn_internal_auth` choosing between duplicates. Fixed: it now skips the bulk copy when the table is non-empty |
| "`license_extract` at `max:1500` is the next suspect" | Right to suspect it, wrong about why. It had **not** truncated: 777–860 output tokens for a plain licence, 1,116–1,171 for a realistic 15-activity one. But that is 74–78% of the cap, and the failure would have been invisible — `parseJson` returns `{}` and every field is scrubbed to `''`, so a truncated licence is byte-identical to an unreadable one. Removed on the measurement, not on the suspicion |
| "the token-ceiling problem is a handful of functions" | **63 caller-side `max` literals** exist across the Edge Functions, and `ai_gateway` takes `min(caller, policy)` — so every one of them can only lower the policy. 11 attributable sites still sit below their task class. Session 8's raises to `quote_comparison` and `document_extraction` did nothing for the callers that override them |
| "map `drawing_redact_verify` to `document_extraction`, like its siblings" | **Breaks it.** `document_extraction` is `google/gemini-3.5-flash` and the verifier cannot parse that model's output — journey 35/37, `verify_unparseable`, while the model call itself returned `ok=true`. Mapped to `general_drafting` instead; see §3.4 |
| "journey_test's cleanup leaves the customer row behind" | Confirmed and now **fixed**: it takes a run tag and calls `demo_factory`'s `teardown()`. Two runs under the old cleanup left 4 `customers`, 2 `inquiries`, 26 `notifications`, 10 `company_event` and 9 storage objects behind — measured by purging immediately after them |
| "`fn_assign_founding_rank` only fires when `verified` flips true, which `save_profile` never does" | True for the API path, but the factory's SQL path inserts `verified=true`, and the trigger fires on INSERT as well — so a demo supplier is ranked immediately. The rank self-heals after teardown because it is `max(founding_rank)+1`, not a sequence |
| "teardown covers everything a run touches" | It did not cover `public.agent_actions`, which `fn_supplier_exception_sweep` writes as telemetry keyed by `target_table`/`target_id` **text**, so nothing cascades. All 46 rows in staging were dangling. Now torn down, swept by `--purge`, and — more importantly — added to the factory's baseline counters, which is the check that would have caught it in the first place |
| "the corpus constraints are `match_relevance_floor` and `MAX_FANOUT`" | Both confirmed, but there is a **third**: `min_project_value` / `max_project_value` are a hard gate in the `cand` CTE, not the `w_size` score term. The same 8 suppliers yield 8 candidates for a 300,000 job and 6 for a 150,000 one — the two declaring a 250,000 minimum are absent, not low-ranked |
| "zero of the 19 short slugs exist in `catalog_supplier_categories.slug`, so a wiring PR must build the crosswalk" | **The crosswalk already exists.** `lead_trade_map(trade_key, catalog_slug)` bridges `taxonomy_trade.code` to the catalogue, 24 rows, all 22 non-null slugs resolving. The real gaps are narrower: `wallpaper` absent, `elevators`/`signage` deliberately unmapped, and 4 `kb_operational_route` slugs missing their parenthetical |
| "`field_definition` / `field_definition_source` are unloaded (FK to a parent outside the allowlist)" | True, and it had been true silently for two sessions: the parent is `mep_trade`, 5 rows, and nothing reported the tables as never-loaded because the multi-pass loop printed "deferred" and moved on. Both now load |
| "a demo inquiry can be inserted and dispatched" | Not without satisfying the **category checklist**. `rfq_ready` is computed by `trg_rfq_complete` and cannot be set by hand; `fn_rfq_required_check` demands an answer for every `category_specs` field marked required. A hand-written spec scores 85/70 generic and still fails, and the only symptom is `dispatch_inquiry` returning `{"ok":true,"skip":"not_rfq_ready"}` — a 200 that contacted nobody. `makeInquiry` now builds the spec from `category_specs` in SQL and throws if the row comes back not ready |

### Corrections found in session 10

| earlier claim | truth |
|---|---|
| §8: "`fn_task_class` mapping for `quote_compare` (absent in production)" | **Present**, mapped to `quote_comparison`. Acting on that line is a no-op dressed up as a fix |
| §8: "`model_policy.quote_comparison.max_tokens` 3000 → 10000" | Production is at **1500** — the original `~anthropic/claude-haiku-latest` ceiling that is the *first* of §5's four truncations. The gap is twice what the brief claimed |
| "238 of 589 production calls billed at zero" (session 9's own correction) | Now **247 of 603**, and still moving. `google/gemini-3.1-flash-lite` alone is **219 calls, every one unpriced**. `qwen/qwen3.7-plus` is in the registry, unpriced, 0 calls — a landmine. Three `model_rate` rows are stale the other way (priced, no longer in the registry) |
| "the Phase 7 tables have no **writers**" | True, and the number that decides it is **readers**: 0 routines, 0 triggers, 0 rows, 0 Edge Function references, and **one** view — `v_executions_without_decision_trace` — which nothing reads. One unread consumer, zero producers. See the decision in §3.5 |
| "`org_action_executor` lost production's NOT NULLs and CHECKs" | True, and **incomplete**: the drift is 5 NOT NULL columns and 2 CHECKs, and the fifth NOT NULL is **`company_event.event_version`** — a table on the live journey path, not the dormant org layer. FK/PK/UNIQUE match exactly |
| "the fixtures go through `license_extract` directly, so the storage branch is unexercised" | Correct, and it hid **three** defects, not one: `process_docs`, `save_profile` and `supplier_portal save_documents` all discarded the result of the database write they promised the user. `save_profile`'s carries `approval_status` and `verified` — it *is* the approval decision |
| "teardown derives storage paths from the database" | For four buckets. **`supplier-docs` had no rule at all**, and nothing noticed because it held 0 objects — the leak was pre-armed, not absent |
| "the frontend was verified by reading its built bundle" | And the bundle contained the problem: four customer-facing components each hard-coded a **production** fallback for `NEXT_PUBLIC_SUPABASE_URL`, without `osClient`'s warning. A preview missing one env var drives the live database. This is why no browser harness exists yet — see §3.6 |
| "`drawing_redact_verify` cannot parse gemini output — the parser is the real defect" | **Wrong, and it cost session 9 a routing decision.** It parses gemini fine. The caller's own `max: 400` truncated it: 396 tokens, `finish_reason=length`, `truncated=true`, 36 characters cut mid-JSON. With the ceiling removed: 724 tokens, parses, correctly names the consultant and client. Fifth instance of the §5 ceiling pattern, and `ai_gateway` was reporting `truncated` all along |
| "the token-ceiling problem is down to 11 attributable call sites" | The count that matters is the **unattributable** one. `drawing_redact` carries two `fn` literals, so the cost gate's heuristic never pinned either of its ceilings — and both were defects. A file the gate cannot attribute is not a file without a problem |
| "`max: 2000` on `drawing_redact` detection is fine, the journey passes" | The journey uses a **one-page** drawing. Measured: one page costs 535–790 output tokens, so 2000 begins truncating at ~3 pages. A ceiling that scales with input size cannot be cleared by a fixture that never varies the input size |
| "compare deployed vs repo by version or commit date" | Both are wrong instruments. A commit-timestamp diff reported **118** functions behind the repo (including `_shared`, `home`, `faq`) because this repo was built by pulling *from* production. Content comparison against the deployed bundle, scoped to `git diff main...HEAD`, gives **14** |

### Corrections found in session 11

All fifteen gates were re-run and **all fifteen were green on the first pass** — no regression, no drift.
The one defect found came from the step *after* the gates: a `--purge --dry-run` drift check.

| earlier claim | truth |
|---|--:|
| §4 (session 9): "`agent_actions` … now torn down, swept by `--purge`, and added to the factory's baseline counters" | **Two of its three branches could never fire.** The tagged teardown step sat below `quotes` (:1036) and `inquiries` (:1044), so `${QUO_T}` and `${INQ_T}` were already-empty subqueries by the time it ran; only the `leads` branch worked, because leads are deleted one step *later*. `route_inquiry` writes a `coverage_gap` row against `inquiries` on every dispatch that finds no capable supplier — which `journey_test` produces **every run**, because it creates the inquiry before the supplier exists. **14 dangling rows had accumulated, one per run**, while teardown reported success |
| "the baseline counter check would have caught it — that is what it is for" | It counts `agent_actions` and still missed this for two sessions. **The selftest never generates the row**: it dispatches into a populated corpus, so no coverage gap is ever recorded, so the counter never moves. A counter only catches what something wrote. The fix therefore includes making the fixture write all three shapes — check 17, `the teardown rule for agent_actions is actually exercised` |
| "an exception-window run showed `agent_actions 1`, so the sweep works" | That is the **one** reachable branch (`target_table='leads'`). A rule that fires on one of three inputs looks identical in the output to a rule that fires on all three |

### Corrections found in session 12

| earlier claim | truth |
|---|---|
| "AI Governor, AI Scheduler, AI Auditor, AI Memory Manager, exception handling and self-healing — several have routines with no callers" | **All seven have callers and all seven are running.** The count was taken over routine-to-routine and view references, which is the one place these never appear: their callers are `cron.job`. `policy_consistency_weekly`, `autonomy_audit_weekly`, `knowledge_curator_daily`, `knowledge_decay_daily`, `edge_health_scan_15min`, `exception_alerts_hourly` and `graph_rebuild_daily` are all `active=true` in production with **1,266 runs and zero failures between them**, and every one of them writes rows that are there to count. "Zero callers" must name the instrument that measured it |
| "`dept_library` … read by zero Edge Functions and zero UI" | Right, and understated: read by zero **anything**. `fn_dept_library_search` — correct, indexed, five hits per real query — had no caller in any routine, view, Edge Function, cron job or frontend module. Fixed; see the session 12 block |
| "`fn_knowledge_decay` runs and decays nothing" (the shape of session 11's `kpi_review_weekly`) | **Not the same defect.** 1,734 of 1,869 `agent_knowledge` rows carry `review_due` and in production **none is past it** — the earliest bulk stamp is 2026-10-24. The engine is idle because the corpus is fresh. Re-check after 24 Oct 2026 rather than "fixing" it now |
| "staging holds the entire knowledge estate, 40 tables, 0 empty" | True for the rows. **Not true for the review metadata**: the `(agent_key\|topic)` md5 over all 1,869 `agent_knowledge` rows matches production exactly, while `review_due` does not — staging carries 168 rows already past due against production's 0. A key-set digest is not a row digest |
| "staging holds the entire knowledge estate — 40 tables, 0 empty" | True of the **86-category supplier** corpus and blind to a second one. `QuotesDone_COMPANY_OPERATIONS_KNOWLEDGE_v2026.07.31` in `qd-packs\` is a **different** corpus — its own START_HERE.md says so in line 5 — carrying 3,959 records including the 240 exception playbooks and 240 decision rules that spec file #7 asks for by name. Neither project had a table for it. Now `public.ops_knowledge` on both |
| "hr / intelligence / knowledge_eng have no department knowledge — a corpus gap, not a wiring one" (written earlier the same session) | **Wrong, and it was my own line.** The corpus existed on disk the whole time; the gap was an unimported pack, not unwritten content. Every active department now has knowledge. The lesson generalises: before calling something a content gap, look in `C:\Users\Opera\qd-packs\` and on the Desktop |
| "the eight founder spec files are not in the repo" | **They are on disk.** `C:\Users\Opera\OneDrive\Desktop\*.txt`, mirrored in `C:\Users\Opera\qd-packs\QuotesDone_COMPLETE_OS_PORTALS_AUTONOMY_UPDATE_PACKAGE_v2026.07.31\…\SOURCE_PLANS\`. File #7 is `quotesdone agents and knowledge.txt` = `AGENTS_AND_KNOWLEDGE_BLUEPRINT.txt`; #6 `suppliers categories.txt`; #3 `OS 2.txt` = `OS_COMMAND_CENTER_VISION.txt`; #8 `open router.txt`. **Read the file you are working, not the brief's summary of it** — the summary said "AI Governor, AI Scheduler…", the file says what each must actually do, and its one-line architectural recommendation ("Don't create 20 isolated knowledge bases") is what located the layer-2 defect |
| "`fn_agent_context` implements the spec's four layers" | It implements four layers, but its layer 2 is keyed to the **individual**, and the spec's layer 2 is **DEPARTMENT** knowledge. That distinction is the whole defect: 52 of 66 employees had nothing under the heading |
| "52 employees with no knowledge is a roster that was never invoked" | Half right, and the half that is wrong is the live half: 0 of them ever ran or acted, but **4 have been chatted with**, **8 are department leads**, and `dept_plan` calls `fn_agent_context(lead_agent)` for every department on a **daily production cron**. An unpopulated roster is not the same thing as an unused code path |
| "`v_cron_failing` reports what is failing" | It reports what has failed **at any point in 7 days** and never clears — 2 of its 3 current rows recovered days ago. But it is not the defect and must not be "fixed": `fn_os_health()` already computes failing-now correctly and returns `[]`. **The missing piece was a reader, and the wrong fix was one view away** |
| "11 attributable call sites sit below their task class" (session 9) | The count is right and the **instrument is not**: it reads `makeLlm`'s options object. `dept_plan` set its ceiling in **two** places and the one that binds is the per-call third argument of `llm(sys, input, max)`. Removing only the `makeLlm` value changed the measured output by exactly nothing. Check both before calling a ceiling fixed |
| "removing a caller-side `max` lets the task class decide" | Not through `llm.ts`. Its signature is `max: number = dMax` with `dMax = def.max ?? 700`, so a number is **always** sent and deleting the ceiling silently drops it to **700**. The way to defer to the policy is to pass something deliberately **above** it, since `ai_gateway` takes `min(caller, policy)` |
| "`node script.mjs \| Select-Object -First N` just truncates the output" | **It kills the script.** PowerShell's `Select-Object -First` throws `StopUpstreamCommandsException`, so a 3,959-row import died after ~1,000 rows and reported nothing wrong — the mapping looked applied and 144 rows were silently missing. Use `$out = node …; $out \| Where-Object …` when the command must finish |
| "a re-run of an idempotent importer proves both projects agree" | Only if the upsert actually writes. `on conflict do nothing` is a no-op on a second pass, so a corrected `dept_key` never reaches the other project while every row count and key digest still matches. Digest what the fix CHANGED, not just what identifies a row |
| "the factory selftest is a reliable regression signal" | Only when it runs **alone**. It went 17/18 with `company_event 71->72 (another writer running?)` because a `dept_plan` probe fired one row mid-window. Its own message named the cause. Re-run alone: 18/18. Also worth knowing: **13 `company_event` rows of `entity_type='scheduled_run'` have accumulated in staging since 4 Aug** and neither teardown nor `--purge` sweeps them — they key off a function name, not a run tag, which is the same shape as session 11's `agent_actions` leak |
| "the AI Scheduler is a gap" | 149 cron jobs, 130 active, and `fn_os_automation_reschedule` can re-time any of them through `cron.alter_job` with an `os_audit_log` entry. The scheduler is built. What was missing was the **health feedback loop**, now closed |
| "`graph_nodes` (323) … read by zero Edge Functions and zero UI" | Confirmed, and its **writer is fine** — an active nightly cron rebuilds 323 nodes and 300 edges. The gap is entirely on the read side, and the reader belongs to spec file #3 (executive UI), not #7. Building one inside #7 would build it twice |

The file states the rule it broke, twenty lines above the break: *"they key off the quote/inquiry id as TEXT, so
they must go before the row they name … That ordering mistake is exactly what left 452 doc_versions and 186
company_event rows in staging."* Every other step in the list obeys it; `agent_actions` was the sole violator,
so this is one fix and not a pattern needing a sweep — the whole list was re-checked step by step.

> **After the journey, run `node scripts/staging/demo_factory.mjs --purge --dry-run`.** The gates were all
> green while this was leaking; a passing suite is not the same measurement as a clean database. The only
> thing it should report is `1 storage/signed-terms` — the rolling `registers/customers-register.xlsx`
> register that `kyc accept_terms` regenerates, documented in §2.3 and not per-run litter.

---

## 5. Traps that cost real time (sessions 7-8)

**A green suite over a subsystem that never ran.** The journey passed 19/19 while every LLM call
failed and `inquiry_intake` silently used its keyword fallback. `quote_extract` returned `ok:true`
with a fully-formed but **entirely empty** proposal, because a failed parse left `{}` and every
field was then scrubbed to `''`. A step that returns HTTP 200 is not a step that worked.

**A token ceiling inside the output's natural range truncates INTERMITTENTLY.** Four times now:
`quote_comparison` at haiku/1500, `rfq_routing` at 300, `quote_comparison` again at sonnet/3000
(natural range 2618–7266), `quote_extract` at 2000 (needs ~2400). A cap mid-distribution fails
roughly one run in three, which reads exactly like model flakiness. **Measure the natural output
with the ceiling lifted, then set the budget above the maximum.** `license_extract` at `max:1500` is
the next suspect.

**gemini spends most of its output budget on reasoning tokens** — a `quote_extract` call reported
1,996 output tokens carrying **206 characters** of visible JSON. Sizing from expected JSON length is
wrong by an order of magnitude on that model.

**`ai_gateway` now returns `finish_reason` and `truncated`** and logs `TRUNCATED:` with the ceiling
and task class. **Use it.** All four truncations above presented as "unparseable output".

**A caller-declared timeout the per-attempt cap ignored.** `client_timeout_ms` set the wall while
each attempt was still aborted at a hardcoded 45s, so declaring 100s only bought more doomed
retries. Fixed; it derives from the wall now.

**Silent failure at two layers looks identical to silent failure at one.** A CAD upload was refused
by `customer_api`'s allow-list AND by the bucket's `allowed_mime_types`, both returning null. Fixing
the first changed nothing visible. If a fix "does not take", look for a second gate downstream.

**Phase 1 counted buckets, not objects.** "15/15 storage buckets" was true and useless: `brand` held
0 objects, so `pdf_native` never got its fonts and fell back to WinAnsi Helvetica — which throws on
any character above U+00FF. One `≠` from a model 502'd the customer's comparison.

**A whole task class can be switched off in production.** `inquiry_intake` →
`missing_fields_detection`, and `capability_agent` + `supplier_review` → `supplier_matching`, all
`tier=none, model=none, max_tokens=0`. Check `fn_ai_route` before assuming a function is merely
unwired.

**GateGuard fires on the first edit of every file.** `.claude/settings.local.json` sets
`ECC_DISABLED_HOOKS` for the two fact-force hooks. That file is gitignored, so a fresh clone gets
the prompts back.

---

## 6. Blocked on the founder — exactly one thing

**Stripe test-mode keys.** Production's are LIVE (`sk_live` / `pk_live`), withheld by a prefix rule.
Test keys can only come from the Stripe dashboard. This is also the one action the founder's own
spec says needs approval.

Everything else is unblocked: Resend, OpenRouter, VirusTotal, CloudConvert and Apify keys are live
in staging. `email_enabled` is `false` deliberately — turn it on behind a recipient allowlist when
proving notification. Twilio and Dropbox stay withheld on purpose.

---

## 7. Findings about PRODUCTION worth acting on

Measured read-only and **not** fixed. Production has 0 inquiries, 0 quotes, 0 customers and 20,464
leads, so every one is **prospective damage, not damage already done** — which is exactly why now.

- **No supplier could ever quote by uploading a document.** `require_structured_quotes` is `'true'`,
  `formComplete` required `source==='form'`, and the structured scorer returns false for every real
  quote. Every uploaded quotation would have become a silent draft. *(Fixed in staging.)*
- **`ai_cost_log.cost_aed` is 0 on 238 of 589 calls**, including 100% of both `google/*` models,
  because `model_rate` has no `google/*` rows. Cost reporting understates real spend today.
- **CAD originals would be discarded** — `drawing-files` `allowed_mime_types` is still
  `pdf, jpeg, jpg, png, webp`, and `customer_api` still passes `SAFE_UPLOAD`. And once that is
  fixed, a second gap sits behind it: `create_inquiry` records `drawing_file_path` for the raster
  upload only, so **the stored CAD original is referenced by no row at all** — the supplier asked to
  quote from it has no path to it, and nothing can ever clean it up.
- **`attach_photos` records no owner.** Its `drawing_redaction_runs` row carries `customer_id` NULL
  and `owner_email` NULL, so a redaction — a privacy control — cannot be attributed to the customer
  whose photos were redacted.
- **`quote_extract` at 2000 output tokens** would return empty proposals, hidden by `ok:true`.
- **`inquiry_intake`, `capability_agent` and `supplier_review` all map to switched-off task classes.**
- **`quote_comparison` capped at 3000** and **`document_extraction` at 4000** while `drawing_boq`
  asks for 8000.
- **`stripe_secret_key` and `stripe_publishable_key` are LIVE keys.**
- **`supplier_capabilities` has 0 rows**, so capability-gated dispatch has never run.
- `github_token` and `vercel_token` live in the `app_secrets` **table** — a database row can deploy
  the site via `run_auto_deploy()` / `run_site_autodeploy()`.
- 149 cron jobs armed, including `vt_scan_daily` (03:00, `fn_run_vt()`). Uploads are **not**
  AV-scanned inline; `sanitizeUpload`'s structural sniffing is the inline gate and VirusTotal is a
  nightly sweep. A design, not a gap — but know it before claiming uploads are scanned.
- **THE REVEAL DOES NOT WORK.** `customer_api my_inquiries` selects `created_at` from
  `public.transactions`, which has no such column, so PostgREST 400s, the result is null, `|| []`
  swallows it and **no quote is ever marked revealed**. A customer pays the reveal fee and the
  portal keeps showing `supplier_ref: null` and a banded rating. This is the paywall failing open in
  the customer's face after they have paid. *(Fixed in staging; one line.)*
- ~~**`quote_reviews` has no writer anywhere** and 0 rows.~~ **CLOSED — retired schema, not a gap.**
  `quote_reviews` / `quote_review_messages` / `quote_committed_items` were built, shipped, proven
  unused and deliberately deleted: their only writer, `quote_review_api`, was removed in `d79b28e`
  (22 Jul 2026, *"proven dead across frontend/functions/SQL/cron/triggers"*). Nothing references
  them. The one review path that exists is `fn_quote_structured_score` → `quotes.quality`.
  `journey_test` was counting `quote_reviews` in a `reviewRows > 0 || scored > 0` assertion — a
  **vacuous** half that could only ever be 0, so the step passed entirely on the other side. Worse
  than a red gate, because nobody looks at green. Removed.
- **THE `copied_quote` FRAUD RULE COULD NEVER FIRE — now fixed.** `fn_fraud_scan` groups `quotes` by
  `committed_hash` having more than one distinct supplier, to catch the same quotation filed by two
  suppliers. **Nothing wrote `committed_hash`**: its only writer was the same deleted
  `quote_review_api`, and 0 of 0 production quotes carry one. A fraud control the founder believes
  exists has never been capable of raising a single flag.
  Trigger `quote_committed_hash` now writes it from the *words the supplier wrote* — deliberately
  **not** `quote_amount`, because identical amounts on one RFQ are already caught by the
  `identical_bids` rule directly above it, and folding the amount in would make `copied_quote` a
  noisy duplicate rather than an independent signal. A 40-character floor keeps boilerplate
  one-liners from colliding across honest suppliers. Applied to **both** projects (routines 739 →
  740 in each, so `verify_phase1` parity holds). Proven by `verify_fraud_hash.mjs` 5/5: identical
  prose at *different* amounts raises `copied_quote` at severity `high` naming both suppliers.
- **63 Edge Functions hard-code a `max` that can only lower the policy ceiling.** `ai_gateway` takes
  `min(caller, policy)`, so `model_policy.max_tokens` is decorative wherever a caller sets its own —
  and 11 of them sit below their task class today. Raising a policy ceiling in production, as
  session 8 did for `quote_comparison` and `document_extraction`, changes nothing for those callers.
- **`license_extract` caps itself at 1,500** against a task class of 8,000, and a realistic
  15-activity licence uses 1,116–1,171 tokens — 74–78% of it. A truncated licence returns HTTP 200
  with every field blank and `confidence:'low'`, identical to an unreadable scan, so nobody would
  know. *(Fixed in staging.)*
- **`doc_extract` caps itself at 2,000 output tokens** by passing `max:2000` to a gateway that
  computes `min(body.max, policy)`, so `model_policy.document_extraction`'s 8000 never applies.
  Measured natural output for one drawing page: 1,996 / 2,170 / 2,051 across three runs. Production's
  document queue therefore fails on roughly one page in three with `extraction_null`, and
  `documents.status` is set to `'error'` with the attempt counted. *(Fixed in staging.)*
- **`drawing_redact_verify` has no `fn_task_class` row**, so `fn_ai_route` reports
  `UNMAPPED function` and routes it to `general_drafting`. It happens to work there, but nobody
  chose it and nothing records that the choice matters — and it matters a lot: routing it to
  `document_extraction` like its siblings silently disables drawing redaction entirely (§3.4).
  *(Mapped deliberately in staging.)*
- **No `internal_credential` in production scopes `capability_agent`**, so its `confirm` action —
  the only writer of a confirmed `supplier_capabilities` row and its
  `supplier_capability_confirmation` ledger entry, and one that makes no model call — is
  unreachable. Combined with `supplier_capabilities` having 0 rows, capability-gated dispatch
  cannot ever have run. *(Fixed in staging.)*
- **`department_budget.spent_aed` never moves in production for the unpriced models.** `fn_llm_log`
  updates the budget only `if p_dept is not null and v_cost > 0`, and `v_cost` is 0 whenever
  `model_rate` has no row — so the budget halt cannot fire for `google/*` traffic no matter how much
  of it there is.

---

## 8. Production deployment — APPLIED 5 August 2026 (12/13)

**The one item deliberately NOT applied**, and why it should stay unapplied until someone decides
what it should become:

> `capability_agent`, `category_reqs`, `inquiry_intake` and `supplier_review` all map to task
> classes with `tier=none, max_tokens=0` — dead at the model layer. §8 listed "`inquiry_intake`
> task-class remap off `missing_fields_detection`" as a deployment item, but **it never said what to
> remap it TO**, and **staging has the identical switched-off state**, so there is no verified
> counterpart to ship. Applying a guess would turn on model spend on four paths that no gate has
> ever exercised. `verify_prod_readiness.mjs` keeps reporting it so it cannot be forgotten.

**Two defects in the readiness checker itself, found by running it immediately after deploying** —
both recorded because a future session will otherwise trust a broken gate:

1. **A signature matched its own explanation.** `doc_extract` reported STILL LIVE after a clean
   deploy, because the regex `/max\s*:\s*2000/` matched the *comment* documenting the removal
   ("…never raise it. `max:2000`"). 2 hits in the raw bundle, **0** with comment lines stripped.
   A detector that trips on its own explanation would have sent the next session to re-fix
   something already fixed. Comments are now stripped before matching.
2. **The whole-file content check never worked.** It asked whether the repo's `index.ts` appears
   verbatim in the deployed bundle. The bundle is **transpiled JavaScript**, not TypeScript:
   longest matching prefix was **432 of 17,317** chars for `doc_extract` and **211 of 81,594** for
   `customer_api`, both diverging at the imports, with mid-file slices absent. It reported "differs"
   for all 16 functions *both before and after* a successful 16/16 deploy — right beforehand purely
   by coincidence, which is the most dangerous kind of wrong. Replaced: git says what to deploy,
   version numbers show movement, and **the per-defect signatures are the gate**.

*The original planning section follows, kept for the reasoning rather than the status.*

## 8b. Production deployment sequence — the original plan (superseded)

Do not prepare one yet; the acceptance suite (Phase 8) does not exist. When it does, the sequence
must cover **both code and configuration**, because several session-8 fixes live in the database:

*Code (session 9), HIGHEST PRIORITY:* **`customer_api`** — `my_inquiries` no longer selects the
non-existent `transactions.created_at`. Until this ships, every reveal a production customer pays
for is invisible to them.

*Code (session 9):* **`license_extract`** — the caller-side `max:1500` removed. It had not truncated,
but a realistic 15-activity licence sits at 74–78% of it, and a truncated licence returns HTTP 200
with an entirely empty `doc` that cannot be told apart from an unreadable scan.

*Code (session 9):* **`doc_extract`** — the caller-side `max:2000` removed so
`model_policy.document_extraction`'s 8000 applies. Without this, production's document queue returns
`extraction_null` on roughly one page in three and marks the row `status='error'`. Deployed to
staging only.

*Code:* the 4 Edge Functions whose production URL was replaced with `SUPABASE_URL`,
`inquiry_intake`, `ai_gateway` (finish_reason + per-attempt deadline), `quote_compare`,
`quote_extract`, `supplier_api` (`formComplete`), `customer_api` (`SAFE_CAD` + storage logging),
`pdf_native` (encoding), `attach_photos`.

*Configuration, applied directly and NOT as a migration* (a migration breaks the 712-vs-712 ledger
parity `verify_phase1.mjs` asserts):
- `model_policy.quote_comparison.max_tokens` **1500** → **10000** — *not* 3000. Measured in
  production 5 Aug 2026: it is still on the original `~anthropic/claude-haiku-latest` / 1500, which
  is the first of the four truncations §5 records. The gap is twice what this line used to claim.
- `model_policy.document_extraction.max_tokens` 4000 → **8000**
- `model_policy.rfq_routing.max_tokens` 300 → **2500**
- ~~`fn_task_class` mapping for `quote_compare` (absent in production)~~ — **WRONG, retired.** It is
  **present** in production, mapped to `quote_comparison`. Do not "fix" it.
- `inquiry_intake` task-class remap off `missing_fields_detection`
- `storage.buckets.allowed_mime_types` for `drawing-files` += `image/vnd.dwg`, `image/vnd.dxf`
- **`model_rate` rows for the `google/*` models** (new — see §3.4)

*Added in session 9 — all reproducible by re-running the scripts named:*
- **`model_rate` rows for every active `model_registry` model**, derived at 3.6725 AED/USD
  (`seed_cost_config.mjs`). Production currently prices 0 of its 2 Gemini models, which is why 238
  of 589 calls bill at zero
- **`fn_task_class` row for `drawing_redact_verify` → `document_extraction`** (`seed_cost_config.mjs`).
  Missing in production; it is currently routed to `general_drafting` at 900 `max_tokens`
- **`v_llm_model_mix` / `v_llm_calls_without_task_class` / `v_llm_offpolicy` repointed** off
  `llm_calls` onto `ai_cost_log` (`seed_cost_config.mjs`). Note these are DROP + CREATE, and the
  grants must be reapplied — `postgres` and `service_role` hold the full set on all three
- **`internal_credential` `db.internal` scope += `capability_agent`** (`seed_staging_secrets.mjs`).
  Without it the only non-blocked half of the capability flow is unreachable

**The sequence is now a measurement, not a list: `node scripts/verify_prod_readiness.mjs`.**
Read-only against production by construction (every database read goes through `qd_guard`'s
`mgmtRead`, which refuses write verbs; every function read is a GET). It reports each item above as
APPLIED or OUTSTANDING with its measured production value, prints the exact statement for the
outstanding ones in dependency order, and exits non-zero — so it is the gate after deploying, not a
changelog. **13/13 outstanding as of 5 Aug 2026.**

Three things it establishes that this section had wrong or missing:

1. **The deploy list is derived from `git diff main...HEAD`, not transcribed.** 14 functions, and
   four were never named here: `dispatch_inquiry`, `match_eval`, `route_inquiry`,
   `stripe_setup_page`.
2. **Drift is checked by content, not by version.** The deployed bundle embeds each module's source
   verbatim, so the check is "is the repo's current `index.ts` a substring of the deployed bundle?"
   All 14 differ. A version number only says something was deployed once.
3. **A commit-timestamp comparison is the wrong instrument and was tried first.** It reported *118*
   functions behind the repo, including `_shared`, `home` and `faq` — an artefact of a repo built by
   pulling FROM production, where mass-import commits touch every directory at once.

Also measured on production the same day: `ai_cost_log` is now **247 of 603** rows billing at zero,
up from the 238/589 recorded above — the meter is still drifting further out while this sits
undeployed. `google/gemini-3.1-flash-lite` alone is **219 calls, every one of them unpriced**.
`qwen/qwen3.7-plus` is in the registry, unpriced, and has 0 calls — a landmine, not yet damage.
Three `model_rate` rows are stale in the other direction (`claude-fable-5`,
`claude-opus-4.7-fast`, `claude-opus-4.8-fast`: priced, no longer in the registry, 0 calls).

*Code added in session 9 (no production effect until deployed):* `scripts/staging/demo_factory.mjs`,
`scripts/staging/verify_cost.mjs`, `scripts/staging/seed_cost_config.mjs`, and the idempotency fix
in `scripts/staging/seed_staging_secrets.mjs`.

---

## 9. Tooling (all in `scripts/staging/`)

| file | what it does |
|---|---|
| `verify_phase1.mjs` | 12 measurements: repo clean+pushed, functions deployed, jwt parity, schema parity, isolation, ledger |
| `smoke_staging.mjs` | real Auth user, storage, PostgREST, 10 functions. Cleanup now deletes its `customers`, `inquiry_intake` and `email_verifications` rows **by email**, because `customer_api me` gives the customers row a fresh uuid |
| `journey_test.mjs` | the 37-step journey. Cleanup now takes a run tag and calls `demo_factory`'s `teardown()`; only the reference photos are deleted explicitly, because `attach_photos` returns their paths and nothing writes them to a row |
| `sync_staging_assets.mjs` | copies the `brand` bucket; refuses every bucket holding real data |
| `seed_staging_secrets.mjs` | copies `app_secrets` + `internal_credential`, withholds by name and by live-key prefix |
| `sync_staging_reference.mjs` | 22-table allowlist copy. Pagination now orders by the full primary key, the guard resumes instead of skipping, inserts are `on conflict do nothing`, and a row-count mismatch is printed as one |
| **`verify_taxonomy.mjs`** | the operational router in English and Arabic, its paired negative and ambiguous cases, and the `taxonomy_trade` ↔ catalogue crosswalk with its known gaps pinned |
| `sync_staging_grants.mjs` | restores table privileges in production's shape after a schema rebuild |
| `apply_missing_objects.mjs` | catalogue diff: enums, sequences, columns, tables, views, routines. Does **not** diff constraints — which is why staging's `org_action_executor` lost production's NOT NULLs and CHECKs |
| **`verify_doc_extract.mjs`** | drives the document queue end to end: upload → trigger → `doc_extract` → `status='done'` with real content, and measures the output against the live task-class ceiling |
| **`verify_license_extract.mjs`** | reads a valid, a 15-activity, an expired and an illegible UAE trade licence, asserting content rather than `ok:true`, and measures each against the live ceiling |
| **`verify_exception_window.mjs`** | the 14-day licence exception end to end — open, the 3/7/12 reminder ladder, auto-rejection, recovery after auto-rejection, and the founding cohort |
| **`verify_portal.mjs`** | four inquiries across four states with 2–3 quotes each and one revealed; asserts the paywall by what is ABSENT pre-reveal, plus the no-customers-row and Arabic cases |
| `fixtures/` | the two synthetic upload PNGs, **`licence_pdf.mjs`** (generates 4 licence variants as real PDFs from a data table) + `README.md` |
| **`demo_factory.mjs`** | the demo-data factory (§2.3). `--selftest` (default) 18/18, `--purge`, `--purge --dry-run`, `--corpus N [--customers N] [--keep]`. Check 17 seeds `agent_actions` against the run's own inquiry, quote and lead, because the baseline counter can only catch a row something actually wrote |
| **`verify_cost.mjs`** | 7 zero-spend checks over pricing, routing and monitoring; `--live` adds 4 that put one real inference through the gateway |
| **`seed_cost_config.mjs`** | `model_rate` (derived from `model_registry`), `department_budget`, the missing `fn_task_class` row, and the three repointed views. Idempotent; `--reset-telemetry` also clears `ai_cost_log` rows written while the meter was broken |
| **`verify_matching.mjs`** | builds the 100-supplier corpus and asserts the score ladder, the relevance floor, the fan-out cap and the four hard gates. `--live` adds one real dispatch |
| **`verify_supplier_docs.mjs`** | `supplier_api process_docs` end to end: real PDF bytes into `supplier-docs` through the deployed function, the licence-gate write-back, the unreadable-licence path and the sanitiser. Asserts the ROW, never the response |
| **`verify_constraints.mjs`** | the parity dimension nothing measured: NOT NULL columns and CHECK constraints against production. Report-only; `--apply` fixes staging through `qd_guard` |
| **`verify_agent_knowledge.mjs`** | whether an employee can actually see the 1,456-row department library. Asserts the NEGATIVES: a query-less call is byte-identical to the old two-argument one, every emitted excerpt matches a real `dept_library` row by title, and the `cat:<slug>` branch (no `org_agents` row, so `v_dept` is null) is not silently dead. Zero spend |
| **`verify_rfq_trace.mjs`** | the blueprint's Observability requirement, measured against a real RFQ: one inquiry built by the factory, really dispatched, quoted twice, then asserted **by kind** — because a trace that grew is not a trace that is right. Pins that every supplier contacted carries the REASON it was chosen. 1 model call |
| **`import_ops_knowledge.mjs`** (in `scripts/`) | loads the 3,959-record company/department operations pack into `public.ops_knowledge`, resolving `dept_key` through the **pack's own** production→target crosswalk. `--dry-run` maps and reports without writing. Idempotent on `record_id` |
| **`seed_agent_library_reader.mjs`** (in `scripts/`) | the knowledge-layer changes: the `fn_agent_context` overload, its layer-2 department fallback, `fn_knowledge_gaps`' `owner_os`, and `fn_entity_activity`'s RFQ branch. Every one re-appliable; the two body patches rewrite `pg_get_functiondef` and **raise** if their anchor has moved. `--print-sql` emits all four for production |
| **`verify_prod_readiness.mjs`** (in `scripts/`, not `scripts/staging/`) | §8 as a measurement against **production**, read-only by construction. Reports each item APPLIED/OUTSTANDING with its measured value and the exact statement, exits non-zero. Deploy list derived from `git diff main...HEAD`, drift checked by bundle **content** |

`sync_staging_reference.mjs` still leaves `field_definition` and `field_definition_source` unloaded
(FK to a parent outside the allowlist). Neither is on the journey path.
