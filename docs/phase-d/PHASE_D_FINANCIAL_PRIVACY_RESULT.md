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
| FINANCE defects executed and refused | **3 / 5** |
| PRIVACY defects executed | **2 / 5** — PD-PRIV-003 refused as required; PD-PRIV-004 executed and could not discriminate (see D44); the other three are NOT_RUN with a named blocker |
| objects carrying an ownership scope | **56 / 56** |
| outbound requests from a 30-workflow drive | **0** |

## Boundary of this evidence

Measured on the one project on 2026-08-19 (database clock). Financial claims are about the ladder,
the trigger and the refunds relation. Privacy claims are about ownership scope and the outbound
surface **only** — this phase did not test any authenticated read path, any RLS policy, or any
storage object, and does not claim to have.
