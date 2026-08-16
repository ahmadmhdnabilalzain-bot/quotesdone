# S3 — system-execution trace coverage: aborted-transaction rehearsal

Everything below was produced against **production** (`htdblwldjkcgjvmqkbeh`) inside a transaction
that ends in `raise exception`. Nothing was committed, nothing was deployed, no cron job was
altered, no email or webhook left the estate, and no paid provider was called
(`NO_PAID_AI=true`, `OPENROUTER_DISABLED=true`, `AI_PROVIDER_MODE=mock`; this increment contains no
inference path of any kind).

```sql
begin;
  -- scripts/sql/kernel_s3_system_execution_traces.sql, with its own begin/commit stripped
  -- probe block, ends in raise exception
rollback;
```

Wall time for the whole payload, migration plus probe: **4.3 s**.

---

## The measurement that started this, confirmed independently

```
select count(*) from public.phase_c_component where trace_policy_id = 'TRACE-SYSTEM-EXECUTION';
  -> 656
select count(*) from public.phase_c_component
 where trace_policy_id = 'TRACE-SYSTEM-EXECUTION' and mutates_state;
  -> 609
select count(*) from public.phase_c_trace where trace_policy_id = 'TRACE-SYSTEM-EXECUTION';
  -> 0
```

80 traces existed in total when this increment started — 49 TASK, 10 WORKFLOW, 9 STEP,
9 FOUNDER-COMMAND, 3 HANDOFF — and not one of them under the policy that says
`trace_required = YES` and `completed_without_trace_allowed = NO`. `cron.job_run_details` holds
**191,155** completed firings between 2026-07-19 and 2026-08-16. All of them untraced.

The total moved from 80 to **99** during the session as other kernel increments landed in parallel;
the transcript below therefore shows `of 102` (99 live plus the 3 the probe wrote and rolled back)
and the live red line reads `0 of 99`. The TRACE-SYSTEM-EXECUTION count was **0 at every reading**,
before and after, and production is unchanged by this rehearsal:

```
components_on_policy 656 | sysexec_traces 0 | wrapped_cron 0 | active_cron 23 | s3_objects_live 0
```

---

## What moved policy, how many, and on what evidence

**23 of the 656 moved. 633 stay, including every one of the 609 that change state.**

| to | n | what they are |
|---|---|---|
| `TRACE-INFRASTRUCTURE` | 22 | 9 retired 410 responders that execute nothing at all; 7 read-only content readers; 3 read-only exports; 3 read-only reads (public_stats, report_body, quote_quality) |
| `TRACE-MONITORING` | 1 | `edge:vercel_status` — a read-only deployment health probe, which is the literal scope of that policy |

A component moved only when **two independent measurements agreed**:

1. `phase_c_component.mutates_state = false` (the registry), and
2. a sweep of the component's own source on `rebuild/phase-c-execution-kernel`, 2026-08-17, finding
   no mutation verb (`insert` / `upsert` / `update` / `delete` / `rpc` / a POST, PUT, PATCH or
   DELETE request / storage `.upload(` / auth-admin user creation) **and** no artefact production
   (PDF, XLSX, image or CSV rendered or uploaded).

The per-component hit list from (2) is stored in `phase_c_component_trace_exemption.source_measurement`,
so the reader can re-run the same sweep and disagree with it.

### The K11 derivation was recorded, including where it had nothing to say

`fn_kernel_component_reachability` is stored verbatim against every exempted component. It is
decisive for cron components (`ACTIVE_CRON`, reachable, with schedule and run count). It is **not**
decisive for edge functions: K11 seeded platform probes for only the fifteen components it
measured, so for every other edge function the derivation returns *"no reachability vector"* — which
is the absence of a measurement, not a finding of unreachability. That string is stored as-is rather
than quoted as agreement. A derivation with nothing to say must not be cited as a second witness.

### The nine components the registry and the source disagree about

The sweep contradicted `mutates_state = false` on nine of the forty-seven components the registry
calls non-mutating:

| component | what the source does |
|---|---|
| `edge:asset_delete` | deletes storage objects |
| `edge:doc_render`, `edge:make_xlsx`, `edge:marketing_image`, `edge:pdf_native` | `upsert` plus storage `.upload(` |
| `edge:qa_mint` | `admin.auth.admin.createUser` |
| `edge:qa_suite` | `insert`, `delete`, `rpc` |
| `edge:social_stage` | outbound POST and PATCH |
| `edge:voice_otp` | `upsert` |

**All nine stay on TRACE-SYSTEM-EXECUTION and none is exempted** — the safe side. `mutates_state` is
**not** corrected here: K11's exposure invariant reads that column, and correcting it is that
increment's subject. It is disclosed, not silently trusted and not silently fixed.

One further disclosure: the sweep read the **repository** file. `edge:voice_otp`'s repository file
contains an `upsert`, while K11's platform probe records the **deployed** body as a 410 stub. Two
different objects. Nothing here depends on resolving it, because `edge:voice_otp` is not exempted
either way.

Fourteen more of the forty-seven render an artefact or make an outbound request and are likewise
left in place: `attach_photos`, `cad_convert`, `drawing_boq`, `extract_text`, `kb_research_test`,
`license_extract`, `make_pdf`, `profile_ai`, `quote_pdf`, `quote_review`, `site_deploy`,
`stripe_setup_page`, `supplier_review`, `transcribe`, `translate_html`. `quote_pdf` is the clearest:
it renders the customer-facing quote document, and TRACE-INFRASTRUCTURE's scope excludes official
outputs by name.

Full 656-row disposition: **`docs/phase-c-kernel/S3_SYSTEM_EXECUTION_COVERAGE.csv`**.

| disposition | n |
|---|---|
| `EXEMPT_INFRASTRUCTURE_READ_ONLY` | 22 |
| `EXEMPT_MONITORING_READ_ONLY` | 1 |
| `STAYS_WIRED_CRON` | 22 |
| `STAYS_CRON_NOT_ACTIVE_NOT_WIRED` | 183 |
| `STAYS_REGISTRY_SAYS_READ_ONLY_SOURCE_SAYS_IT_WRITES` | 9 |
| `STAYS_UNWIRED_NO_EXECUTION_LOG` | 419 |
| | **656** |

---

## What got wired, and the registry claim that did not survive contact

The registry labels **187** cron components `activation_state = 'active'`. Only **23** of the 206
`cron.job` rows are actually `active = true`, and one of those (jobid 278, the K5 outbox deliverer)
has no registry row at all. So **165 registry-"active" cron components cannot execute**, and
wrapping them would have produced 165 wrappers that never fire and a coverage number that looked
like work.

The 22 that can execute — active `cron.job`, `mutates_state = true`, on TRACE-SYSTEM-EXECUTION —
are wrapped, by **one shared function**, `fn_kernel_cron_exec(jobid)`. Each job's command becomes
`select public.fn_kernel_cron_exec(<jobid>)`; the original command is stored verbatim in
`phase_c_system_execution_wrapper` and executed by the wrapper, which writes one complete trace per
firing whether the work succeeded or failed. **Nothing was activated**: `active` is never passed to
`cron.alter_job`, and the active count is 23 before and 23 after.

Jobid 278 is deliberately left alone rather than given an invented registry row; it is named as an
open item below.

---

## Transcript

### The re-scope, measured inside the transaction

```
A0 components still on TRACE-SYSTEM-EXECUTION ......... 633
A0 of which state-changing .......................... 609
A0 exemptions recorded .............................. 23
A0   -> TRACE-INFRASTRUCTURE : 22
A0   -> TRACE-MONITORING : 1
A0 state-changing on a read-only policy ............. 0 (must be 0)
A0 cron jobs wrapped ................................ 22
A0 active cron jobs now calling the wrapper ......... 22
A0 active cron jobs in total (unchanged) ............ 23
```

### (A) the writer refuses every missing field class — 23 refusals, all `23514`

```
A1 refused missing component_id         23514 | TRACE-SYSTEM-EXECUTION incomplete: "component_id" is missing or empty. The
A1 refused missing system_actor         23514 | TRACE-SYSTEM-EXECUTION incomplete: "system_actor" is missing or empty. The
A1 refused missing accountable_role_id  23514 | TRACE-SYSTEM-EXECUTION incomplete: "accountable_role_id" is missing or emp
A1 refused missing trigger_source       23514 | TRACE-SYSTEM-EXECUTION incomplete: "trigger_source" is missing or empty. T
A1 refused missing authority_result     23514 | TRACE-SYSTEM-EXECUTION incomplete: "authority_result" is missing or empty.
A1 refused missing state_before         23514 | TRACE-SYSTEM-EXECUTION incomplete: "state_before" is missing or empty. The
A1 refused missing state_after          23514 | TRACE-SYSTEM-EXECUTION incomplete: "state_after" is missing or empty. The
A1 refused missing result               23514 | TRACE-SYSTEM-EXECUTION incomplete: "result" is missing or empty. The polic
A1 refused missing correlation_id       23514 | TRACE-SYSTEM-EXECUTION incomplete: "correlation_id" is missing or empty. T
A1 refused missing causation_id         23514 | TRACE-SYSTEM-EXECUTION incomplete: "causation_id" is missing or empty. The
A1 refused missing started_at           23514 | TRACE-SYSTEM-EXECUTION incomplete: "started_at" is missing or empty. The p
A1 refused missing finished_at          23514 | TRACE-SYSTEM-EXECUTION incomplete: "finished_at" is missing or empty. The
A1 refused absent failure KEY      23514 | TRACE-SYSTEM-EXECUTION incomplete: the "failure" field is absent. It may b
A1 refused no scope at all        23514 | TRACE-SYSTEM-EXECUTION incomplete: no scope. Give workflow_id (and step_id
A1 refused unjustified scope      23514 | TRACE-SYSTEM-EXECUTION incomplete: technical_scope "too short" is too shor
A1 refused unknown component      23514 | TRACE-SYSTEM-EXECUTION incomplete: component "dbfn:nope()" is not in phase
A1 refused component off-policy   23514 | TRACE-SYSTEM-EXECUTION refused: component "edge:home" is scoped to "TRACE-
A1 refused unknown system actor   23514 | TRACE-SYSTEM-EXECUTION incomplete: system actor "system.nobody" does not r
A1 refused unresolvable role      23514 | TRACE-SYSTEM-EXECUTION incomplete: accountable role "head_of_vibes" does n
A1 refused unresolvable step      23514 | TRACE-SYSTEM-EXECUTION incomplete: step "W29-S99" does not resolve in phas
A1 refused result vocabulary      23514 | TRACE-SYSTEM-EXECUTION incomplete: result "went_fine" is not one of succee
A1 refused failed w/o cause       23514 | TRACE-SYSTEM-EXECUTION incomplete: result is "failed" and failure is empty
A1 refused success + failure      23514 | TRACE-SYSTEM-EXECUTION incomplete: result is "succeeded" and yet a failure
A1 refused finished before start  23514 | TRACE-SYSTEM-EXECUTION incomplete: finished_at 2026-08-16 21:57:32.097093+
```

`failure` is nullable but its **key** must be present. An omitted field is not the same statement as
a null one, and the writer says so.

### (B) the read-only exemption guard — refuses in both directions, and is not a wall

```
B2 refused state-changing -> read-only  23514 | phase_c_component cron:health_check: mutates_state is true and trace_policy_id is "TRACE-INFRASTRUCTURE". A component th…
B2 refused read-only w/o exemption      23514 | phase_c_component edge:make_pdf: no exemption recorded for policy "TRACE-MONITORING". The policy allows completion witho…
B2 refused exempt -> mutates_state      23514 | phase_c_component edge:home: mutates_state is true and trace_policy_id is "TRACE-INFRASTRUCTURE". A component that chang…
B2 allowed: exempt component moved BACK to TRACE-SYSTEM-EXECUTION (guard is not a wall)
```

The third line is the back door closed: a component cannot be moved to a read-only policy while
read-only and then quietly become state-changing. The fourth is the proof the guard is not a
condition that cannot **not** fire — a move towards TRACE-SYSTEM-EXECUTION passes untouched.

### One complete valid trace, every required field populated

```
A3 valid trace written: trace_id 1609
A3   component_id=cron:health_check
A3   system_actor=system.scheduler  (trace.system_actor_id=system.scheduler)
A3   accountable_role_id=it_operations_engineer  (trace.actor_role_id=it_operations_engineer, manager=quality_and_release_director)
A3   workflow_id=W29  step_id=W29-S01  technical_scope=(null - workflow scope given)
A3   trigger_source=cron.job/7 schedule */30 * * * *
A3   authority_result=allowed_autonomous:security_secret_rotation:autonomous_internal_review
A3   state_before=scheduled_due -> state_after=succeeded   result=succeeded
A3   failure=(null, and the KEY was present)
A3   correlation_id=corr-rehearsal-0001  causation_id=cron.job/7@2026-08-17T00:00:00.000Z
A3   started_at=2026-08-16 22:56:52.010805+00  finished_at=2026-08-16 22:56:54.010805+00
A3   trace: policy=TRACE-SYSTEM-EXECUTION kind=system_execution ref=cron:health_check status=sealed sealed_at=…
A3   trace: input_hash=no_input_recorded output_hash=9b1751bd331d17d4f91c2c61c1d43560
A3 execution record is append-only     23514 | phase_c_system_execution is append-only: UPDATE on trace 1609 refused.
D4 epoch is immovable                 23514 | phase_c_kernel_epoch is append-only: UPDATE on epoch S3_SYSTEM_EXECUTI…
```

### (C) the wrapper, both ends

Run against synthetic wrapper rows carrying harmless payloads — `select 1` and `select 1/0` — so no
real scheduled work executed and nothing left the estate:

```
C4 wrapper OK  trace=1610 result=succeeded scheduled_due->succeeded wf=(technical) auth=allowed_autonomous:routine_operational_decision:autonomous_internal window_ok=t
C4   trigger_source=cron.job/999901 'cron:control_mode_sweep_5min' schedule '(unreadable)'
C4   causation_id=cron.job/999901@2026-08-16T22:56:55.874Z
C4 wrapper FAIL trace=1611 result=failed state_after=failed failure=22012 division by zero
C4   technical_scope=technical scope: scheduled infrastructure execution registered as 'OUT_OF_SCOPE' in phase_c_component.workflow…
```

The failing branch is the one that matters: the work rolled back inside its own sub-transaction and
the trace still records `result=failed` with the sqlstate and the message.

### (D) the state function — and proof the coverage line can go both ways

A check that only ever reports one value is not a check. The coverage line was driven red, green and
red again inside the transaction, by inserting synthetic firings into the execution log:

```
D5 fn_kernel_system_trace_state() BEFORE any wrapped cron has fired
D5 y new_state_changing_system_executions_missing_a_trace       0 of 0
D5 n new_state_changing_system_executions_with_required_trace   0 of 0 wrapped cron executions since the epoch

D5 after one synthetic firing whose trace exists
D5 y new_state_changing_system_executions_missing_a_trace       0 of 1
D5 y new_state_changing_system_executions_with_required_trace   1 of 1 wrapped cron executions since the epoch

D5 after a second synthetic firing with NO trace in its window
D5 n new_state_changing_system_executions_missing_a_trace       1 of 2
D5 n new_state_changing_system_executions_with_required_trace   1 of 2 wrapped cron executions since the epoch
```

`0 of 0` is reported as **not ok**, deliberately. A scorer whose input is absent must not print a
pass — that is the defect this increment exists to remove, and it would be absurd to reintroduce it
in the increment's own state function. The line goes green at the first firing of a wrapped job,
which is within five minutes of apply (`control_mode_sweep_5min`).

Full state function:

```
D5 n new_state_changing_system_executions_with_required_trace   0 of 0 wrapped cron executions since the epoch
D5 y new_state_changing_system_executions_missing_a_trace       0 of 0
D5 y state_changing_components_on_a_read_only_policy            0 of 23
D5 y read_only_components_without_a_recorded_exemption          0 of 23
D5 y active_state_changing_cron_components_not_wrapped          0 of 22
D5 y system_execution_traces_without_a_complete_record          0 of 3
D5 y new_system_executions_claiming_founder_authority           0 of 2
D5 y historical_untraced_system_executions                      16929 of 16929 wrapped-cron firings predate the kernel epoch and have no trace, by design
D5 y historical_untraced_cron_executions_all_jobs               191156 of 191156 cron firings on record predate the epoch
D5 y system_execution_components_with_no_observable_execution_log 428 of 633 components on TRACE-SYSTEM-EXECUTION are edge functions, database triggers or event subscriptions; this database holds no invocation log for them, so their coverage is unknown, not 100%
D5 y components_moved_to_a_read_only_policy                     23 of 656 moved off TRACE-SYSTEM-EXECUTION with a recorded exemption; 633 remain, including all 609 state-changing components
D5 y new_system_executions_recorded_as_failed                   1 of 2
D5 y traces_written_under_trace_system_execution                3 of 102
```

`191,156` includes the two synthetic rows inserted by the probe and deleted before the full run;
the real figure on production today is **191,155**.

### The K6 collision, resolved rather than shipped

```
E6 y completed_traces_still_mutable                   0 of 102
E6 y orphan_traces_system_execution                   0 of 102
E6 y raw_total_traces                                 102 of 102
E6 n system_execution_components_with_no_trace        606 of 633
E6 y traces_sealed_with_no_sealed_at                  0 of 102
E6 y traces_with_unmapped_subject_kind                0 of 102
E6 y traces_written_under_trace_system_execution      3 of 102
E6 fn_kernel_trace_integrity red lines in total: 5
```

Live today, before S3: **6 red lines**, including `traces_written_under_trace_system_execution`
at `0 of 99`. After S3: **5**. S3 turns that line green and adds no new red.

`system_execution_components_with_no_trace` moves from `609 of 656` to `609 of 633` on apply
(numerator unchanged — nothing state-changing moved policy — denominator smaller by the 23 read-only
components that left with a recorded exemption), and to `606 of 633` in this rehearsal because three
traces were written. **It stays red and it should**: it goes green only when every state-changing
component under this policy has actually been traced, which S3 starts and does not finish.

---

## Why one function moved file, and what changed in it

`fn_kernel_trace_integrity` maps a trace's `subject_kind` through a `CASE` whose else-branch is
`'unmapped'`, and asserts that no trace is unmapped. The first system-execution trace would have
turned `traces_with_unmapped_subject_kind` red — **truthfully**, because K6's integrity function had
never been told the kind. The fix is one `CASE` branch plus the equivalent orphan line for the new
kind, whose subject is a component rather than one of the five kernel objects.

Leaving a corrected copy in S3 while the original stayed in `kernel_k6_trace_ledger.sql` would have
left two files defining one routine. `sql_files_match_live` resolves that by commit time and would
certify whichever body happened to be newest, which is exactly how a correction once sat in the
repository at zero reported drift. So the **definition moved**: it now lives only in
`scripts/sql/kernel_s3_system_execution_traces.sql` §8, and `kernel_k6_trace_ledger.sql` carries a
pointer where it used to be. K6 shrinks from 882 to 693 lines; no check K6 wrote was removed or
weakened.

**Apply order: K6 first, then S3.** Re-applying K6 after S3 would restore the old body and break
`traces_with_unmapped_subject_kind`.

---

## The rollback, rehearsed on top of the migration in the same aborted transaction

```
R1 active cron jobs still calling the wrapper ....... 0 (must be 0)
R1 active cron jobs .............................. 23 (must be 23)
R1 the 22 wrapped jobs present .................... 22
R1 components on TRACE-SYSTEM-EXECUTION ........... 656 (must be 656)
R1 components on a read-only policy ............... 0 (must be 0)
R1 traces kept (NOT deleted by rollback) .......... 0
R1 execution records kept ........................ 0
R1 S3 functions remaining ........................ 0 (must be 0)
R1 S3 rolled-back tables remaining ............... 0 (must be 0)
R1 fn_kernel_trace_integrity red lines ........... 6
```

Wall time 3.0 s. Every cron command is restored verbatim from
`phase_c_system_execution_wrapper.original_command`, all 23 exempted components go back to
TRACE-SYSTEM-EXECUTION, and the red-line count returns to the live figure of 6. `traces kept` and
`execution records kept` read 0 because that run wrote none — the rollback does not delete them by
design, and the reasons are in the rollback file's header.

---

## Defects this rehearsal caught in my own file

1. **`md5('')` as the default input hash.** The first valid trace recorded
   `input_hash=d41d8cd98f00b204e9800998ecf8427e` — a real-looking hash asserting "the input was
   empty" when the truth was "no input was recorded". A fabricated fact inside the record whose job
   is to establish facts. Now `no_input_recorded`, and the wrapper always supplies
   `md5(original_command)`.

2. **The coverage line proved nothing on its first pass.** `0 of 0` with `ok = false` is correct but
   it does not show the line can ever go green. Driving it green and back to red with synthetic
   firings found that the first attempt at the green case was itself wrong: `now()` is fixed for the
   whole transaction, so a synthetic firing stamped `now() - 10 seconds` was classified historical
   and never entered the population. A test that cannot pass is as useless as a check that cannot
   fail.

---

## Open, named, not fixed here

- **cron.job 278 `phase_c_outbox_deliver_1min`** is active, changes state, and has no
  `phase_c_component` row at all — it was created by K5 after the registry was built. It is
  therefore in none of the 656 and is not wrapped. Inventing a registry row for it is a registry
  change, not a tracing change. It needs one.
- **419 components have no observable execution log.** Edge functions, database triggers and event
  subscriptions leave no invocation record in this database, so their trace coverage is *unknown*.
  The state function says unknown; it does not say 100%.
- **183 cron components labelled `active` in the registry have no active `cron.job` row.** They
  cannot execute. That is a K11-shaped exposure finding, recorded in the CSV, not repaired here.
- **`mutates_state` is wrong on nine components** (list above). Correcting it moves K11's exposure
  invariant and belongs to that increment.

## Collisions with work being written in parallel — for the lead, not fixed here

- **`scripts/sql/kernel_k10_trigger_inbox.sql` writes TRACE-SYSTEM-EXECUTION traces directly**
  through `fn_phase_c_trace_write` (two call sites, around lines 664 and 721), bypassing
  `fn_kernel_system_execution_trace`, with `subject_kind = 'trigger_inbox'` and
  `component_id = 'dbfn:fn_kernel_trigger_submit(jsonb)'`. If both files apply as they stand:
  `traces_with_unmapped_subject_kind` goes red (K6 does not map `trigger_inbox`), and S3's
  `system_execution_traces_without_a_complete_record` goes red because those traces carry no
  `phase_c_system_execution` record. Both reds would be **true**. The fix is to route K10's two
  call sites through `fn_kernel_system_execution_trace`, which is what the policy's single-writer
  shape is for. I have not edited K10 — it is another agent's increment and neither file is applied.
- **Apply order matters twice.** K6 before S3 (S3 owns `fn_kernel_trace_integrity` now). And if
  `scripts/sql/kernel_s0_routine_ownership.sql` records which file defines which routine, its row
  for `fn_kernel_trace_integrity` must name `kernel_s3_system_execution_traces.sql`; today it says
  no MANIFEST file defines it.
