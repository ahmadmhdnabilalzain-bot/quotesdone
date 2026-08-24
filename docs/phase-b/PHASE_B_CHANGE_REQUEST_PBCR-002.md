# PBCR-002 — the decision vocabulary 33 of the 35 decision steps do not have

**Status on 24 Aug 2026: RAISED. NOT APPROVED. NOT APPLIED.**
`public.fn_phase_b_baseline_drift()` returns **0 rows**. The effective Phase B baseline is unchanged
— 30 workflows / 257 steps / 56 objects / 54 rules / 32 gates / 159 handoffs / 347 events. Nothing
in this session changed a frozen Phase B row and nothing in this document records an approval.

**This change request is not required for Phase D to be re-audited.** It is raised because §4 of the
founder's instruction of 24 Aug 2026 requires that every consequential closed-domain field either
carry an authoritative domain or be covered by a formal change request, and 33 of the 35 `decision`
fields have no vocabulary anywhere in the frozen estate. Inventing one is what the same section
forbids. The recommendation at the foot of this document is **decide the 15, and drop the key on the
18** — but either answer is his.

---

## What Gate 5 measured, and what is now fixed without him

The final independent acceptance audit measured that `schema_output_w17_s06` accepted
`decision = NOT_A_DECISION`, and that the hole was structural: **140 of 257 output schemas typed a
consequential verdict-shaped key as a bare string with no domain** — `decision` on 35 steps,
`verdict` on 47, `state_change` on 58.

Re-measured here, the cause was one line each in `public.fn_phase_d_handler_execute`:

```
when 'DECISION_HANDLER'  then … 'decision',     coalesce(s.required_output,'')
when 'EXECUTION_HANDLER' then … 'state_change', coalesce(s.required_output,'')
```

`phase_b_workflow_step.required_output` is a **prose sentence** — "Case decision with required
actions.", "Active customer account." So the field named `decision` never carried a decision and the
field named `state_change` never carried a state; both carried a restatement of the artefact, which
the `output` key already carries in full. There was nothing for a domain to be about.

**478 of the 2,793 (schema, field) pairs across all 514 schemas now carry an enforced domain**
(was 257, all of them `status`), and none of the values was invented:

| field | schemas | authority |
|---|---|---|
| `status` | 257 | `fn_phase_c_output_validate` — the frozen Phase C output authority |
| `state_change` | 58 | `phase_d_object_state_contract.allowed_states`, enforced by trigger `z40_phase_d_object_record_contract` |
| `target_object` | 58 | the 56-id business-object registry (identical across three tables) |
| `verdict` | 47 | `fn_kernel_review_decide`, a frozen Phase C subject; corroborated by CHECK `phase_d_file_revision_verdict_ck` |
| `method` | 31 | the only reachable value in the producing routine |
| `receiving_role_id` | 25 | frozen `phase_b_handoff.receiving_role_id`, canonicalised through `fn_phase_c_resolve_actor` |
| `decision` | **2** | W17-S06 → CHECK `phase_c_refund_decision_ck`; W08-S06 → CHECK `phase_d_file_revision_verdict_ck` |

`decision = NOT_A_DECISION` on W17-S06 is now **refused**. That closes what Gate 5 named.

---

## What is left, and why it is his

The other **33** decision steps. They fall into two groups, and the difference matters.

### Group 1 — fifteen steps whose frozen contract names ALTERNATIVES in prose

The frozen `phase_b_workflow_step.required_action` genuinely enumerates the choices. Verified
undrifted against the sealed `docs/phase-b/PHASE_B_WORKFLOW_STEP_REGISTRY.csv`.

| step | frozen text | alternatives it names |
|---|---|---|
| W01-S06 | "Approve the operating objective set within founder boundaries or escalate reserved decisions." | approve / escalate |
| W02-S06 | required_output: "Approved corrective initiative or founder decision request." | approve / escalate |
| W05-S07 | "Set the inquiry to quote-ready, waiting for customer, blocked, rejected or cancelled." | five |
| W06-S05 | "Confirm, reject or leave proposed each route and record the basis." | three |
| W07-S02 | "Classify the document as BOQ/specification, drawing/CAD, image, certificate or other supported evidence." | five |
| W10-S05 | "Approve, request correction, refuse, suspend or escalate the supplier." | five |
| W14-S08 | "Approve the quote for comparison, hold for clarification or exclude with reason." | three |
| W16-S04 | required_output: "Updated payment state." | the six rungs of `phase_d_payment_state` |
| W21-S05 | "Approve, reject or escalate the opportunity based on fit, risk and economics." | three |
| W22-S07 | step_name: "Release go/no-go" | go / no-go |
| W23-S02 | "Define expected behavior, safety, latency, cost, regression and rollback criteria." | (see group 2) |
| W23-S08 | "Accept the evaluated change as a release candidate or return it for correction." | two |
| W24-S06 | "Issue the final independent go/no-go within the founder-approved deployment policy." | go / no-go |
| W28-S07 | "Approve, refuse, condition or escalate the proposed act." | four |
| W30-S07 | "Restore authority, continue restriction, reassign work or propose retirement based on evidence." | four |
| W30-S10 | required_output: "Founder-approved/rejected organization change request." | approved / rejected |

**The alternatives are frozen. The TOKENS are not.** "request correction" is a phrase; whether the
value written into a contract is `correction_requested`, `request_correction`, `changes_requested`
or something else is a decision nobody has made. A spelling this session chose would appear in **no
routine body, no check constraint and no committed file** — measured: `correction_requested`,
`held_for_clarification`, `retirement_proposed`, `partially_resolved`, `request_further_evidence` and
`leave_proposed` return zero hits across `pg_proc.prosrc`, every `pg_constraint` definition, and
every file under `docs/` and `supabase/`. That is an invented domain value, which §4 forbids as
firmly as it forbids leaving the field unconstrained.

**W16-S04 was nearly assigned the six-rung payment ladder and is deliberately not.**
`public.phase_d_payment_state` carries **no CHECK constraint** (only `PRIMARY KEY (state_key)` and
`UNIQUE (rung)`) and **no foreign key anywhere references it**. BR-033 reads the CONTEXT key
`monetary_state`, never the output key `decision`, and passes only the two rungs with
`authorizes_reveal = true` — so four of the six would have been refused by the very rule cited as
the authority. It is in group 1 as a prose reading, not in the measured set.

**W17-S06 is a narrowing, and it is disclosed.** Its frozen `required_action` names five outcomes —
approve, reject, escalate, partially resolve, request further evidence — and the canonical service
admits two. Measured: no table in this estate can record the other three. §5 of the founder's
instruction directs this exact domain for this exact step, so it is applied; whether the frozen text
should be narrowed to match is part of what this change request puts to him.

### Group 2 — eighteen steps whose frozen contract names no choice at all

W01-S04, W03-S01, W04-S05, W11-S04, W13-S03, W15-S05, W18-S05, W19-S04, W20-S01, W22-S01, W23-S02,
W25-S02, W26-S02, W26-S08, W27-S06, W27-S09, W29-S02, W30-S03.

Their `required_action` is an act with a single artefact outcome — "Define affordable department
resource envelopes…", "Prioritize gaps by customer impact, revenue opportunity, risk and cost…",
"Capture the selected quotation/supplier…". For these the honest question is not *what vocabulary*
but **whether `decision` should be a required key on the schema at all**. It is currently a
duplicate of `output` with the step name stripped, and nothing downstream reads it: no
`phase_d_object_write_map` column map names a `decision` key on any mapped object, and the
DECISION_HANDLER effect payload adds only `decided_by` and `decided_at`.

---

## What was done in the meantime, so nothing is blocked

All 33 are recorded in `public.phase_d_output_domain_registry` with
`field_semantic_type = 'CLOSED_ENUM_UNDEFINED'`, each naming this change request in its
`domain_source` and quoting its own frozen `required_action`. A CHECK on that table refuses a
CLOSED_ENUM_UNDEFINED row that does not name a `PBCR-nnn`, so the hole cannot become silent.

They declare **no** `enum_domains` entry, so **no correct run can be refused by one**, and the
handler's derivation falls back to the frozen prose exactly as before. `fn_phase_d_schema_validate`
still enforces on all 33 that the key is present, is a string, is non-empty, and that the contract
is closed to invented keys.

**The board says so out loud.** `fn_phase_d_contract_state()` carries:

```
every_registered_closed_domain_is_declared_on_its_schema
  0 undeclared of 478 registered CLOSED_ENUM field(s);
  33 field(s) are registered CLOSED_ENUM_UNDEFINED and raised as PBCR-002 —
  their frozen contract states no vocabulary and one this session chose would be an invented value.
```

---

## The eleven required elements

| element | |
|---|---|
| **1. Subject** | `phase_b_workflow_step.required_action` / `required_output` for 33 steps, and the `decision` key on their output schemas. |
| **2. What is frozen today** | The 257 step rows, including their `required_action` and `required_output` text. Verified undrifted against the sealed committed registry, 0 of 35 drifted. |
| **3. What is proposed** | For the 15: a committed token registry giving each named alternative one exact value. For the 18: remove `decision` from the schema's `required_keys`, or state the vocabulary. **No change to workflow ownership, order, states, transitions, gates, business rules, handoff accountability, category-overlay authority or founder boundaries.** |
| **4. Why** | A field named `decision` that carries a prose sentence is the Gate 5 defect. It is closed for the 2 steps with an enforcing authority and cannot be closed for the other 33 without a vocabulary only he can set. |
| **5. Evidence** | Gate 5 of `PHASE_D_FINAL_INDEPENDENT_ACCEPTANCE_20260824.md`; the derivation lines quoted above, read from `pg_proc`; the zero-hit searches for the candidate tokens; `public.phase_d_output_domain_registry` (2,793 rows, 33 CLOSED_ENUM_UNDEFINED). |
| **6. Phase A impact** | None. `fn_phase_a_baseline_drift()` 0 rows. No department, role or overlay count moves. |
| **7. Phase B impact** | The 15 gain a token registry; the 18 either lose a schema key or gain a vocabulary. Counts unchanged either way: 30 / 257 / 56 / 54 / 32 / 159 / 347. |
| **8. Phase C / D impact** | `phase_d_handler_schema.enum_domains` gains up to 33 entries; `fn_phase_d_handler_execute`'s DECISION_HANDLER arm already reads caller → committed catalogue → prose, so a domained step is answered by a catalogue row exactly as W17-S06 and W08-S06 are now. |
| **9. Backward compatibility** | Full while deferred. Applying it would require a committed catalogue value per domained step, as P03 supplied for the two. |
| **10. Rollback** | Delete the added catalogue rows and rebuild `enum_domains` from the registry — the same statement P04 already uses. |
| **11. Change reason string** | `set local app.phase_b_change_reason = 'PBCR-002: the decision vocabulary 33 of the 35 decision steps do not have'` |

---

## The A / B / C classification, re-derived from the frozen text on 24 Aug 2026

The founder's instruction of 24 Aug requires each affected field to be classified, and requires
that PBCR-002 **not** be raised for values already enforced by the canonical review, refund,
payment, publication or state-transition services. This section is that classification, derived
from the frozen `required_action` / `required_output` and from what the estate actually enforces —
not inherited from the section above.

**The test applied to each field:**

| class | test |
|---|---|
| **A. DERIVED_FROM_EXISTING_FROZEN_CONTRACT** | an authority already in the estate refuses an out-of-domain value for this field, and the frozen contract's named outcomes map onto it **without a spelling choice** |
| **B. PHASE_D_SCHEMA_REPAIR_ONLY** | the frozen contract names no mutually-exclusive alternatives, so `decision` carries no choice. The repair is a Phase D schema-shape change — drop the key, or bind it to an already-enforced object-state domain. **No Phase B row moves** |
| **C. REQUIRES_PBCR-002** | the frozen contract names mutually-exclusive alternatives and **no authority anywhere in the estate spells them** |

### Class A — 478 (schema, field) pairs. Already applied. Nothing is asked of the founder.

Measured on production: `phase_d_output_domain_registry` holds 2,793 pairs, of which **478 carry an
enforced domain** — `status` 257, `state_change` 58, `target_object` 58, `verdict` 47, `method` 31,
`receiving_role_id` 25, `decision` 2 (W17-S06, W08-S06). Every allowed-values array was read from an
authority that already refuses an out-of-domain value elsewhere. **None of these is in PBCR-002 and
none should be** — that is exactly the case the founder's instruction forbids raising.

### Class B — 18 steps. Phase D schema repair. Nothing is asked of the founder.

W01-S04, W03-S01, W04-S05, W11-S04, W13-S03, W15-S05, **W16-S04**, W18-S05, W20-S01, W22-S01,
W23-S02, W25-S02, W26-S02, W26-S08, W27-S06, W27-S09, W29-S02, W30-S03.

Their frozen `required_action` is an act with one artefact outcome — *"Define affordable department
resource envelopes…"*, *"Prioritize gaps by customer impact…"*, *"Capture the selected
quotation/supplier…"*.

**Nothing downstream reads the key, re-measured 24 Aug 2026 — with one correction to the section
above.** Of the 22 rows in `public.phase_d_object_write_map`, **one** does name a `decision` key:
`review_record → public.review_chain`, mapping `decision → verdict`. But **no frozen step's declared
effect targets `review_record`** — `phase_d_step_effect` has 0 rows for that object — so no step's
`decision` output is ever read through it. The four steps that touch a review relation (W28-S01,
S02, S07, S08) write `public.legal_reviews`, whose write map carries only
`title / summary / doc_kind / risk_level` and **no** `decision` key, and which has no domain CHECK
constraint of any kind. The DECISION_HANDLER effect payload adds only `decided_by` and `decided_at`.

All 18 output schemas are identical in shape —
`{status, output, acceptance_assertions, evidence_refs, decision, rationale, authority_ref}` — and
none of them carries a `state_change` or `target_object` key, so `decision` is not a duplicate of a
domained sibling; it is a duplicate of `output`.

**W16-S04 moved from group 1 to class B on measurement, and this correction is the point of
re-deriving.** The section above placed it in group 1 as a prose reading. Measured:
`public.phase_d_object_state_contract` holds `payment_transaction → {open, pending, settled,
refunded, failed, reconciled}`, and that contract **is** enforced — by trigger
`z40_phase_d_object_record_contract` on `phase_d_object_record`, which is the same authority that
domained all 58 `state_change` fields. W16-S04's frozen action is *"Apply only an allowed
transaction-state transition using the provider event"* and its output is *"Updated payment state"*.
That is the state-transition service the founder's instruction names. No founder decision is
required: bind the field to the enforced contract, or drop it in favour of `state_change`.

*(The earlier objection stands against a different table. `public.phase_d_payment_state` carries no
CHECK and nothing references it, and BR-033 reads the context key `monetary_state`, never the output
key. Those are true and they are about `phase_d_payment_state`, not about
`phase_d_object_state_contract`.)*

### Class C — 15 steps. **This is all PBCR-002 asks for.**

| step | frozen text that names the alternatives | alternatives |
|---|---|---|
| W01-S06 | "Approve the operating objective set within founder boundaries **or escalate** reserved decisions." | approve / escalate |
| W02-S06 | output: "Approved corrective initiative **or** founder decision request." | approve / escalate |
| W05-S07 | "Set the inquiry to quote-ready, waiting for customer, blocked, rejected or cancelled." | five |
| W06-S05 | "Confirm, reject or leave proposed each route and record the basis." | three, **per route** |
| W07-S02 | "Classify the document as BOQ/specification, drawing/CAD, image, certificate or other supported evidence." | five |
| W10-S05 | "Approve, request correction, refuse, suspend or escalate the supplier." | five |
| W14-S08 | "Approve the quote for comparison, hold for clarification or exclude with reason." | three |
| **W19-S04** | "Approve a recovery, communication, support, restriction or exit recommendation." | five — **or one plan.** The sentence is genuinely ambiguous and resolving it is his call |
| W21-S05 | "Approve, reject or escalate the opportunity based on fit, risk and economics." | three |
| W22-S07 | "Issue the independent release decision and hand approved candidates to W24." | go / no-go |
| W23-S08 | "Accept the evaluated change as a release candidate or return it for correction." | two |
| W24-S06 | "Issue the final independent go/no-go within the founder-approved deployment policy." | go / no-go |
| W28-S07 | "Approve, refuse, condition or escalate the proposed act." | four |
| W30-S07 | "Restore authority, continue restriction, reassign work or propose retirement based on evidence." | four |
| W30-S10 | output: "Founder-approved/rejected organization change request." | approved / rejected |

**W19-S04 moved into class C**, replacing W16-S04, on the same re-derivation. Its frozen action
names five things after the word "Approve"; whether that is a choice among five or the approval of
one composite plan cannot be settled by measurement, and guessing it is what §4 forbids.

**Why no authority covers these fifteen.** Measured directly, not inferred:

- `public.transactions` — **no** status CHECK constraint;
- `public.inquiries` — **no** status CHECK constraint, so W05-S07's five states are enforced nowhere;
- `public.customers` — one CHECK, on `locale`; nothing on account state;
- `public.documents` — **no** kind CHECK, so W07-S02's five classifications are enforced nowhere;
- `phase_d_object_state_contract` covers object **lifecycles** (`organization_change_request →
  {open, recorded, accepted, selected, logged}`), not step decisions — "approved / rejected" is not
  in that set, so W30-S10 is not derivable from it;
- the candidate tokens a session would otherwise invent — `correction_requested`,
  `held_for_clarification`, `retirement_proposed`, `partially_resolved`,
  `request_further_evidence`, `leave_proposed` — return **0 hits in `pg_proc.prosrc` and 0 in every
  `pg_constraint` definition**, re-measured 24 Aug 2026. Under `docs/` and `supabase/` the only two
  files that contain any of them are **this change request** and
  `docs/phase-d/PHASE_D_BUILDER_CLOSURE.md`, both of which are discussing their absence. No
  authority anywhere spells them.

### Summary

| class | fields | asked of the founder |
|---|---|---|
| **A** | 478 (schema, field) pairs | nothing — already applied at HEAD |
| **B** | 18 `decision` fields | nothing — Phase D schema repair, no Phase B row moves |
| **C** | **15** `decision` fields | **one sentence** |

**PBCR-002's scope is therefore the 15 class-C steps, not 33.** The other 18 are Phase D's to
repair and are tracked as such.

### The exact PBCR-002 founder approval sentence

Required only for the 15 class-C fields, and only if he wants them given a vocabulary rather than
left registered as `CLOSED_ENUM_UNDEFINED`:

> **I approve PBCR-002 — the decision vocabulary for the fifteen steps classified C in
> `docs/phase-b/PHASE_B_CHANGE_REQUEST_PBCR-002.md`, sha256 `<B2>` — and the tokens listed there
> are the approved values.**

`<B2>` is the sha256 of **this file as committed**, read with
`sha256sum docs/phase-b/PHASE_B_CHANGE_REQUEST_PBCR-002.md` and stated in the commit that
introduces this section.

**A token list is not proposed here.** The alternatives are frozen and his; the spellings are not,
and a spelling this session chose would appear in no routine, no constraint and no committed file.
He can answer with the tokens, or with "use the words already in the frozen text", or by declining
— and Phase D is not blocked by any of the three, because all 33 stay registered
`CLOSED_ENUM_UNDEFINED` naming this change request, which fails no gate in
`PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1` §B Gate FD-02.

## Recommendation

**Defer the 18 and decide the 15 — but neither is urgent, and Phase D does not wait on either.**

For the 18, the more likely correct answer is that `decision` should not be a required key on a step
whose frozen contract names no choice. That is a schema-shape change, not a vocabulary, and it
should not be guessed.

For the 15, the alternatives are already his — they are in the frozen registry he approved. What is
missing is only the spelling, and one sentence from him settles it.

**What must NOT happen:** a session picking tokens because a gate reads better with them. A domain
whose members exist nowhere in the estate cannot refuse anything a writer produces; it is an
expectation typed into the check it guards, and it would make Gate 5 look closed while closing
nothing.
