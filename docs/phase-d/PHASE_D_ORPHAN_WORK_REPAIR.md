# ORPHANED WORK — REPAIR REGISTER AND THE BOARD THAT COULD NOT SEE IT

**Session:** narrow Phase D / Phase C correction, 2026-08-27
**Production project:** `htdblwldjkcgjvmqkbeh`
**Applied:** `scripts/sql/phase_c_active_work_whose_business_parent_is_gone.sql`
**Reversal:** `scripts/sql/down/phase_c_active_work_whose_business_parent_is_gone_down.sql`

---

## 1. The eight runs, individually

Every one opened 2026-08-26 by a fixture drive; every one's customer had been deleted by that
drive's own zero-residue cleanup, which knew about `public.customers` and not about the kernel work
the customer's INSERT trigger (`z50_customer_registered_kernel_emit`) had committed.

| run | workflow | state before | business object | customer exists | step run | task | handoff | outbox | effects | traces | opened |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 209068 | W04 | active | `customer_account:06245659-70e2-4566-b603-7b0d68590ebd` | **no** | 514208 W04-S01 active | 518679 queued | 0 | 642387 delivered | 0 | 5 (3 open) | 10:54:08+00 |
| 209069 | W04 | active | `customer_account:3f142c87-d42d-4a37-a86b-39208fe8cd16` | **no** | 514209 W04-S01 active | 518680 queued | 0 | 642388 delivered | 0 | 5 (3 open) | 10:54:08+00 |
| 209070 | W04 | active | `customer_account:51ceb51a-11e8-4e26-ada0-9321a99875ed` | **no** | 514210 W04-S01 active | 518681 queued | 0 | 642390 delivered | 0 | 5 (3 open) | 11:33:51+00 |
| 209071 | W04 | active | `customer_account:c8948b0e-4d45-400e-ba0c-7698b6b81b17` | **no** | 514211 W04-S01 active | 518682 queued | 0 | 642391 delivered | 0 | 5 (3 open) | 11:33:51+00 |
| 209072 | W04 | active | `customer_account:dbbad73f-0295-4a73-bf3e-8f2096e6dcb7` | **no** | 514212 W04-S01 active | 518683 queued | 0 | 642392 delivered | 0 | 5 (3 open) | 11:35:49+00 |
| 209073 | W04 | active | `customer_account:7fda60a0-76f4-45b4-a674-9bad12f5f548` | **no** | 514213 W04-S01 active | 518684 queued | 0 | 642393 delivered | 0 | 5 (3 open) | 11:35:49+00 |
| 209193 | W04 | active | `customer_account:6d5280eb-4735-468b-a93f-0e38408a1d50` | **no** | 514782 W04-S01 active | 519261 queued | 0 | 643088 delivered | 0 | 5 (3 open) | 11:57:18+00 |
| 209194 | W04 | active | `customer_account:c0ed8e2c-88ac-4e2b-a76c-55ce6d55faa3` | **no** | 514783 W04-S01 active | 519262 queued | 0 | 643089 delivered | 0 | 5 (3 open) | 11:57:18+00 |

**Creation source:** the `customer_account` INSERT path, not a founder command — `command_id` is
NULL on all eight and `start_event` is `EV-W04-STARTED` on all eight.
**Fixture / test / historical / real:** fixture. All eight were created on 2026-08-26 by Phase D
fixture drives; `public.phase_d_effect_ledger` holds **0 rows** for their step runs, so no external
effect was ever produced and nothing left the estate.

## 2. The repair

Rehearsed first in a transaction that ended in `raise exception` (all eight returned `ok:true`), then
applied for real. One `fn_kernel_cancel` call per run — the canonical kernel cancellation path,
`subject_kind = 'workflow_run'`, which is the arm that requires no founder because an autonomous run
has no founder in the loop:

```sql
select public.fn_kernel_cancel(jsonb_build_object(
  'subject_kind','workflow_run', 'subject_ref', '<run_id>', 'op','cancel',
  'actor','system.workflow_engine',
  'reason','ORPHANED_PARENT_MISSING_PRE_FIX: the customer_account this W04 run was opened for no
            longer exists. …No parent row is recreated to close them.'));
```

`fn_kernel_cancel` refuses its own transaction if it leaves any queued derived work behind — the
postcondition is asserted inside the routine, not asserted *about* afterwards.

**Measured immediately after, from a new statement:**

| | |
|---|---|
| runs not cancelled | **0** |
| step runs still live | **0** |
| tasks still live | **0** |
| open traces on those runs | **0** (24 sealed) |
| outbox rows still deliverable | **0** |
| rows deleted | **0** |
| customers recreated | **0** |

The eight outbox rows were already `delivered` before the repair and were **not** rewritten: a
delivered event is a fact that happened, and `fn_kernel_cancel` only supersedes what has not yet left
the queue. `traces_sealed` in the routine's own return reads 0 because the three open traces per run
were already sealed by the `fn_phase_c_trace_write` calls in steps (c)–(e); the sweep in step (h)
correctly found nothing left. Verified independently: open traces on run 209068 went 3 → 0 across one
call.

## 3. Why the board could not see them

`fn_kernel_orphaned_work` asked one question in six ways — *is there live work under a CANCELLED
command or a CANCELLED run?* All six rows read `0 of N` and all six were **correct**. These eight
were not under a cancelled anything. Their parent had been DELETED, and a deleted parent leaves no
cancelled row to hang the question on, so the board had no denominator that could contain them.

## 4. The generalized board

`public.phase_d_business_object_binding` already gives each of the 56 canonical business objects its
canonical relation and primary identity column, and a run's `business_object_id` is
`<object_id>:<identity>`. That map is what the new detector reads — not a customer-only hard-coded
check.

`fn_kernel_orphaned_work()` now returns **13 rows**. The original six are unchanged, word for word.

| row | expected | 2026-08-27 |
|---|---|---|
| `live_tasks_of_cancelled_commands` | 0 | 0 of 47 |
| `live_runs_of_cancelled_commands` | 0 | 0 of 11 |
| `live_step_runs_of_cancelled_runs` | 0 | 0 of 19 |
| `open_handoffs_of_cancelled_runs` | 0 | 0 of 0 |
| `undelivered_outbox_of_cancelled_commands` | 0 | 0 of 7 |
| `open_traces_of_cancelled_subjects` | 0 | 0 of 193 |
| **`active_runs_whose_business_parent_is_gone`** | 0 | **0 of 6 active runs** |
| **`active_step_runs_under_a_missing_parent`** | 0 | 0 of 0 |
| **`live_tasks_under_a_missing_parent`** | 0 | 0 of 0 |
| **`open_handoffs_under_a_missing_parent`** | 0 | 0 of 0 |
| **`undeliverable_outbox_under_a_missing_parent`** | 0 | 0 of 0 |
| **`open_traces_whose_run_subject_has_no_parent`** | 0 | 0 of 0 |
| **`active_runs_whose_subject_is_not_keyed_by_its_binding`** | informational, each named | 6 of 6, listed below |

New routines: `fn_kernel_business_subject_resolve(text)` (the resolver) and
`fn_kernel_business_parent_missing()` (the detector). Both revoked from PUBLIC and `anon`.

## 5. The second class, found by writing the first

The strict question returns run **352** as well: W29, `active` since 2026-08-17,
`business_object_id = incident:agent_action:3833`. The `incident` binding names
`public.os_incidents` keyed on `id`, whose ids are bigints 1..32. `agent_action:3833` is not one.

**It is not an orphan.** `public.agent_actions` row 3833 exists and is still `pending` — agent
`security`, kind `security_incident`, risk `high`, *"10 high/critical security event(s) in the last
7 days"*. Its producer is the db trigger `trg_page_high_agent_action`, recorded CONNECTED_ACTIVE. The
parent is alive; the **subject key** is what disagrees: W29 writes
`incident:agent_action:<agent_actions.id>` and the canonical map says `incident:<os_incidents.id>`.

**The run was not cancelled.** Cancelling live work about a live, still-pending high-severity
security item to make a count read zero is not available. It is named in its own board row with the
row that does back it.

The resolver therefore does not stop at the binding. It asks three questions in order, and reports
which one answered:

1. does the identity match the binding's `primary_identity` on the canonical relation? → `RESOLVED`
2. does it appear under **any** comparable column of that relation? → `RESOLVED (under a column
   other than <primary_identity>)`
3. is the identity itself `<token>:<id>`, with a public table called `<token>` or `<token>s`
   carrying that id? → `KEYED_OUTSIDE_ITS_BINDING`, naming the relation that does hold it

Only after all three is a subject `PARENT_MISSING`. **Question 2 exists because the primary identity
is not how every producer keys its subject, and a guard that assumes it is becomes an outage.**
Measured the same afternoon: W16 writes `payment_transaction:<transactions.payment_ref>` while the
map says `payment_transaction:<transactions.id>`, and `payment_ref` is not unique — so no
candidate-key rule reaches it either. Enforcing on the primary key alone would have refused every
W16 run the estate can produce, and it did refuse the injected-defect probe that drives one.

None of this is an allow-list or a per-case exemption register; each tier is a generic question about
whether a row exists that this run is about. The finding — three producers keying a subject by
something other than the binding's primary identity — is what the informational board row is for.

**Ceiling, stated:** question 2 is a sequential scan of one relation per workflow-run INSERT. 26 runs
exist in total and the largest bound relation is `public.leads` at 20,465 rows, so no index is
warranted today; if workflow-run creation ever becomes hot, narrow it by extending
`phase_d_business_object_binding` rather than by dropping the scan.

**And a verified Phase D fixture context is exempt from the refusal entirely.** The Phase D drives
open workflows on subjects they invent — `dispatch_batch:chk-w12-s06`, `payment_transaction:probe:reveal:1` —
inside transactions that always abort. `fn_phase_d_fixture_context()` recomputes an HMAC over the
current txid, the approved operation key and the audited grant row, and returns null for an absent
context, a hand-set GUC, a token from another transaction or a grant that does not exist (F01).
Opening one needs an enabled row in `public.phase_d_test_operation` and refuses `anon` and
`authenticated` outright, so no browser, edge function or cron job can obtain one. The exemption is
transaction-local and audited by `fixture_run_id`.

**Recorded as an open finding, not repaired here:** the W29 producer and
`phase_d_business_object_binding` disagree about how an `incident` subject is keyed. Re-keying a
committed run is not possible, and changing what the security pager emits is business automation,
which this session is holding.

The other five in that row are the honest denominator: `founder_command:` ×3 and two 2026-08-16
`ZZ-CANARY-…` subjects with no prefix at all. Those are kernel-internal or canary subjects with no
business-object binding. They are counted and named as UNMAPPED rather than silently passed, because
a prefix nobody has bound is a subject nobody is checking.

## 6. Prevention — both guards forced to fire, not merely deployed

`fn_kernel_workflow_start` and `fn_kernel_cancel` are frozen Phase C subjects and were **not**
touched. Both guards are triggers on tables.

**A. A run may not open on a parent that is not there.**
`a10_kernel_workflow_run_parent_exists` BEFORE INSERT on `public.phase_c_workflow_run`. `a10_` so it
fires after `a00_kernel_write_guard` and `a00_kernel_workflow_run_trace_guard`. It refuses **only**
`PARENT_MISSING`; `UNMAPPED_PREFIX` and `KEYED_OUTSIDE_ITS_BINDING` pass, which is what keeps
`founder_command:` and the security pager working.

Forced through the canonical door, in an aborted transaction:

```
fn_kernel_workflow_start(W04, customer_account:8df40727-…)
  -> 23503  phase_c_workflow_run: W04 names business object customer_account:8df40727-…, and no row
            of public.customers has id=8df40727-…. (kernel_workflow_start_parent_missing)
```

**B. Deleting a parent closes its work first.**
`a00_kernel_parent_delete_guard` BEFORE DELETE on `customers`, `inquiries`, `quotes`,
`transactions`, `leads`, `refunds`, `os_incidents` — one generic function reading the same binding
map.

**It compensates; it does not refuse — and the first version of this file had it the other way
round.** Refusing was measured against the estate the same afternoon and broke it: every fixture that
creates a customer cleans up by deleting that customer, the customer's own INSERT trigger
`z50_customer_registered_kernel_emit` opens a W04 run, so the delete was refused and two ZZ DEMO rows
were left committed on production. `fn_phase_d_fixture_residue()` went 0 → 2 and four Phase D checks
went red. A guard that turns every cleanup into residue manufactures the orphans it exists to stop.
Cancelling first is the stronger half of the instruction (*"refuses while active work exists, **or**
performs canonical compensation/cancellation first"*): a refusal can be worked around by a caller
that gives up on the delete and leaves the row; compensation means an orphan cannot be produced by a
delete at all. It is also what a PDPL erasure should do.

Forced, in an aborted transaction: insert a real customer, let its own trigger open the W04 run, then
delete the customer.

```
live_runs_after_insert = 1
delete = ACCEPTED   run_states = cancelled   task_states = cancelled
live_after_delete = 0   customer_rows = 0
```

That is the exact sequence that produced the eight orphans, and it can no longer produce one. The
postcondition is asserted inside the trigger too: if any live run still names the object after the
compensation loop, the delete is refused `23503` rather than allowed to orphan it.

The two ZZ DEMO customers the refusing version left behind were removed through the compensating
guard: both their W04 runs came out `cancelled` and `fn_phase_d_fixture_residue()` returned to **0**.

## 7. Required outcomes

| required | result |
|---|---|
| every orphaned run reaches a truthful terminal state | **8 of 8 cancelled** with `ORPHANED_PARENT_MISSING_PRE_FIX` |
| open steps / tasks / handoffs / effect intents cancelled or superseded | 8 step runs, 8 tasks, 0 handoffs, 0 effect intents |
| traces sealed consistently | 24 open → 0 open |
| event/outbox rows cannot deliver | 0 deliverable; the 8 delivered rows left as the facts they are |
| immutable evidence preserved | no row deleted; closure evidence and sealed traces written by the kernel |
| parent/customer rows not recreated to green a board | 0 recreated |
| active orphaned runs | **0** |
| active orphaned steps / tasks / handoffs / effects / events | **0** |
| board denominator nonzero and truthful | 6 active runs, 47 tasks, 19 step runs, 193 traces, 11 runs, 7 outbox |
| direct historical deletion | **0** |
