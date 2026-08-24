# PHASE D — FINAL ACCEPTANCE STANDARD, V1

**Status: RAISED FOR FOUNDER APPROVAL. NOT YET FROZEN.**
It becomes the frozen standard on the founder's approval sentence in §E. Until then it is a
proposal, and the acceptance target is whatever the 24 August audit measured.

**This document is the final and only Phase D acceptance standard.** When it is approved, no other
document — no session brief, no handover, no later audit — may add a mandatory Phase D gate, move a
denominator, widen a pass condition, or promote a disclosure into a gate. §E is the only door.

**Authoritative baseline.** `audit/phase-d-final/PHASE_D_FINAL_INDEPENDENT_ACCEPTANCE_2026-08-24.md`,
sha256 `18606dd9f98797b72174b0bffcd64495170bc3acc01b09921832fe5d219a3a74`, committed in this change
so the standard's baseline is in the repository rather than in one person's downloads folder. It
measured **13 of 15 mandatory gates passing**, Gate 1 failing (governance approval authenticity) and
Gate 5 failing (consequential output-field domains).

Why this document exists: the acceptance target moved between audit sessions. **Eight Phase D
independent acceptance reports** are present in this repository — 19 August, four on 20 August,
21 August and 24 August — each measuring a partly different set. This freezes one set.

---

## A. FROZEN BASELINES

These seven are preconditions, not gates. If any one of them is not true, no Phase D gate result
means anything, because the estate being measured is not the estate that was approved.

| baseline | required | how it is read |
|---|---|---|
| Phase A drift | **0** | `select * from public.fn_phase_a_baseline_drift();` → 0 rows |
| effective Phase B drift | **0** | `select * from public.fn_phase_b_baseline_drift();` → 0 rows, and the baseline reproduces as 30 workflows / 257 steps / 56 objects / 54 rules / 32 gates / 159 handoffs / 347 events |
| Phase C freeze drift | **0** | `select * from public.fn_phase_c_freeze_drift();` → every row `ok`; `frozen_subjects_drifted` 0 of 25; `amendments_awaiting_founder_approval` 0 of 5; `amendments_approved_on_written_instruction_only` 0 of 5 |
| repository → production drift | **0** | `node scripts/checks/canonical_routine_manifest.mjs --all` → `repository -> production drift 0` |
| production → repository drift | **0** | same command → `production -> repository drift 0`, `uncommitted application DDL 0`, `manifest gaps 0`, `conflicting current definitions 0`, `ambiguous routine winners 0`, exit 0 |
| automation hold | **remains active** | `fn_phase_d_gate_evaluate('GATE-032','{}')` → PASSED, active cron ≤ the selective ceiling of 25 |
| paid-provider hold | **remains active** | `fn_kernel_paid_provider_gate(<any named model>)` → `allowed: false`, `8 of 8 routes are held open-circuit` |

**Read at HEAD `521ed160af1c995aa4d42d8bb9f048d720ade09e`, production clock 2026-08-24T20:22:08Z**,
and all seven hold:
Phase A 0, Phase B 0, Phase C freeze 0 not-ok of 8 rows, repository→production 0, production→
repository 0, GATE-032 PASSED at 23 active cron of 25, provider gate refusing every named model.

---

## B. TWO REMAINING REPAIR GATES

These two, and only these two, are what stands between the estate and Phase D acceptance.

### Gate FD-01 — Governance Approval Authenticity

Change request: **PCCR-006**, `docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-006.md`.
Migration: `scripts/sql/phase_c_pccr006_governance_approval_authenticity.sql` (committed, **listed
in `scripts/sql/PENDING.txt`, deliberately not applied**).

Required — each line is a case an independent audit must be able to execute:

| # | requirement | must resolve as |
|---|---|---|
| 1 | no typed founder email can approve | a call carrying only an approver string → refused |
| 2 | no direct `approved_by` / `approved_at` mutation | a direct UPDATE on `phase_c_change_request` or `phase_c_freeze_amendment` → refused |
| 3 | no deferred request can silently become approved | writing an approver onto a DEFERRED row → refused, and the disposition does not move |
| 4 | no arbitrary auth subject | a subject not equal to the bound event's subject → refused |
| 5 | no arbitrary amendment digest | any 64-hex string that is not the real amendment-table digest → refused |
| 6 | no migration-written verified-session claim | an INSERT claiming `AUTHENTICATED_FOUNDER_SESSION` from a `postgres` connection → refused |
| 7 | verified founder JWT | the only accepted route is a GoTrue-issued bearer token for a registered, active founder identity |
| 8 | server-verified auth subject | `approval_auth_subject` is derived, never supplied by the caller |
| 9 | exact amendment digest | the recorded digest equals the sha256 of the amendment table the row names |
| 10 | exact decision | the recorded decision equals the decision the verified event was minted for |
| 11 | transaction-bound, short-lived, single-use approval event | same `txid_current()`, `expires_at ≤ issued_at + 10 min`, UNIQUE nonce, consumed once |
| 12 | immutable governance decision | UPDATE and DELETE on the decision ledger → refused |
| 13 | replay idempotent | the same approval replayed returns `ALREADY_DECIDED` and writes no second row |

**Pass condition:** all 13 execute as stated against the deployed objects, and Gate 1's own four
probes from the 24 August audit (§ GATE 1, cases A–D) each refuse.

### Gate FD-02 — Consequential Output Domains

Required:

| # | requirement | required result |
|---|---|---|
| 1 | every consequential finite-vocabulary field has an authoritative domain | 0 registered CLOSED_ENUM fields undeclared on their schema |
| 2 | decision fields constrained | every `decision` field either carries an enforced domain or is registered `CLOSED_ENUM_UNDEFINED` naming an open `PBCR-nnn` |
| 3 | verdict fields constrained | **47 of 47** |
| 4 | state_change fields constrained | **58 of 58** |
| 5 | all other mechanically discovered finite-domain fields constrained | `status` 257, `target_object` 58, `method` 31, `receiving_role_id` 25 |
| 6 | wrong type refused | executed on the live validator |
| 7 | invalid domain value refused | executed on the live validator, on every closed-domain field name |
| 8 | unsupported field refused | closed contract, `additionalProperties = false` on all 514 |
| 9 | **W17-S06 `decision = NOT_A_DECISION` refused** | refused, with a conforming control that validates |
| 10 | all 514 schemas pass | 514 discovered, 514 parsed, 0 without a version, 0 open, 0 required key untyped |
| 11 | all 1,799 step cases pass | 1,799 of 1,799, 0 failed |

**Pass condition:** all 11 as stated. Requirement 2 is satisfied by a registered
`CLOSED_ENUM_UNDEFINED` row only while its named change request is open; a closed change request
with the field still undefined fails this gate.

**Builder position on FD-02 at HEAD:** the builder claims this gate is met — see
`docs/phase-d/PHASE_D_GATE5_BUILDER_EVIDENCE.md`, labelled **BUILDER_EVIDENCE_PENDING_FINAL_AUDIT**.
That claim is not an acceptance and does not close the gate.

---

## C. REGRESSION SET

The 13 gates that passed in the 24 August independent audit are frozen here as the regression set.
An independent audit re-runs these and must reproduce these exact results. **No result and no
denominator in this section is new.** Every number is the one the 24 August audit measured.

`sha256` is of the committed script at HEAD `521ed16`. A script whose hash has moved must be
re-read before its result is trusted — the hash is how a later audit knows whether it is running
the thing this standard froze.

| # | audit section | exact script / query | committed script sha256 | numerator | denominator | required result |
|---|---|---|---|---|---|---|
| 1 | Gate 0 — frozen baselines and parity | `select * from public.fn_phase_a_baseline_drift();` | *(routine, digest read live)* | 0 | 0 rows expected | 0 rows |
| 2 | Gate 0 | `select * from public.fn_phase_b_baseline_drift();` | *(routine)* | 0 | 0 rows expected | 0 rows; baseline 30 / 257 / 56 / 54 / 32 / 159 / 347 |
| 3 | Gate 0 | `select * from public.fn_phase_c_freeze_drift();` | *(routine)* | 8 ok | 8 rows | every row `ok`; 0 of 25 drifted; 0 of 5 awaiting; 0 of 5 written-instruction-only |
| 4 | Gate 0 | `node scripts/checks/canonical_routine_manifest.mjs --all` | `60766276aaa6c7568cd8520bb10f50d6c70494597b076aec36480599acb369dd` | 0 findings | 6 lines | all six 0, exit 0 |
| 5 | Gate 0 | `node --test scripts/checks/application_source_of_truth.test.mjs` | `36bbd49ccd048d5fadacd2565980e40b456754be67f582c213b0cc3d16a3b2af` | 0 | 7 lines | 0 on all seven |
| 6 | Gate 0 | `node scripts/verify_deploy_parity.mjs --all` | `7c0e199221efac4398f70f283d3500fc449359bc16f76c13e24a357434da2d60` | 202 | 202 functions | DEPLOY PARITY OK across 202 functions |
| 7 | Gate 0 | `node scripts/checks/export_from_either_source_is_identical.mjs` | `e8df0206b545e3ac5005559c49b2aae162d3ede2a07a09a6ea96e1a70c99af68` | — | — | byte-identical |
| 8 | Gate 2 — 15 deliverables | `PHASE_D_DRIVE=1 node --test scripts/checks/phase_d_deliverables_match_production.test.mjs` | `39c10b721a0c59442395beb62c0879ba258180f0f0fdaab290c867e864437f96` | every assertion | every assertion the check declares | **all pass, and the tracked-file diff after verification is 0.** The audit read **12 of 12** with 9 builders; PR #466 added two builders and the same check reads **14 of 14** — the frozen property is *every assertion passes and every built file reproduces byte-identically*, not the assertion count |
| 9 | Gate 2 | `node scripts/phase_d/build_all.mjs` (11 builders, order fixed in `lib/deliverable.mjs`) | `ba9b57ca0ed7c8a293ffd74c5f8068bb3656ca4ba2113c8e8c1ad0f2379adae6` | 15 | 15 required deliverables | all 15 present, committed and current |
| 10 | Gate 2 | `node --test scripts/checks/phase_d_documents_do_not_contradict_each_other.test.mjs` | `64858e61d252b8a723124f2fbe4858736c59adf553788664e7e5d3d5bb6a6391` | 3 | 3 | 3 of 3 |
| 11 | Gate 3 — migration / rollback coverage | `node scripts/phase_d/build_migration_rollback_classification.mjs` + `node --test scripts/checks/phase_d_migrations_are_classified.test.mjs` | `03d667c3f3c20cfc622596ce933ab05f89472a7dabedf0bd102205d22b97c263` / `717a5e5343cc6e47804bba9f5f56afc4dc4058238da14862ace077d5e0289deb` | every discovered file | every `scripts/sql/phase_d_*.sql` file — **a moving denominator, and the only one in this table** | **0 unclassified, 0 duplicate, 0 absent from `MANIFEST.txt` or `PENDING.txt`, 0 requiring an explicit down and missing one.** The audit read 252 files / 87 requiring a down; **at HEAD `521ed16` it is 256 / 88 / 0 missing**, because PR #466 added four. The frozen thing here is the four zeros, not the file count |
| 12 | Gate 4 — 257 handler effects and callers | `node scripts/phase_d/build_handler_implementation_result.mjs` | `d26756da284c707f9d5cef20f0b5833b2c9548ebe18da42e7b886b7a05ff529f` | 257 | 257 frozen steps | every step has an implemented handler and a real caller |
| 13 | Gate 6 — 56 objects | `node scripts/phase_d/prove_object_reference_round_trip.mjs` | `3a4da1bb28059eadb8c3b5a023e12530b38ca93432c6174142db4f554cdaa2bf` | 56 | 56 object strategies | 55 round-trip through a canonical relation, 1 through its declared external-effect intent; mismatched 0, refused 0, not-created 0, replay duplicates 0; residue 0 |
| 14 | Gate 7 — 54 rules and 32 gates | `node scripts/phase_d/build_rule_gate_result.mjs` | `94b5cd3be2758d442ef1e93d750cee21b0c5d6a02e933d4ff061f65d83258c0a` | 54 + 32 | 54 rules, 32 gates | 54 of 54 carry one truthful status (34 FAIL/BLOCK, 16 non-pass, 4 `ENFORCED_PASS` each naming a delegate that refuses); 29 of 32 gates block on missing evidence, 3 are `MEASURED` with a numeric reason; null gate results 0; gates with no refusal code 0 |
| 15 | Gate 8 — nine product controls | `PHASE_D_DRIVE=1 node scripts/phase_d/build_injected_defect_result.mjs` (the nine are `phase_d_injected_defect_disposition_history`, all `REAL_PRODUCT_GAP`) | `8dbfbb8c273afd54658a6e5faeb52b1e4f428bf0660ae90f877facdfda09ce82` | 9 | 9 controls | controls executed 9/9, expected controls hold 9/9, accepted defects 0, partial side effects 0, fixture residue 0 |
| 16 | Gate 9 — 75 defect cases | same script, against `registries/PHASE_D_INJECTED_DEFECT_CATALOG.csv` | `8dbfbb8c273afd54658a6e5faeb52b1e4f428bf0660ae90f877facdfda09ce82` | 75 | 75 catalogue rows | REFUSED_AS_REQUIRED 70, SAFE_SCOPED_RESULT_AS_REQUIRED 2, IDEMPOTENT_NO_DUPLICATE 2, FAIL_CLOSED_AS_REQUIRED 1; NOT_RUN 0; NOT_DISCRIMINATED 0; accepted defects 0; live exemption register **0 rows** |
| 17 | Gate 10 — 1,799 step cases | `node scripts/phase_d/run_step_cases_live.mjs`, then `select * from public.fn_phase_d_case_state();` | `491f5420a8d60c5d6b58b77091ed90eeb82da13980aa7da71ccf6d9ed994f8ce` | 1,799 | 257 steps × 7 kinds | 257 driven, 1,799 cases, 1,799 passed, 0 failed; `live_step_run` 1,542, `kernel_boundary` 257 |
| 18 | Gate 11 — 159 handoffs | `node scripts/phase_d/build_handoff_event_result.mjs` | `51ca1be341bd99624df8cf8016ee98b482025ae6190895e4ce7ecdf76ddceeab` | 159 | 159 frozen handoffs | 159 contracts, 0 either way without a counterpart, 159 distinct distinguishing keys, 0 where accountability does not move |
| 19 | Gate 12 — 347 events | same script, plus `select * from public.fn_phase_d_event_evidence_state();` | `51ca1be341bd99624df8cf8016ee98b482025ae6190895e4ce7ecdf76ddceeab` | 347 | 347 frozen events | 347 of 347 carry a final evidence status; 0 fail-closed with no reason; 0 whose consumption re-applied the producer action; 0 without correlation, trace or retry budget; `self_loop_reapplied` 0 on all 54 |
| 20 | Gate 13 — 257 transaction-local effects | `node scripts/phase_d/build_transaction_local_evidence.mjs` | `5be66a14398ead3dfb0337c9f7904530e3586d20b0eb0b15b5b406479a61fe00` | 257 | 257 declared effects | **257 of 257**, each with an effect id and a handler id, all rolled back; 0 wrong-width rows. The audit reached 257 as 252 from the drive plus 5 dispatched separately through `fn_phase_d_dispatch_step` (W17-S11, W24-S10, W27-S10, W30-S10 after its founder review, W30-S11). At HEAD the builder emits all 257 itself — those five were present all along and had been cut off by the management endpoint's 2,000-character cap, which PR #466 fixed. **Either route must reach 257** |
| 21 | Gate 14 — application paths | `node scripts/phase_d/build_frontend_api_call_graph.mjs` | `b7cfdb77976493bcda1837bf654989dce8b7f7a51413bc0d3fdfaf07991c8c87` | 77 | 77 (component, edge function) pairs | 62 `FULL_APPLICATION_PATH_CONNECTED`, 14 with no bound Phase D object, 1 realtime subscription; 76 of 77 edge functions in the repository; every customer- and supplier-facing W04–W17 path connected with a bound object |
| 22 | deliverable 8 — RLS / security / storage | `node scripts/phase_d/run_section8_security_probes.mjs` → `PHASE_D_STORAGE_RLS_SECURITY_RESULT.md` | `ac8c9bcd925bacd90c527c87d5477b198fbb621e9ce4ed649183e4314210357d` | as recorded in the deliverable | as recorded | reproduces the committed deliverable |
| 23 | deliverable 9 + Gate 8 — financial / privacy / legal controls | `PHASE_D_FINANCIAL_PRIVACY_RESULT.md`, controls PD-FIN-004, PD-LEGAL-004, PD-LEGAL-005, PD-PRIV-002, PD-PRIV-005 re-executed through item 15 | `8dbfbb8c273afd54658a6e5faeb52b1e4f428bf0660ae90f877facdfda09ce82` | 5 | 5 controls | each refuses its negative cases and admits its one control case; `public.refunds` 0 throughout |
| 24 | capability / content fixtures | `node scripts/phase_d/prove_capability_boundary.mjs`; `node scripts/phase_d/build_fixture_catalogue.mjs`; `node --test scripts/checks/phase_d_fixture_catalogue_matches_the_file.test.mjs` | `a1cb794711c7ff87a258d355caf41079df976e172a36fa958b11c7138c9bd261` / `d5cac1be326fdae0c89fbdcff760098627a2376780c4b624f3ac2f3d2f6bff83` / `c81f97ab723ec86d66afdd3566f2c8c0180f0c789ed2f493e7ec8ab1f7f1ae80` | 21 | 21 capability steps | 21 of 21 probed five ways; catalogue matches the committed file |
| 25 | 30 workflows in happy / failure / cancel / replay | `PHASE_D_DRIVE=1 node scripts/phase_d/build_workflow_implementation_result.mjs` and `node scripts/phase_d/build_four_mode_result.mjs` | `0adba8199badeace48c2b350f1877246cf999aae3851a66ae83bc149516e94e7` / `5bed55ddf40a9bdf8bb3bc13d5355047a49ad8ec5535b880e2e952960c5650d4` | 30 | 30 frozen workflows | all four modes reproduce the committed CSV; residue 0 |
| 26 | external adapters | `PHASE_D_EXTERNAL_EFFECTS_RESULT.md`, plus `select * from public.fn_phase_d_external_state();` | *(deliverable + routine)* | 0 live | — | `phase_d_external_attempt` 0; `PHASE_D_EXTERNAL_EFFECT_MODE=mock` throughout |
| 27 | trace / idempotency / concurrency | `node scripts/phase_d/run_concurrency_probes.mjs` → `PHASE_D_IDEMPOTENCY_CONCURRENCY_RESULT.md` | `d187fa858277721704783d60124f0ecc67d6d35d6a1e3905aeb41890cc71bd63` | as recorded | as recorded | reproduces the committed deliverable |
| 28 | automation hold | `select * from public.fn_phase_d_gate_evaluate('GATE-032','{}'::jsonb);` | *(routine)* | 23 | ceiling 25 | PASSED — active cron at or below the selective ceiling |
| 29 | zero-cost | `PHASE_D_ZERO_COST_EVIDENCE.md` + `node --test scripts/checks/zero_cost_evidence_window_covers_the_work.test.mjs` | `a4d3eb75ddac7ef337397f55ba4066da9b93c0771c124af91e83d17190526b3c` | 2 | 2 | 2 of 2; `llm_attempt`, `ai_usage`, `ai_cost_log` deltas all **0**; paid inference **USD 0.00**; `net.http_request_queue` 0 |
| 30 | zero residue | `select * from public.fn_phase_d_fixture_residue();` and the business-table sweep | *(routine)* | 0 | 0 expected | customers 0, inquiries 0, quotes 0, transactions 0, quote_comparisons 0, refunds 0, `phase_c_refund_decision` 0, `founder_approval_request` 0, `phase_d_effect_ledger` 0, `phase_d_object_record` 0, `phase_d_dispatch` 0, `phase_d_quote_normalisation` 0, `phase_c_founder_auth_event` 0, `fn_phase_d_fixture_residue()` 0 |

**One denominator moves, and it is item 11.** The number of `scripts/sql/phase_d_*.sql` files grows
whenever a repair is applied — it grew by four between the audit and this document. Freezing the
file count would make the standard fail on its own first repair. What is frozen is the **result**:
nothing unclassified, nothing duplicated, nothing outside the manifest, nothing owed a down script
and missing one. Every other denominator in this table is a count of frozen Phase B or Phase D
subjects and does not move without a change request.

**Boundary on this table, stated rather than implied.** Items 1–3, 26, 28 and 30 are database
routines, not committed scripts, so they have no file hash; their bodies are covered by regression
item 4 (`canonical_routine_manifest --all`), which is what proves the deployed body is the
committed one. Items 22 and 27 reproduce prose deliverables whose internal numerators are stated in
the deliverables themselves and are not restated here, because restating them here would create a
second denominator for one subject — the shape this estate has been bitten by before.

---

## D. NON-BLOCKING DISCLOSURES

Four facts are recorded here as disclosures. **A disclosure is not a gate**, and §E forbids a later
audit from reading one as a gate.

### D1. `steps_with_no_effect_ever_produced = 257`

**Classification: `PERSISTENT_PRELAUNCH_ACTIVITY_METRIC`.**

`fn_phase_d_effect_state.steps_with_no_effect_ever_produced` reads `phase_d_effect_ledger`, which
every Phase D drive rolls back. It is a measure of whether a step has ever run **and left a row**,
in an estate that is deliberately pre-launch and deliberately leaves no rows. Its five
informational siblings name exactly what holds each subset: 21 capability steps refusing under the
provider hold, 14 writing zero-residue tables, 78 writing real tables the rule does not name, 144
writing only Phase D storage. The handler board states the distinction in its own row — *"the green
above says the path EXISTS, this says whether it has RUN."*

**It does not block Phase D while both of these hold:**

- transaction-local effects independently reproduce **257 / 257** (regression item 20);
- persistent business residue remains **0** (regression item 30).

If either stops holding, this stops being a disclosure — not because the disclosure changed, but
because its two conditions are gates.

### D2. `event_self_loops = 54`

**Classification: `STRUCTURAL_SAME_SUBJECT_NO_REEMIT`.**

A self-loop is `phase_b_event.emitted_by = primary_consumer_role_id` — 54 of 347, every one an
`EV-Wxx-Syy-COMPLETED` event. The "self" is the **role**, not the event and not the step: 15 are
terminal closure steps, 39 have a successor that is a different step owned by the same role, and
**0** have a successor equal to the producing step.

**It does not block Phase D while all three of these hold:**

- `ACTIVE_RUNTIME_SELF_LOOP = 0`;
- `ACTIVE_DUPLICATE_BUSINESS_EFFECT = 0`;
- all 54 remain independently observed emitted and consumed with no producer reapplication
  (24 August: 54 observed emitted AND consumed, 0 with reapply > 0 or not handled, 0 not observed).

**No Phase B change request is needed and none should be raised to relabel any of the 54.**

### D3. Paid-provider hold

**It is a required boundary, not an implementation blocker.** `fn_kernel_paid_provider_gate` refuses
every named model — *"8 of 8 routes are held open-circuit until 2126-08-15"*. A step that refuses
with `pd_capability_unavailable` under that hold is behaving correctly, and a gate may not be
recorded as failed because the hold prevented a paid call. Twenty-one capability steps are in this
position and are named in D1.

### D4. Zero-residue policy

**It is a required boundary, not an implementation blocker.** Phase D drives production inside
transactions that abort. A measurement that reads a persistent table and finds nothing is measuring
the policy, not the implementation. A gate may not be recorded as failed because a correctly
rolled-back drive left no row.

---

## E. ACCEPTANCE CHANGE CONTROL

After the founder approves V1:

- **no new mandatory Phase D gate may be introduced;**
- **no denominator may be changed;**
- **no pass condition may be expanded;**
- **no later audit may reinterpret a disclosure in §D as a gate;**

unless the founder approves a change request named

> **`PHASE_D_ACCEPTANCE_STANDARD_CHANGE_REQUEST`**

containing all six of:

1. exact old requirement;
2. exact proposed requirement;
3. reason;
4. product / security impact;
5. affected evidence;
6. founder approval.

A change request that omits any of the six is not a change request. An audit finding that would
require a new gate is recorded as a **finding**, reported, and left to this process — it does not
become a gate by being written down.

**What this does not restrict.** It does not stop an audit finding a defect against an existing
gate, and it does not stop the estate being repaired. It stops the *target* moving.

### The exact founder approval sentence for this standard

> **I approve `PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1` — sha256 `<D>` — as the final and only Phase D
> acceptance standard.**

`<D>` is the sha256 of **this file as committed**, and it is deliberately not written inside the
file: a digest that quotes itself cannot be verified, and every earlier attempt in this estate to
put a document's own hash inside the document produced a constant that could not be recomputed. It
is recomputed the same way `scripts/checks/pccr_approval_matches_committed_tables.test.mjs`
recomputes an amendment-table digest:

```bash
sha256sum docs/phase-d/PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1.md
```

The digest as of the commit that introduces this file is stated in that commit's message and in the
decision packet that accompanied it. If the file is edited, the digest moves and the sentence must
be reissued against the new one — which is the point.

---

## F. TERMINATION STATES

| who | state |
|---|---|
| **Builder** | `PHASE_D_READY_FOR_INDEPENDENT_AUDIT` |
| **Independent audit** | `PHASE_D_FINAL_ACCEPTANCE_PASS` **or** `PHASE_D_FINAL_ACCEPTANCE_FAIL` |
| **Founder, after an audit pass** | `PHASE_D_FOUNDER_APPROVED_AND_FROZEN` |

**Removed by this standard: the requirement that the builder must declare founder approval before
the independent audit.** The builder's terminal state is `PHASE_D_READY_FOR_INDEPENDENT_AUDIT` and
nothing more. Founder approval comes **after** an audit pass, not before it — a builder cannot
usefully hold a founder approval for work an independent audit has not yet checked, and requiring
one produced sessions that stalled on an approval nobody could give.

This does **not** change PCCR-006 or PBCR-002: those are Phase C and Phase B change requests, they
each need the founder's approval in their own right, and Gate FD-01 cannot be closed without his.
The requirement removed here is the separate, procedural one about the builder's own state.

---

## What this standard deliberately does not cover

Stated so its silence is not read as a pass:

- V3 knowledge certification, professional agent-quality certification, and Phase E knowledge /
  tool / model tests — out of scope, not run;
- the nine autonomous sources that do not route through the kernel inbox
  (`fn_kernel_trigger_state`) — a **Phase C** subject, tabled in
  `docs/phase-d/PHASE_D_AUTONOMOUS_SOURCE_BYPASS_TABLE.md`, and not a Phase D gate;
- the five `fn_kernel_trace_integrity` rows and the one `fn_kernel_write_guard_state` row that read
  red today — pre-existing Phase C items, disclosed in §6 of the decision packet, not Phase D gates;
- the eight findings the 24 August audit recorded as *not failing a mandatory gate* — they are
  repairs, tracked separately, and none of them may become a gate except through §E.
