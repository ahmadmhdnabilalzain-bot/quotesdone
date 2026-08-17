# K10 REHEARSAL — real autonomous trigger adapters

File: `scripts/sql/kernel_k10_trigger_inbox.sql`
Rollback: `scripts/sql/rollback/kernel_k10_trigger_inbox.rollback.sql`
Inventory: `docs/phase-c-kernel/K10_TRIGGER_INVENTORY.csv`

Rehearsed 17 Aug 2026 against the live project `htdblwldjkcgjvmqkbeh`, in ONE transaction that
applies the whole file, runs every demonstration, and then aborts. **Nothing was committed.** After
the run, `to_regclass` on all three new tables returned null, `to_regproc` on the adapter returned
null, `phase_c_workflow_run` still held 10 rows, `phase_c_task` still held 38, and `cron.job`
still had exactly 23 active jobs — the same 23 as before.

Zero paid inference. This file calls no model, no provider and no inference edge function; the
adapter's only outbound call is `fn_kernel_workflow_start`.

## How to rehearse it again

```
node scratchpad/k10/rehearse.mjs
```

which sends `begin;` + the file (its own `begin;`/`commit;` stripped) + `demo.sql`, and ends in a
`raise exception` carrying the report. The transaction is discarded by the server when the
connection ends. `scratchpad/k10/csv.mjs` regenerates the CSV the same way, in seven aborted
chunks.

## What the run proves

1. **The file applies.** All three tables, the view, the two functions and the routing-guard trigger
   are created, the 25 trigger types seed, and the 479-row inventory populates from the live
   catalogue — cron jobs, row triggers and event triggers by `insert … select`, edge functions and
   frontend paths from recorded probes with their evidence.
2. **All eight source classes go through ONE adapter.** Seven create a run, a step run, exactly one
   task and exactly one factual event; the eighth is refused as a recorded `DEFERRED_HANDLER`.
3. **Every owner is a canonical role, and none is the founder or the Chief of Staff.**
   `rfq_qualification_manager`, `supplier_onboarding_specialist`, `cfo`,
   `corporate_performance_director`, `it_operations_engineer`, `payments_and_billing_manager`,
   `supplier_matching_dispatch_operator` — each resolved `kind=canonical` through
   `fn_phase_c_resolve_actor`, each `founder?=f chief_of_staff?=f`.
4. **The same idempotency key twice creates nothing.** `run+0 step+0 task+0 event+0 inbox+0` on
   every one of the eight replays, and the first result is returned.
5. **Both idempotency layers execute.** The key layer (same `idempotency_key`) and the object layer
   (a *different* key resolving to the same workflow + business object) are separate branches, and
   demonstration (g) forces the second one: `status=duplicate`, the same `run=221`, `added run+0
   task+0 event+0`. Without (g) that branch would have shipped unexecuted.
6. **Five refusals fire, and each is recorded rather than raised.** An unmapped type, an
   unauthorised source system, a payload missing the key the recorded rule needs, a
   `DEFERRED_HANDLER` class, and — raised, because there is nothing recordable — re-entry from event
   delivery.
7. **The registry guard refuses W01.** Registering a trigger type against the founder-command
   workflow raises `23514` naming both owners. The guard can fire and it can also not fire: all 24
   mapped rows insert cleanly in the same transaction.

## The transcript

```
K10 REHEARSAL — DELIBERATE ROLLBACK

=========== 1. fn_kernel_trigger_state() BEFORE any submission ===========
active_autonomous_source_with_no_adapter  ok=t
   expected: 0 of 52 active autonomous sources (479 inventoried)
   actual  : 0 of 52 active autonomous sources unaccounted for (479 inventoried); 3 carry a recorded DEFERRED_HANDLER, 2 are founder command surfaces held out of this population by name
active_adapter_bypassing_fn_kernel_workflow_start  ok=t
   expected: 0 of 24 active trigger types
   actual  : 0 routines read kernel_trigger_inbox and create work without fn_kernel_workflow_start; fn_kernel_trigger_submit calls it: true
normal_autonomous_trigger_routing_through_founder  ok=t
   expected: 0 of 24 mapped trigger types
   actual  : 0 of 24 mapped trigger types (workflow owner or entry-step owner)
normal_autonomous_trigger_routing_through_chief_of_staff  ok=t
   expected: 0 of 24 mapped trigger types
   actual  : 0 of 24 mapped trigger types; W01 is the founder-command path and is refused by a00_kernel_trigger_type_routing_guard, not merely absent
duplicate_trigger_delivery_creating_duplicate_workflow  ok=t
   expected: 0 of 0 resolved inbox rows
   actual  : 0 repeated idempotency keys + 0 (workflow, object) pairs with more than one run, of 0 resolved inbox rows
trigger_source_using_the_domain_event_outbox_as_its_request_queue  ok=t
   expected: 0 of 479 inventoried sources
   actual  : 0 of 479 inventoried sources. The predicate is live: it matches 2 routines in the database (the legacy ingress pair), and no ACTIVE source reaches them
active_autonomous_source_not_yet_routing_through_the_inbox  ok=f
   expected: 0 of 52 active autonomous sources — NOT MET BY K10
   actual  : 52 of 52 active autonomous sources still start or change business work without entering the kernel. K10 builds the door and registers the routes; moving each source onto it is the wiring increment.
inventory_row_whose_accountable_role_does_not_resolve  ok=t
   expected: 0 of 479 inventoried sources
   actual  : 0 of 479 inventoried sources
disposition_split  ok=t
   expected: reported, never counted as one backlog of owed handlers
   actual  : 4 owe a handler (no Phase B workflow starts from that signal); 411 are not business triggers at all (guards, audits, probes, held jobs); 2 are founder command surfaces that must never get an autonomous adapter; 62 carry an adapter

=========== 2. inventory shape ===========
cron_job / CONNECTED_ACTIVE = 11
cron_job / CONNECTED_INACTIVE = 13
cron_job / DEFERRED_HANDLER = 182
database_trigger / CONNECTED_ACTIVE = 14
database_trigger / DEFERRED_HANDLER = 219
edge_function / CONNECTED_ACTIVE = 19
edge_function / DEFERRED_HANDLER = 4
edge_function / INTENTIONALLY_RETIRED = 2
event_trigger / DEFERRED_HANDLER = 7
frontend_path / CONNECTED_ACTIVE = 5
frontend_path / DEFERRED_HANDLER = 3
derived: 479 sources, 296 active, 54 active+work-creating, 0 routing through the inbox, 0 replaying the outbox

=========== 3. eight source classes, one adapter ===========

--- customer_event / customer.inquiry_submitted  (source edge:inquiry_intake)
  status=accepted  inbox_id=1  workflow=W05  object=inquiry:ZZ-DEMO-K10-INQ-1  run=221
  created: run+1 step_run+1 task+1 event+1 handoff+1 inbox+1
  step W05-S01 owner=rfq_qualification_manager (kind=canonical) | task 1117 owner=rfq_qualification_manager | founder?=f chief_of_staff?=f
  REPLAY same idempotency_key: duplicate=true status=accepted run=221 | added run+0 step+0 task+0 event+0 inbox+0

--- supplier_event / supplier.registration_submitted  (source edge:supplier_api)
  status=accepted  inbox_id=3  workflow=W09  object=supplier_account:ZZ-DEMO-K10-SUP-1  run=222
  created: run+1 step_run+1 task+1 event+1 handoff+0 inbox+1
  step W09-S01 owner=supplier_onboarding_specialist (kind=canonical) | task 1118 owner=supplier_onboarding_specialist | founder?=f chief_of_staff?=f
  REPLAY same idempotency_key: duplicate=true status=accepted run=222 | added run+0 step+0 task+0 event+0 inbox+0

--- scheduled_event / scheduled.financial_close  (source cron:gl_sync_nightly)
  status=accepted  inbox_id=5  workflow=W27  object=financial_close:ZZ-DEMO-2026-08  run=223
  created: run+1 step_run+1 task+1 event+1 handoff+1 inbox+1
  step W27-S01 owner=cfo (kind=canonical) | task 1119 owner=cfo | founder?=f chief_of_staff?=f
  REPLAY same idempotency_key: duplicate=true status=accepted run=223 | added run+0 step+0 task+0 event+0 inbox+0

--- deadline_sla_event / deadline.sla_breach  (source cron:sla_watch_hourly)
  status=deferred  inbox_id=7  workflow=(none)  object=(none)  run=(none)
  REFUSAL RECORDED: trigger type deadline.sla_breach is a DEFERRED_HANDLER: the frozen Phase B registry declares no workflow that starts from this signal. DEFERRED. No Phase B workflow starts from a deadline or SLA breach: all 34 phase_b_sla_policy breach_actions escalate, block, remind or open an exception WITHIN the open run. The handler belongs with the exception and escalation engine, not with a workflow start. Accountable for building it: coo, as the owner of system.scheduler and of the SLA clock.
  created: run+0 step_run+0 task+0 event+0 handoff+0 inbox+1
  REPLAY same idempotency_key: duplicate=true status=deferred run=(none) | added run+0 step+0 task+0 event+0 inbox+0

--- kpi_deviation_event / kpi.company_target_miss  (source cron:kpi_review_weekly)
  status=accepted  inbox_id=9  workflow=W02  object=performance_recovery_case:ZZ-DEMO-K10-REVENUE-AED  run=224
  created: run+1 step_run+1 task+1 event+1 handoff+1 inbox+1
  step W02-S01 owner=corporate_performance_director (kind=canonical) | task 1120 owner=corporate_performance_director | founder?=f chief_of_staff?=f
  REPLAY same idempotency_key: duplicate=true status=accepted run=224 | added run+0 step+0 task+0 event+0 inbox+0

--- system_health_event / system.incident_opened  (source cron:health_check)
  status=accepted  inbox_id=11  workflow=W29  object=incident:ZZ-DEMO-K10-INC-1  run=225
  created: run+1 step_run+1 task+1 event+1 handoff+0 inbox+1
  step W29-S01 owner=it_operations_engineer (kind=canonical) | task 1121 owner=it_operations_engineer | founder?=f chief_of_staff?=f
  REPLAY same idempotency_key: duplicate=true status=accepted run=225 | added run+0 step+0 task+0 event+0 inbox+0

--- webhook_provider_event / provider.payment_event  (source edge:stripe_webhook)
  status=accepted  inbox_id=13  workflow=W16  object=payment_transaction:ZZ-DEMO-K10-evt-1  run=226
  created: run+1 step_run+1 task+1 event+1 handoff+0 inbox+1
  step W16-S01 owner=payments_and_billing_manager (kind=canonical) | task 1122 owner=payments_and_billing_manager | founder?=f chief_of_staff?=f
  REPLAY same idempotency_key: duplicate=true status=accepted run=226 | added run+0 step+0 task+0 event+0 inbox+0

--- workflow_followup_event / workflow.safe_package_approved  (source kernel:step_complete)
  status=accepted  inbox_id=15  workflow=W12  object=dispatch_batch:ZZ-DEMO-K10-INQ-1  run=227
  created: run+1 step_run+1 task+1 event+1 handoff+0 inbox+1
  step W12-S01 owner=supplier_matching_dispatch_operator (kind=canonical) | task 1123 owner=supplier_matching_dispatch_operator | founder?=f chief_of_staff?=f
  REPLAY same idempotency_key: duplicate=true status=accepted run=227 | added run+0 step+0 task+0 event+0 inbox+0

=========== 4. the guards fire ===========
(a) registry guard fired on W01: 23514 / kernel_trigger_type zz.demo.founder_route: workflow W01 is owned by "ceo" and its entry step W01-S01 is owned by "chief_of_staff". Normal autonomous work bypasses both the founder and the Chief of Staff — that is a frozen boundary, not a pr
(b) unmapped type -> status=refused inbox_id=17 trace=2527 reason=no registered trigger type named customer.telepathy. An unmapped trigger is recorded and refused; it is never resolved to the nearest workflow.
(c) unauthorised source -> status=refused reason=source system ui:/portal is not permitted to submit provider.payment_event. Permitted: edge:stripe_webhook, edge:stripe_confirm
(d) missing payload key -> status=refused reason=business object rule inquiry:{inquiry_id} needs payload key(s) inquiry_id and the payload does not carry them. The object is refused, not guessed.
(e) delivery re-entry refused: 23514 / re-entry refused: fn_kernel_trigger_submit is a kernel writer and was called from event delivery
(g) different key, same business object -> status=duplicate run=221 (first run was 197-style) | added run+0 task+0 event+0
(f) outbox-replayer predicate: 3 routines without the comment strip, 2 with it

=========== 5. fn_kernel_trigger_state() AFTER the submissions ===========
active_autonomous_source_with_no_adapter  ok=t
   expected: 0 of 52 active autonomous sources (479 inventoried)
   actual  : 0 of 52 active autonomous sources unaccounted for (479 inventoried); 3 carry a recorded DEFERRED_HANDLER, 2 are founder command surfaces held out of this population by name
active_adapter_bypassing_fn_kernel_workflow_start  ok=t
   expected: 0 of 24 active trigger types
   actual  : 0 routines read kernel_trigger_inbox and create work without fn_kernel_workflow_start; fn_kernel_trigger_submit calls it: true
normal_autonomous_trigger_routing_through_founder  ok=t
   expected: 0 of 24 mapped trigger types
   actual  : 0 of 24 mapped trigger types (workflow owner or entry-step owner)
normal_autonomous_trigger_routing_through_chief_of_staff  ok=t
   expected: 0 of 24 mapped trigger types
   actual  : 0 of 24 mapped trigger types; W01 is the founder-command path and is refused by a00_kernel_trigger_type_routing_guard, not merely absent
duplicate_trigger_delivery_creating_duplicate_workflow  ok=t
   expected: 0 of 8 resolved inbox rows
   actual  : 0 repeated idempotency keys + 0 (workflow, object) pairs with more than one run, of 8 resolved inbox rows
trigger_source_using_the_domain_event_outbox_as_its_request_queue  ok=t
   expected: 0 of 479 inventoried sources
   actual  : 0 of 479 inventoried sources. The predicate is live: it matches 2 routines in the database (the legacy ingress pair), and no ACTIVE source reaches them
active_autonomous_source_not_yet_routing_through_the_inbox  ok=f
   expected: 0 of 52 active autonomous sources — NOT MET BY K10
   actual  : 52 of 52 active autonomous sources still start or change business work without entering the kernel. K10 builds the door and registers the routes; moving each source onto it is the wiring increment.
inventory_row_whose_accountable_role_does_not_resolve  ok=t
   expected: 0 of 479 inventoried sources
   actual  : 0 of 479 inventoried sources
disposition_split  ok=t
   expected: reported, never counted as one backlog of owed handlers
   actual  : 4 owe a handler (no Phase B workflow starts from that signal); 411 are not business triggers at all (guards, audits, probes, held jobs); 2 are founder command surfaces that must never get an autonomous adapter; 62 carry an adapter

=========== 6. the inbox ledger ===========
1 customer_event accepted customer.inquiry_submitted W05 inquiry:ZZ-DEMO-K10-INQ-1 run=221 trace=2493
3 supplier_event accepted supplier.registration_submitted W09 supplier_account:ZZ-DEMO-K10-SUP-1 run=222 trace=2498
5 scheduled_event accepted scheduled.financial_close W27 financial_close:ZZ-DEMO-2026-08 run=223 trace=2504
7 deadline_sla_event deferred deadline.sla_breach - - run=- trace=2505
9 kpi_deviation_event accepted kpi.company_target_miss W02 performance_recovery_case:ZZ-DEMO-K10-REVENUE-AED run=224 trace=2511
11 system_health_event accepted system.incident_opened W29 incident:ZZ-DEMO-K10-INC-1 run=225 trace=2516
13 webhook_provider_event accepted provider.payment_event W16 payment_transaction:ZZ-DEMO-K10-evt-1 run=226 trace=2521
15 workflow_followup_event accepted workflow.safe_package_approved W12 dispatch_batch:ZZ-DEMO-K10-INQ-1 run=227 trace=2526
17 customer_event refused (none) - - run=- trace=2527
18 webhook_provider_event refused provider.payment_event - - run=- trace=2528
19 customer_event refused customer.inquiry_submitted - - run=- trace=2529
20 customer_event duplicate customer.inquiry_submitted W05 inquiry:ZZ-DEMO-K10-INQ-1 run=221 trace=2530
```

## The three things this rehearsal found, that a green run would have hidden

**A regex over `pg_proc.prosrc` cannot tell a call from a comment, and here it mattered.**
Line 103: the outbox-replayer predicate matches **3** routines without the comment strip and **2**
with it. `fn_kernel_event_consume` and `fn_kernel_outbox_deliver` both contain the string
`fn_kernel_workflow_start` inside a comment explaining why a consumer must never call it, and a
naive predicate reads one of those explanations as a violation. Every derivation in this file
strips `--` and `/* */` before matching. The two that survive the strip are the legacy pair,
`fn_phase_c_event_ingress` and `fn_phase_c_event_consume`, which genuinely do it — and no ACTIVE
source reaches them, which is what check 6 says.

**A check whose population came from the column the migration writes.** The first draft of check 1
counted "active autonomous source with no adapter" over sources whose `connection_state` was not
`CONNECTED_*`. Since §5f *sets* `connection_state`, assigning adapters would have emptied the
check's own denominator and turned it green by construction. The population is now derived live
from `cron.job.active`, `pg_trigger.tgenabled` and `pg_event_trigger.evtenabled` — nothing this
migration writes can move it. Concretely: resuming any of the 67 held cron jobs that write a work
queue moves that row *into* the population by itself, and the board goes red until it has an
adapter.

**A `LEFT JOIN` that produced a NULL owner.** The first run aborted with `23502`: cron 101 is
assigned `deadline.sla_breach`, which has no workflow, so `w.accountable_role_id` from the left
join was NULL and `accountable_role_id` is `NOT NULL`. Fixed with `coalesce(w.accountable_role_id,
s.accountable_role_id)` — a deferred assignment keeps the system actor's owner. It aborted rather
than writing a NULL owner, which is the behaviour you want, but it is worth recording that the
first shape of that statement would have given 25 sources an owner of nothing had the column been
nullable.

## What is NOT met, and why

`active_autonomous_source_not_yet_routing_through_the_inbox` is **52 of 52, ok=false**, and it is
reported on the board rather than in prose because it is the whole point of the next increment.

K10 builds the door, registers 24 routes to it, and inventories every source that must come
through. It rewires nothing. Moving 52 live sources onto a new entry point in the same file that
introduces the entry point would be unrehearsable, and 14 of the 52 are row triggers whose
rewiring needs `fn_kernel_step_complete` (K3, being built in parallel) to exist first.

Note the shape of the two numbers together:

* `active_autonomous_source_with_no_adapter` = **0 of 52** — every live source that starts work has
  a registered route, or a recorded reason why it cannot have one.
* `active_autonomous_source_not_yet_routing_through_the_inbox` = **52 of 52** — none of them takes
  that route yet.

A single "CONNECTED" column would have collapsed those into one green claim. `connection_state`
carries the assignment and `routes_through_inbox` carries the measurement, and they are different
columns for that reason.

## The four sources that owe a handler nobody has built

`disposition_split` reports them separately from the 411 guards, probes and held jobs, so a real
backlog of four cannot hide inside a fake backlog of 415:

| source | why no workflow |
|---|---|
| `edge:resend_webhook` | A hard bounce or spam complaint. W13 starts from an *approved queued notification*, not from its failure. |
| `edge:supplier_ack` | "I have contacted the customer" is a step event inside an open W14 run (SLA-SUPPLIER-ACK, 4h), not a workflow start. Belongs to K3. |
| `edge:unsubscribe` | Consent withdrawal. W13 *enforces* consent; no workflow begins when it is withdrawn. |
| `cron:101 sla_watch_hourly` | All 34 `phase_b_sla_policy` breach actions escalate, block, remind or open an exception **within** the open run. No workflow starts from a deadline. |

Each is recorded as `DEFERRED_HANDLER` with the evidence above rather than mapped to the nearest
plausible workflow.

## Counts move under you

The estate is being changed by other work while this was rehearsed. `pg_trigger` held 231
non-internal triggers when the inventory was first measured, 232 when the CSV was generated and 233
at the final rehearsal, which is why the CSV has 478 rows and the transcript says 479. Nothing in
the file depends on the number: §5a–5c are `insert … select` over the live catalogue and re-read it
at apply time, and every denominator in `fn_kernel_trigger_state()` is a `count(*)` taken when the
check runs. The CSV is a snapshot with a timestamp; the board is the live measurement.

## Apply order and blast radius

Apply after K5 and K2, both already live. K10 reads `fn_kernel_workflow_start`,
`fn_kernel_assert_not_in_delivery`, `fn_phase_c_trace_write` and `fn_phase_c_resolve_actor`, and
creates none of them.

It writes no Phase A or Phase B table. It writes no existing Phase C table. It creates no task, no
run and no event at apply time — the closing assertion block proves the inbox is empty and aborts
otherwise. It contains no `cron.schedule`, no `cron.alter_job` and no `net.http_post`, and the same
block compares the set of active cron jobs before and after and aborts if a single one moved. It
also refuses to apply at all while `email_cron_2min`, `sms_flush` or `wa_flush` is active — the
three doors out of the system stay shut, so nothing a future trigger causes can reach a person
outside the company while the hold is on.
