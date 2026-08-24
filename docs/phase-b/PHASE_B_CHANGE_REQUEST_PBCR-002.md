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
