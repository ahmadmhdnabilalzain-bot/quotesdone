# Phase D Q-series — builder evidence

**BUILDER_EVIDENCE_PENDING_FINAL_AUDIT.** Nothing in this document is an acceptance. Every number
below was measured on production `htdblwldjkcgjvmqkbeh` on 25 Aug 2026 and every command that
produced one is named beside it, so an independent audit can re-run rather than re-read.

**Reproduced by:** the commands in each section; the whole set is `scripts/sql/phase_d_q01…q06` plus
the checks named in §7.

**Scope.** This session did six things and refused a seventh. It repaired the guard that was
silently refusing the founder's own governance decisions, closed the 18 class-B decision fields,
routed customer creation through the kernel, repaired the three things that regression broke, and **did not apply PCCR-006** — because the approval
that would have authorised it was refused by the estate before it could be recorded. §1 is that
refusal, measured.

---

## 1. The two founder decisions of 24 Aug 2026, verified from the immutable records

### Decision 1 — PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1: **VERIFIED**

| attribute | value |
|---|---|
| exact original text | `I approve PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1 — sha256 63cf6429901e812ca8261d53a602ac686317d592c289139500d42ab9927c0d5e — as the final and only Phase D acceptance standard.` |
| command ID | **36607** |
| message ID | **37730** |
| created_at / received_at | `2026-08-24 22:47:19.558921+00` |
| raw_text_hash | `de3749ea145c0b644a2c92b6ee8f59e82db6fc137c10e7a06fca0a71a2e736bf` — **recomputed on production**: `encode(digest(raw_text,'sha256'),'hex') = raw_text_hash` → `true`, length 173 |
| actor recorded by os_api | `management@quotesdone.com`, `os_audit_log` id **18825**, action `founder_command`, at `22:47:19.512935+00` |
| authenticated founder identity | `phase_c_founder_identity` → `management@quotesdone.com`, active, kind `email`, `auth_user_id 1256c7ec-17bf-4b1e-af8f-aaa32a8fdd14`; `auth.users.last_sign_in_at 2026-08-24 22:46:00.113154+00` — 79 seconds before the command |
| audit-log record | `os_audit_log` 18825, detail carries the sentence verbatim |
| one immutable root trace | `phase_c_trace` **3981202**, policy `TRACE-FOUNDER-COMMAND`, subject_kind `command`, subject_ref `36607`, actor `founder`, system actor `system.command_router`, status `open`. Exactly one row for this command |
| tasks_created | **0** |
| workflow_ids | **[]** — `founder_command_interpretation` v1 records `workflow_ids = ''` |
| task_ids | **[]** — `founder_command_task_link` 0 rows, `founder_command_workflow_link` 0 rows |
| no external effect | 0 notification rows, 0 outbox rows, 0 provider calls attributable to this command |
| state | `clarification_required` — `AMBIGUOUS`, confidence 0.0, *"no registered command intent matches this instruction"* |

The digest in his sentence equals `sha256sum docs/phase-d/PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1.md`
= `63cf6429901e812ca8261d53a602ac686317d592c289139500d42ab9927c0d5e`, byte for byte.

### Decision 2 — PCCR-006: **NOT VERIFIABLE AS A COMMAND, AND THE ESTATE REFUSED IT**

The text is exact and the digest matches. The record does not exist.

| attribute | value |
|---|---|
| exact original text | `I approve PCCR-006 — governance_approval_authenticity — as set out in docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-006.md, sha256 c787bfcfe38578010f29e4ed2dcaddc602be42f16eb3a320aab6f75519561ceb.` — character-for-character the sentence PCCR-006 §"What the founder is being asked for" requests, with the digest filled in |
| document digest | `sha256sum docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-006.md` = `c787bfcf…519561ceb` — **matches** |
| command ID | **none** |
| message ID | **none** |
| raw_text_hash | **none stored** |
| created_at | only an audit timestamp: `2026-08-24 22:47:32.503481+00` |
| actor recorded by os_api | `management@quotesdone.com`, `os_audit_log` id **18826**, action `founder_command_clarify`, `command_id 36607` |
| audit-log record | present (18826) |
| root trace | **none** |
| tasks_created / workflow_ids / task_ids | 0 / [] / [] |
| no external effect | confirmed |

**It was submitted as the clarification ANSWER on command 36607, not as a second command** — so it
was never going to produce a `founder_command_message` row of its own. And it did not even land on
the clarification it answered: `founder_command_clarification` 679 still reads
`answer_text = NULL, answered_at = NULL`, `founder_command_interpretation` holds one version, and
command 36607 is still `clarification_required`.

**Why, measured.** `os_api` writes its audit row BEFORE the RPC, so 18826 proves receipt and not
success. The edge log for that second:

```
22:47:32.425Z  GET  | 200 | /auth/v1/user                             <- identity verified
22:47:32.485Z  POST | 201 | /rest/v1/os_audit_log                     <- the receipt
22:47:32.504Z  POST | 200 | /rest/v1/rpc/fn_control_mode_require      <- the gate said allowed
22:47:32.526Z  POST | 403 | /rest/v1/rpc/fn_founder_command_clarify   <- the decision, refused
```

and the ONLY `postgres_logs` entry in the surrounding half hour:

```
22:47:32.749Z  permission denied for table phase_c_trace
```

That is `42501`, which PostgREST returns as 403. §2 is the defect and its fix.

**Consequence, stated plainly.** His PCCR-006 approval is a real, authenticated instruction and it is
recorded in an immutable audit log. It is **not** an immutable authenticated Command Center
*decision record*: no command id, no message id, no `raw_text_hash`, no trace. PCCR-006 is a change
to a frozen Phase C subject whose entire subject is that approvals must be derived from a verified
record rather than asserted. Applying it on the strength of a decision the estate refused would be
the exact defect it closes, so **it is not applied**. §2 removes the obstacle; the decision is his to
re-submit.

---

## 2. Q01 — a deferred guard that ran as the caller

`scripts/sql/phase_d_q01_a_deferred_guard_that_ran_as_the_caller.sql`
sha256 `a5b05ddc2af9de4c7ad378b3f822c5b52c8f030ffb13dd87367ce8e2f71a6f90`
rollback `scripts/sql/down/phase_d_q01_a_deferred_guard_that_ran_as_the_caller_down.sql`
sha256 `1c4e3b7a3d52e61587fe3692f787b23c6d01a83a32cc8de3b2f45513ec74ebb1`

`z90_system_execution_pair_guard` is `DEFERRABLE INITIALLY DEFERRED` on `public.phase_c_trace` and
its function was SECURITY INVOKER. A deferred trigger fires at COMMIT, when the SECURITY DEFINER
context that opened the transaction is gone, so it ran as the TRANSACTION's role — which PCCR-003
deliberately made `authenticated` for every founder path. Measured:

| role | `phase_c_trace` SELECT | `phase_c_system_execution` SELECT |
|---|---|---|
| `authenticated` | **false** | **false** |
| `service_role` | true | true |

The guard's first statement reads `phase_c_trace`. It denied before it had read a single thing it
exists to check.

**Proved by one added line.** Three probes, all in aborted transactions, all as
`set local role authenticated` with the founder's own `request.jwt.claims`:

| probe | result |
|---|---|
| `fn_founder_command_clarify(36607, …)` | `{"ok": true, "answer_recorded": true, "tasks_created": 0, "task_ids": []}` |
| the same **+ `set constraints all immediate`** (fires the deferred triggers exactly as COMMIT would) | `42501 permission denied for table phase_c_trace` |
| the same, after Q01 | `CLARIFY + DEFERRED CHECKS OK` |

**Blast radius.** `os_api` reaches `fn_founder_command_submit` through `admin` (service_role, which
has the grant) and `fn_founder_command_clarify` / `fn_founder_command_control` through
`asCaller(authHeader)`. Both of the latter write `phase_c_trace` through the state guard, so both
queued this trigger, so both have been failing at COMMIT with a 403 since PCCR-003 was applied.

**Not one predicate changed.** Negative and positive controls, executed as `authenticated` with the
deferred checks forced, after the fix:

| control | result |
|---|---|
| `TRACE-SYSTEM-EXECUTION` with `subject_kind='trigger_inbox'` (rule 6) | REFUSED `23514` |
| `subject_ref <> component_id` | REFUSED `23514` |
| `status='sealed'` with `sealed_at IS NULL` (rule 4) | REFUSED `23514` |
| sealed with no `phase_c_system_execution` row (rule 1) | REFUSED `23514` |
| **positive control** — an OPEN system-execution trace whose subject is its component | **ACCEPTED** |
| probe residue afterwards | **0** |

---

## 3. Q02 — the eighteen class-B decision fields

`scripts/sql/phase_d_q02_eighteen_decision_fields_that_duplicated_output.sql`
sha256 `716805d51a12b92af8552798ee214492be2282c00df42118f7734ffec6dfa5ed`
rollback sha256 `6b531a76afa4e74befbaf9460eaa50b51f8aafcaa4677a96f33579203139958a`

**`CLOSED_ENUM_UNDEFINED` is not a completed authoritative domain and is not described as one here.**
It is a registered, disclosed hole naming an open change request.

| | before | after |
|---|---|---|
| `decision` fields on `phase_d_output_domain_registry` | 35 | **18** |
| of those, carrying an enforced domain | 2 | **3** (W08-S06, W17-S06, **W16-S04**) |
| registered `CLOSED_ENUM_UNDEFINED` | 33 | **15** — exactly the class-C population, asserted by name |
| enforced `CLOSED_ENUM` fields, all names | 478 | **479** |
| class-B repairs complete | — | **18 of 18** |
| class-B fields remaining `CLOSED_ENUM_UNDEFINED` | — | **0** |
| Phase A drift | 0 | **0** |
| Phase B drift | 0 | **0** |

**Seventeen removed** — W01-S04, W03-S01, W04-S05, W11-S04, W13-S03, W15-S05, W18-S05, W20-S01,
W22-S01, W23-S02, W25-S02, W26-S02, W26-S08, W27-S06, W27-S09, W29-S02, W30-S03. Their frozen
`required_action` is an act with one artefact outcome and `output` already carries the complete
result. Measured before removal: of 22 `phase_d_object_write_map` rows exactly one names a
`decision` key (`review_record → review_chain`), and `phase_d_step_effect` has 0 rows targeting
`review_record`, so no frozen step's `decision` is read through it.

**One bound** — W16-S04, whose frozen action is *"Apply only an allowed transaction-state transition
using the provider event"*, to `phase_d_object_state_contract.payment_transaction`
`{open, pending, settled, refunded, failed, reconciled}`, the contract
`z40_phase_d_object_record_contract` enforces. Catalogue row `PDF-4108` supplies `settled` so the
prose fallback never reaches a field that now has a domain.

**The handler follows the contract, not a list.** `fn_phase_d_handler_execute`'s DECISION_HANDLER arm
emits `decision` only where the output schema declares it — a query against
`phase_d_handler_schema`, so when the founder decides PBCR-002 the arm needs no second edit.

**Controls: 90 of 90 as required.** Five per repaired field, executed against the live validator:

| control | fields | result |
|---|---|---|
| valid | 18 | accepted 18 |
| invalid-domain | 18 | refused 18 |
| wrong-type | 18 | refused 18 |
| null | 18 | refused 18 |
| invented-field (for the seventeen this is `decision` itself — the key they used to require) | 18 | refused 18 |

Reproduce: `node scripts/checks/phase_d_input_schemas_are_typed_and_closed.test.mjs` for the gate,
and the per-field matrix above from `public.fn_phase_d_schema_validate`.

**Rollback rehearsed**, aborted transaction, 25 Aug: restores `decision_fields=35 undefined=33
enforced=2 schemas_declaring=35 pdf4108=0 w16_domain=(absent)`.

---

## 4. The exact PBCR-002 vocabulary for the fifteen class-C steps

`docs/phase-b/PHASE_B_CHANGE_REQUEST_PBCR-002.md`
**new sha256 `4e201c387f3746c8400f55553622aa3c57639f7f2b45d58f9e8c83a4010d3b7a`**

The section that said *"a token list is not proposed here"* is replaced by an exact table: for each
of the fifteen steps — step ID, the frozen step text quoted, the field, the exact allowed values,
a definition per value, terminal/nonterminal meaning, the state/object affected and the state each
value implies, a positive control, an invalid sentinel, compatibility, migration and rollback.

No blanket "use the words in the frozen text" sentence remains, and no token is left undefined.
Every value is traceable to a word in that step's own frozen sentence, and the tokens' absence from
the estate is re-measured and stated: 0 hits in `pg_proc.prosrc`, 0 in every `pg_constraint`.

**Two questions are marked rather than resolved quietly**, because measurement cannot settle either:

- **W06-S05** — the frozen sentence's grain is *per route*; `decision` is one string per step run.
- **W19-S04** — *"Approve a recovery, communication, support, restriction or exit recommendation"*
  reads as five kinds or as one composite plan. Both token lists are given.

**Not applied.** The migration and rollback are described and deliberately not committed: a committed
migration for an unapproved change is one command away from being applied.

---

## 5. Q03 — the active inquiry source bypass

`scripts/sql/phase_d_q03_a_customer_created_by_eleven_paths_and_routed_by_none.sql`
sha256 `2e0b535b93db2272609d822f3d6754f50a11e3bdc989f5b46bcd4d8a26faab67`
rollback sha256 `6598aceedd48314689ab8c8486df417dbfbf828342020bc7462b723d62f4d1f8`

**The fix is at the table, and the measurement is why.**
`docs/phase-d/PHASE_D_AUTONOMOUS_SOURCE_BYPASS_TABLE.md` named two creators of `public.customers`.
`public.phase_c_edge_function_writes` holds **eleven**: `customer_api`, `inquiry_intake`,
`messages_api`, `compliance_archive`, `kyc`, `login_otp`, `mobile_otp`, `os_api`, `os_ops`,
`pdpl_erase`, `wa_optin_set`. A per-function adapter would have covered one of eleven.

```
any creator INSERTs public.customers
  -> z50_customer_registered_kernel_emit (AFTER INSERT, FOR EACH ROW, sorts last)
  -> fn_kernel_source_emit('dbtrigger:public.customers:z50_customer_registered_kernel_emit', …)
  -> fn_kernel_trigger_submit  (trigger_type customer.registered)
  -> public.kernel_trigger_inbox
  -> W04, its first step run and its first task
```

**Verified by execution on production, in an aborted transaction, with a real
`insert into public.customers`:**

| requirement | measurement |
|---|---|
| one customer → at most one W04 workflow | inbox rows **1**, workflow **W04**, object `customer_account:<id>`, runs **1**, step runs **1**, tasks **1** |
| duplicate event → no duplicate workflow | replay `duplicate=true`, `created={run:0, task:0, event:0, step_run:0, inbox_row:0}`, inbox after **1**, runs after **1** |
| customer_api and inquiry_intake both covered | and nine others — the coverage is on the row, not the caller |
| source validation | refused unless the key is in `kernel_trigger_type.allowed_source_systems` and carries a `phase_c_source_cutover` row; both written before the trigger exists |
| correlation / causation | `customer:<id>` / `customers.insert:<id>` |
| trace | `TRACE-SYSTEM-EXECUTION` **3981255** |
| founder absent | first step owner `customer_onboarding` |
| Chief of Staff absent | same |
| no external effect | notifications **0**, `phase_d_external_attempt` **0**; the one outbox row is a domain event and `fn_kernel_outbox_deliver` writes only `phase_c_event_delivery_attempt` — no HTTP, no provider |
| automation remains held | a trigger, not a cron. No schedule activated, no provider un-held, `control_mode_action` untouched |

**Frozen Phase C subjects:** none touched. `fn_kernel_source_emit`, `fn_kernel_trigger_submit` and
every one of the 25 frozen subjects are called, never modified. No Phase C change request is owed by
this file.

### The bypass board

`select * from public.fn_kernel_trigger_state();`

```
active_autonomous_source_not_yet_routing_through_the_inbox   0 of 29     ok
```

And §5c is how the OTHER board — the committed-disposition one that read 1 — reached zero too.

### `edge:drawing_redact` — classified

**READ_ONLY / DERIVED_INTERNAL**, and state-changing — the two are not in conflict and the
distinction is the classification. Measured: ACTIVE v21; exactly one bounded write,
`insert into public.drawing_redaction_runs`, plus objects in the `drawing-files` bucket; **zero**
rows naming any work table. The row it writes is the PROVENANCE of the redaction it just performed,
which `create_inquiry` reads to decide which redacted paths may be attached, fail-closed when
absent. It is not class A (it starts no workflow; the business event on this path is the document
arriving, carried by `customer.document_uploaded`) and not class B (there is no live run to signal —
redaction happens at upload time, before any inquiry exists). Recorded in both registries.

### The eight false-positive measurement rows, corrected

| finding | rows | correction |
|---|---|---|
| **F1** a frontend path can never pass the routing check — and a browser route is not an autonomous source | 5 | `recorded_creates_work = false`, disposition `HUMAN_DRIVEN_SURFACE_NOT_AN_AUTONOMOUS_SOURCE`, evidence naming the edge functions each route reaches |
| **F2** `creates_work_now` reads the table name, not the write | 2 | disposition `RECOMPUTATION_ONLY_NO_BUSINESS_WORK`, carrying the reading: `quote_items_rescore`'s whole body is `update quotes set status = status`; `quote_items` holds 0 rows since 16 Aug |
| **F3** `attach_photos` does not write; what it calls does, and was not inventoried | 1 | `recorded_creates_work = false` (0 rows in `phase_c_edge_function_writes`), and `drawing_redact` inventoried |

**No product path was rebuilt.** Every statement in that section writes a measurement.

### F4 — routing attributed per TABLE, not per function

`v_kernel_trigger_source_derived` now requires **every** bounded work table an edge function writes
to be kernel-routed, and publishes the ones that are not in a new `unrouted_work_tables` column.
`edge:customer_api` read `routes_through_inbox = true` while its `public.customers` INSERT reached
nothing; that credit can no longer be granted by a sibling table.

`public.inquiry_intake` is marked `is_draft` on the work-table list with its reason travelling
beside it: a draft is not work, `customer_api` promotes a ready draft into `public.inquiries`, and
THAT insert reaches the kernel through `trg_inquiry_received_a`.

### The gap the corrections rest on, published

Every correction above says *"the write happens in the edge function, which is inventoried
separately."* That is true of 25 functions and not of others, so the board gained a row:

```
edge_functions_writing_a_work_table_and_absent_from_the_inventory
  52 of 143 edge functions with a measured write are absent from public.kernel_trigger_source
  while writing a work table.                                                            ok=false
```

**`ok = false` on purpose.** It is owed work, not an exemption. Eight of the 52 write
`public.customers` and are covered by the table trigger regardless.

---

## 5b. Q04 — a reversal that could not reverse the one record the estate refuses to let it

`scripts/sql/phase_d_q04_a_reversal_that_could_not_reverse_the_append_only_record.sql`

**A regression Q03 caused, and it is the guard working.** `kernel_positive_controls.test.mjs` went
21 of 21 → **20 of 21** after Q03: `fn_phase_d_committed_scenario_close` threw

```
23514 :: phase_c_system_execution is append-only: DELETE on trace 4041726 refused.
```

The scenario's fixture INSERTs a customer; Q03's adapter now writes a TRACE-SYSTEM-EXECUTION trace
and its execution row; the close deletes traces by `run_id`;
`phase_c_system_execution_trace_id_fkey` is ON DELETE CASCADE; and
`z10_phase_c_system_execution_append_only` refuses every DELETE with no maintenance door, on
purpose.

**Neither side is wrong.** Creating a customer is no longer fully reversible, by design. The harness
now says so instead of throwing: it counts the append-only-backed traces **and their ancestors**
(`phase_c_trace_parent_trace_id_fkey` is a self-reference with no cascade — found on the first
rehearsal, which is what rehearsing is for), retains exactly those, deletes the rest, and discloses
the count on the scenario row in both the CLOSED and the FAILED shape. The precedent is this
routine's own treatment of `kernel_maintenance_write`: *"Counted and disclosed, never hidden."*

**Not changed:** the append-only guard (a guard the harness can talk round is not a guard), the
customers adapter (exempting the fixture would rebuild the bypass one table lower), or the watermark
set — `phase_c_system_execution` is not watched and adding it would make every future scenario fail
for the same reason, which is the opposite of disclosing it.

| control | result |
|---|---|
| the close, after Q04 | `ok:true`, removed `{public.phase_c_trace: 3, public.customers: 1, public.leads: 1, …}`, retained `public.phase_c_trace_retained_append_only: 2` |
| **negative control** — one extra unaccounted trace, so `phase_c_trace` sits at watermark + v_ao + 1 | **REFUSED** `23514 … watermark drift: public.phase_c_trace 6303 -> 6306` |
| all kernel positive controls | **21 of 21 accepted, 0 failed**; row counts before/after unchanged on all seven relations |

The relaxation is exactly `v_ao` and not one row more, and the branch was forced rather than
assumed.

---

## 5c. Q05 — three coverage claims that broke the parser that reads them, and the bypass reaching zero

`scripts/sql/phase_d_q05_three_coverage_claims_that_broke_the_parser_that_reads_them.sql`

**The second regression Q03 caused, and the one that closed the original finding.**
`public.phase_c_source_cutover.disposition_evidence` is not prose. `fn_kernel_cutover_measure`
parses it as `<kind>:<ref>` — `retired | read_only | inactive | routine | trigger` — and honours a
`routine:` claim only when that routine exists AND reaches a kernel door. Q03 appended a true
sentence to a column a machine reads, and two boards went red:

| board row | after Q03 | after Q05 |
|---|---|---|
| `coverage_claims_with_nothing_behind_them` | **2** | **0** |
| `active_sources_bypassing_the_kernel` | **3** | **0** |

- `edge:customer_api` and `edge:inquiry_intake` — `split_part(…,':',2)` on
  `routine:trg_inquiry_received; routine:trg_customer_registered_kernel` reads
  `trg_inquiry_received; routine`, which is not a routine. A claim that was true and proven became a
  claim with nothing behind it.
- `edge:drawing_redact` — `routine:none — no adapter, by classification`. `none` is not a routine.
  The row is class C and the parser has a kind for exactly that: `read_only`.

**And `edge:inquiry_intake` was the original bypass of one.** Its `disposition_evidence` had never
been machine-readable: it began `measured 2026-08-18:`, so `split_part(…,':',1)` returned
`measured 2026-08-18`, which is not one of the five kinds, so the row fell through to the bypass
count. That was RIGHT — the sentence itself says the `public.customers` write had no kernel
discharge, and it did not. Q03 built the discharge; Q05 writes the claim in the keyed shape
(`trigger:z50_customer_registered_kernel_emit`, whose `ev_routine` resolves through `pg_trigger` to
`trg_customer_registered_kernel`, a kernel caller) and moves the 18 Aug measurement verbatim into
`cutover_action`, which is the prose column, so nothing is lost.

**Not one predicate of `fn_kernel_cutover_measure` changed.** The rows it reads were corrected to the
shape it has always required.

### The two boards that disagreed now agree, at zero

`docs/phase-d/PHASE_D_AUTONOMOUS_SOURCE_BYPASS_TABLE.md` finding **F5** recorded that
`fn_kernel_cutover_measure` read 1 bypass and `fn_kernel_trigger_state` recomputed 9, and that
neither said which was the subject.

```
fn_kernel_cutover_measure.active_sources_bypassing_the_kernel                    0     ok
fn_kernel_cutover_measure.active_sources_writing_business_work_directly          0     ok
fn_kernel_cutover_measure.coverage_claims_with_nothing_behind_them               0     ok
fn_kernel_trigger_state.active_autonomous_source_not_yet_routing_through_inbox   0/29  ok
```

### The gap is closed, not allowanced

`scripts/checks/kernel_boards_are_green.test.mjs` is the estate's own mechanism for a disclosed gap:
a `kernel-boards.json` ratchet entry needs an owner, a reason over 40 characters and an integer
`max_numerator` that may never grow.

| entry | before | after |
|---|---|---|
| `fn_kernel_trigger_state.active_autonomous_source_not_yet_routing_through_the_inbox` | ratcheted at **9**, owner `OPEN — 2 quote_items triggers, 2 edge functions writing customers…` | **deleted**. The check's own comment says so: *"deleted because it reached zero — that is the goal, not a failure"*. A new bypass is now a hard failure with nothing to fit under |
| `fn_kernel_cutover_measure.active_sources_bypassing_the_kernel` | ratcheted at **1** | **0**, held |
| `fn_kernel_trigger_state.edge_functions_writing_a_work_table_and_absent_from_the_inventory` | — | **added at 52**, owner `open — Phase C kernel cutover, source inventory completeness increment`. A real gap, disclosed with a name on it, that may not grow |

`node --test scripts/checks/kernel_boards_are_green.test.mjs` → **7 of 7**, 40 boards, 458 checks.

**The 52 is a ratchet and not a green lie.** Making it `ok=true` would have been the easy way to keep
the board clean; the estate already has the honest mechanism and it is used here.

---

## 5d. Q06 — a SECURITY DEFINER function created and left executable by PUBLIC

`scripts/sql/phase_d_q06_a_security_definer_function_created_and_left_public.sql`

The third thing Q03 broke, and the one the session's own standing rule names: *every SECURITY
DEFINER function you CREATE is granted EXECUTE to PUBLIC; revoke it in the same migration.* Q03
CREATEd `public.trg_customer_registered_kernel()` as SECURITY DEFINER and did not revoke.

```
no SECURITY DEFINER routine in public is anon-executable  ->  [trg_customer_registered_kernel]
exactly the two customer-document routines are authenticated-executable  ->  the set changed
```

**Stated rather than minimised:** it is a trigger function — no arguments, returns `trigger`, raises
`0A000` outside a trigger context — so no caller could have made it do anything. That is why the
blast radius was small. It is not a reason to leave it: the check measures the surface, not the
exploit, and it is right to. Q01 was a REPLACE and correctly left its ACL alone; Q03 was a CREATE
and was not.

| after Q06 | |
|---|---|
| `anon_cannot_execute_security_definer.test.mjs` | **7 of 7** |
| ACL | `{postgres=X/postgres,service_role=X/postgres}` — the one both siblings carry |
| the trigger still fires | re-verified end to end: 1 inbox row, W04, 1 run, 1 step, 1 task, replay creates nothing |

---

## 6. Decision-packet process debt

| item | before | after |
|---|---|---|
| Phase D deliverables 14/14 vs 15/15 | the check printed **14** — its `test()` count — while the approved denominator is **15** named files | a named assertion prints **15 of 15** present, tracked, non-empty and reproducible, read from `PHASE_D_REQUIRED_DELIVERABLES.md`, never from the check |
| a prose deliverable naming no reproducing command | `PHASE_D_IDEMPOTENCY_CONCURRENCY_RESULT.md` named none of the four candidates | it now names `node scripts/phase_d/run_concurrency_probes.mjs`, and the check fails any prose deliverable that names none |
| graphify ingesting audit verdict headings | **274 heading nodes from 14 audit documents**, including one labelled "Verdicts" | `.graphifyignore` excludes them by filename FAMILY, not by list; after regeneration **0** |
| graphify staleness | `graph.json` built at `01c4b0f`, five commits behind | rebuilt at `0b80bde` = HEAD; 26,048 nodes, 29,478 edges, 3,639 communities |
| a generator that cannot tell a frontend route from a state-changing source adapter | `routes_through_inbox` had no arm a `frontend_path` row could ever satisfy | frontend rows are dispositioned as what they are; routing is attributed per table; the inventory gap is a board row |
| rollback scripts in the wrong directory | this session first wrote three `_down.sql` files into `scripts/sql/`, where the classifier read them as migrations needing their own rollbacks — 3 checks red | moved to `scripts/sql/down/`, the convention 100 existing files already use. 7 of 7 checks pass, 0 required and missing |

### The 14/14 vs 15/15 answer, in full

Nothing reduced a denominator. Two numbers about two different populations were read as one.

- **14** is the number of `test()` blocks in
  `scripts/checks/phase_d_deliverables_match_production.test.mjs`. `node --test` prints `pass 14`.
  It moves whenever `BUILDERS` gains an entry — it read 12 with 9 builders and 14 with 11 — which is
  why the frozen standard's row 8 freezes *"every assertion passes and every built file reproduces
  byte-identically"* and explicitly **not** the assertion count.
- **15** is the deliverable count, and the same check already asserted it — inside a test named after
  `PHASE_D_BUILDER_CLOSURE.md`. An assertion labelled with the wrong subject is one nobody reads as
  the thing it checks.

It now has its own test, its own name and its own printed lines:

```
required deliverables present  15 of 15
tracked by git                 15 of 15
reproducible                   15 of 15 (8 regenerated and diffed byte-for-byte;
                                          7 prose, each naming its reproducing command)
denominator silently reduced   0 — read from PHASE_D_REQUIRED_DELIVERABLES.md, never from this file
```

---

## 7. Gates, re-run

### The frozen FD-02 schema-domain gate — **PASSES**

`node --test scripts/checks/phase_d_input_schemas_are_typed_and_closed.test.mjs` → **8 of 8**.
479 `CLOSED_ENUM` fields enforced, 0 undeclared on their schema; 15 `CLOSED_ENUM_UNDEFINED`, each
naming PBCR-002; 7 closed-domain field names, conforming accepted and sentinel refused on all;
1,799 of 1,799 step cases.

### The frozen FD-01 governance gate — **OPEN**, re-measured

All five PCCR-006 objects are absent, because PCCR-006 is not applied:

```
fn_phase_c_governance_decide=false   phase_c_governance_decision=false
auth_event.action_class=false        a05_change_request_approval_is_derived=false
a05_freeze_amendment_session_claim_is_verified=false
```

The four findings still reproduce (aborted transaction, 25 Aug — `phase_c_change_request` unmoved
afterwards: PCCR-004 `DEFER_OR_REJECT`, PCCR-005 `DEFERRED`, `phase_c_founder_auth_event` 0 rows):

| case | result |
|---|---|
| A — typed approver onto DEFERRED PCCR-004 | **ACCEPTED**, `disposition=APPROVED approved_by=management@quotesdone.com` |
| A2 — the same on PCCR-005 | **ACCEPTED**, `disposition=APPROVED` |
| B — `disposition='APPROVED'` with no approver | **ACCEPTED** |
| D — `fn_phase_c_founder_subject_bind` from a `postgres` connection | **ACCEPTED** — a founder session minted with no bearer token in existence |
| E — a NON-founder approver | REFUSED `23514 pccr_approver_not_the_founder` |
| F — the refund door with no bind in the transaction | REFUSED `28000 not the founder: no verified auth subject` |

**And one thing the 24 August audit did not state, found by running D and F in the same
transaction:** after D's migration-minted bind, F **succeeds**. A founder session minted from a
`postgres` connection opens the refund door in the same transaction. That is finding D's real reach,
and it is what PCCR-006's Amendment B (`session_user = 'authenticator'`) and Amendment A
(`and e.action_class is null`) exist to close.

### The frozen 13-gate regression set

| # | gate | result |
|---|---|---|
| 1 | `fn_phase_a_baseline_drift()` | **0 rows** |
| 2 | `fn_phase_b_baseline_drift()` | **0 rows** |
| 3 | `fn_phase_c_freeze_drift()` | **8 of 8 ok** |
| 4 | `canonical_routine_manifest.mjs --all` | conflicting 0, ambiguous 0, manifest gaps 0, repo→prod 0, prod→repo 0, uncommitted DDL 0 → **exit 0** |
| 5 | `application_source_of_truth.test.mjs` | 0 on all seven |
| 6 | `verify_deploy_parity.mjs --all` | **DEPLOY PARITY OK — 202 functions** |
| 7 | `export_from_either_source_is_identical.mjs` | **identical: YES** (see disclosure below) |
| 8 | `PHASE_D_DRIVE=1 … phase_d_deliverables_match_production.test.mjs` | **pass 15, fail 0**; every built deliverable reproduces byte-for-byte |
| 9 | `build_all.mjs` | 11 builders ok; **15 of 15** required deliverables present and current |
| 10 | `phase_d_documents_do_not_contradict_each_other.test.mjs` | **4 of 4** |
| 11 | `build_migration_rollback_classification.mjs` + its check | **7 of 7**; 0 unclassified, 0 duplicate, 0 absent from MANIFEST/PENDING, **0 required and missing** |
| 12 | `build_handler_implementation_result.mjs` | 257 of 257 |
| 13 | Gate 6 — `prove_object_reference_round_trip.mjs` | 56: 55 round-tripped + 1 intent; mismatched 0, refused 0, not-created 0, replay duplicates 0, residue 0 |
| — | Gate 7 | 54 rules ENFORCED, 0 OUTSTANDING; 32 gates ENFORCED, 0 NAMED_BUT_ABSENT |
| — | Gate 8 / 9 | 75 executed with a discriminating result, NOT_RUN 0, FAILED TO REFUSE 0, attempt rows left behind 0, live exemption register **0 rows** |
| — | Gate 10 | 1,799 of 1,799 cases; 257 kernel_boundary, 1,542 live_step_run |
| — | anon cannot execute SECURITY DEFINER | **7 of 7** (2 red between Q03 and Q06 — see §5d) |
| — | kernel boards are green | **7 of 7**; 40 boards, 458 checks; the kernel-bypass ratchet DELETED because it reached zero |
| — | kernel positive controls | **21 of 21 accepted, 0 failed** (20 of 21 between Q03 and Q04 — see §5b) |
| — | kernel invariants | PASS, 0 unmeasured |
| — | Phase C invariants | PASS, 71/71 |

**No gate was added. No denominator was moved. No frozen disclosure was reinterpreted.**

### Two committed-script digests have moved since the standard froze them

The standard says a script whose hash has moved must be re-read before its result is trusted. Two
have, and both are re-read above:

| script | frozen at `521ed16` | now | why |
|---|---|---|---|
| `phase_d_deliverables_match_production.test.mjs` | `39c10b72…` | `c3ee4ceb…` | this session added the 15/15 assertion — one assertion inside an existing gate, no new gate and no moved denominator |
| `phase_d_documents_do_not_contradict_each_other.test.mjs` | `64858e61…` | `036ee5f4…` | **not this session.** PR #467 — the commit that introduced the standard — also changed this file, so the digest recorded against `521ed16` was already stale when it was frozen. Reported, not edited: the standard is his |

### Schema export

`export_from_either_source_is_identical.mjs` read **not identical** before this session's refresh
and now reads **identical: YES**. Of the 540 changed lines in `supabase/schema/full_schema.sql`,
**5** name objects this session created; the other 535 predate it — the export had not been
regenerated since `521ed16`.

---

## 8. Zero cost, zero external effect

| measurement | value |
|---|---|
| `ai_cost_log` rows this session | **0** |
| last row in `ai_cost_log`, all time | `2026-08-15 02:51:33+00` — before the provider hold |
| `phase_c_trace` rows with a provider, this session | **0** |
| `phase_d_external_attempt`, all time | **0** |
| `ai_usage` rows this session | **0** |
| notification rows this session | **1** — `health_alert` id 7030 at `22:30:00`, status `digest`, written by the 15-minute health cron **before** this session's first apply and not attributable to it |
| graphify regeneration | `graphify update .` — AST-only, no API key, no request to any provider |

---

## 9. What is still open

| # | blocker | why it is open |
|---|---|---|
| 1 | **FD-01 / PCCR-006** | His approval was submitted, authenticated and audit-logged, and then refused at COMMIT by the defect Q01 fixes. The clarify path now works, so the same sentence submitted again will produce a command with a `raw_text_hash` and a trace. **Only he can submit it.** |
| 2 | **PBCR-002** | The exact vocabulary for the fifteen class-C steps is written out and committed; the migration is deliberately not. One sentence from him decides it, and two of the fifteen carry a question he may answer differently |
| 3 | 52 edge functions write a work table and hold no inventory row | published as `ok=false` on the kernel trigger board rather than classified by guess |
| 4 | `graphify-out/.graphify_labels.json.sig` covers 222 of 3,639 label entries | it was written 22 Jul; only graphify's SEMANTIC pipeline rewrites it and that needs a paid LLM key, which the provider hold forbids. **Boundary:** measured that nothing in THIS repository reads it; graphify's own internals were not read |
| 5 | PCCR-006 has no row in `public.phase_c_change_request` | PCCR-001…005 do. Raising a change-request row is a governance act, so it is reported rather than done |
