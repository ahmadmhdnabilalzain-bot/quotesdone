# 12 Aug 2026, part 3 — the company assigned its work to nobody

Third and final segment. PRs [#257](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/257), [#258](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/258), [#259](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/259) merged. Both projects, every change verified by execution.

---

## Row #3 is confirmed back at 127/152

Not inferred this time — a full scorer run. The re-score after part 2 had come out **126**, and the regression was mine: I created the `kb_embed_priority_kinds` cron and never added it to `cron_registry`, so `s38-manual-always-current` went MET → MISSING with *"1 active cron job(s) are undocumented"*. Registered on both projects; the check's own predicate now reads 0 undocumented / 0 documented-but-gone, and the full re-run confirms **127/152**.

The lesson is in the commit because it generalises: **every `cron.schedule` needs a `cron_registry` row in the same change.** I applied it to the next cron I added an hour later.

---

## Pulling the `employee-performance` thread to the floor

`employee-performance` and `employee-current-thoughts` are MISSING on Row #3. Neither is a UI defect — both fail on **coverage**, and the coverage number turned out to be the session's largest finding.

**First layer — reputation was inventing a score.** 93 active employees, 75 with no `agent_runs` row ever, 76 that have never cost a fils. Yet 93 had a KPI and 93 had a reputation. `fn_reputation_recompute` computes `coalesce(corr,50)*0.30 + …`, so no evidence scores exactly **50** — and `standard` is `>= 50`.

```
before:   trusted  11  avg 76.2    0 never ran
          standard 82  avg 51.0   75 never ran, 76 never spent
```

50 is not neutral. It is the exact boundary of `standard`, so zero evidence landed one point above probation, indistinguishable from a real 50 — `least(100, NULL)` at organisational scale. It also made the probation gate **unreachable** for idle employees, and let the recovery branch treat "never worked" as "recovered".

Absence of evidence now has its own name: tier **`unmeasured`**, score **NULL**.

```
after:    unmeasured 57 (no score) · standard 22 avg 61.6 · trusted 8 avg 78.0
          senior_trusted 3 avg 88.8 · probation 3 avg 37.5
```

One autonomous grant gated (143 → 142), and not by the new tier — `analytics_director` has reliability **0.0**, meaning every run it ever made errored. Those three would have hit probation on the next scheduled run anyway; today's outcome grading is what made their dimensions computable at all.

**Second layer — and this is the one that matters.** `org_tasks.assigned_agent` **has no writer anywhere**: not in the 41 SQL routines that touch `org_tasks`, not in `supabase/functions`, not in `src`.

| status | tasks | `assigned_agent` NULL |
|---|---|---|
| assigned | 339 | **339 — 100%** |
| total | 922 | 779 (85%) |

339 tasks carry a status that says *assigned* and not one names an employee. And the schema was **built** for this — `org_agents` has `department`, `manager_key`, `seniority`, `max_open_tasks`, `available`, `unavailable_until`, `routing_tier`. A complete assignment and capacity model with nothing writing the one column that uses it. That is why 75 employees have no runs, why 57 came out unmeasured, and why both Row #3 employee checks fail. **An employee with no work has no performance to show.**

`fn_org_task_assign` picks the least-loaded available employee in the task's own department, treats `max_open_tasks` as a hard ceiling, and leaves a task unowned rather than overloading anyone. Probation employees rank last but still receive work — starving them is how they would stay on probation forever. Measured on production: **92 assigned, 0 over ceiling, employees holding open work 5 → 33.**

**The 267 left unowned are the point, not a shortfall.** The run note now names the departments generating more work than they staff:

```
exec 82/28 · procurement 32/47 · knowledge 29/21 · sales 22/15 · marketing 21/29 · finance 16/25
```

`exec` generates three times the work it employs people to do. That is a hiring signal, and it is in the note rather than a silent counter.

---

## A correction to my own part-2 reasoning

I reported 1,870 `employee_task` steps skipped with 0 done as a stalled loop. It is not. Reading the skip payload: *"the owning task was performed and reviewed as one act; this step was never separately observed, so it is skipped rather than claimed as done."* That is deliberate, honest bookkeeping — the real work unit is `org_tasks`, and the workflow is a shadow of it. Similarly, 21 of the 75 "idle" employees have completed real work through `org_tasks`; `agent_runs` is the cron log, not an employee record, which `fn_reputation_recompute`'s own comment already said.

---

## One security drift I introduced, caught by the check

`project_parity` reported `anon-executable SECURITY DEFINER  prod 57  staging 56  DRIFT +1 prod-only: fn_org_task_assign`. `apply_sql --promote` reads `pg_get_functiondef()` back from staging and posts **only the definition** — the `revoke all … from public` in the same file had run on staging alone, leaving a SECURITY DEFINER function callable by `anon` in production. Revoked and confirmed with `has_function_privilege`; parity back to **BOTH PROJECTS IN SYNC**.

Worth knowing for every future `--promote`: the body travels, the grants and any DML do not.

---

## Closing state

```
Row #3        127/152 (full run) · gates 23/23 both · parity IN SYNC · advisors 0 ERROR both
reputation    57 unmeasured · 22 standard · 8 trusted · 3 senior_trusted · 3 probation
tasks         employees holding open work 5 -> 33 · 267 unowned, by department, named
leads         16,964 in vocabulary (+519) · 18,037 sendable · invite_enabled FALSE
knowledge     trade/regulation/material 100% embedded on staging, draining on production
demand        customers 0 · inquiries 0 · quotes 0 — UNCHANGED
```

Still open: the 67 unclassified workflow steps (`org_task` #1394), `prompt_cache_enabled` pending a week's re-measure, Spec #3 UI, BoQ fixtures (blocked on drawings), the mobile-verification gate (needs your handset), and the invite ramp (yours to call — 8.6% on role addresses against an 0.08 brake).
