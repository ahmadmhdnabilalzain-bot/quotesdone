# Phase D — financial and privacy result

**Measured on production in aborted transactions. Where a control is asserted, it was made to FIRE
before it was believed.**

---

## 1. Money — the rungs, and what each authorises

`public.phase_d_payment_state` is a **6-rung ladder**, and only **2 rungs authorise a reveal**:

| rung | state | authorises reveal |
|---|---|---|
| 1 | `checkout_created` | no |
| 2 | `payment_initiated` | no |
| 3 | `provider_success` | no |
| 4 | `payment_confirmed` | no |
| 5 | `payment_reconciled` | **yes** — the ladder itself calls this "the founder-approved bar in BR-020" |
| 6 | `reveal_authorized` | **yes** — terminal, recorded separately so a reveal that already happened is distinguishable from one that merely may |

The ladder's own text is the reasoning: a provider 200 is "the provider's claim about itself", and
"confirmed is a fact about the EVENT" — neither is reconciliation. Nothing below rung 5 authorises a
reveal.

**Proved by injection (PD-FIN-005):** setting a payment object's working state to a value that is
not a rung is **refused** — `pd_stage_payment_state_undeclared`. The guard is a trigger that reads
the ladder table, not a CHECK listing six literals, so adding a rung is picked up rather than
contradicted. Spelling the rungs into a CHECK would be the "expectation typed into the check it
guards" defect this estate has already paid for.

## 2. Refunds — every one needs the founder

`z00_refund_founder_decision_only` fires when `status = 'approved'` and requires `decided_by` to be
an active row in `public.phase_c_founder_identity` (**2 active identities**).

**Proved by injection (PD-FIN-003), and this is the control that matters most in the phase:**

```
insert into public.refunds (... status='approved', decided_by='trust_and_safety_manager' ...)
  -> REFUSED, SQLSTATE 42501
```

**Phase D never approves a refund.** W17 writes the refund at its declared working state,
`requested`, and a deploy control asserts that a full 30-workflow drive leaves **0 refunds in
`approved`** and **0 approved refunds whose decider is not an active founder identity**. The guard is
therefore never engaged and no founder identity is forged anywhere.

### What changed, and what did not

W17 was carried into this session as a founder blocker. It was not one. GATE-020 reads
`public.refunds.decided_by` and `decided_at` — **not** `phase_c_refund_decision`, which both the
prior closure and the session brief assumed. W17-S06 "Decide case outcome" is a DECISION_HANDLER
accountable to `trust_and_safety_manager`, acting *within authority*, and it had **no columns to
record its decision in**. The decision columns joined the write map; the founder guard was not
touched.

### One finding that is his, not an engineer's

**GATE-020 guards a step called "Execute approved financial action" and checks only that *some*
decision exists — not that it was an approval.** A rejected case satisfies it. Phase B is frozen and
the gate contract is not Phase D's to change, so this is measured and reported rather than altered.
Under the hold nothing executes, so no money moves either way — but the gate's own name and its
predicate disagree.

## 3. Separation of duties — declared, not yet enforced by a Phase D path

`phase_c_refund_decision` carries `executor_role_id` and `reconciler_role_id`, which is the shape
separation of duties needs. **No Phase D path writes that table** — GATE-020 reads `public.refunds`
instead. So PD-FIN-001 ("payment marked reconciled by the executor") is **NOT_RUN**, with that as its
named blocker. It is not claimed as covered by the founder trigger, which enforces a different thing.

## 4. Privacy — ownership is declared on every object

All **56** bound objects carry an `ownership_scope`: **12 CUSTOMER**, **10 SUPPLIER**, the rest
COMPANY. The canonical writer resolves the owner from that scope rather than from a generated key —
CUSTOMER takes `customer_id`, SUPPLIER takes `supplier_id` — which is what stopped a customer-scoped
object being written under an identifier for a customer that does not exist.

`supplier_safe_package` is the object that separates what a supplier may see from what the customer
wrote, and GATE-013 tests **who approved it** rather than that it exists.

### The privacy work this phase did NOT do, stated plainly

Five of the six PRIVACY defects are **NOT_RUN**, and none is mapped onto a nearby guard:

| defect | blocker |
|---|---|
| supplier payload contains customer email | the safe package is recorded as an object; its **contents** are not rendered or scanned in Phase D |
| drawing has unapproved redaction | file revision state is a storage and document-pipeline fact |
| signed URL path belongs to another supplier | storage authorization; no Phase D path mints a signed URL |
| raw inquiry endpoint called by supplier | needs a supplier bearer token and a response body |
| hidden metadata leaks identity | needs a rendered artifact; no Phase D path renders one |

**All five need section 8, which is not built.** Calling them covered because some SQL-level guard
exists nearby would be exactly the defect this estate keeps finding — an instrument reporting on the
wrong subject.

## 5. Outbound identity exposure

The one privacy-adjacent thing this phase *did* prove is negative and important: before D17 every
fixture build enqueued **two outbound POSTs to production**, one of them `dispatch_inquiry` — the
RFQ offer to matched suppliers — while the factory reported `external_effects: 0`. Nothing was sent,
because every transaction aborts and pg_net reads committed rows. It is now **0**, guarded at the
canonical writer, and asserted on every scenario build.

---

## 6. Numbers

| | |
|---|---|
| payment rungs · rungs authorising reveal | **6** · **2** |
| active founder identities | **2** |
| refunds approved by Phase D | **0** |
| FINANCE defects executed and refused | **4 / 5** — PD-FIN-001 closed 24 Aug at br031_executor_is_reconciler, which is registered at fn_kernel_reviewer_independent and not at phase_c_refund_decision, as its blocker had said. PD-FIN-004 is a permanent exemption: a fixture may never forge a founder decision |
| PRIVACY defects executed | **3 / 5** — PD-PRIV-001 closed 24 Aug at br011_identity_before_reveal; PD-PRIV-003 refused as required; PD-PRIV-004 executed and could not discriminate, because closing it needs a committed inquiry and a committed inquiry cannot be reversed (the trace ledger is append-only and frozen); PD-PRIV-002 and PD-PRIV-005 are NOT_RUN, both because the subject — a drawing-revision redaction state, a rendered artifact — does not exist in this estate |
| objects carrying an ownership scope | **56 / 56** |
| outbound requests from a 30-workflow drive | **0** |

## Boundary of this evidence

Measured on the one project on 2026-08-19, and the two defect fractions re-measured on 2026-08-24 (database clock). Financial claims are about the ladder,
the trigger and the refunds relation. Privacy claims are about ownership scope and the outbound
surface **only** — this phase did not test any authenticated read path, any RLS policy, or any
storage object, and does not claim to have.

---

## 2026-08-24 — the four controls this session added, and what each was measured doing

Regenerated after the final production apply of the `phase_d_o01`–`phase_d_o10` sequence.
Project `htdblwldjkcgjvmqkbeh`. Every figure below was produced by executing the control on
production inside a transaction that aborts; nothing here is a claim about code that was read.

### Financial — PD-FIN-004, the append-only founder refund decision

The append-only control was never the gap. `a00_phase_c_refund_decision_immutable` refuses UPDATE
and DELETE and permits a superseding INSERT, and it has done throughout. What was missing was a
**producer**: `public.kernel_write_authority` held **zero** rows for `phase_c_refund_decision`, so
Door 1 of `fn_kernel_write_guard` could never open for it and **no routine in the estate could
create the row the trigger exists to protect**. The table held 0 rows and the guard had never been
asked a question.

`phase_d_o02` registers `public.fn_kernel_refund_decision_record` — the canonical founder refund
decision service. It resolves the founder through `fn_phase_c_require_founder` (28000 for anyone
with no verified auth subject) and writes `decided_by` **from the verified identity, never from the
call**, so the service cannot record a decision in his name even if a caller asks it to.

Driven 2026-08-24, one aborted transaction:

| arm | result |
|---|---|
| the service called with no verified founder subject | REFUSED `28000` |
| a decision recorded through the service | accepted; `decided_by` = the identity `fn_phase_c_require_founder` returned |
| an edit asked of the service | REFUSED `pd_refund_decision_append_only` |
| a raw UPDATE, past the audited maintenance door | REFUSED `23514` "the decision is append-only; supersede it, do not edit it" |
| a raw DELETE | REFUSED `23514` "a founder refund decision cannot be deleted" |
| the original row, re-read | **unchanged** |
| a superseding decision citing the prior one | **accepted** |
| `op='execute'` against the superseded decision | REFUSED `pd_refund_execution_without_founder_decision` |

The two raw arms are driven by `scripts/checks/protected_table_guards_actually_fire.test.mjs` and
not by the deliverable builder, because a literal `update public.phase_c_refund_decision` inside
`fn_phase_d_run_injected_defects` is exactly what `fn_kernel_write_guard_state`'s
`routines_that_write_a_protected_table_with_no_authority` exists to surface — it took that board
from 1 of 37 to 3 of 39 before the writes moved.

### Financial — the binding between the ledger and the money, which did not exist

`public.refunds` never read the ledger. There was no column joining the two and no predicate
requiring one, and `public.fn_refund_decide` gates on
`exists (select 1 from phase_c_founder_identity where lower(identity) = lower(btrim(p_decided_by)))`
— a **caller-supplied string** compared against a register, the shape PCCR-003 removed from
`fn_phase_c_require_founder` and which survived here. `z00_refund_founder_decision_only` returns
`NEW` untouched unless `status = 'approved'`, and `public.refund_status_transition` **allows**
`requested -> succeeded` ("Fast settlement; Stripe confirmed before we saw the pending event").
A refund could therefore reach `succeeded` — money moved — having passed no founder check of any
strength, against his standing ruling of 17 Aug 2026 that every refund needs him at any amount.

`phase_d_o02` adds `public.refunds.refund_decision_id` and
`z05_refund_execution_requires_decision`. A **platform-originated** refund may not arrive at or move
into `approved`, `processing` or `succeeded` without an approved, non-superseded decision on the
ledger. Refusal code `pd_refund_execution_without_founder_decision`. Measured: a platform refund
inserted at `succeeded` with no decision is refused; the identical row citing an approved decision
is accepted.

Measured before the guard, so it cannot break work in flight: `public.refunds` 0 rows,
`public.phase_c_refund_decision` 0 rows. The guard refuses nothing that exists.

**An externally originated settlement is admitted, not refused, and that is deliberate.**
`fn_refund_settle`'s outside-the-platform branch records money **Stripe already moved**. Refusing
that insert does not stop the refund; it destroys our only record of it. Those rows are admitted,
required to name their external originator, and counted separately by
`public.fn_kernel_refund_ledger_state()` so an externally settled refund can never be read as one
the founder approved.

`public.fn_refund_decide` and `public.refund_status_transition` were **not** changed. Their
weaknesses are real, they are recorded here, and closing them is a live-money production change on
a separate table — not a Phase D harness change.

### Privacy — PD-PRIV-002, the redaction state a supplier-facing revision had to carry

Before: `public.drawing_redaction_runs` recorded pipeline outcomes written by TypeScript
(`empty`, `detect_truncated`, `detect_failed`, `detect_exception`, `failed`, `partial`, `complete`,
`original_stored`) and not one of them is an approval by an accountable reviewer; **zero** pg_proc
bodies referenced the table, so no predicate could read it. BR-012 counted an approved package
record and resolved the approver string and never opened the file set, so a package with an
unredacted drawing and one with a clean drawing returned the **identical** `ENFORCED_PASS`.
GATE-013 never dereferenced `safe_package_ref` at all — the value reached only `format()`.

`phase_d_o04` adds `public.phase_d_file_revision` (source and safe digests, redaction state,
method, elements removed, reviewer, verdict, trace, supersession) with
`a10_phase_d_file_revision_reviewer` refusing an author who is also the reviewer, and
`public.fn_phase_d_file_revision_dispatchable`. `phase_d_o07` gives BR-012 and GATE-013 the leg.
Measured over the committed fixtures:

| revision | verdict |
|---|---|
| `zz-demo-rev-drawing-unredacted` (PENDING) | `pd_revision_redaction_unapproved` |
| `zz-demo-rev-drawing-rejected` (REJECTED) | `pd_revision_redaction_rejected` |
| `zz-demo-rev-drawing-superseded` | `pd_revision_superseded` |
| `zz-demo-rev-drawing-safe` (APPROVED, scanned CLEAN) | **dispatchable** |
| the same revision, dispatch naming different bytes | `pd_revision_digest_mismatch` |
| a package naming no revision at all | `pd_revision_redaction_state_absent` |

The package answer is the **worst** revision answer, never an average and never a majority: one
leaking file in a set is a leak.

### Privacy — PD-PRIV-005, the hidden metadata nothing looked at

`BR-011` was measured, before the change, returning `ok = TRUE` for
`/Author (ZZ DEMO Omar Bin Faisal) /Creator (AL NAHDA CONSULTANTS)` — its row arm searches
`public.customers` (0 rows) and its shape arm tested exactly two patterns. The exact injection this
case names — a customer's name in a PDF `/Info` dictionary — passed the one rule that names it.

`phase_d_o04` registers `public.phase_d_personal_identifier_class` (the list moves out of the
predicate, so extending it is a row and not a redeploy) and `public.phase_d_metadata_scan`, whose
CHECK refuses a `CLEAN` verdict that carries findings and an `IDENTIFIERS_FOUND` verdict that
carries none. `scripts/phase_d/metadata_scan.mjs` reads PDF `/Info` and XMP, PNG `tEXt`/`iTXt`/
`zTXt` and JPEG `APP1`/`COM` **with no dependency at all** — a metadata field is text in the bytes,
and this repository already writes PDFs by hand for the same reason.

Recorded by `run_metadata_scan_probe.mjs --write` over the committed fixtures:

```
supplier_drawing_dirty.pdf   IDENTIFIERS_FOUND  5   customer_email, customer_phone_ae, messenger_handle, filesystem_username
supplier_drawing_clean.pdf   CLEAN              0
supplier_photo_dirty.png     IDENTIFIERS_FOUND  4   customer_email, customer_phone_ae, customer_phone_intl, embedded_url
supplier_photo_clean.png     CLEAN              0
(a corrupt PNG)              SCAN_FAILED            fail-closed
(an unhandled media type)    UNSUPPORTED            fail-closed
```

`zz-demo-rev-photo-unredacted` is the case that matters most: it is **redaction-APPROVED by an
independent reviewer** and still refused, `pd_hidden_metadata_identifier_found`, because the bytes
its approval names carry identity a human reviewer did not see. A redaction approval is not a
metadata verdict, and the two are separate facts on separate columns.

**What this deliberately does not decide.** `person_name_freeform` and `site_address` are registered
`HUMAN_REVIEW`, not `REGEX`: a regular expression cannot decide whether a string is somebody's name,
and scoring that class automatically as absent is the "absent input scores as satisfied" shape.
`document_author_field` closes the machine-decidable half — a **populated** author, creator, owner
or last-modified-by field in a supplier-facing artefact has identified somebody whatever the value
is, and that is decidable.

### Zero cost and zero effect over these four controls

`public.llm_attempt` last row `2026-08-15 02:51:33+00`; `public.ai_usage` last row
`2026-07-13 23:37:25+00`. Neither moved during this session. No provider was called, no file left
the estate, no notification was sent, and `public.refunds` is still 0 rows.
