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

**PBCR-002's scope is therefore the 15 class-C steps, not 33.** The other 18 were Phase D's to
repair and are repaired: scripts/sql/phase_d_q02_eighteen_decision_fields_that_duplicated_output.sql,
applied to production on 25 Aug 2026. Seventeen no longer declare the key and W16-S04 is bound to
the enforced payment-transaction state contract.

---

## The exact proposed vocabulary — all fifteen class-C steps

**This section replaces the one that said "a token list is not proposed here".** The founder's
instruction of 25 Aug 2026 requires an exact vocabulary table with no blanket "use the words in the
frozen text" sentence and no undefined token list, so every token below is written out.

**Where the tokens come from, and why that is not the same as inventing them.** Each value is a word
already in that step's own frozen `required_action` or `required_output`, lowercased and
snake_cased. The estate is not the source — measured 24 and re-measured 25 Aug 2026,
`correction_requested`, `held_for_clarification`, `retirement_proposed`, `quote_ready`,
`waiting_for_customer`, `returned_for_correction`, `no_go`, `conditioned`,
`other_supported_evidence`, `authority_restored`, `restriction_continued` and `work_reassigned`
return **0 hits in `pg_proc.prosrc` and 0 in every `pg_constraint` definition**, and under `docs/`
and `supabase/` the only files containing any of them are this change request and
`docs/phase-d/PHASE_D_BUILDER_CLOSURE.md`, both discussing their absence. **So this is a PROPOSAL
and it is his to accept, amend or refuse.** What it is not is a guess: a reader can check every
token against the frozen sentence beside it, which is the property "use the words in the frozen
text" asserted without ever doing.

**How to read the columns.**

- **state/object affected** — the `phase_d_object_state_contract` the step's declared effect writes,
  and the state each value implies. The mapping is a proposal too; the contracts themselves are
  measured and unchanged.
- **terminal / nonterminal** — terminal means the step's work is finished on that value and the
  workflow moves on or stops. Nonterminal means the same object comes back to a person or a step.
- **positive control** — the value the committed fixture catalogue would carry so the step can be
  driven, exactly as `PDF-4106` / `PDF-4107` do for W17-S06 and W08-S06 and `PDF-4108` now does for
  W16-S04.
- **invalid sentinel** — a value the domain must refuse.
  `phase_d_output_domain_registry_closed_is_complete` requires the control to be inside the domain
  and the sentinel to be outside it, so both are load-bearing rather than decorative.
- **compatibility** — every one of the fifteen declares NO domain today, so declaring one is
  strictly narrowing and **cannot be done without the catalogue row in the same change**: the
  DECISION_HANDLER arm falls back to the frozen `required_output` prose, which is not a member of
  any domain proposed here, so a domain applied alone would refuse every run of that step. This is
  measured, not feared — it is what `phase_d_p03` had to fix for the two steps that already have a
  domain.

---

### 1. W01-S06 — Approve operating objective set

> **Frozen:** *"Approve the operating objective set within founder boundaries or escalate reserved
> decisions."* — output: *"Approved company objectives or founder decision request."*

| field | `decision` |
|---|---|
| **allowed values** | `approved`, `escalated` |
| **definitions** | `approved` — the objective set is inside the founder boundaries and is approved as it stands. `escalated` — the set contains a reserved decision the step may not take, and it is referred to the founder. |
| **terminal / nonterminal** | `approved` **terminal** — the artefact is published and W01 proceeds. `escalated` **nonterminal** — the objective set waits on a founder decision. |
| **state / object affected** | `company_objective` {open, active, superseded, published}. `approved` → `published`; `escalated` → stays `open`. |
| **positive control** | `approved` |
| **invalid sentinel** | `zz_not_an_objective_decision` |
| **compatibility** | narrowing; needs its catalogue row in the same change |

### 2. W02-S06 — Approve corrective initiative

> **Frozen:** *"Select the intervention, expected result, owner, review date and stop condition."* —
> output: *"Approved corrective initiative or founder decision request."*

| field | `decision` |
|---|---|
| **allowed values** | `approved`, `escalated` |
| **definitions** | `approved` — the intervention, owner, review date and stop condition are settled and the initiative is approved. `escalated` — the initiative exceeds the step's authority and becomes a founder decision request. |
| **terminal / nonterminal** | `approved` **nonterminal** — the initiative is now work to be executed and reviewed. `escalated` **nonterminal**. |
| **state / object affected** | `performance_recovery_case` {open, in_progress, verified, resolved, closed, rejected}. `approved` → `in_progress`; `escalated` → stays `open`. |
| **positive control** | `approved` |
| **invalid sentinel** | `zz_not_a_corrective_decision` |
| **compatibility** | narrowing; needs its catalogue row in the same change |

### 3. W05-S07 — Decide qualification status

> **Frozen:** *"Set the inquiry to quote-ready, waiting for customer, blocked, rejected or
> cancelled."*

| field | `decision` |
|---|---|
| **allowed values** | `quote_ready`, `waiting_for_customer`, `blocked`, `rejected`, `cancelled` |
| **definitions** | `quote_ready` — qualification is complete and the inquiry may be routed to suppliers. `waiting_for_customer` — qualification cannot complete until the customer supplies something named in the reason. `blocked` — qualification cannot complete for a reason inside the company. `rejected` — the inquiry is refused on its merits. `cancelled` — the customer withdrew it. |
| **terminal / nonterminal** | `rejected` and `cancelled` **terminal**. `quote_ready` **nonterminal** — W06 continues. `waiting_for_customer` and `blocked` **nonterminal** — the inquiry returns to this step. |
| **state / object affected** | `inquiry` {open, active, suspended, closed}. `quote_ready` → `active`; `waiting_for_customer` → `suspended`; `blocked` → `suspended`; `rejected` → `closed`; `cancelled` → `closed`. |
| **positive control** | `quote_ready` |
| **invalid sentinel** | `zz_not_a_qualification_status` |
| **compatibility** | narrowing; needs its catalogue row in the same change |

### 4. W06-S05 — Confirm route set

> **Frozen:** *"Confirm, reject or leave proposed **each route** and record the basis."* — output:
> *"Versioned confirmed/proposed/rejected route set."*

| field | `decision` |
|---|---|
| **allowed values** | `confirmed`, `rejected`, `proposed` |
| **definitions** | Applied to the **route set**, which is what the step's declared effect writes. `confirmed` — at least one route is confirmed and the set is issued for dispatch. `proposed` — no route is confirmed yet; the set stands as a proposal. `rejected` — every route in the set is rejected. |
| **terminal / nonterminal** | `confirmed` **terminal** for the step. `proposed` **nonterminal**. `rejected` **terminal** — the set is closed and a new one must be built. |
| **state / object affected** | `inquiry_route_set` {open, issued, submitted, approved, rejected, superseded}. `confirmed` → `approved`; `proposed` → `issued`; `rejected` → `rejected`. |
| **positive control** | `confirmed` |
| **invalid sentinel** | `zz_not_a_route_set_decision` |
| **compatibility** | narrowing; needs its catalogue row in the same change |

> **THE ONE PLACE THE GRAIN DIFFERS FROM THE FIELD, AND IT IS DISCLOSED.** The frozen sentence says
> **each route**, and `decision` is one string per step run. This proposal puts the per-route
> confirm/reject/leave-proposed values in `output` — where the versioned route set already carries
> them — and uses `decision` for the set-level disposition above. The alternative is to declare that
> W06-S05 has no step-level decision at all and drop the key, which is what class B did for
> seventeen other steps. **Either is defensible and the choice is his.** It is called out here
> rather than settled quietly because a field whose grain does not match its subject is exactly the
> defect Gate 5 found.

### 5. W07-S02 — Classify document type and handling path

> **Frozen:** *"Classify the document as BOQ/specification, drawing/CAD, image, certificate or other
> supported evidence."*

| field | `decision` |
|---|---|
| **allowed values** | `boq_specification`, `drawing_cad`, `image`, `certificate`, `other_supported_evidence` |
| **definitions** | The document's classification, which selects its handling path. `boq_specification` — a bill of quantities or written specification. `drawing_cad` — a drawing or CAD file, which is the path that must reach redaction before any supplier sees it. `image` — a photograph or reference image. `certificate` — a certificate or compliance document. `other_supported_evidence` — supported evidence that is none of the four. |
| **terminal / nonterminal** | all five **nonterminal** — a classification routes the document, it does not finish it. |
| **state / object affected** | `inquiry_document` {open, issued, submitted, approved, rejected, superseded}. All five → `submitted`. Classification is not approval, and this step's declared effect is `CAPABILITY_REQUEST` with no effect object, so no state is written by the step itself. |
| **positive control** | `drawing_cad` |
| **invalid sentinel** | `zz_not_a_document_class` |
| **compatibility** | narrowing; needs its catalogue row in the same change |

### 6. W10-S05 — Issue verification decision

> **Frozen:** *"Approve, request correction, refuse, suspend or escalate the supplier."*

| field | `decision` |
|---|---|
| **allowed values** | `approved`, `correction_requested`, `refused`, `suspended`, `escalated` |
| **definitions** | `approved` — the supplier passes verification. `correction_requested` — a named defect must be corrected and resubmitted. `refused` — verification fails on its merits. `suspended` — the supplier is held pending something outside this step. `escalated` — the decision exceeds this step's authority. |
| **terminal / nonterminal** | `approved` and `refused` **terminal**. `correction_requested`, `suspended` and `escalated` **nonterminal**. |
| **state / object affected** | `supplier_verification_case` {open, in_progress, verified, resolved, closed, rejected}. `approved` → `verified`; `refused` → `rejected`; `correction_requested`, `suspended`, `escalated` → `in_progress`. |
| **positive control** | `approved` |
| **invalid sentinel** | `zz_not_a_verification_decision` |
| **compatibility** | narrowing; needs its catalogue row in the same change |

### 7. W14-S08 — Approve or exclude quote from comparison

> **Frozen:** *"Approve the quote for comparison, hold for clarification or exclude with reason."*

| field | `decision` |
|---|---|
| **allowed values** | `approved_for_comparison`, `held_for_clarification`, `excluded` |
| **definitions** | `approved_for_comparison` — the quote is eligible to appear in the comparison the customer sees. `held_for_clarification` — a named question must be answered by the supplier first. `excluded` — the quote does not enter the comparison, and the reason is recorded with it. |
| **terminal / nonterminal** | `approved_for_comparison` and `excluded` **terminal**. `held_for_clarification` **nonterminal**. |
| **state / object affected** | `quotation` {open, active, suspended, closed}. `approved_for_comparison` → `active`; `held_for_clarification` → `suspended`; `excluded` → `closed`. |
| **positive control** | `approved_for_comparison` |
| **invalid sentinel** | `zz_not_a_comparison_decision` |
| **compatibility** | narrowing; needs its catalogue row in the same change |

### 8. W19-S04 — Approve supplier intervention

> **Frozen:** *"Approve a recovery, communication, support, restriction or exit recommendation."* —
> output: *"Supplier retention action plan."*

| field | `decision` |
|---|---|
| **allowed values** | `recovery`, `communication`, `support`, `restriction`, `exit` |
| **definitions** | The kind of intervention approved. `recovery` — a plan to bring performance back inside policy. `communication` — a communication to the supplier and nothing more. `support` — assistance provided to the supplier. `restriction` — the supplier's work is restricted while the case runs. `exit` — the relationship is ended. |
| **terminal / nonterminal** | `exit` **terminal**. The other four **nonterminal** — each becomes a plan with a measurement window. |
| **state / object affected** | `supplier_retention_case` {open, in_progress, verified, resolved, closed, rejected}. `exit` → `closed`; the other four → `in_progress`. |
| **positive control** | `recovery` |
| **invalid sentinel** | `zz_not_an_intervention_kind` |
| **compatibility** | narrowing; needs its catalogue row in the same change |

> **THE ONE GENUINELY AMBIGUOUS SENTENCE, AND IT IS STILL AMBIGUOUS.** *"Approve a recovery,
> communication, support, restriction or exit recommendation"* reads two ways and measurement cannot
> settle it: **(a)** five mutually-exclusive recommendation kinds, which is the reading above and
> the one that makes `decision` a decision; **(b)** one composite plan that may contain any of the
> five, in which case the domain is `{approved, escalated}` and the five belong in `output` beside
> the measurement window. Reading (a) is proposed because the frozen output — *"Supplier retention
> action plan"* — names one plan and the frozen action names its kind. **If he intends (b), the
> tokens for this step are `approved` and `escalated` and everything else in this row is unchanged.**

### 9. W21-S05 — Approve engagement path

> **Frozen:** *"Approve, reject or escalate the opportunity based on fit, risk and economics."*

| field | `decision` |
|---|---|
| **allowed values** | `approved`, `rejected`, `escalated` |
| **definitions** | `approved` — the opportunity is pursued. `rejected` — it is declined on fit, risk or economics. `escalated` — it exceeds this step's authority and goes to the founder. |
| **terminal / nonterminal** | `approved` and `rejected` **terminal**. `escalated` **nonterminal**. |
| **state / object affected** | `partnership_opportunity` {open, in_progress, verified, resolved, closed, rejected}. `approved` → `verified`; `rejected` → `rejected`; `escalated` → `in_progress`. |
| **positive control** | `approved` |
| **invalid sentinel** | `zz_not_a_partnership_decision` |
| **compatibility** | narrowing; needs its catalogue row in the same change |

### 10. W22-S07 — Release go/no-go

> **Frozen:** *"Issue the independent release decision and hand approved candidates to W24."* —
> output: *"Release decision and W24 handoff."*

| field | `decision` |
|---|---|
| **allowed values** | `go`, `no_go` |
| **definitions** | `go` — the change is released and the candidate is handed to W24. `no_go` — it is not released and returns for correction. |
| **terminal / nonterminal** | `go` **terminal** for W22 and opens the W24 handoff. `no_go` **terminal** for this release attempt; the change returns to development. |
| **state / object affected** | `product_change` {open, active, superseded, published}. `go` → `published`; `no_go` → `active`. |
| **positive control** | `go` |
| **invalid sentinel** | `zz_not_a_release_decision` |
| **compatibility** | narrowing; needs its catalogue row in the same change |

### 11. W23-S08 — Approve release-candidate handoff

> **Frozen:** *"Accept the evaluated change as a release candidate or return it for correction."*

| field | `decision` |
|---|---|
| **allowed values** | `accepted`, `returned_for_correction` |
| **definitions** | `accepted` — the evaluated AI change becomes a release candidate and is handed to W24. `returned_for_correction` — it goes back with the failing criterion named. |
| **terminal / nonterminal** | `accepted` **terminal** for W23. `returned_for_correction` **nonterminal**. |
| **state / object affected** | `ai_change` {open, active, superseded, published}. `accepted` → `published`; `returned_for_correction` → `active`. |
| **positive control** | `accepted` |
| **invalid sentinel** | `zz_not_a_handoff_decision` |
| **compatibility** | narrowing; needs its catalogue row in the same change |

### 12. W24-S06 — Issue release go/no-go

> **Frozen:** *"Issue the final independent go/no-go within the founder-approved deployment policy."*

| field | `decision` |
|---|---|
| **allowed values** | `go`, `no_go` |
| **definitions** | `go` — the release candidate is deployed under the founder-approved deployment policy. `no_go` — it is not, and the reason is recorded against the candidate. |
| **terminal / nonterminal** | both **terminal** — this is the final independent decision. |
| **state / object affected** | `release_candidate` {open, issued, submitted, approved, rejected, superseded}. `go` → `approved`; `no_go` → `rejected`. |
| **positive control** | `go` |
| **invalid sentinel** | `zz_not_a_release_verdict` |
| **compatibility** | narrowing; needs its catalogue row in the same change |

> The two `go`/`no_go` steps deliberately share a spelling. They are different decisions on
> different objects — W22-S07 releases a product change, W24-S06 deploys a release candidate — and a
> shared token for the same act at two gates is how the estate already treats `approved` at W08-S06
> and W17-S06.

### 13. W28-S07 — Issue review decision

> **Frozen:** *"Approve, refuse, condition or escalate the proposed act."*

| field | `decision` |
|---|---|
| **allowed values** | `approved`, `refused`, `conditioned`, `escalated` |
| **definitions** | `approved` — the proposed act may proceed as described. `refused` — it may not. `conditioned` — it may proceed only if the named conditions are met, and the conditions are recorded with it. `escalated` — the decision exceeds this reviewer's authority. |
| **terminal / nonterminal** | `approved` and `refused` **terminal**. `conditioned` and `escalated` **nonterminal**. |
| **state / object affected** | `legal_risk_review` {open, in_progress, verified, resolved, closed, rejected}. `approved` → `resolved`; `refused` → `rejected`; `conditioned` and `escalated` → `in_progress`. |
| **positive control** | `approved` |
| **invalid sentinel** | `zz_not_a_review_decision` |
| **compatibility** | narrowing; needs its catalogue row in the same change |

### 14. W30-S07 — Restore, continue restriction or reassign

> **Frozen:** *"Restore authority, continue restriction, reassign work or propose retirement based on
> evidence."*

| field | `decision` |
|---|---|
| **allowed values** | `authority_restored`, `restriction_continued`, `work_reassigned`, `retirement_proposed` |
| **definitions** | `authority_restored` — the evidence supports returning the capability's authority. `restriction_continued` — the restriction stands and the case runs on. `work_reassigned` — the work moves to another owner while the case runs. `retirement_proposed` — retirement is proposed, which is a recommendation and not the retirement itself. |
| **terminal / nonterminal** | `authority_restored` **terminal**. The other three **nonterminal** — `retirement_proposed` in particular opens W30-S10, where the founder decides. |
| **state / object affected** | `capability_case` {open, in_progress, verified, resolved, closed, rejected}. `authority_restored` → `resolved`; `retirement_proposed` → `verified`; `restriction_continued` and `work_reassigned` → `in_progress`. |
| **positive control** | `authority_restored` |
| **invalid sentinel** | `zz_not_a_capability_decision` |
| **compatibility** | narrowing; needs its catalogue row in the same change |

### 15. W30-S10 — Approve formal organizational change request

> **Frozen:** *"Prepare the formal Phase A change request for founder decision."* — output:
> *"Founder-approved/rejected organization change request."*

| field | `decision` |
|---|---|
| **allowed values** | `approved`, `rejected` |
| **definitions** | `approved` — the founder approved the organization change request. `rejected` — he rejected it. |
| **terminal / nonterminal** | both **terminal**. |
| **state / object affected** | `organization_change_request` {open, recorded, accepted, selected, logged}. `approved` → `accepted`; `rejected` → `logged`. |
| **positive control** | `rejected` |
| **invalid sentinel** | `zz_not_a_change_request_decision` |
| **compatibility** | narrowing; needs its catalogue row in the same change |

> **THIS ONE IS A FOUNDER DECISION AND ITS POSITIVE CONTROL IS `rejected` ON PURPOSE.** The frozen
> output says *founder-approved/rejected*, and Phase A is frozen: changing the number of
> departments, canonical roles or category overlays needs a real PACR with his approval in a
> verified session. So the value on this field must be **derived from a recorded founder decision**,
> never asserted by a caller — the same shape `fn_phase_c_require_founder` already enforces on the
> refund door, and the shape PCCR-006 extends to the governance path. The fixture carries `rejected`
> for the identical reason `PDF-4106` carries `rejected` for W17-S06: it is the outcome a
> non-founder may record.

---

## Migration and rollback for the fifteen

Neither is applied by this document, and neither may be applied before his approval.

| | |
|---|---|
| **Migration** | `scripts/sql/phase_b_pbcr002_the_decision_vocabulary_for_fifteen_steps.sql` — for each of the fifteen: set `phase_d_handler_schema.enum_domains->'decision'` to the values above, bump `schema_version`, re-derive `source_digest` from the frozen step text; move the registry row from `CLOSED_ENUM_UNDEFINED` to `CLOSED_ENUM` with `allowed_values`, `valid_control_value`, `invalid_sentinel_value`, `domain_source` quoting the frozen sentence and `source_digest` from `fn_phase_d_domain_source_digest('table:public.phase_b_workflow_step')`; and insert one `phase_d_fixture_catalogue` row per step (`PDF-4109` … `PDF-4123`) carrying the positive control. Stated in the same transaction as `set local app.phase_b_change_reason = 'PBCR-002: the decision vocabulary 33 of the 35 decision steps do not have'`. **NOT WRITTEN AND NOT COMMITTED** until he approves — a committed migration for an unapproved change is a file one command away from being applied. |
| **Rollback** | `scripts/sql/phase_b_pbcr002_the_decision_vocabulary_for_fifteen_steps_down.sql` — delete the fifteen catalogue rows, remove `decision` from `enum_domains` on the fifteen schemas, and return each registry row to `CLOSED_ENUM_UNDEFINED` naming PBCR-002. This is the same statement pair `phase_d_p04` already uses, and it restores exactly the state this document describes today. |

**Nothing in Phase D is blocked by any of this.** All fifteen stay registered
`CLOSED_ENUM_UNDEFINED` naming this change request, which fails no gate in
`PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1` §B Gate FD-02. The eighteen class-B fields are already
repaired — `scripts/sql/phase_d_q02_eighteen_decision_fields_that_duplicated_output.sql`, applied to
production on 25 Aug 2026 — so `decision` fields now number 18, of which 3 carry an enforced domain
and 15 are these.

### The exact PBCR-002 founder approval sentence

Required only for the 15 class-C fields:

> **I approve PBCR-002 — the decision vocabulary for the fifteen steps classified C in
> `docs/phase-b/PHASE_B_CHANGE_REQUEST_PBCR-002.md`, sha256 `<B2>` — and the tokens listed there
> are the approved values.**

`<B2>` is the sha256 of **this file as committed**, read with
`sha256sum docs/phase-b/PHASE_B_CHANGE_REQUEST_PBCR-002.md` and stated in the commit that introduces
this section and in the decision packet that accompanies it. It is deliberately not written inside
the file: a digest that quotes itself cannot be recomputed.

**Two of the fifteen carry a question he may want to answer differently**, and both are marked above
rather than resolved quietly: W06-S05, where the frozen sentence's grain is per route and the field
is per step run; and W19-S04, where *"Approve a recovery, communication, support, restriction or
exit recommendation"* reads as five kinds or as one composite plan. If he answers only those two,
the other thirteen stand as written.

## Recommendation

**Decide the fifteen. The eighteen are done.**

The eighteen class-B fields were a Phase D schema repair and are applied — seventeen no longer
declare a key their frozen contract gave no choice for, and W16-S04 is bound to the
payment-transaction state contract that was already enforced. Nothing was asked of him for any of
them.

For the fifteen, the alternatives are already his — they are in the frozen registry he approved.
What was missing was the spelling, and it is now written out above so his answer can be one sentence
instead of a design exercise.

**What must NOT happen:** a session applying these tokens because a gate reads better with them. A
domain whose members exist nowhere in the estate cannot refuse anything a writer produces until the
schemas declare it AND the catalogue can answer it; applied without his approval it would be an
expectation typed into the check it guards, and it would make Gate 5 look closed while closing
nothing. That is why the migration above is described and not committed.
