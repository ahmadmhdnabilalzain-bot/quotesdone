# Phase D — injected defect coverage after the kernel dispatch

What each of the 38 unexecuted injected defects still needs, now that D36 has spliced the Phase D
handler dispatch into the kernel's two step openers.

All figures measured against production project `htdblwldjkcgjvmqkbeh` on 2026-08-20 unless a
different date is stated on the line. Branch `feat/phase-d-remediation-to-acceptance`.

---

## 1. What changed, and what it does not yet prove

Before D36, `fn_phase_d_handler_execute` had two callers and both were harnesses
(`fn_phase_d_drive_workflow`, `fn_phase_d_step_cases`). Every injected defect whose blocker read
"needs a committed run" was blocked on the same thing: the only paths that reached a Phase D handler
were the ones written to abort.

Measured on the live catalogue today, that chain is now:

```
fn_kernel_workflow_start   -> (inline first step run)         -> fn_phase_d_dispatch_step -> fn_phase_d_handler_execute
fn_kernel_step_complete    -> fn_kernel_open_step (successor) -> fn_phase_d_dispatch_step -> fn_phase_d_handler_execute
```

Verified by reading `pg_proc.prosrc`: `fn_kernel_workflow_start` and `fn_kernel_open_step` both name
`fn_phase_d_dispatch_step`; `fn_kernel_step_complete` names `fn_kernel_open_step`;
`fn_phase_d_dispatch_step` names `fn_phase_d_handler_execute`. All four are VOLATILE and SECURITY
DEFINER, so they execute in the caller's own transaction — a real arrival's transaction, which
commits.

**The boundary, and it is the whole point of this document.** The mechanism exists. It has not run.

| measured | value |
|---|---|
| `public.phase_d_dispatch` rows | **0** |
| `public.phase_d_effect_ledger` rows | **0** |
| `public.phase_c_workflow_run` rows | 18 |
| `public.phase_c_workflow_step_run` rows | 24 |
| `current_setting('app.phase_d_dispatch', true)` | null → the routine's own default `'on'` applies |

Nothing has arrived since D36 landed. So every defect in class A below is discharged **in mechanism,
not in evidence**: the harness it was waiting for now exists as the production path, and it will be
discharged the first time a real arrival drives a workflow to completion — and not before.

Two further conditions sit between a dispatch and a handler execution, and both are outcomes
`fn_phase_d_dispatch_step` records rather than exceptions it raises:

- `NO_BINDING` — the step has no `phase_d_handler_binding` or no `phase_d_step_effect` row.
- `INPUTS_UNRESOLVED` — one or more declared input keys resolve from no real source
  (`fn_phase_d_step_inputs` returns them under `unresolved`). The dispatch records the row and
  returns; the handler is not called.

A class-A defect whose step lands on `INPUTS_UNRESOLVED` is not discharged by the arrival. That is
measurable the moment `phase_d_dispatch` holds its first row, and is not measurable before.

**One correction to the brief that commissioned this document.** It states "all 16 registered ACTIVE
class-A sources reach `fn_phase_d_handler_execute`". Measured: `phase_c_source_cutover` holds **20**
rows at `source_class = 'A NEW_WORK_REQUEST'` and `current_activation = 'ACTIVE'`, all 20 carrying a
`target_workflow` that exists in `phase_b_workflow`, over **8** distinct target workflows, of which
6 have a `dbtrigger:` component id. No reading of that table produced 16. The figure 20 is used below.

---

## 2. Population

75 catalogue defects. Overlay report today: 37 `REFUSED_AS_REQUIRED`, 38 `NOT_RUN`, 0 `NOT_REFUSED`.

D44 reclassifies two of the 37 to `NOT_DISCRIMINATED` (§5), giving 35 / 2 / 38.

Per category, executed-and-refused out of 5:

| category | today | after D44 |
|---|---|---|
| AUTH | 4 | **3** |
| CONCURRENCY | 4 | 4 |
| DISPATCH | **0** | **0** |
| FILES | 5 | 5 |
| FINANCE | 3 | 3 |
| IDEMPOTENCY | 4 | 4 |
| LEGAL | **0** | **0** |
| NOTIFY | 4 | 4 |
| OUTBOX | 4 | 4 |
| PRIVACY | 2 | **1** |
| PROVIDER | 3 | 3 |
| QUOTE | **0** | **0** |
| REVIEW | 2 | 2 |
| STATE | 2 | 2 |
| TRACE | **0** | **0** |

---

## 3. The 38, one row each

Classes:

- **A — discharged by the kernel dispatch.** The blocker names a transaction boundary that the
  production path no longer imposes. Evidence arrives with the first real run.
- **B1 — needs one `record(...)` call in the §8 runner.** `scripts/phase_d/run_section8_security_probes.mjs`
  (636 lines) already mints real bearers; these nine are the rows whose blocker carries the prefix
  `SECTION 8 WAS EXECUTED 2026-08-19 AND DOES NOT REACH THIS CASE — `.
- **B2 — needs its own harness or an unbuilt capability.**
- **C — out of scope, not coverage debt.** The subject is kernel-owned or frozen Phase B.

| defect | category | class | why | what it still needs |
|---|---|---|---|---|
| PD-DISP-001 | DISPATCH | **A** | GATE-011 already refuses a not-quote-ready inquiry under the W05 drive; only the commit boundary was missing | a real inquiry arrival that is deliberately not quote-ready, then read `phase_d_dispatch` |
| PD-DISP-004 | DISPATCH | **A** | assignment and outbox counts have to be reconciled across a run that survives | one committed run; compare assignment rows against outbox rows afterwards |
| PD-IDEM-002 | IDEMPOTENCY | **A** | needed two `fn_kernel_step_complete` calls on the same **committed** step run | the same step completed twice through the kernel path, in two transactions |
| PD-LEGAL-002 | LEGAL | **A** | `customer_terms_acceptance` is APPEND_ONLY and its writer refuses a second version by name; the rewrite needs a committed acceptance row to rewrite | one committed acceptance, then a second write against the same business key |
| PD-REV-002 | REVIEW | **A** | a step left in `waiting_review` cannot be observed inside an aborting transaction | one committed run stopped at a review step with no verdict |
| PD-REV-004 | REVIEW | **A** | the REJECTED path is proved in D9k but not as this injection | one committed run driven to a REJECTED verdict; assert no successor task |
| PD-REV-005 | REVIEW | **A** | sealing happens on commit | one sealed verdict row, then an edit attempt |
| PD-STATE-002 | STATE | **A** | `closed_at` has to be readable after the run | one committed run closed with a mandatory blocker open |
| PD-STATE-003 | STATE | **A** | the successor must be observable after the fact | one committed run where a non-terminal step is treated as closure |
| PD-TRACE-004 | TRACE | **A** | the failed insert has to commit its trace before an orphan can exist | one committed failed idempotent insert; count traces before and after |
| PD-AUTH-005 | AUTH | **B1** | a category overlay presented as a task owner; the SQL path resolves the actor before any authority check, so only the API path can inject it | one `record(...)` posting an overlay id as task owner through an authenticated edge function |
| PD-DISP-005 | DISPATCH | **B1** | a category overlay attempting a dispatch through an authenticated path | one `record(...)` driving a dispatch as an overlay identity |
| PD-LEGAL-001 | LEGAL | **B1** | certificate rendering is outside Phase D | one `record(...)` against the certificate-issuing surface, asserting no certificate before terms acceptance |
| PD-LEGAL-004 | LEGAL | **B1** | tax/legal static-file freshness is a content-pipeline fact | one `record(...)` asserting the freshness requirement blocks a stale interpretation |
| PD-PRIV-001 | PRIVACY | **B1** | the safe package is recorded as an object; its **contents** are never rendered or scanned in Phase D | one `record(...)` posting a payload containing a customer email to the supplier-safe approval path |
| PD-PRIV-002 | PRIVACY | **B1** | file revision state is a storage + document-pipeline fact | one `record(...)` dispatching a drawing whose redaction is unapproved |
| PD-PRIV-005 | PRIVACY | **B1** | no Phase D path renders an artifact | one `record(...)` scanning a rendered artifact's metadata |
| PD-QUOTE-001 | QUOTE | **B1** | needs supplier A's token editing supplier B's quote over the API | one `record(...)` against the supplier quote-write surface with two real supplier bearers — **and see §4 on the fixture** |
| PD-QUOTE-004 | QUOTE | **B1** | needs a customer read of an unpublished quote through the portal | one `record(...)` reading an unpublished quote with a real customer bearer |
| PD-CONC-001 | CONCURRENCY | **B2** | a true race needs two concurrent database sessions | a harness opening two connections that both commit; under the zero-effect hold that leaves rows behind, so it needs a named cleanup |
| PD-DISP-002 | DISPATCH | **B2** | the fixture writes approved suppliers only; BR-015 refuses the rest before dispatch | a pending / rejected / expired supplier fixture presented to the assignment path |
| PD-DISP-003 | DISPATCH | **B2** | GATE-013 tests who approved the safe package; the write map does not permit a non-approver to write the approval column | a path that can stage an unapproved safe package, or an explicit statement that the write map makes this uninjectable |
| PD-FIN-001 | FINANCE | **B2** | `phase_c_refund_decision` carries `executor_role_id` and `reconciler_role_id`, but no Phase D path writes that table — GATE-020 reads `public.refunds` | the section 9 refund execution path wired to `phase_c_refund_decision` |
| PD-FIN-004 | FINANCE | **B2** | needs a committed founder decision row to attempt to rewrite | a real founder decision. A fixture may **never** forge one — every refund needs the founder, at any amount, and that is now enforced by a trigger rather than a convention. This defect is uninjectable by design and should be recorded as such, not as debt |
| PD-LEGAL-003 | LEGAL | **B2** | the founder approval path is `phase_c_refund_decision` and no Phase D route writes it | same wiring as PD-FIN-001 |
| PD-LEGAL-005 | LEGAL | **B2** | the independence refusal is proved for reviewers (PD-REV-001); a COMPLIANCE review is not a Phase D step | a COMPLIANCE review path, or an explicit out-of-scope ruling |
| PD-NOTIFY-005 | NOTIFY | **B2** | section 9 records an approved payload and its sha256 but never renders a body; the PII detector runs in the edge functions | a rendered supplier-facing message body to scan |
| PD-PROV-002 | PROVIDER | **B2** | requires a gate READ to fail — a permission or relation error mid-gate | a grant revoked on production, which the hold forbids; or a gate whose read target can be made unreadable in a transaction the gate observes |
| PD-PROV-004 | PROVIDER | **B2** | a repository scan for a direct provider client lives in CI, not the database | a deliberate bypass added to an edge function and CI observed refusing it |
| PD-QUOTE-002 | QUOTE | **B2** | its blocker names a **missing publish path**, not a transaction boundary: "GATE-017 refuses a quote with no amount and is exercised by the W14 drive; as an INJECTION it needs a publish attempted on the incomplete quote". A committed W14 run does not by itself attempt a publish | a publish attempt on an incomplete quote — see §4 for the only safe surface |
| PD-QUOTE-003 | QUOTE | **B2** | `quotation_evaluation` is bound but no Phase D step writes an evidence-bearing claim | a step that writes a technical claim with its evidence, so a claim without evidence can be presented |
| PD-QUOTE-005 | QUOTE | **B2** | the normalization path is not built | the normalization path |
| PD-OUTBOX-004 | OUTBOX | **C** | the 54 event self-loops are a property of frozen Phase B, not a Phase D defect — see §6 | nothing in Phase D. Restate the blocker: it currently calls the self-loops "a FROZEN Phase B property" while `public.phase_b_event`, the table they live in, carries **zero** non-internal triggers and no `z90_phase_b_freeze` |
| PD-STATE-004 | STATE | **C** | injecting a missing successor owner means editing `phase_b_workflow_step`, which `z90_phase_b_freeze` refuses without a change request | nothing. The freeze **is** attached to this table (verified: `z90_phase_b_freeze`, `a10_phase_b_owner_guard`, `z00_kernel_truncate_guard`), so the blocker is accurate here |
| PD-TRACE-001 | TRACE | **C** | the subject is `public.phase_c_workflow_step_run`; `phase_d_business_object_binding.workflow_step_run.current_status = 'KERNEL_OWNED'` and `fn_phase_d_object_write` refuses it with `pd_object_kernel_owned` | nothing in Phase D. Doing it raw tests the kernel |
| PD-TRACE-002 | TRACE | **C** | as PD-TRACE-001 | nothing in Phase D |
| PD-TRACE-003 | TRACE | **C** | as PD-TRACE-001; `sealed_at` is a kernel column | nothing in Phase D |
| PD-TRACE-005 | TRACE | **C** | the read-only trace exemption is decided in the kernel; Phase D has no path that requests it | nothing in Phase D |

**Totals: A 10 · B1 9 · B2 13 · C 6 = 38.**

Three `KERNEL_OWNED` objects exist in `phase_d_business_object_binding`: `handoff_record`,
`workflow_run`, `workflow_step_run`. All four class-C TRACE defects name one of them.

---

## 4. The four categories at 0 of 5

### DISPATCH — 0 / 5

Nothing in DISPATCH is blocked by the zero-effect hold. `dispatch_batch` is
`relation_kind = 'PHASE_D_OBJECT_VIEW'`, `current_status = 'PHASE_D_STORE'`, canonical relation
`public.v_obj_dispatch_batch`, and it has **no** row in `phase_d_object_write_map` — so a write lands
in `public.phase_d_object_record` and touches no real table.

- PD-DISP-001, PD-DISP-004: one committed arrival each (class A).
- PD-DISP-005: one `record(...)` in the §8 runner (class B1).
- PD-DISP-002: a supplier fixture in `pending` / `rejected` / `expired`. Today the §8 fixture insert
  (`run_section8_security_probes.mjs:170-171`) writes `approval_status = 'pending'` already, so the
  fixture shape exists; what is missing is presenting it to the assignment path, where BR-015 refuses
  before dispatch.
- PD-DISP-003: needs the safe-package approval column writable to a non-approver. The write map does
  not permit that. Either an injection surface is built or the defect is recorded as uninjectable
  with the write map named as the reason.

### LEGAL — 0 / 5

- PD-LEGAL-002: class A. `customer_terms_acceptance` is `PHASE_D_STORE` with ownership scope
  CUSTOMER and no write-map row, so a committed acceptance costs one `phase_d_object_record` row and
  nothing else. This is the cheapest LEGAL defect to discharge.
- PD-LEGAL-001, PD-LEGAL-004: class B1 — certificate rendering and static-file freshness are outside
  the database; both need a §8 `record(...)`.
- PD-LEGAL-003: needs the founder approval path wired to `phase_c_refund_decision`. Same missing
  wiring as PD-FIN-001.
- PD-LEGAL-005: needs a COMPLIANCE review path that does not exist as a Phase D step.

### QUOTE — 0 / 5

See §5 for the write path in full. In summary: PD-QUOTE-001 and PD-QUOTE-004 need §8 `record(...)`
calls; PD-QUOTE-002 needs a publish attempt; PD-QUOTE-003 needs a step that writes an
evidence-bearing claim; PD-QUOTE-005 needs the normalization path.

### TRACE — 0 / 5

Four of the five (PD-TRACE-001/002/003/005) are class C: the subject is a kernel-owned relation and
`fn_phase_d_object_write` refuses it with `pd_object_kernel_owned`. They should be recorded as out of
scope, not as coverage debt — a Phase D coverage figure that counts them will never reach 5 / 5 and
will read as a permanent red for something Phase D is not permitted to touch.

PD-TRACE-004 is class A and is discharged by a committed run.

---

## 5. The QUOTE write path, from the code

The brief that commissioned this document says QUOTE "must use the mock adapter path rather than
writing `public.quotes`". The first half is right and the second is not: the mock adapter cannot
reach a QUOTE step. Measured:

`fn_phase_d_run_external_cases()` selects its population from `public.phase_d_step_effect` where
`expected_effect_type = 'EXTERNAL_EFFECT_INTENT'` (verified: its `prosrc` names both the table and
the literal). That predicate matches **12 steps**:

```
W03-S07 · W13-S01 W13-S02 W13-S03 W13-S04 W13-S05 W13-S06 W13-S07 · W15-S04 · W16-S02 · W17-S07 · W20-S06
```

No W14 step is among them, and W14 is the quotation workflow. `fn_phase_d_external_deliver(jsonb)`
is the adapter the case runner calls; it is never handed a QUOTE step, so it cannot exercise one.

### Why `public.quotes` must not be written by a harness

`public.quotes` carries **9** non-internal triggers, all `tgenabled = 'O'`: `mask_quote_contact`,
`quote_committed_hash`, `quotes_quality`, `reg_quote_doc`, `trg_event_quote`, `trg_new_quote_sms`,
`trg_quote_expiry_b`, `trg_scrub_quote_contacts`, `version_quote`.

`trg_new_quote_sms` runs `public.notify_new_quote_sms()`, whose body opens:

```sql
-- K20 cutover. A new quotation row is the declared start of W14. Placed at the TOP, before the
-- early return for an inquiry with no customer …
perform public.fn_kernel_source_emit('dbtrigger:public.quotes:trg_new_quote_sms', jsonb_build_object(
  'source_ref',  NEW.id::text,
  'raw_payload', jsonb_build_object('quotation_id', …, 'inquiry_id', …, 'supplier_id', …)));
select i.summary, i.customer_id into inq from public.inquiries i where i.id = NEW.inquiry_id;
if inq.customer_id is null then return NEW; end if;
```

The emit is unconditional and precedes the null-customer early return. `phase_c_source_cutover`
classifies `dbtrigger:public.quotes:trg_new_quote_sms` as `source_class = 'A NEW_WORK_REQUEST'`,
`target_workflow = 'W14'`, `current_activation = 'ACTIVE'` — so one row inserted into
`public.quotes` starts a real W14 workflow run. The recon measured that as
`kernel_trigger_inbox 1→2`, `phase_c_workflow_run 18→19`, `phase_c_workflow_step_run 24→25`,
`company_event 1439→1440`, with `notifications` unchanged (the SMS insert is unreachable while
`customers` holds 0 rows).

**And as of D36 it goes one hop further than that inventory records.**
`fn_kernel_workflow_start` opens the run's first step inline and calls `fn_phase_d_dispatch_step`,
which calls `fn_phase_d_handler_execute`. So an insert into `public.quotes` now also produces a
`phase_d_dispatch` row and, if the step's inputs resolve, a Phase D handler execution and an
effect-ledger row. Whether the recon's 8-relation inventory was taken before or after D36 landed is
not established here; `phase_d_dispatch` holds 0 rows today, which is consistent with the insert
never having been performed since.

### The safe surface

`quotation_evaluation` and `quotation_revision` are both
`relation_kind = 'PHASE_D_OBJECT_VIEW'` / `current_status = 'PHASE_D_STORE'`, canonical relations
`public.v_obj_quotation_evaluation` and `public.v_obj_quotation_revision`, ownership scope COMPANY on
`owner_ref`, primary identity `business_key`. Neither has a row in `phase_d_object_write_map`.

`fn_phase_d_object_write` reads `phase_d_object_write_map` and writes `public.phase_d_object_record`;
an object with no write-map row therefore lands only in `phase_d_object_record`. The recon measured
exactly that for `quotation_evaluation`: `phase_d_object_record` 0→1, with `public.quotes`,
`notifications`, `company_event`, `kernel_trigger_inbox` and `phase_c_workflow_run` all unchanged.
Genuinely inert.

30 of the 56 bound objects are `PHASE_D_OBJECT_VIEW` and 30 are `PHASE_D_STORE` — the same 30.

### The one exception, named so it is not walked into

`quotation` is not in that set. Its `phase_d_object_write_map` row reads:

| field | value |
|---|---|
| `target_relation` | `public.quotes` |
| `operation` | `UPSERT_STATE` |
| `key_column` | `id` |
| `owner_column` | `supplier_id` |
| `column_map` | `{"id":"business_key","status":"state","inquiry_id":"inquiry_id","supplier_id":"owner_ref","quote_amount":"quote_amount"}` |

`quotes.id` is **uuid** and receives `business_key`; `quotes.supplier_id` is **bigint** and receives
`owner_ref`. A wrong shape raises `22P02`; a fabricated owner raises `23503 quotes_supplier_id_fkey`.
Both refusals happen before the triggers fire, which is why an accidental probe against `quotation`
usually errors rather than starting a workflow — but a well-formed one will start W14.

**So: exercise QUOTE through `quotation_evaluation` / `quotation_revision`, never through
`quotation`, and not through the mock adapter, which never sees a W14 step.**

---

## 6. G1 — the 54 event self-loops are not a Phase D defect

`fn_phase_d_event_state()` check #4 publishes `event_self_loops` with an expected value of `0`
against a measured 54. Measured on the subject rather than on the check:

| measurement | value |
|---|---|
| `phase_d_event_reconciliation` rows | 347 |
| `is_self_loop` | 54 |
| `producer = primary_consumer_role_id` | 54 — the same 54; 0 rows differ either way |
| of the 54, producer is the step's own `phase_b_workflow_step.accountable_role_id` | 54 |
| of the 54, `next_step_if_pass = 'WORKFLOW_COMPLETE'` | 15 |
| of the 54, successor step accountable to the **same** role | 39 |
| of the 54, successor accountable to a **different** role | **0** |
| of the 54, successor unresolved, or event id yielding no step id | 0 |
| `phase_b_event` rows | 347; join on `event_id` matches all 347 |
| producer mismatches against `phase_b_event.emitted_by` | **0** |
| consumer mismatches against `phase_b_event.primary_consumer_role_id` | **0** |

The reconciliation copies both roles verbatim from `phase_b_event` and gets them right on every row.
Every self-loop is a step whose emitting role either ends the workflow or hands to a successor it
also owns. That is a property of the frozen Phase B workflow graph. **It is not a Phase D repair and
no Phase D file should drive 54 to 0.**

The remediation plan's premise for G1 is inverted. It states `consumer_resolves` is false on 346 of
347. Measured: `consumer_resolves` is **true on 346** and false on **1** — `EV-W14-S04-COMPLETED`,
producer `quote_evaluation_specialist`, consumer `relevant_category_overlay`, a dynamic-actor token,
`is_self_loop = false` and therefore not among the 54. `producer_resolves` is 286 true / 61 false.

Two boundaries to state out loud:

1. `public.phase_b_event` carries **zero** non-internal triggers — no `z90_phase_b_freeze`, not even
   `z00_kernel_truncate_guard`. `public.phase_b_workflow_step` does carry all three. So "frozen" is
   accurate for the step graph the self-loops are derived from and is a convention, not an
   enforcement, for the event table itself. Every blocker and board that calls the self-loops "a
   FROZEN Phase B property" — PD-OUTBOX-004's included — is relying on a freeze that is not attached
   to the table it names.
2. The residual red is the check's **expected value**, not the data. If it is restated, the honest
   form keeps a zero expectation and narrows the subject —
   `is_self_loop and next_step_if_pass <> 'WORKFLOW_COMPLETE' and successor_owner <> producer` —
   which measures 0 today and would fire on a genuine regression. Retyping `'0'` as `'54'` would be
   an expectation typed into the check it guards, and is not proposed here.

---

## 7. Boundary of this document

- Every count above was read from production with `select`. Nothing was written.
- `fn_phase_d_run_injected_defects()` was **not** called while preparing this document. It is
  VOLATILE and not idempotent within a transaction: measured over three sequential calls in one
  aborted transaction, call 1 reported 0 `NOT_REFUSED` and call 2 reported 2 (PD-OUTBOX-001 and
  PD-OUTBOX-002, whose outbox attempt counts accumulate). The 37 / 38 baseline and the per-defect
  blocker text quoted here come from the committed
  `docs/phase-d/PHASE_D_INJECTED_DEFECT_RESULT.csv`, which is that runner's first-invocation output.
- Class A is a statement about mechanism. With `phase_d_dispatch` at 0 rows, **no class-A defect has
  been observed discharged.** Do not publish class A as coverage until a real arrival has produced a
  `phase_d_dispatch` row with outcome `EXECUTED`.
- The `INPUTS_UNRESOLVED` outcome means a step can be dispatched and still not reach the handler.
  How many of the 257 steps resolve all their declared inputs from a real source is not measured
  here, and it bounds class A.
