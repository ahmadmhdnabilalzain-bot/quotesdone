# Phase C final acceptance — autonomous canary

Gates 6 and 7. Both drives used a **real entry path**: a row arriving in the table the production
Edge Function and the public route write to. `fn_kernel_workflow_start` was never called as the
test. Both ran inside transactions that always aborted, so nothing external could fire.

---

## Gate 6 — autonomous NEW_WORK_REQUEST entry — **PASS**

**Source chosen:** `edge:contact_submit`, which shares its adapter with `ui:/[locale]/contact`.
Both are ACTIVE, class `A NEW_WORK_REQUEST`, targeting W18 `customer.support_signal`, accountable
`customer_success_director`, discharged by `routine:trg_contact_message_to_kernel`.

**Real entry path:** an insert into `public.contact_messages` — exactly what
`supabase/functions/contact_submit` and the contact route do.

```
insert into public.contact_messages (name, email, phone, message, source, status)
values ('ZZ ACCEPTANCE PROBE','acceptance-gate6@example.invalid', …)
```

The chain, measured at each hop:

```
public.contact_messages                       row 4 inserted
  -> trigger z95_contact_message_to_kernel     AFTER INSERT, FOR EACH ROW
  -> fn_kernel_source_emit('edge:contact_submit', {source_ref, raw_payload})
  -> public.kernel_trigger_inbox               1 row, status = accepted
  -> kernel workflow start
  -> public.phase_c_workflow_run               1 run, workflow W18
  -> public.phase_c_workflow_step_run          1 step run
  -> public.phase_c_task                       1 task, step W18-S01, owner customer_support
  -> public.phase_c_trace                      5 rows
  -> public.phase_c_event_outbox               1 row
```

| required | measured | |
|---|---|---|
| source → canonical adapter → trigger inbox → kernel start → run → step run → task | every hop present, in that order | ok |
| founder absent | 0 `founder_command` rows behind the run | ok |
| Chief of Staff absent | 0 tasks owned by `chief_of_staff` | ok |
| AI CEO absent unless genuinely company-level | 0 tasks owned by `ai_ceo` / `chief_executive`; a contact-form message is not company-level | ok |
| one workflow | 1 | ok |
| one initial task | 1 | ok |
| exact accountable role | task owner `customer_support`; `phase_b_workflow_step` where `step_id='W18-S01'` has `accountable_role_id = customer_support` — the registry and the runtime agree | ok |
| canonical trace | 5 trace rows under the run | ok |
| duplicate source delivery produces no duplicate workflow | `fn_kernel_source_emit` called a second time with the same `source_ref`: inbox **still 1**, runs **still 1**, tasks **still 1** | ok |
| source does not directly write workflow/task state | the adapter's only statement is `perform fn_kernel_source_emit(...)`; the structural proof is Gate 9 — no identity outside the kernel can write those tables | ok |
| no paid inference | 0 new `llm_attempt` rows during the drive | ok |
| no external customer/supplier side effect | 0 new `notifications`; the transaction aborted, so no `net.http_post` was ever committed | ok |

Note on the register's `accountable_role` column: it records `customer_success_director` as the
source-level accountable owner, while the task correctly carries `customer_support`, the canonical
owner of W18-S01. These are two different things — source accountability and step ownership — and
neither contradicts the other.

---

## Gate 7 — EXISTING_WORKFLOW_SIGNAL — **FAIL**

### 7.1 The source that works

**Source chosen:** `edge:customer_documents` — ACTIVE, class `B EXISTING_WORKFLOW_SIGNAL`, targeting
"W07 — the EXISTING run, never a new one", signal `document.arrived_for_run`, discharged by
`routine:trg_document_to_kernel`.

**Real entry path:** an insert into `public.documents` with `ref_table = 'inquiries'`, which fires
`z95_document_to_kernel`. A canary W07 run was opened first for `inquiry:ZZ-ACCEPT-G7`, so the
signal had a live run to find.

```
RESULT
  existing_run     = 541
  runs_for_object  = 1
  signal_rows      = 1
  signal_status    = attached
  signal_result    = {"active_step": "W07-S01", "attached_to_run": 541}
  correlation      = signal:edge:customer_documents:37:document.arrived_for_run:541
  causation        = edge:customer_documents:37
  trace            = 5485
  steps_before     = W07-S01=active
  steps_after      = W07-S01=active
  AFTER DUPLICATE  signals = 1   runs = 1
  INVALID          status = refused
                   reason = "a signal about an existing workflow must name workflow_run_id. There is
                             no lookup by business object here on purpose: guessing which run a
                             signal belongs to is how one arrival lands on two runs."
                   runs created = 0
```

| required | measured | |
|---|---|---|
| existing workflow found | run 541 | ok |
| no second workflow created | 1 run for the business object | ok |
| signal validated against the current workflow state | the service reads the run `for update`, refuses a terminal run, refuses a workflow mismatch, and records the active step in `result` | ok |
| current step or appropriate corrective path updated | the signal is attached to the active step run. `document.arrived_for_run` is declared ATTACH_ONLY, and the registry states why: *"It is evidence on the run, not a new intake"* — completing a step from a file arrival would certify work nobody did | ok |
| trace and causation preserved | `trace_id 5485`, correlation and causation ids both recorded, the signal trace parented to the run trace | ok |
| duplicate signal produces no duplicate action | second emit with the same ref → 1 signal row, 1 run | ok |
| invalid signal refused explicitly | `status = refused` with a stated reason, 0 runs created | ok |

### 7.2 Why the gate fails anyway

`public.kernel_signal_type` holds 11 registered types. **Ten are `activation_state = 'inactive'`,**
including every disposition that changes state:

| disposition | what it does | types | active |
|---|---|---|---|
| ATTACH_ONLY | records the arrival against the run | `document.arrived_for_run`, `deadline.due`, `followup.due`, `provider.callback`, `retry.due`, `sla.breach`, `supplier.acknowledgement`, `supplier.quote_revision` | **1 of 8** |
| COMPLETE_STEP | delegates to `fn_kernel_step_complete` | `clarification.response` | **0 of 1** |
| REVIEW_VERDICT | delegates to `fn_kernel_review_decide` | `review.verdict` | **0 of 1** |
| CANCEL | delegates to `fn_kernel_cancel` | `run.cancellation_requested` | **0 of 1** |

`fn_kernel_signal_submit` refuses an inactive type at step 3. Proved by execution against a live
W14 run, in an aborted transaction:

```
signal_ok = false
status    = refused
reason    = signal type 'supplier.quote_revision' is registered with activation_state 'inactive'
            and does not accept submissions.
```

Ten of the twelve ACTIVE `B EXISTING_WORKFLOW_SIGNAL` sources name one of those inactive types:

| source | signal type | type state |
|---|---|---|
| `dbtrigger:public.inquiry_matches:notify_matched_supplier` | `followup.due` | inactive |
| `dbtrigger:public.notifications:trg_invite_status_on_send` | `provider.callback` | inactive |
| `dbtrigger:public.quote_items:quote_items_roll` | `supplier.quote_revision` | inactive |
| `dbtrigger:public.supplier_dues:trg_due_paid` | `provider.callback` | inactive |
| `dbtrigger:public.transactions:trg_refund_resolved` | `provider.callback` | inactive |
| `edge:messages_api` | `clarification.response` | inactive |
| `edge:stripe_confirm` | `provider.callback` | inactive |
| `edge:supplier_ack` | `supplier.acknowledgement` | inactive |
| `edge:supplier_portal` | `supplier.quote_revision` | inactive |
| `ui:/[locale]/me` | `clarification.response` | inactive |

Only `edge:customer_documents` and `edge:sup_dob` carry the one active type.

Corroborating fact: `public.kernel_signal_inbox` holds **0 rows** on production. Outside an aborted
transaction, no signal has ever been submitted to this estate.

The consequence for the register — ten rows verdicted CUT_OVER against a door that refuses them —
is recorded under Gate 2 in `PHASE_C_FINAL_KERNEL_ACCEPTANCE.md`.

**Smallest responsible component:** the `activation_state` column of `public.kernel_signal_type` —
ten rows read `inactive` while `phase_c_source_cutover` records their sources as ACTIVE and
CUT_OVER.

**GATE 7: FAIL**
