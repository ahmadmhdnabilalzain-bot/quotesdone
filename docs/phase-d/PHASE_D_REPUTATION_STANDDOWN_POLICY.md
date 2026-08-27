# REPUTATION UNDER A FOUNDER STAND-DOWN — MEASUREMENT POLICY

**Session:** narrow Phase D / Phase C correction, 2026-08-27
**Production project:** `htdblwldjkcgjvmqkbeh`
**Applied:** `scripts/sql/phase_c_the_scorer_would_have_read_a_hold_as_underperformance.sql`
**Reversal:** `scripts/sql/down/phase_c_the_scorer_would_have_read_a_hold_as_underperformance_down.sql`
**Board:** `select * from public.fn_reputation_hold_state();`

---

## 1. The state, measured

| fact | value |
|---|---|
| `public.agent_reputation` rows | 93 |
| every row computed at | `2026-08-12 13:45:16.723325+00` |
| stand-down opened | `2026-08-16 06:10:19.732174+00` (`company_stand_down` id 1), extended id 2, partially resumed ids 3–4; **`resumed_at` is NULL on all four** |
| snapshot age at 2026-08-27 12:30 UTC | 14.9 days |
| snapshot predates the stand-down by | 3.8 days |
| cron jobs total / active | 206 / **23** — backups, uptime probes, governance monitors |
| `reputation_weekly` (job 161) | **inactive** |
| `outcome_evaluate_daily` (job 143) | **inactive** |

## 2. What would have happened if the scorer had been run

Every dimension `fn_reputation_recompute` reads is an activity window ending at `now()`:

| dimension | source | window |
|---|---|---|
| correctness | `outcome_record` verdicts | all time, by actor |
| reliability | `agent_runs` | `started_at > now() - 30 days` |
| cost efficiency | `ai_cost_log` | `occurred_at > now() - 30 days` |
| collaboration | `review_chain` decisions | all time |

Eleven days into a hold those windows are empty **by instruction**. The routine already handles the
case where *every* dimension is null — that is the `unmeasured` tier, score NULL, and it deliberately
changes no authority. But a **partial** reading is scored, and a partial reading built from a stopped
company scores low. Below 50 is `probation`, and twenty lines further down:

```sql
update employee_authority a set max_tier = 'gated'
  from agent_reputation p
 where p.agent_key = a.agent_key and p.tier = 'probation' and a.max_tier = 'autonomous'
```

`agent_reputation.tier` is not decorative. Three routines consume it:

* `fn_check_spend` — `probation` sets the personal spend limit to 0 and routes the decision to a person;
* `fn_org_task_assign` — `probation` is ranked last for every assignment;
* `fn_pick_reviewer` — a `probation` department head is replaced by a delegate.

So a recompute during the hold is a real loss of authority caused by the clock moving rather than by
anything anyone did.

## 3. The policy, as a mechanism rather than a sentence

**Observation window frozen at the stand-down.** `fn_reputation_recompute` reads
`public.company_stand_down` first. While a row has `resumed_at IS NULL` it returns, without touching
anything:

```json
{ "ok": false,
  "status": "PAUSED_BY_FOUNDER_STANDDOWN",
  "scored": 0, "gated": 0, "restored": 0, "unmeasured": 0,
  "observation_window_frozen_at": "2026-08-16 08:35:59.46423+00",
  "last_valid_snapshot_at": "2026-08-12 13:45:16.723325+00",
  "note": "…No employee is scored, promoted or demoted while the founder's hold is open… This is not
           a PASS and it is not a performance regression." }
```

**No absence-of-activity penalty during the hold.** Nothing is written to `agent_reputation`,
`employee_authority` or `autonomy_control_audit`.

**The last valid snapshot stays available and is marked.** It is not deleted, hidden or recomputed —
it remains the basis of every tier in use. `fn_reputation_hold_state()` states its disposition:

```
snapshot_disposition  STALE_DUE_TO_FOUNDER_STANDDOWN: 93 employee(s) last scored
                      2026-08-12 13:45:16.723325+00, 14.9 days ago and 3.8 days before the
                      stand-down began
```

**It cannot newly promote or demote authority while stale** — because the only routine that moves
authority from a tier is the one that now refuses to run. That is the third board row, and it is a
real check, not an informational one: it reads the live `prosrc` for the pause and fails if the guard
is gone.

**Scorer status is `PAUSED_BY_FOUNDER_STANDDOWN`. It does not report PASS and does not report a
performance regression.** `ok` is explicitly `false`.

**Resume only after a complete new observation window.** Lifting the hold is not enough: the 30-day
windows would still overlap the held period and would still carry it into the score. After a
`resumed_at` is set, the routine returns `NOT_MEASURED_DURING_HOLD` with `first_valid_recompute_at`
until a full 30 days have elapsed **entirely after** the resume. **No retroactive penalty for the
held period.**

## 4. Proof it is a mechanism

The migration's assertion block calls `fn_reputation_recompute()` **for real**, with the hold open,
and asserts on what came back and on what did not change — a branch that returns zero because the
system is idle proves nothing.

```
OK  scorer=PAUSED_BY_FOUNDER_STANDDOWN  agent_reputation=93 (unchanged)  gated=<n> (unchanged)
```

Asserted: status is a pause value; `ok` is not true; the row count did not move; the snapshot's
`max(computed_at)` did not move; the `employee_authority` gated count did not move;
`fn_reputation_hold_state()` is red on 0 rows.

## 5. Board, 2026-08-27

| check | expected | actual | ok |
|---|---|---|---|
| `scorer_status` | paused while a hold is open | `PAUSED_BY_FOUNDER_STANDDOWN since 2026-08-16 08:35:59.46423+00` | yes |
| `snapshot_disposition` | `STALE_DUE_TO_FOUNDER_STANDDOWN` | 93 employees, 14.9 days old, 3.8 days pre-stand-down | yes |
| `stale_snapshot_may_not_move_authority` | 0 authority changes possible | the routine returns the pause and writes no row to `agent_reputation`, `employee_authority` or `autonomy_control_audit` | yes |
| `reputation_weekly_is_inactive` | false | false | yes |
| `outcome_evaluate_daily_is_inactive` | false | false | yes |

## 6. Scope

`reputation_weekly` and `outcome_evaluate_daily` remain **inactive**; this file activated nothing and
recomputed nothing. Four employees were not demoted because the scorer was not run — not because the
result was overridden.

**This item is not a Phase D acceptance blocker.** `PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1` does not
name reputation freshness among its preconditions or gates, and nothing here adds a gate.
