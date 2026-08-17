# Phase C final acceptance — legacy-path retirement

Gates 10, 11 and 14. Every disposition in `public.kernel_retired_path` was verified independently —
grants read from `pg_proc.proacl`, callers found by scanning every deployed routine body and the
whole of `supabase/functions` and `src`, and each path **executed** with its real signature inside a
transaction that aborted.

---

## Gate 10 — the eight retired paths — **PASS**

| path | recorded disposition | replacement |
|---|---|---|
| `fn_phase_c_event_ingress` | DISABLED | `fn_kernel_workflow_start` |
| `fn_phase_c_step_advance` | DISABLED | `fn_kernel_step_complete` |
| `fn_phase_c_outbox_settle` | READ_ONLY_HISTORICAL | `fn_kernel_outbox_deliver` |
| `fn_phase_c_event_consume` | COMPATIBILITY_WRAPPER_TO_KERNEL | `fn_kernel_event_consume` |
| `fn_phase_c_outbox_deliver` | COMPATIBILITY_WRAPPER_TO_KERNEL | `fn_kernel_outbox_deliver` |
| `fn_phase_c_workflow_start` | KERNEL_INTERNAL_PRIMITIVE | `fn_kernel_workflow_start` |
| `fn_phase_c_task_create` | KERNEL_INTERNAL_PRIMITIVE | `fn_kernel_workflow_start` |
| `fn_phase_c_outbox_claim` | KERNEL_INTERNAL_PRIMITIVE | `fn_kernel_outbox_deliver` |

### Grants — measured from the catalogue, not from the builder's check

```
path                        proacl                    anon   authenticated   service_role
fn_phase_c_event_consume    postgres=X/postgres       false      false           false
fn_phase_c_event_ingress    postgres=X/postgres       false      false           false
fn_phase_c_outbox_claim     postgres=X/postgres       false      false           false
fn_phase_c_outbox_deliver   postgres=X/postgres       false      false           false
fn_phase_c_outbox_settle    postgres=X/postgres       false      false           false
fn_phase_c_step_advance     postgres=X/postgres       false      false           false
fn_phase_c_task_create      postgres=X/postgres       false      false           false
fn_phase_c_workflow_start   postgres=X/postgres       false      false           false
```

The ACL is explicit rather than default, so the "`revoke … from anon` is a silent no-op when the
grant is held through PUBLIC" trap does not apply here: PUBLIC holds nothing.
`has_function_privilege` was evaluated per role rather than inferred from the ACL string.

### Callers

| required | measured |
|---|---|
| active callers of old workflow-start logic | **0** outside the kernel — `fn_phase_c_workflow_start` is called by `fn_kernel_workflow_start` only |
| active callers of old step-progression logic | **0** — nothing in the database, `supabase/functions` or `src` names `fn_phase_c_step_advance` |
| active direct task creators | **0** — `fn_phase_c_task_create` is called by `fn_kernel_open_step` and `fn_kernel_workflow_start`, both kernel |
| active old outbox workers | **0** — `fn_phase_c_outbox_settle` has no caller anywhere |
| old cron jobs invoking parallel runtime | **0** — cron 278 `phase_c_outbox_deliver_1min` runs `select public.fn_kernel_outbox_deliver(25, 'cron:phase_c_outbox_deliver_1min')` |
| direct grants permitting bypass | **0**, per the ACL table above |

All eight names were also grepped across `supabase/functions` and `src`: **0 files** reference any
of them.

One apparent caller was checked and dismissed: `fn_phase_c_event_binding_status` appears to name
`fn_phase_c_outbox_claim`, but the match is inside a **string literal** describing the binding —
`'durable row phase_c_event_outbox; claim fn_phase_c_outbox_claim (FOR UPDATE SKIP LOCKED); '` — not
a call. The builder's own state check excludes it by name for exactly that reason.

### Compatibility wrappers

| wrapper | body size | calls |
|---|---|---|
| `fn_phase_c_event_consume` | 2 newlines | `fn_kernel_event_consume` |
| `fn_phase_c_outbox_deliver` | 2 newlines | `fn_kernel_outbox_deliver` |

Both call **only** the canonical kernel and contain no independent business logic — there is no room
in a two-line body for any.

### Retired functions refuse state-changing execution — executed, not asserted

Called with their real signatures (a first pass with guessed signatures produced `42883 does not
exist` and was discarded — a signature miss is not a refusal):

```
DISABLED   fn_phase_c_event_ingress(text,text,jsonb)
             refused 23514 "fn_phase_c_event_ingress is retired: an event records that a state
                            change happened, it does not cause one. Start work with fn_kern…"

DISABLED   fn_phase_c_step_advance(bigint,text,text,jsonb)
             refused 23514 "fn_phase_c_step_advance is retired: it derived successors from
                            phase_b_handoff alone, so a step with a real next_step_if_pass and …"

READ_ONLY  fn_phase_c_outbox_settle(bigint,boolean,text,text)
             refused 23514 "fn_phase_c_outbox_settle is READ_ONLY_HISTORICAL and no longer settles
                            anything (outbox_id 1)"

WRAPPER    fn_phase_c_event_consume(bigint)          ran — delegates to the kernel, as designed
WRAPPER    fn_phase_c_outbox_deliver(int,text)       ran — delegates to the kernel, as designed
```

The injected-defect suite corroborates both DISABLED refusals independently: *"a retry opens a NEW
step run and preserves the first attempt"* and *"an out-of-order delivery cannot mark a
dead-lettered event delivered twice"* both now pass **because the retired path refuses**.

### Historical reads remain available

`fn_phase_c_outbox_settle` refuses to write but the historical `phase_c_event_outbox` rows it once
settled remain readable, and the retired register itself preserves each path's original purpose in
`evidence`.

### Stated boundary

The three `KERNEL_INTERNAL_PRIMITIVE` paths do **not** refuse when invoked directly by the database
owner (`postgres`), because they hold write authority in `kernel_write_authority` and the guard
permits them. Their protection is the GRANT: no role that an Edge Function, a browser, or a
PostgREST client can hold may execute them. This is recorded so the property is not overstated as
"the body refuses" — for these three it is "the door is locked", which is a different and weaker
statement, though sufficient against every identity reachable from outside the database.

**GATE 10: PASS**

---

## Gate 11 — refund-only founder approval — **PASS**

| required | measured |
|---|---|
| general founder approval UI absent | `src/lib/osClient.ts` exposes no general approval call; its only `founder_approval_required` reference is a display field on a result type |
| general founder approval endpoint absent or inaccessible | `os_api` exposes `prompt_approve`, `simulation_approve` and `report_recommend_approve`. These approve a prompt version, a simulation and a report recommendation. None writes `founder_approval_request`; none blocks routine business work waiting for him |
| non-refund founder approval records = 0 | `founder_approval_request` holds **0 rows** of any class. `fn_kernel_founder_approval_state`: `founder_approval_classes_are_refund_only = refund_decision`, `non_refund_rows_in_founder_approval_request = 0 of 0`, `non_refund_rows_in_v_founder_inbox = 0 of 0` |
| routine work blocked on founder = 0 | `org_tasks` carrying `needs_founder` with a non-terminal status: **0**. `org_tasks_newly_routed_to_founder_that_are_not_refunds = 0 of 46` |
| informational critical alerts do not create approvals | the K21 page path writes a `notifications` row and emits a W29 incident to the kernel; it creates no `founder_approval_request` and sets no `needs_founder` |
| specific refund approval inbox present | `v_founder_inbox` exists and is refund-scoped |
| refund cannot execute without an immutable founder decision | injected-defect suite: *a refund decided by someone other than the founder is refused* (`28000` + `fn_phase_c_require_founder`); *a refund executed against a REJECTED decision is refused* |
| founder refund decisions append-only and undeletable | `a00_phase_c_refund_decision_immutable` — `BEFORE DELETE OR UPDATE ON public.phase_c_refund_decision FOR EACH ROW` |
| decision changes require a superseding row | the table carries `supersedes_decision_id` and `supersession_reason`; with UPDATE and DELETE refused, a superseding row is the only route |
| payment executor and reconciler are separate canonical identities | `z10_phase_c_refund_decision_guard` BEFORE INSERT OR UPDATE; injected-defect suite: *a refund whose executor is also its reconciler is refused*; stored rows violating it: **0**. `refund_decisions_that_are_mutable = 0 of 0` |

A direct probe insert of a refund decision was itself refused by `a00_kernel_write_guard` —
*"no routine with write authority for this table is on the call stack"* — so a refund decision
cannot be created outside the kernel at all. The immutability and separation properties were
therefore verified from the trigger definitions and from the injected-defect suite rather than from
a row created for the test.

`phase_c_refund_decision` currently holds 0 rows, so no live decision was inspected. That boundary
is stated rather than papered over.

**GATE 11: PASS**

---

## Gate 14 — goal cascade — **PASS**

`trg_goal_cascade` fires on `old.active is true and new.active is false` — a goal being **retired**.

| required | measured |
|---|---|
| does not incorrectly start W02 for goal retirement | a live `company_goals` row (`classification_accuracy`) was retired inside an aborted transaction. **0** new workflow runs, **0** new W02 runs, **0** new `phase_c_task`, **0** new `org_tasks`, **0** new `kernel_trigger_inbox` rows |
| business side effect disabled | the deployed body contains no live `insert into public.org_tasks`; the statement is present only as a comment, so a reader sees what was removed instead of inferring it from a gap |
| recorded as an explicit Phase B/Phase C wiring gap | `phase_b_phase_c_wiring_gap` **gap 27**: *"no Phase B workflow defines what happens when a company goal is retired"*, recorded 2026-08-17 05:51 UTC, with `evidence_command = select prosrc from pg_proc where proname = 'trg_goal_cascade'` |
| cannot create work until an approved handler exists | the only work-creating statement is disabled, and the trigger calls no kernel door, so there is no path by which it can create work |
| preserves historical behaviour and evidence | the trigger keeps its definition and its objective-supersession behaviour; the disabled statement is left visible; the register records the classification and the reasoning — W01 starts from a founder mandate and W02 from a material KPI or trajectory miss, and a deliberate retirement is neither |

The register's classification is `D RETIRE_OR_HISTORICAL`, status
`BUSINESS_SIDE_EFFECT_DISABLED_BEHAVIOUR_OWED` — one of the three rows that explain why
CUT_OVER 32 + READ_ONLY 19 = 51 against 54 active sources.

**GATE 14: PASS**
