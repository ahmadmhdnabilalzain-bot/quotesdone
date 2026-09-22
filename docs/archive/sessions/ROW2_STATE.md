# ROW #2 — THE UNIVERSAL OS BLUEPRINT: 110 / 110 (100%)

Measured on production 2026-08-09. Full run, **110 checks, 0 MISSING, 0 errored**, no denominator
shortfall. Scorer: `scripts/staging/verify_os_blueprint.mjs`, modules in
`scripts/staging/os_blueprint/`. Spec committed at `docs/specs_row2_universal_os_blueprint.txt`.

---

## 1. THE WORKLIST WAS STALE, AND THAT IS THE HEADLINE

`docs/sessions/ROW2_WORKLIST.md` was audited **6 Aug 2026** and triaged 45 NOT MET requirements —
11 wrong checks, 34 real gaps — with evidence and a minimal fix for each. Re-measured today,
**44 of those 45 were already closed.** The session-15 note recording "65/110 (59%)" is three days
and several merged rows out of date.

The right first move on this row was therefore to **run the scorer, not to work the worklist**. Two
of its entries had already been overtaken in a way that would have wasted a whole change:

- `comp-16-*` (seven requirements) — the worklist's fix was "one edit to `fn_exec_meeting` that
  reads `v_os_health` and names the seven figures". A generator was written to do exactly that and
  **refused**: `fn_exec_meeting` already reads `v_os_health`. Had it not asserted its anchor, it
  would have produced a second, duplicate read.
- `contract-consolidation` leg 3 — the worklist recorded "0 `priority.updated` events have ever
  existed". Today: **20 in the last 30 days, all 20 delivered to a subscriber.**

## 2. THE ONE REQUIREMENT THAT WAS ACTUALLY OPEN — AND IT WAS A WRONG CHECK

`contract-consolidation` read 336 of 1,091 deliveries closed in 21 days = 31%, against a bar of 50%.

The check's history is instructive. Its first form was `count(...) > 0` inside a window, so **one**
closed delivery scored the whole consolidation loop MET. That was hardened on 6 Aug to
`2 * closed >= all`. The hardening was right about the disease and wrong about the population.

Read on production:

| the 1,091 deliveries in the window | |
|---|---|
| closed (result + `closed_at`) | 336 |
| open — and the `org_task` is genuinely unfinished | **755** |
| of which `assigned` 714 · `proposed` 28 · `in_progress` 11 | |
| open — and the task is `done` (the actual leak) | **2** |

**753 of the 755 are open because the work is still being done.** The ratio therefore rises and
falls with how much is in flight: the company could finish everything it has and score MET, or take
on a week of new work with a flawless loop and score MISSING. A backlog gauge wearing a loop
check's name — the same error as the first version, pointed in the opposite direction.

The requirement is *"the loop closes"*: when event-derived work **finishes**, its result must return
to the delivery that caused it. So the population is deliveries whose task is done, and the bar is
that essentially all of them close. Measured that way: **336 of 338.**

**This is not a loosening.** The new form is stricter on the dimension that matters — ≥95% of
*finished* work must report back, against the old 50% of *all* work — and it keeps the absolute
floor so it can never pass on zero. If `fn_event_consolidate` stopped, done tasks would pile up
unclosed and it fails within a day; the old form would not have noticed while the queue drained.

## 3. AND THE TWO LEAKED ROWS WERE NOT A DEFECT EITHER

Both were `knowledge_director` deliveries whose tasks had just been marked done. The consolidation
cron is healthy — `event_consolidate`, hourly at `:25`, **66 succeeded runs in 3 days**, and exactly
2 candidates waiting. Running `fn_event_consolidate` by hand returned `deliveries_closed: 2` and the
count went to **0**.

They were in flight between hourly runs. This is the same "bus latency, not bus failure" pattern the
worklist already established for `xos-02-event-bus`, and it is precisely what the corrected check's
5% tolerance exists to absorb. **Nothing needed building.**

---

## 4. WHAT THIS ROW LOOKS LIKE ON PRODUCTION

All 17 blueprint components and the cross-OS contract, across 10 operating systems:

- **10 staffed OS**, with purpose, mission, mandate and responsibilities that all reach the agent prompt
- **Decision Engine** — 1,249 decisions, 283 in 7 days, all ten chain steps populated, read by 9 objects
- **KPI Engine** — 94 active KPIs, all 94 with `measure_sql`, live non-writing readers
- **Event bus** — 1,091 deliveries, 753/753 correlated, 53 active subscriptions, 2 live observability
  readers on cron
- **Health** — 10/10 OS carry all eight dimensions, and they reach the weekly exec meeting
- **Learning** — 7,826 knowledge revisions in 30 days, 219 of 252 lessons traceable to a dispatched event
- **Outcomes** — 51 outcome records, none overdue, all gradeable (the first grading window opens 11 Aug)

## 5. THE STANDING LESSON

Three rows in a row have now turned on the same thing: **the brief or the worklist is a hypothesis,
the scorer is the measurement.**

- Row #6's brief named a defect whose proposed fix would have caused a regression.
- Row #8's own scorer twice anchored on the wrong object — a task class the estate does not define,
  and a table with zero writers.
- Row #2's worklist named 45 gaps of which 44 were already closed.

Every one of those documents was accurate when written. None was accurate when read.
**Run the scorer first, every time.**
