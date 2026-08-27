# The eight spec files, measured — 27 August 2026

Every number below was produced by running the scorer named beside it against
`htdblwldjkcgjvmqkbeh`, read-only, in this session. Nothing here is carried over from a brief.

| # | Spec | Scorer | Score | Classified |
|---|------|--------|-------|------------|
| 1 | Company architecture | `verify_spec_architecture.mjs` | **44/48** (92%) | yes — `SPEC1_MISSING_CLASSIFICATION.csv` |
| 2 | Universal OS blueprint | `verify_os_blueprint.mjs` | **54/110** (49%), was 45, 1 unmeasured | no |
| 3 | Executive UI | `verify_os2_blueprint.mjs` | **111/152** (73%), was 104 | yes — `SPEC3_MISSING_CLASSIFICATION.csv` |
| 4 | Customer portal | `verify_portal_blueprint.mjs` | **140/147** (95%), 5 unmeasured | yes — `SPEC4_MISSING_CLASSIFICATION.csv` |
| 5 | Supplier portal | `verify_supplier_blueprint.mjs` | **224/234** (96%) | yes — `SPEC5_MISSING_CLASSIFICATION.csv` |
| 6 | Supplier categories and their agents | `verify_category_agents.mjs` | **249/283** (88%) | no |
| 7 | Agents and knowledge | *(no single scorer — see below)* | not measured | no |
| 8 | OpenRouter cost optimization | `verify_ai_router.mjs` | **208/226** (92%) | no |

## Spec file #7 has no scorer, and the one that looks like it cannot run

`docs/specs_row7_agents_and_knowledge.txt` exists. No script prints a `SPEC FILE #7` banner, and
none of the eight scorers above covers it. The closest instrument,
`scripts/staging/verify_os_knowledge_cluster.mjs`, **dies on production**: it reaches line 140,
calls `mgmtWrite`, and `qd_guard`'s `assertNotProduction` refuses it —

```
ProductionRefusal: REFUSED: write targeted production (htdblwldjkcgjvmqkbeh). Batch 0 forbids this.
    at verify_os_knowledge_cluster.mjs:140
```

It was written against staging, and staging was deleted on 15 August 2026 at the founder's
instruction. It got through ten checks and stopped. Until it is rewritten as a read-only probe (or
as an aborted-transaction probe, which is the pattern this repository already uses for exactly
this), spec file #7 has no measurement at all and any number claimed for it would be invented.

## Checks that did not return

Nine requirements across two files came back as transport or statement timeouts, not verdicts:

* spec #2 — `comp-16-risk`, `comp-16-performance`, `comp-16-backlog`, `comp-16-quality`,
  `comp-16-cost`, `comp-16-automation`, `os-exclusive-ownership`
* spec #4 — `spatial-live-shipment-status`, `pred-future-requirement`, `pred-time-window`,
  `pred-recommended-action`, `pred-customer-ui`

An errored check is an **unmeasured requirement**, not a MISSING one. The cause in spec #2 was
diagnosed and partly repaired on 27 Aug (see `os_blueprint/components_14_17.mjs`): liveness was a
correlated predicate that rendered all 1,291 public routine sources per candidate. It is now an
uncorrelated name list computed once. `comp-16-health-score` still exceeds the budget; the
remaining cost has not been isolated. Spec #4's five share a customer-routine closure with the same
shape and have not been touched.

## What the red actually is

Across the four files classified so far — #1 (4 red), #3 (48), #4 (7), #5 (10) — all 69 rows,
counted from the CSVs themselves:

* **43 STALE_UNDER_HOLD.** The founder's stand-down of 16 August paused 183 of 206 cron jobs. Every
  one of these lines is a paused clock or a freshness bound behind one. None was activated.
* **10 GENUINELY_ABSENT.** The build list. Five of the six in spec #3 were built this session, and
  the sixth — the DB leg of `employee-knowledge-used` — was deliberately not, because closing it
  would have meant writing a knowledge-usage row for a retrieval that did not happen. Spec #5's
  four are not built.
* **6 CHECK_IS_WRONG.** Instruments reporting on the wrong subject. All six are in spec #3 and all
  six were fixed and re-measured this session.
* **5 UNMEASURED.** Spec #4's shared closure timeout. Not verdicts.
* **4 NO_SUBJECT_TO_MEASURE.** 0 customers, 0 inquiries, 0 quotes, AED 0 revenue, ever.
* **1 FOUNDER_ACCEPTED.** The portal sidebar, approved 13 August.

Spec #2's 58 red lines and 7 unmeasured, spec #6's 34 and spec #8's 18 are **not** in that count.
They are measured and unclassified.

## What actually fixed comp-16, and what did not

The first attempt replaced the correlated liveness predicate with an uncorrelated name list. It did
not stop the timeouts and it MADE ONE WORSE: `comp-16-capacity` had been returning a real verdict
and came back "transport failed after 7 attempts" instead. Trading a measured requirement for an
unmeasured one to chase six others is a net loss, so it was reverted.

What was kept is the correctness half — `RAN` resolves the cron command through
`phase_c_system_execution_wrapper`, so liveness can see the twenty-two active jobs whose command is
`select public.fn_kernel_cron_exec(<jobid>)` and names no routine at all.

With that, and with the machine no longer running a scorer chain and hand queries against the same
management API at the same time, **all ten comp-16 checks complete with zero errors**:

```
MET     comp-16-risk, performance, backlog, quality, cost, automation, fn-os-health
MISSING comp-16-health-score-column, comp-16-health-score, comp-16-capacity
        7 of 10 on the comp-16 section alone
```

So six of the seven spec #2 requirements recorded as UNMEASURED above are now measured, and all six
of those are MET. The lesson is one this repository keeps relearning: a timeout is not a verdict,
and the first explanation for a timeout — here, an expensive query shape — was not the whole cause.
Concurrent load on the same management API was part of it, which is exactly why the session skill
says not to run two scorers against the same project at once.

`os-exclusive-ownership` in spec #2 and the five spec #4 checks (`spatial-live-shipment-status` and
the four `pred-*`) share a different closure and have not been re-measured.

## Spec file #2, re-measured end to end after the revert

`54/110`, up from `45/110`, with **one** errored check instead of seven. Nine lines turned green
and none turned red:

```
comp-14-can-decide          comp-16-backlog        comp-16-performance
comp-15-who-approves        comp-16-cost           comp-16-quality
comp-16-automation          comp-16-fn-os-health   comp-16-risk
```

Seven of the nine are comp-16 lines that were previously timing out. The other two —
`comp-14-can-decide` and `comp-15-who-approves` — are not in that section at all. They turned green
because their liveness clauses can now see the running crons through
`phase_c_system_execution_wrapper`, which is the same defect that cost spec #3 four lines. That is
the strongest evidence that the wrapper blindness is estate-wide and not a spec #3 curiosity: it was
suppressing two unrelated requirements in a different file, in a different section, written by a
different hand.

`os-exclusive-ownership` is the one remaining unmeasured check in spec #2.
