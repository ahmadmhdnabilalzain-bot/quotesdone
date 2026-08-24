# Phase D — final independent acceptance audit

**Verdict: PHASE_D_FINAL_ACCEPTANCE_FAIL**

Two mandatory gates fail on measurement. Nothing in this report was repaired, except one
production change **this audit itself caused**, which is disclosed in full in §A and was restored.

---

## Preflight record

| | |
|---|---|
| git commit | `6479d322032387d0ff16453663e7790c11538b09` (main, = `origin/main`, 0 ahead / 0 behind) |
| PR #464 | MERGED 2026-08-24T08:48:33Z → `2c9e3f2` |
| PR #465 | MERGED 2026-08-24T13:52:25Z → `6479d32` (= HEAD) |
| production project | `htdblwldjkcgjvmqkbeh` (one project; staging deleted 15 Aug 2026) |
| audit start | 2026-08-24T14:20:05Z |
| migration count | 728 in `supabase_migrations.schema_migrations`; Phase D applied production-direct through `scripts/sql` + `MANIFEST.txt` |
| active cron | 23 (selective automation-hold ceiling 25) |
| automation hold | held — GATE-032 measures 23 of 25 |
| provider hold | held — `fn_kernel_paid_provider_gate` refuses **every** named model: "8 of 8 routes are held open-circuit until 2126-08-15" |
| working tree | clean of tracked changes at audit start (`git status --porcelain -uno` = 0) |
| tags | `phase-a-…-2026-08-15`, `phase-b-…-2026-08-15`, `phase-c-founder-approved-2026-08-18` |

Nested repositories exist under `vendor/reference/` (5). They contain no `scripts/sql` or
`docs/phase-d` path and did not enter any scan.

---

## Gate results

| gate | subject | verdict |
|---|---|---|
| 0 | preflight and frozen baselines | **PASS** |
| 1 | PCCR state | **FAIL** |
| 2 | 15 required deliverables | PASS |
| 3 | migrations and rollbacks | PASS with findings |
| 4 | 257 step effects and real callers | PASS |
| 5 | 514 strict schemas | **FAIL** |
| 6 | 56 business objects | PASS |
| 7 | 54 rules and 32 gates | PASS |
| 8 | the nine final product controls | PASS |
| 9 | injected-defect catalogue | PASS |
| 10 | 1,799 step-contract cases | PASS |
| 11 | 159 handoffs | PASS |
| 12 | 347 events and the 54 self-loops | PASS |
| 13 | the reported 257 "no effect ever produced" | PASS |
| 14 | application paths, frontend and API | PASS |

---

## GATE 1 — FAIL. Founder approval on the governance path is a typed string

Present state is clean and is not the finding:

- PCCR-004 `DEFER_OR_REJECT`, `approved_by` null, `approved_at` null.
- PCCR-005 `DEFERRED`, `approved_by` null, `approved_at` null.
- `fn_phase_c_freeze_drift()` — `frozen_subjects_drifted` 0 of 25,
  `amendments_awaiting_founder_approval` 0 of 5, every row `ok=true`.
- Frozen `fn_kernel_cancel` and the Phase C review service are the live bodies; no proposed PCCR
  body is deployed.

The gate also requires proof that the new constraint and trigger **cannot** be walked past. They
can. Measured in aborted transactions on production:

**1. A deferred request accepts an approver — by being silently re-dispositioned.**

```
update public.phase_c_change_request
   set approved_by='management@quotesdone.com', approved_at=now()
 where change_request_ref='PCCR-004';
→ ACCEPTED
→ AFTER: disposition=APPROVED  approved_by=management@quotesdone.com
         reason="Founder disposition, 24 Aug 2026. The frozen cancellation se…"
```

`phase_c_change_request_deferral_is_not_approval` never fires, because the BEFORE trigger
`a15_phase_c_change_request_disposition_follows_approval` rewrites `disposition := 'APPROVED'`
first. The row that comes out carries the **deferral's own reason text as its approval reason**.
PCCR-005 behaves identically.

**2. A migration can write a verified-session approval it never had.**

```sql
insert into public.phase_c_freeze_amendment (…, approved_by, approval_basis,
       approval_route, approval_auth_subject, approved_amendment_table_digest, …)
values (…, 'management@quotesdone.com', 'AUTHENTICATED_FOUNDER_SESSION',
        'auth.uid()', '1256c7ec-17bf-4b1e-af8f-aaa32a8fdd14', repeat('a',64), …);
→ ACCEPTED
```

Every constraint checks only the **shape** of the claim: the route is in a list, the subject is
not null, the digest matches `^[0-9a-f]{64}$` — `repeat('a',64)` passes. Nothing compares
`approval_auth_subject` to an authenticated subject and nothing verifies the digest is the real
amendment-table digest.

**3. The guard behind both is a string comparison.**

`fn_phase_c_founder_approver_guard` resolves `new.approved_by` against
`public.phase_c_founder_identity` and returns. No session, no `auth.uid()`, no bound event.

**4. The change request itself states the guarantee that does not hold.**
`docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-004.md`, §11:

> `public.phase_c_change_request` carries a CHECK — `phase_c_change_request_deferral_is_not_approval`
> — that refuses an `approved_by` on a deferred or rejected request, **so this row cannot later be
> read as an approval.**

Measured above, the row *can* later be read as an approval, and it keeps the deferral's reason text
while doing so. The CHECK is real; it simply never sees a deferred row, because the trigger has
already changed the disposition by the time it is evaluated.

**This is the defect PCCR-003 already fixed on the money path, left unfixed on the governance
path.** `fn_phase_c_require_founder` — reached in the same estate, verified here — raises `28000`
on a typed identity and requires a `phase_c_founder_auth_event` row carrying `txid_current()`:

```
refund door, no session      → REFUSED 28000 "no verified auth subject on this call"
refund door, typed founder   → REFUSED 28000  (same)
```

The consequence is that `fn_phase_c_freeze_drift`'s row
*"An approval recorded from a written instruction is not a founder session… which no migration can
perform"* is an assertion its own columns cannot enforce. The board is green because nobody has
written the row, not because the row is refused.

**What does compensate, stated so the finding is not read as larger than it is.**
`scripts/checks/pccr_approval_matches_committed_tables.test.mjs` recomputes the sha256 of
`docs/phase-d/PHASE_D_PCCR_AMENDMENT_TABLES.md` and compares it to each row's
`approved_amendment_table_digest`. Run here: all five amendments match, and a forged row carrying
`repeat('a',64)` would fail it. That is a real control — but it is a **repository check, not a write
guard**, and it has two gaps that matter for this gate:

- it covers `phase_c_freeze_amendment` only. The PCCR-004/PCCR-005 disposition flip on
  `phase_c_change_request` is guarded by nothing at all;
- Phase D deploys production-direct — apply first, PR afterwards — so a forged row would be **live**
  for the whole window between apply and merge, and `fn_phase_c_freeze_drift()`, which every closure
  document cites, would read green the entire time.

Gate 1 required: *a migration to forge founder approval = not allowed*, and *written instruction to
be presented as verified-session approval = not allowed*. At the layer the gate names — the
constraint and the trigger — both are allowed.

---

## GATE 5 — FAIL. The output contract constrains `status` and nothing else

The brief names eight cases `schema_output_w17_s06` must refuse. Executed against
`fn_phase_d_schema_validate` on production, with a conforming control that validates:

| case | result |
|---|---|
| conforming payload (control) | **valid** ✓ |
| `status` as a number | refused — wrong type ✓ |
| `acceptance_assertions` as a string | refused — wrong type ✓ |
| `evidence_refs` as a number | refused — wrong type ✓ |
| `decision` as an array | refused — wrong type ✓ |
| `status = purple-elephant` | refused — outside declared domain ✓ |
| **`decision = NOT_A_DECISION`** | **ACCEPTED** ✗ |
| invented `refund_amount_aed` | refused — closed contract ✓ |
| invented arbitrary property | refused — closed contract ✓ |

This is not one slip. Derived over all 257 output schemas:

- every output schema declares **exactly one** enum domain, and it is always `status`;
- **140 of 257** output schemas type a consequential verdict-shaped key as a bare string with no
  domain — `decision` on **35** steps, `verdict` on **47**, `state_change` on **58**.

The 35 steps whose output types `decision` as an unconstrained string include W17-S06 (refund
decision), W27-S06 and W27-S09 (finance), W08-S06 (privacy review) and W30-S03.

**What does hold, stated so the finding is not read as larger than it is:** the services that act
on a decision constrain it themselves — `fn_kernel_review_decide` refuses anything but
`approved / rejected / changes_requested`, and `fn_kernel_refund_decision_record` refuses anything
but `approved / rejected` (both executed here). No money or verdict moves on `NOT_A_DECISION`. The
failure is at the layer Gate 5 audits: the declared step contract.

**Why it survived to here.** The estate's own guard,
`scripts/checks/phase_d_input_schemas_are_typed_and_closed.test.mjs`, passes 5 of 5 — its output
assertion is *"the output contract still refuses a bad **status** and an invented key."* It tests
the one field that has a domain. A check scoped to the only constrained key cannot report that the
other 140 schemas constrain nothing.

Everything else in Gate 5 passes: 514 schemas discovered (257 input + 257 output, 257 distinct
steps), 514 parsed, 0 missing a version, 0 open (`additionalProperties=false` on all 514), 0
required keys untyped, 514 stable ids in canonical shape, runtime validator
`fn_phase_d_schema_validate` used on every path — and the malformed-output case for all 257 steps
passes at the kernel boundary in the 1,799-case run.

---

## GATE 12 — PASS. The 54 self-loops are structural, and the runtime does not loop

"Ratcheted" was not accepted. All 54 rows were identified and classified independently.

**Derivation.** A self-loop is `phase_b_event.emitted_by = primary_consumer_role_id`. That is 54 of
347. Every one is an `EV-Wxx-Syy-COMPLETED` event. Joined to the frozen step registry:

| | |
|---|---|
| self-loop rows | 54 |
| producer role = the producing step's accountable role | 54 |
| producing step **is** the closure step (event terminal) | 15 |
| successor exists and is a **different** step | 39 |
| successor owned by the same role | 39 |
| **successor = the producing step (true re-entry)** | **0** |
| successor unresolved | 0 |

The "self" is the **role**, not the event and not the step. Classification: **all 54 = C,
STRUCTURAL_SAME-SUBJECT_NO_REEMIT.** A = 0, B = 0, D = 0, E = 0.

**Runtime proof, written for this audit, persisting nothing.** Each of the 30 frozen workflows was
driven through the canonical path; the outbox rows actually emitted were read back; the canonical
consumer `fn_kernel_event_consume` was called on each; and the business rows the consume call
**added** were counted (`phase_c_task` + `phase_c_workflow_run` + `phase_c_workflow_step_run` +
`phase_c_event_outbox`). Every transaction ended in `raise exception`.

```
30 workflows | 317 emissions | 317 handled | 0 re-applied
             | correlation 317 | causation 317 | dedupe 317 | trace 317 | retry budget 317
```

Then per event id, for the 54:

```
self-loop event ids in registry:              54
observed emitted AND consumed:                54
observed with reapply>0 or not handled:        0
not observed:                              (none)
```

`ACTIVE_RUNTIME_SELF_LOOP = 0`. `ACTIVE_DUPLICATE_BUSINESS_EFFECT = 0`. Unexplained rows = 0. No
Phase B change request is needed and none should be raised to relabel anything.

The remaining Gate 12 properties follow from the same measurement and from the injected-defect
catalogue re-executed at HEAD: one delivery creates at most one downstream effect (the consumer
added 0 rows on every one of 317 deliveries, and `fn_kernel_step_complete` remains the single
progression path); idempotent replay creates no additional effect (`outbox row consumed twice …
first consumption added 0 outbox row(s), second added 0`); the correlation/causation chain is
acyclic because every consumption emits nothing, so no causation edge can point back into the chain
that produced it; cancellation prevents pending delivery (`delivery after cancellation refused:
pd_external_cancelled`); and retry/dead-letter does not recreate producer work (`attempt 1 retryable
preserved (1 row), attempt 2 delivered=true`; `terminal: retry_class=TERMINAL dead_lettered=true
delivered=false`).

For the full 347: `fn_phase_d_event_evidence_state()` reports 347/347 carrying a final evidence
status, 0 fail-closed events with no reason, 0 whose consumption re-applied the producer action, 0
without correlation, trace or retry budget — and the reconciliation table shows all 347
`OBSERVED_IN_OUTBOX` / consumer `HANDLED`, with `self_loop_reapplied = 0` on all 54.

---

## GATE 4 and GATE 13 — the 257 effects, and what the red board measures

**What the board measures.** `fn_phase_d_effect_state.steps_with_no_effect_ever_produced = 257`
(expected 0) is a **persistent** count: it reads `phase_d_effect_ledger`, which every Phase D drive
rolls back. Its five informational siblings name exactly what holds each subset — 21 capability
steps refusing under the provider hold, 14 writing zero-residue tables, 78 writing real tables the
rule does not name, 144 writing only Phase D storage — and the handler board states the distinction
in its own row: *"the green above says the path EXISTS, this says whether it has RUN."*

Classification: **A — VALID_PERSISTENT_PRODUCTION_ACTIVITY_METRIC.** The check *name* alone would
read as B; the board reconciles its own meaning in adjacent rows, so it is truthful. It does not
fail Phase D.

**Independent reproduction of the effects.** `build_transaction_local_evidence.mjs` was re-run at
HEAD into a scratch directory:

```
254 effect rows over 252 distinct steps
VERSIONED_ARTIFACT 58 · KERNEL_ONLY_TRANSITION 47 · DOMAIN_MUTATION 66 · REVIEW_VERDICT 41
CAPABILITY_REQUEST 21 · MEASUREMENT_RECORD 7 · EXTERNAL_EFFECT_INTENT 12
rollback: customers 0, effect ledger 0, residue 0
```

That is **252 of 257**, not 257. Five steps produce nothing in that harness: **W17-S11, W24-S10,
W27-S10, W30-S10, W30-S11**. Four are closure steps the workflow drive never reaches; W30-S10 needs
a review.

So each of the five was driven separately, held open at that step, and dispatched through the
kernel's own door `fn_phase_d_dispatch_step`:

```
W17-S11  EXECUTED  effect_id 141102  hdl_w17_s11   effects +1
W24-S10  EXECUTED  effect_id 141113  hdl_w24_s10   effects +1
W27-S10  EXECUTED  effect_id 141124  hdl_w27_s10   effects +1
W30-S10  REFUSED   pd_review_not_recorded          effects +0
W30-S11  EXECUTED  effect_id 141146  hdl_w30_s11   effects +1
```

W30-S10's refusal is its contract, not a gap — its declared reviewer is `founder`. With the founder
review recorded first:

```
W30-S10  EXECUTED  effect_id 141212  hdl_w30_s10   effects +1
```

**252 + 5 = 257 of 257 declared effects produced inside protected transactions**, each carrying an
effect id and a handler id, all rolled back. Persistent `phase_d_effect_ledger`, `phase_d_dispatch`,
`phase_d_object_record` and `fn_phase_d_fixture_residue()` all read **0** afterwards.

**Finding on the deliverable, not on the implementation.** The committed
`PHASE_D_TRANSACTION_LOCAL_EVIDENCE.csv` states its denominator as *"254 of 254 effects ledgered
inside an aborted transaction"* — its numerator measured against itself. Against the 257 frozen
steps it is 252. The deliverable library's own header warns about exactly this shape.

---

## GATE 8 — the nine product controls, executed

Each control was executed against the deployed predicate or door, with a control case differing in
one respect. Nothing persisted.

**PD-AUTH-005** — real overlay `category_overlay_004_formwork-and-scaffolding-suppliers` and its
alias `opcat-004` both resolve `kind=overlay` → `admissible=false / pd_overlay_cannot_own_task`;
`inquiry_router` and `quote_evaluation` → admissible. At the kernel door on a live run:
overlay owner REFUSED 23514, overlay alias REFUSED 23514, tasks 58→58, step runs 30→30, traces
6027→6027 across both; canonical owner `inquiry_router` ACCEPTED. Overlay contribution remains —
W14-S05 lists `relevant_category_overlay` in `contributors` and
`phase_b_dynamic_actor.may_be_accountable = false`; 0 steps, 0 tasks and 0 step runs are
accountable to any overlay.

**PD-LEGAL-005** — `fn_kernel_reviewer_independent`: self → false; own alias
(`marketplace_content_privacy_reviewer` ↔ `moderation_specialist`) → false in both directions;
independent reviewer → true; null → false; unresolvable → false. On a live W04-S04 run with
`compliance_and_privacy_officer` as the declared reviewer, and a conforming output payload so the
verdict is the only variable:

```
A. complete with NO verdict     → REFUSED 23514 "names … as its independent reviewer and no approved…"
B. reviewer records REJECTED    → complete REFUSED 23514
C. reviewer records APPROVED    → complete ACCEPTED ok=true      (control)
creator self-review             → ok:false, not_the_declared_reviewer
edit the sealed verdict trace   → REFUSED 23514 "sealed trace evidence is append-only"
```

**PD-FIN-004** — created through the canonical protected path (`fn_kernel_refund_decision_record`
after binding a verified founder subject); with no session and with a typed founder string both
refused `28000`.

```
create → ok=true decision_id 1540
UPDATE → REFUSED 42501   DELETE → REFUSED 42501   original unchanged: true
supersede → ok=true id 1541, original still present, supersedes_decision_id=1540
public.refunds rows throughout: 0
```

**PD-LEGAL-004** — over every registered source, `require_authoritative=true`, as of today:
non-authoritative → refused; superseded → refused; review-by 2021-03-31 → refused (stale); undated
→ refused; unknown source → `pd_legal_source_missing`; current authoritative → **USABLE**.

**PD-PRIV-002 / PD-PRIV-005** — `fn_phase_d_file_revision_dispatchable` over the committed
revisions and audit fixtures:

```
PENDING → pd_revision_redaction_unapproved      REVIEW_REQUIRED → pd_revision_redaction_unapproved
REJECTED → pd_revision_redaction_rejected       superseded → pd_revision_superseded
APPROVED + clean scan → DISPATCHABLE            mismatched digest → pd_revision_digest_mismatch
unknown revision → pd_revision_redaction_state_absent
APPROVED but never scanned → pd_metadata_scan_absent
supplier-approved but IDENTIFIERS_FOUND → pd_hidden_metadata_identifier_found
SCAN_FAILED → pd_metadata_scan_failed_closed
SCAN_FAILED then a LATER CLEAN rescan → still refused (worst-outcome rule holds)
```

`redaction_state` is a closed domain (`phase_d_file_revision_state_ck`), so an invented state is
refused at the table.

*Observation, not a failure:* the digest arm is conditional on a digest being supplied, and the
three live callers all invoke the one-argument form. Dispatch is by revision reference, so no
current caller names bytes independently — the arm is correct and currently unexercised.

**PD-QUOTE-001** — SUPPLIER-scoped object, one business key:

```
A writes own          → ok=true
B edits A's record    → REFUSED 23514 pd_object_cross_owner_write
A revises own         → ok=true (control)
versions: 621034 owner=A "A v1" superseded_by 621036 | 621036 owner=A "A v2"
rows owned by B: 0
```

**PD-QUOTE-004** — three fixture comparisons, one owner:

```
owner on DRAFT       → pd_comparison_unpublished        owner on PUBLISHED  → VISIBLE
other on PUBLISHED   → pd_comparison_not_the_owner      other on DRAFT      → pd_comparison_not_the_owner
owner on SUPERSEDED  → pd_comparison_superseded         admin on DRAFT      → VISIBLE
empty caller id      → pd_comparison_not_the_owner      null caller id      → pd_comparison_not_the_owner
```

Ownership is checked before publication, so an unrelated customer is refused on a *published*
comparison too.

**PD-QUOTE-005** —

```
restating supplier-authored field "commercial_terms" → REFUSED pd_normalisation_restates_original
transformation naming no source_fields              → REFUSED pd_normalisation_transformation_absent
valid derived projection                            → ACCEPTED id 559   (control)
identical replay                                    → REFUSED 23505 phase_d_quote_normalisation_replay_uk
```

Supplier-authored fields (`commercial_terms, currency, evidence, lead_time, notes, payment_terms,
quote_amount, scope`) may not be republished in the projection; lineage is mandatory; replay
creates no duplicate.

**Controls executed 9/9. Expected controls hold 9/9. Accepted defects 0. Partial side effects 0.
Persistent fixture residue 0.**

---

## The other gates, in brief

**Gate 0.** Branch main; HEAD = PR #465's merge commit; `origin/main` identical; both PRs merged;
Phase A drift 0, Phase B drift 0, Phase C freeze drift 0 (all rows `ok`); effective Phase B baseline
reproduced exactly — workflows 30, steps 257, business objects 56, rules 54, gates 32, handoffs 159,
events 347. PBCR-001 verified in full: W14-S05 `accountable_role_id = quote_evaluation`,
`package_accountable_token = quote_evaluation_specialist`, `actor_kind = canonical_role`, overlay a
contributor with `may_be_accountable = false`, and `H-W14-04-05` / `H-W14-05-06` absent — W14 holds
only `H-W14-01-02` and `H-W14-02-03`. Repository↔production parity: conflicting definitions 0,
ambiguous winners 0, manifest gaps 0, uncommitted application DDL 0, drift 0 in both directions
(see §A — this reached 5 mid-audit through my own error and was restored).
`application_source_of_truth.test.mjs` reads 0 on all seven lines. **Edge functions:
`verify_deploy_parity.mjs --all` → "DEPLOY PARITY OK — 202 function(s) carry the repo's current code
on production."** (Two earlier attempts died on `ECONNRESET`; a transport failure is not a
measurement and was not recorded as one.) The committed schema mirror
`supabase/schema/full_schema.sql` is the subject of lines 2 and 5 of that gate, both 0.

**Gate 2.** Denominator 15, from the committed `PHASE_D_REQUIRED_DELIVERABLES.md`. All 15 present,
committed and current. All nine generated CSVs regenerate **byte-identically** from production at
HEAD, **twice** — two full runs with `PHASE_D_DRIVE=1`, 12 of 12 assertions each, including the two
builders that drive production in aborted transactions
(`PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv`, `PHASE_D_INJECTED_DEFECT_RESULT.csv`), which the
default check silently skips unless that variable is set. Every file carries command, project,
numerator, denominator, attribution and timestamp. Tracked-file diff after verification: **0**. The
six prose deliverables name what they did not probe rather than presenting it as passed;
`phase_d_documents_do_not_contradict_each_other` passes 3/3 and
`zero_cost_evidence_window_covers_the_work` 2/2.

**Gate 3.** 252 `scripts/sql/phase_d_*.sql` files discovered; 252 classified; 0 unclassified; 252
unique; all 252 present in `MANIFEST.txt` with no quoted or duplicate entries; 87 requiring an
explicit down, 0 missing one. Classes: ROUTINE_RESTORE 126, EXPLICIT_DOWN_REQUIRED 67,
ADDITIVE_SURVIVAL_SAFE 25, ROUTINE_INTRODUCED 17, GRANT_RESTORE 7, DATA_PURGE_NOT_REVERSIBLE 4,
ROUTINE_SIGNATURE_CHANGE 4, IRREVERSIBLE_WITH_FOUNDER_APPROVAL 2 — the four extra classes are
defined in `PHASE_D_ROLLBACK_CLASSIFICATION_D9.md` as refinements. All four
DATA_PURGE files delete only fixture rows (`ZZ DEMO — %`, `zz-%`, Phase D's own registry rows); no
business data. Findings below.

**Gate 6.** 56/56 object strategies; the round-trip prover re-run at HEAD: 55 round-tripped through
a canonical relation, 1 through its declared external-effect intent; mismatched 0, refused 0,
not-created 0, replay duplicates 0; rollback returned `phase_d_object_record` and residue to 0.

**Gate 7.** 54/54 rules carry one truthful status. On an empty context: 34 return FAIL/BLOCK, 16
return a non-pass state, 4 return `ENFORCED_PASS` — and each of those four names a delegate that
was made to refuse: BR-048 discriminates directly (overlay → `ENFORCED_FAIL/br048_overlay_dispatch`,
canonical → `ENFORCED_PASS`); BR-053/BR-054 delegate to `fn_kernel_paid_provider_gate`, which
refuses every named model and permits only a declared deterministic path; BR-028 delegates to
`fn_phase_d_handler_execute` / `pd_capability_unavailable`. All 19 previously-constant-pass rules
(BR-006…010, 027, 028, 040, 042, 044…048, 050…054) now read `ENFORCED_FAIL` on violating evidence or
`DELEGATED_TO_KERNEL_GUARD` with a named delegate and refusal code. 32/32 gates: 29 block on missing
evidence; the 3 that pass declare **no** evidence keys and are `MEASURED` gates reading a live
source with a numeric reason (Phase A drift 0; the paid gate refusing every route with 0
`llm_attempt` in 24h; 23 active cron against a ceiling of 25). Null gate results 0; gates with no
refusal code 0; evidence-declaring gates passing on no evidence 0.

**Gate 9.** Denominator 75, derived from the committed
`registries/PHASE_D_INJECTED_DEFECT_CATALOG.csv` (76 lines, 1 header). All 75 re-executed at HEAD
through the real services inside aborted transactions, reproducing the committed CSV byte for byte:
REFUSED_AS_REQUIRED 70, SAFE_SCOPED_RESULT_AS_REQUIRED 2, IDEMPOTENT_NO_DUPLICATE 2,
FAIL_CLOSED_AS_REQUIRED 1 — all four in the permitted set, NOT_RUN 0, NOT_DISCRIMINATED 0, accepted
defects 0. **Live exemption register `public.phase_d_injected_defect_disposition` holds 0 rows.**
`…_disposition_history` holds 9, all `REAL_PRODUCT_GAP` — the nine controls — and is a separate
relation nothing counts as a present exemption.

**Gate 10.** 257 × 7 = 1,799 derived independently. The authoritative harness was copied with its
persistence stripped and re-run at HEAD:

```
steps driven 257 | cases 1799 | passed 1799 | failed 0
positive 257 · missing_input 257 · wrong_actor 257 · invalid_state 257 ·
duplicate 257 · failed_rule_or_gate 257   (all live_step_run)
malformed_output 257                      (kernel_boundary)
```

The builder's "1,542 against a live step run" is exactly reproduced: 6 kinds × 257. The remaining
257 are `malformed_output`, decided at `fn_kernel_step_complete` because the handler builds its own
output from the frozen registry and a caller has no lever on it — recorded as `kernel_boundary`,
not counted as driven.

**Gate 11.** 159 frozen handoffs, 159 contracts, 0 either way without a counterpart. Every contract
carries a packet, acceptance criteria, rejection condition, return owner, SLA policy and closure
condition; 159 distinct distinguishing keys; 0 where accountability does not move. Executed: the
packet validator refuses an empty packet naming the missing keys and accepts the complete packet;
a second acceptance returns the stored decision and opens **no** second task (tasks +0). The
remaining arms are enforced in order in the deployed `fn_phase_d_handoff_accept` — contract present,
`pd_handoff_not_open`, `pd_handoff_run_state_invalid`, `pd_handoff_wrong_receiver` resolved against
the **frozen** contract, then `pd_handoff_packet_incomplete` — with the board reporting 0
acceptances that opened no step run, 0 runs with two decisions and 0 cancelled runs with an open
handoff over 30 real drives.

**Gate 14.** 77 distinct (component, edge function) pairs across 39 files and 39 edge functions:
62 `FULL_APPLICATION_PATH_CONNECTED`, 14 with no bound Phase D object, 1 realtime subscription. 76
of 77 edge functions are in the repository. All customer- and supplier-facing W04–W17 paths are in
the connected set with bound Phase D objects (`customer_api`, `customer_portal`, `inquiry_intake`,
`quote_compare`, `stripe_checkout`, `stripe_confirm`, `messages_api`, `project_api`,
`customer_documents`, `supplier_api`, `supplier_portal`, …). The 14 unbound paths are internal and
OS surfaces — `os_api`, `os_health`, `os_pages`, `os_settings`, `os_catalog`, `os_automation`,
`os_incidents`, `resilience_ping`, `contact_submit`, `transcribe`, `report_body`, `finance_doc`,
`kb_fill_gap` — **and `supplier_onboard`**, which is supplier-facing and is listed as a finding.

---

## Zero-cost and zero-external-effect

Enforced throughout: `NO_PAID_AI=true`, `OPENROUTER_DISABLED=true`, `AI_PROVIDER_MODE=mock`,
`PHASE_D_EXTERNAL_EFFECT_MODE=mock`.

| measurement | baseline 14:20Z | close | delta |
|---|---|---|---|
| `llm_attempt` | 69 (max 2026-08-15) | 69 | **0** |
| `ai_usage` | 14 (max 2026-07-13) | 14 | **0** |
| `ai_cost_log` | 3507 (max 2026-08-15) | 3507 | **0** |
| paid inference cost | — | — | **USD 0.00** |
| OpenRouter HTTP requests | — | — | **0** — `net.http_request_queue` has never held an openrouter URL |
| other paid-AI HTTP requests | — | — | **0** |
| live notifications **sent** | last ever sent 2026-08-16 | none | **0** |
| notification rows created | 673 | 674 | +1 — see below |
| live publications / payments / refunds | 0 | 0 | **0** |
| `phase_d_external_attempt` | 0 | 0 | **0** |
| `stripe_events` | 0 | 0 | **0** |
| `net.http_request_queue` | 0 | 0 | **0** |

**The one notification row, named rather than netted out.** `public.notifications` went 673 → 674.
The new row is id 6465, created 2026-08-24 16:00:00Z by the pre-existing `health_check` cron — the
same hourly/half-hourly series as 03:30, 04:30, 06:30, 07:00, 09:30 and 10:00, all of which predate
this audit. It is an internal `health_alert` (`status='digest'`, `sent_at` **NULL**, `to_role`
admin) reporting a stuck email queue that pre-dates the session. **Nothing was sent**: notifications
sent today = 0, sent since 14:20Z = 0, and the newest `sent_at` anywhere in the table is
2026-08-16 05:30:04Z. The audit's own drives created 0 notification rows — every notification write
happened inside a transaction that aborted.

Ten HTTP responses were recorded in `net._http_response` after 14:20Z. All are attributable to
pre-existing scheduled automation that this audit neither started nor may stop —
`uptime_check_15min` ×3, `health_check` ×2, `smoke_test_30min` ×2, `dropbox_backup_scan` ×3. None is
an AI provider call. `phase_c_outbox_deliver_1min` ran every minute throughout and delivered nothing
new: 0 outbox rows were created today, which is the direct evidence that no aborted transaction
left a deliverable row behind.

Business residue at close: customers 0, inquiries 0, quotes 0, transactions 0, quote_comparisons 0,
refunds 0, `phase_c_refund_decision` 0, `founder_approval_request` 0, `phase_d_effect_ledger` 0,
`phase_d_object_record` 0, `phase_d_dispatch` 0, `phase_d_quote_normalisation` 0,
`phase_c_founder_auth_event` 0, `fn_phase_d_fixture_residue()` 0.

Not run, as instructed: V3 knowledge certification, professional agent-quality certification, Phase E
knowledge/tool/model tests, unrelated product backlog scorecards.

---

## §A — a production change this audit caused, and its restoration

**Disclosed in full because the alternative is a clean count that hides it.**

Gate 3 requires rehearsing rollbacks in aborted transactions. I wrapped seven down scripts as
`begin; <down script> rollback;` after proving that explicit transaction control works over the
management API. **Four of the seven carry their own `begin; … commit;`.** Their `commit` ran inside
my block; my trailing `rollback` then had nothing to undo. The rehearsals for
`phase_d_d10`, `phase_d_d18`, `phase_d_d32` and `phase_d_k09` **committed**.

Effect, measured immediately afterwards by `canonical_routine_manifest.mjs` reporting repository →
production drift of 5:

- dropped: `public.phase_d_step_case_result` (table, 1,799 rows), `fn_phase_d_step_cases`,
  `fn_phase_d_run_step_cases`, `fn_phase_d_case_state`, `fn_phase_d_object_identity_state`,
  `fn_phase_d_external_residue`;
- two rows of `public.kernel_routine_ownership` re-pointed to their pre-K09 values.

`phase_d_e4`'s down raised before committing (it has no transaction control of its own, so my outer
block held) and `phase_d_l01`'s and `phase_d_o14`'s downs rolled back correctly — verified:
`phase_d_context_key_object` still holds 19 rows with its `key_role` column and 4 `DESCRIBES` rows;
`phase_d_object_write_map` 22, `phase_d_fixture_stage` 52, `phase_d_outbound_door` 5,
`phase_d_fixture_catalogue` 153, `phase_d_external_attempt` 0 — all untouched.

**Restoration, through the canonical door:**

1. `apply_sql.mjs phase_d_d10_… --apply --ddl` → 3 routines + the table, read back and identical to
   the file.
2. `apply_sql.mjs phase_d_k09_… --apply --ddl` → both ownership rows back to
   `phase_d_k05_… / QUOTESDONE_APPLICATION`.
3. `phase_d_d18` and `phase_d_d32` refuse a bare re-apply because their embedded self-verification
   blocks need a Phase D fixture context. Their canonical routine definitions were extracted
   verbatim from those same files, with their `revoke`, and applied.
4. `canonical_routine_manifest.mjs --all` → **conflicting definitions 0, ambiguous winners 0,
   manifest gaps 0, repository → production drift 0, production → repository drift 0, uncommitted
   application DDL 0, exit 0.**
5. **Re-applying an earlier file reverted two later ones, and the estate's own gate caught it.**
   `application_source_of_truth.test.mjs` then reported *"ledger claims the repository denies
   1/1225"* — `fn_unsafe_match_eligibility_guard` recorded against `phase_d_k05` where manifest
   order says `phase_d_n01`. K09 was correct when written; `phase_d_n11` and `phase_d_o17` moved
   those ledger rows afterwards, and re-applying K09 put them back. Both later files were re-applied
   in order, after which all seven lines of that gate read 0 — including *in repository missing from
   production 0/735*, *drifted application routines 0/736*, *uncommitted application DDL 0/8373*.
6. `phase_d_d10`'s re-apply also restored its own **pre-K08** CHECK constraint, so the live harness's
   first repopulation attempt was refused by `phase_d_step_case_result_level_ck` (which did not yet
   permit `live_step_run`). `phase_d_k08_the_case_matrix_had_no_word_for_a_live_step_run.sql` was
   re-applied; the constraint again reads
   `step_contract, executor_boundary, kernel_boundary, structural_constraint, live_step_run`.
7. Phase A drift 0, Phase B drift 0, Phase C freeze drift 0, and the Phase B baseline unchanged
   (30 / 257 / 56 / 54 / 32 / 159 / 347) after restoration.
8. `phase_d_step_case_result` was repopulated by re-running the authoritative harness
   `scripts/phase_d/run_step_cases_live.mjs`, which is what produced its committed contents:
   *257 steps driven, 1,799 cases written, 1,799 passed, 0 failed.* The restored table is identical
   in shape to the reading taken before the damage — 1,799 rows, 257 distinct steps, seven kinds ×
   257, `passed = true` on all, `kernel_boundary 257 / live_step_run 1542` —
   and `fn_phase_d_case_state()` reads `per_step_cases_recorded 1799 of 1799`, every row `ok`.

**State after restoration.** Phase A drift 0, Phase B drift 0, Phase C freeze drift 0; Phase B
baseline 30 / 257 / 56 / 54 / 32 / 159 / 347; `application_source_of_truth` 0 on all seven lines;
`canonical_routine_manifest --all` exit 0; edge deploy parity OK across 202 functions; every Phase D
board green except `steps_with_no_effect_ever_produced`, which was red before this audit began and
is the Gate 13 subject.

No tracked file was modified at any point: `git status --porcelain -uno` is 0 and HEAD is unmoved.

No business data was involved at any point; every affected object is Phase D's own machinery. No
evidence was deleted to obtain a clean count — this section is the record.

---

## Findings that do not fail a mandatory gate

1. **`phase_d_e4_the_door_was_never_a_browser_down.sql` cannot execute.** Rehearsed in an aborted
   transaction, it fails its own control: *"E4 down did not restore the prior state: expected 56
   anon / 59 authenticated, got 56 / 62."* The expected counts are committed constants describing an
   ACL that later files (e7's drop-and-recreate, d35's seven revokes, the o-series) have moved since.
   If this rollback were ever needed it would refuse — correctly, but it would not roll back.

2. **Four of seven sampled down scripts carry their own `begin; … commit;`.** A caller who wraps
   one in an outer transaction gets a real deployment, not a rehearsal. There is no marker in the
   classification CSV distinguishing self-committing down scripts from inert ones. See §A.

3. **`PHASE_D_TRANSACTION_LOCAL_EVIDENCE.csv` states "254 of 254"** — its numerator against itself.
   Against the 257 frozen steps it is 252, and the five it does not reach are not named in the file.

4. **`fn_phase_d_run_step_cases()` is superseded but still deployed, and it is destructive.** Its
   first act is `delete from public.phase_d_step_case_result`. Re-run at HEAD it returns
   `passed 1542, failed 257` — all 257 `positive` cases fail at `step_contract`, because it is the
   pre-23-Aug contract-only matrix the live driver replaced. Anything that calls it wipes the
   authoritative 1,799-row table and replaces it with 257 failures.

5. **`fn_phase_d_case_state()` reads green on an empty table.** With
   `phase_d_step_case_result` at 0 rows it reported `per_step_cases_recorded=0`,
   `steps_with_fewer_than_seven_cases=0`, `cases_failing=0` — every check `ok`. Only the first row
   carries the population, and nothing compares it to 1,799.

6. **Two committed artifacts outside the required 15 are stale.**
   `PHASE_D_INJECTED_DEFECT_EXEMPTION_REGISTER.csv` holds 19 rows against a live register of 0 —
   including PD-AUTH-005 as `PERMANENT_EXEMPTION`, which PR #465 closed.
   `PHASE_D_OBJECT_REFERENCE_ROUND_TRIP.csv` records `invoice_receipt`'s physical key as
   `invoice_no`; production and the strategy registry both say `transaction_id`. Neither file is
   regenerated by `build_all.mjs` and neither is byte-checked.

7. **`supplier_onboard` carries no bound Phase D object** in the frontend call graph, while every
   other supplier- and customer-facing path does.

8. **`phase_d_l01`'s `IRREVERSIBLE_WITH_FOUNDER_APPROVAL` label overstates.** It restructures the
   primary key of `phase_d_context_key_object`, a Phase D registry, and carries a working down
   script; no business data is destroyed and no founder approval is recorded against it.
   `phase_d_m01` cites the founder's bounded exception of 23 Aug 2026 in its own header.

---

## Verdict

**PHASE_D_FINAL_ACCEPTANCE_FAIL**

Two mandatory gates fail:

- **Gate 1** — a migration can forge founder approval on `phase_c_change_request` and on
  `phase_c_freeze_amendment`, and writing an approver onto a deferred request silently
  re-dispositions it to APPROVED under the deferral's own reason text. The fix PCCR-003 already made
  on the refund path was not made here.
- **Gate 5** — `schema_output_w17_s06` accepts `decision = NOT_A_DECISION`, and the same hole is
  structural: 140 of 257 output schemas type a consequential verdict-shaped key with no declared
  domain.

Nothing was repaired. Phase E was not begun.

---

## Close-out

At 16:03Z, after every probe and after the restoration in §A:

- `git status --porcelain -uno` = **0**; HEAD = `6479d322032387d0ff16453663e7790c11538b09`.
- Phase A drift 0 · Phase B drift 0 · Phase C freeze drift 0 · Phase B baseline
  30 / 257 / 56 / 54 / 32 / 159 / 347.
- `canonical_routine_manifest --all` exit 0 · `application_source_of_truth` 0 on all seven lines ·
  edge deploy parity OK across 202 functions · migrations 728 · active cron 23 — all unchanged from
  the preflight reading.
- Every Phase D board green except `steps_with_no_effect_ever_produced`, which was red before this
  audit began and is the Gate 13 subject.
- Business residue 0 across customers, inquiries, quotes, transactions, quote_comparisons, refunds,
  `phase_c_refund_decision`, `founder_approval_request`, `phase_d_effect_ledger`,
  `phase_d_object_record`, `phase_d_dispatch`, `phase_d_quote_normalisation`,
  `phase_c_founder_auth_event`, and `fn_phase_d_fixture_residue()`.
- Paid inference **USD 0.00**; `llm_attempt`, `ai_usage` and `ai_cost_log` all unmoved.

Only untracked audit artifacts were created, under `audit/phase-d-final/`.
