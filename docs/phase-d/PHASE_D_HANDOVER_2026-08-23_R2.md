# Phase D — hand-over, 23 Aug 2026 (second session of the day)

Every figure below was measured by execution on `htdblwldjkcgjvmqkbeh` in the session that wrote
this file, and every one names the command that reproduces it. **Phase D is not ready for
independent audit**, for one reason, stated exactly in §7.

---

## 0. Source and baseline

| | |
|---|---|
| branch | `phase-d-k-the-three-steps` |
| base | `main @ b285d4d` (PRs #459 and #460 merged) |
| pull request | [#461](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/461) |
| applied production-direct | K01–K09, each `node scripts/apply_sql.mjs <file> --apply --ddl`, each read back and identical to the file |
| production ahead of main | no — every applied file is committed on the branch, and the branch is the PR |
| Phase A drift | **0 rows** — `select * from public.fn_phase_a_baseline_drift()` |
| Phase B drift | **0 rows** — `select * from public.fn_phase_b_baseline_drift()` |
| Phase C freeze board | **0 red of 8 checks**, `frozen_subjects_drifted` **0 of 25** — `select * from public.fn_phase_c_freeze_drift()` |
| repository → production drift | **0** — `node scripts/checks/canonical_routines.test.mjs` |
| production → repository drift | **0** — same |
| ownership ledger vs repository | **0 findings** — `node scripts/checks/application_source_of_truth.test.mjs` (was 3) |
| schema export | regenerated, 79,077 lines, byte-identical to the live export |
| rollback classification | **208 of 208** Phase D migrations classified, **0** missing down scripts |
| kernel boards | 39 boards, 446 checks, **8 red, 0 undisclosed**, no disclosed gap grown |
| automation hold | 23 active cron jobs, `outcome_evaluate_daily` **inactive** |
| provider hold | `ai_cost_log` rows today **0**, `llm_attempt` **69** (unchanged), paid inference **USD 0.00** |

---

## 1. PCCR-004

Disclosed in full, as one structured amendment table with all 27 required elements, in
[`PCCR_004_AMENDMENT_TABLE.md`](PCCR_004_AMENDMENT_TABLE.md). **Not approved, not applied, not
present on any branch and not present on production**: `sha256(pg_get_functiondef)` of the live
`fn_kernel_cancel` is `fc59489aff…`, which is the frozen baseline digest.

The one Phase D requirement it blocks is named there and it is not the cancellation figure —
cancellation is **30 of 30** with the currently approved frozen service. What cannot be shown
without it is *cancelling one run of a multi-run founder command while leaving that command's other
runs and their derived work intact*.

---

## 2, 3, 4. The three steps that had no effect — all closed

| step | was | now | root cause |
|---|---|---|---|
| `W05-S07` | `gate005_founder_boundary` | **EXECUTED**, DOMAIN_MUTATION | GATE-005's frozen evidence is "within delegated authority **or** founder approval exists" and only the second half was implemented. **A. an existing founder-policy authority reference** — W05 is in the scope of no founder boundary. |
| `W12-S06` | `pd_object_write_produced_nothing` | **EXECUTED**, DOMAIN_MUTATION | Not the fixture's readiness. The effect payload carried no `inquiry_id`, so the assignment was written with a null parent and a BEFORE trigger dropped it in silence. |
| `W16-S05` | `pd_effect_identity_collision` | **EXECUTED**, VERSIONED_ARTIFACT | `reveal_invoices` is `PRIMARY KEY (transaction_id)` and the binding said `invoice_no` — the only one of 26 bindings disagreeing with its relation's own key. |

**W05-S07.** GATE-005 was classified **A**. `phase_b_founder_boundary` — founder-approved, Phase B
frozen, digest-guarded — scopes 17 workflows between its ten boundaries and names neither W05 nor
W18. W05's run is started in production by `trg_inquiry_received_a` when a customer's inquiry
arrives, so under the old contract every customer inquiry would have blocked at qualification
waiting for an approval the founder does not give. **No founder approval request was created and
none is waiting**: `fn_phase_d_founder_authority` returns the delegation as one immutable canonical
reference, `founder_policy:phase_b_founder_boundary@<digest>`, and the digest is
`fn_phase_b_structure_digest()`'s own `founder_boundaries` row — the same value `org_phase_baseline`
holds for phase B. GATE-005's body was `v_ok := true`; it now verifies the reference **exists**, is
**current** against that baseline, and **covers** the workflow, and refuses when any of the three
fails. Proved both directions, including forced negatives for each of the three on the
founder-command branch: `node --test scripts/checks/phase_d_the_three_steps_that_had_no_effect.test.mjs`.

**W12-S06.** The hand-over of this morning recorded the cause as "the fixture inquiry is not
rfq_ready". Measured: that inquiry scores 100, `generic_ready` true, `category_required_ok` true,
`rfq_ready` **true**, and the same insert by hand in the same transaction lands. `inquiry_matches`
has no NOT NULL on `inquiry_id`, so the "columns the relation demands" population never selected the
parent. The effect now carries the inquiry, the eligibility evidence and the inclusion reason; the
writer refuses an orphan by name; both gates on `inquiry_matches` now publish a stable verdict
instead of returning a silent null; and `customer_api` stops counting a refused supplier as a
contacted one — it had been **emailing suppliers the eligibility gate had just refused**.

**W16-S05.** One invoice per transaction, invoice number preserved, replay adds none, unknown
transaction refused by the relation's own foreign key (23503), and BR-020 still refuses a reveal at
every rung below `payment_reconciled` including an unrecognised one. Nothing was weakened.

---

## 5. Effect coverage — 257 of 257

`node scripts/phase_d/build_step_branch_coverage.mjs`

```
frozen steps in the matrix         257 of 257
reached through the canonical path 257 of 257
producing their declared effect    257 of 257      (was 254)
reached only by a direct complete   0
pass edge exercised                257 of 257
fail edge exercised                257 of 257
fail edge matches the frozen model 257 of 257
fail edge produced an effect         0
fail edge produced an object         0
```

**And the boundary of that number, stated.** The committed harness lets the fixture scenario build
every object and asks the workflow under test to withhold its own output on **W12 only**. Asked to
withhold it on all 30 — which is what "a harness must not seed the row the step is supposed to
create" actually means — the same estate measures **248 of 257** after K06 and K07, and the nine
that fall are all of W09, blocked by BR-025 needing a terms acceptance W09-S06 is itself the step
that records. The subject of that rule is not derivable from any register the estate holds today
(`phase_d_fixture_stage.contributes_ref` is null for `supplier_terms_acceptance` and
`phase_d_context_key_object` cannot map `terms_version`/`terms_hash` to one object, because W04 and
W09 own different acceptances). The committed basis is unchanged and reproducible; the stricter one
is recorded here rather than left to be discovered.

Four defects surfaced only because that stricter harness was tried, and all four are fixed:
K06 (a rule governing the workflow that produces its subject — BR-018/W14, BR-032/W16),
K07 part 1 (a run could not see the object it had itself created — W17-S07),
K07 part 2 (a gate demanding a subject before the step that produces it — W08-S01),
and the narrowing that stopped a review row being judged as a comparison (W15-S05).

---

## 6. Step-contract cases — 1,799 of 1,799, and 1,542 of them against a live step run

`node scripts/phase_d/run_step_cases_live.mjs` then `node scripts/phase_d/build_step_case_result.mjs`

```
cases executed              1799        257 steps x 7
cases passed                1799
invalid / vacuous cases        0
decided at live_step_run    1542        the real handler, or the kernel's own dispatch door,
                                        on a step run opened by a real drive of the real workflow
decided at kernel_boundary   257        fn_kernel_step_complete refusing an empty output, k3_output_empty
decided at step_contract       0        was 771
decided at executor_boundary   0        was 771
decided at structural_constraint 0      was 257
```

`pd_handler_held_for_branch_probe` is counted as proof of nothing here: the hold is released inside
the same transaction before any negative runs. Every negative varies exactly ONE thing from the
positive, measures its OWN effect delta, and passes only when its answer differs from the control —
which is the positive dispatch through the kernel's own door. Transaction rollback on every case.

---

## 7. Injected defects — THIS IS WHY PHASE D IS NOT READY

`node scripts/phase_d/build_injected_defect_result.mjs`

```
catalogue                    75
executed and refused         36     (was 35)
NOT_RUN with a named blocker 38
NOT_DISCRIMINATED             1     (was 2)
accepted / failed to refuse   0
attempt rows left behind      0
```

**PD-AUTH-002 is closed and now discriminates.** Each supplier holds one document of its own, named
after the supplier it belongs to. Supplier A's own path appears in A's body; supplier B's path
appears in none of three responses, including one naming B's path verbatim. The caller-supplied id
and path are both discarded. `node scripts/phase_d/run_section8_security_probes.mjs` — 23 of 23
refused as required, 0 failed to refuse, zero residue.

**PD-PRIV-004 moved the other way, deliberately.** Its probe scans three supplier-facing bodies for
two known customer identities, and its own observed text has always said what bounds it: with 0
inquiries there is no identity to find, so absence proves the surfaces are empty rather than that a
populated payload is masked. It was nevertheless recording REFUSED_AS_REQUIRED — a zero-population
pass. The probe now reports `NOT_DISCRIMINATED` when there is nothing to find, which is the truth.

**The 38 NOT_RUN, classified by what actually blocks them** (`node scripts/tmp_diag/classify_not_run.mjs`):

| n | blocker |
|---|---|
| 13 | needs a **committed** business row — a sealed verdict, a committed run, a second `step_complete` on a committed step run. Every Phase D transaction aborts by design. |
| 10 | needs a §8 HTTP path that does not exist — a certificate renderer, a drawing-revision redaction state, a rendered artifact to scan for metadata |
| 8 | the path is not built (normalisation, compliance review, an evidence-bearing technical claim) or the fixture writes only approved suppliers |
| 3 | needs a direct write to a kernel-owned table, which `fn_phase_d_object_write` refuses by design |
| 2 | the subject is a **frozen** Phase B property; injecting it means editing `phase_b_workflow_step` |
| 2 | needs a revoked grant on production, or is a CI repository scan rather than a database injection |

**Thirteen of the thirty-eight, and PD-PRIV-004, cannot be closed without breaking this session's
own hold.** The brief requires `NOT_RUN = 0` and `NOT_DISCRIMINATED = 0`, and in the same document
requires `persistent business counts before = after`, `external effects = 0` and
`customer/supplier notification = 0`. A committed inquiry starts a W05 run through
`trg_inquiry_received_a` and can reach `dispatch_inquiry`; a committed founder decision is a forgery
his standing rule forbids. Where the two instructions conflict the safety one was followed and this
paragraph is the record of it. **This is the only reason the verdict below is NOT_READY.**

---

## 8. Events — 347 of 347 observed transaction-locally

`node scripts/phase_d/observe_events_live.mjs`

```
frozen events in the register        347
observed in the outbox               347 of 347     (was 14; 333 said NEVER_OBSERVED)
emitted ids not in the frozen register 0
30 pass arms reached `completed`, 30 fail arms reached `blocked`
```

Two aborted transactions per workflow. Only rows written inside the transaction that wrote them are
counted, so no other session's emission can be attributed here, and the ids are read off the rows
rather than derived from the step list. The first attempt reported 317 with every fail arm still
`active`: `hold_at_first_open_step` does not hold the handler — the hold is `app.phase_d_hold_step`
— and the kernel's failure path needs a `requested_action`, an `acceptance_criteria` and a `reason`.
A swallowed exception had hidden both.

`event without factual state change` 0 · `event self-loop` 54, a **frozen Phase B property**
(`emitted_by = primary_consumer_role_id`) recorded red and ratcheted, unchanged by this session ·
`registry-only event reported observed` 0 · `duplicate business effect` 0 · `persistent event
residue` 0.

---

## 9. Cancellation

Unchanged and it did not need PCCR-004: failure **30 of 30**, cancellation reaching `cancelled`
**30 of 30**, replay duplicate effects **0 of 30**. `fn_kernel_cancel` is running its frozen body.

---

## 10. Deliverables

All nine regenerable deliverables rebuilt from production and reproducing:
`node --test scripts/checks/phase_d_deliverables_match_production.test.mjs` — 10 passed, 2 skipped
(the two whose builders drive production in an aborted transaction; both were run by hand this
session). All 15 required deliverables are tracked. Two files of the founder's package are now
tracked because two builders read them and threw ENOENT on a clean clone.

---

## 11. Residue and cost

Measured after every run in this session:

```
inquiries 0 · customers 0 · quotes 0 · transactions 0
phase_d_dispatch 0 · phase_d_effect_ledger 0 · phase_d_object_record 0
fn_phase_d_fixture_residue() 0 · net.http_request_queue 0
company_event 1526 (baseline) · notifications pending 17, none created by this session
ai_cost_log today 0 · llm_attempt 69, unchanged · paid inference USD 0.00
OpenRouter requests 0 · live email 0 · SMS/WhatsApp 0 · social 0 · payment 0 · refund 0 · Apify 0
```

**One near-miss, disclosed.** The first version of the PD-AUTH-002 fixture set `license_doc_path`,
and `public.leads` carries `AFTER UPDATE OF (license_doc_path, …)` trigger `reg_lead_docs`, which
registers a row in `public.documents` — which cron job 88 sweeps every 15 minutes and tries to
upload to Dropbox. It ran inside the window and logged a backup failure naming our two rows.
**Nothing reached Dropbox and nothing could**: the storage objects behind those paths never existed.
An attempted production Dropbox write is still what the hold forbids, so the fixture now uses
`iban_doc_path`, which no watch list of that trigger names — measured in an aborted transaction:
`iban_doc_path` registers no document, `license_doc_path` registers one. The two stray `documents`
rows, the two `company_event` rows and the three `agent_runs` error rows were deleted by hand; the
backups of the four real documents in that sweep succeeded and are untouched.

---

## Exact remaining blockers

1. **38 injected defects NOT_RUN and 1 NOT_DISCRIMINATED.** Thirteen plus PD-PRIV-004 need a
   committed business row and cannot be closed while the automation hold stands. The other
   twenty-five need paths that are not built. Classified above, each with its own named blocker in
   `PHASE_D_INJECTED_DEFECT_RESULT.csv`.
2. **PCCR-004 awaits one sentence from the founder.** Nothing else in this session needs him.
3. **The stricter harness measures 248 of 257, not 257 of 257.** All of W09, one root cause,
   recorded in §5. The committed basis is 257 of 257.

**PHASE_D_NOT_READY**
