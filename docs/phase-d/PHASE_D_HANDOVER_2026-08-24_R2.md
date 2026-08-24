# Phase D — final builder session, 24 Aug 2026

Every figure below was measured by execution on `htdblwldjkcgjvmqkbeh` in the session that wrote
this file. Where a figure is bounded, the bound is stated next to it rather than left to be found.

---

## 0. Source and baseline

| | |
|---|---|
| base | `main @ 48195b1` — HEAD, `origin/main` and the working tree's tracked state all equal, PR [#463](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/463) merged |
| applied production-direct | N01–N11, each `node scripts/apply_sql.mjs <file> --apply [--ddl]`, each read back and identical to the file |
| Supabase project | `htdblwldjkcgjvmqkbeh`, the only one |
| Phase A drift | **0 rows** |
| Phase B drift | **0 rows** |
| Phase C freeze board | **0 red**, `frozen_subjects_drifted` 0 of 25, `amendments_awaiting_founder_approval` 0 of 5 |
| active cron | 23 of 206, unchanged · `outcome_evaluate_daily` **INACTIVE** |
| automation hold | `company_stand_down` intact, unchanged |

---

## 1. The brief's premise was a session out of date, and re-measuring said so first

The brief opened with **declared step effects: 254/257** and gave W05-S07, W12-S06 and W16-S05 as
the three that had no effect, with a diagnosis for each. Before building any of the three fixes, the
coverage matrix was re-driven:

```
node scripts/phase_d/build_step_branch_coverage.mjs

frozen steps in the matrix         257 of 257
reached through the canonical path 257 of 257
producing their declared effect    257 of 257
```

All three already produce their declared effect, and the reference each writes is in the matrix:

| step | declared effect | actual reference |
|---|---|---|
| W05-S07 | `DOMAIN_MUTATION/public.inquiries/OBJECT_STATE_WRITE` | `public.inquiries:id=65a05826` |
| W12-S06 | `DOMAIN_MUTATION/public.inquiry_matches/OBJECT_STATE_WRITE` | `public.inquiry_matches:id=18` |
| W16-S05 | `VERSIONED_ARTIFACT/public.reveal_invoices/OBJECT_VERSION_WRITE` | `public.reveal_invoices:trans…` |

W16-S05 is keyed by `transaction_id`, which is the model §4 of the brief named as the expected safe
one. GATE-005 is evaluated on W05-S07 (12 of 12 gates evaluated, dispatch `EXECUTED`, no refusal),
so its classification question — existing policy authority, new founder approval, or a misbound
gate — does not arise: **non-refund founder approval requests created remain 0** and no routine work
waits on the founder. PRs #461 and #463 closed all three; the brief's count predates them.

**What re-measuring found instead is in §2 and §3, and it is real.**

---

## 2. Two defects the brief predicted the shape of, found by measurement

### N01 — the writer's own gate never asked whether the supplier was approved

`public.inquiry_matches` is guarded by two BEFORE INSERT triggers. BR-015 and GATE-014 both read
`approval_status = 'approved' AND verified`. The writer's own guard,
`fn_unsafe_match_eligibility_guard`, read `banned`, `matching_blocked`, `permanently_closed` and
`license_expiry` — **and never `approval_status` at all**. When a caller wrote the assignment without
consulting the gate, an unapproved supplier was accepted.

```
select approval_status, count(*) from public.leads group by 1;
  (null)     20464
  approved       1
```

20,464 of 20,465 suppliers carried no approval decision and every one passed. It also answered
**PASS** for a supplier that is not in `public.leads` at all — a verdict about a subject it could
not find.

Proved in six directions on one key, after the fix:

| arm | verdict | landed |
|---|---|---|
| approved + verified (control) | `PASS` | **true** |
| `approval_status` null | `BLOCKED_SUPPLIER_NOT_APPROVED` — "no approval decision on record (pending)" | false |
| `approval_status = 'rejected'` | `BLOCKED_SUPPLIER_NOT_APPROVED` — names rejected | false |
| `approval_status = 'suspended'` | `BLOCKED_SUPPLIER_NOT_APPROVED` — names suspended | false |
| registration expired | `BLOCKED_INELIGIBLE_SUPPLIER` — names the date | false |
| banned | `BLOCKED_INELIGIBLE_SUPPLIER` — names banned | false |

Pending, rejected, suspended and expired are now **distinguished by reason**, which the 23 Aug
hand-over recorded as an open gap. `registration_expires_at` is read for the first time by anything
in the estate. `BLOCKED_INELIGIBLE_SUPPLIER` is deliberately **not** renamed — an existing check
asserts it by name, and approval is a different fact from a standing bar, so it got its own value
rather than being folded into one that already meant something else.

The Phase D headline did not move: the fixture builds its supplier approved and verified
(supplier 48387), so W12-S06 keeps producing its effect. Had that not been true the repair would
have been the fixture, not the guard.

### N02 — a rejected review stopped nothing on the 229 steps that name no reviewer

`fn_kernel_review_decide` accepts `approved`, `rejected` and `changes_requested`. One predicate reads
the verdict, in two places, and both are guarded by `independent_reviewer_role_id <> ''`. **28 of 257
steps declare one. On the other 229 nothing read the verdict at all** — and even on the 28 the test
is for the *presence of an approval*, never the *presence of a rejection*.

Driven on production:

```
W04-S03  declares no reviewer   review_decide('rejected') -> ok=true
                                recorded verdict          -> 'rejected'
                                step_complete('pass')     -> COMPLETED, state=completed
W04-S04  declares a reviewer    the same rejected verdict -> REFUSED k3_reviewer_verdict_missing
```

`fn_kernel_review_decide` is a **frozen Phase C subject**, so the fix went where the question can
always be answered and nothing is frozen: a `BEFORE UPDATE` guard on
`public.phase_c_workflow_step_run` — the table already carries a sibling of exactly that shape —
refusing a move to `completed` while the **latest** sealed verdict is `rejected` or
`changes_requested`. Every completer passes through that row update, including one that skips the
handler.

Five controls, so the guard fires on exactly the case it names:

```
rejected, outcome pass          REFUSED pd_review_verdict_rejected
no verdict at all               COMPLETED  state=completed
approved verdict                COMPLETED  state=completed
rejected THEN approved          COMPLETED  state=completed     (the correction path)
rejected, outcome fail          COMPLETED  state=failed        (a rejection must let a step fail)
```

Alias self-review, measured on a non-empty population: `fn_kernel_reviewer_independent('ceo', …)`
returns **false** for all three aliases that resolve to `ceo`, and **true** for `general_counsel`.

The one §5 requirement not met is that the service still *accepts* a verdict for a step declaring no
reviewer. It is no longer consequence-free, which was the danger. Narrowing the frozen service is
raised as **PCCR-005 — disclosed, not applied, recommendation defer**.

---

## 3. All 347 events, emitted *and consumed*

`phase_d_event_reconciliation` carried one runtime value for all 347: `OBSERVED_IN_OUTBOX`. What
that measured is exact and narrow — a row carrying the event id was read back out of the outbox
inside the transaction that wrote it. **It proves the producer emitted and says nothing about
consumption.** One uniform value across 347 rows is a column whose name promises a journey and whose
content records a departure.

`public.fn_kernel_event_consume(outbox_id)` is the canonical consumer and it runs **inside the
caller's transaction**, projecting rather than sending. The observer now calls it on every emitted
row, in the same aborted transaction:

```
node scripts/phase_d/observe_events_live.mjs --jobs=3

events_carrying_a_final_evidence_status                  347 of 347   ok
events_runtime_observed_or_proven_terminal_or_deferred   347 of 347   ok
fail_closed_events_stating_no_reason                       0 of 347   ok
events_whose_consumption_reapplied_the_producer_action     0 of 347   ok
observed_events_carrying_no_correlation_id                 0 of 347   ok
observed_events_carrying_no_trace                          0 of 347   ok
observed_events_with_no_retry_budget                       0 of 347   ok
```

**All 347 reached `OBSERVED_SUCCESS`** — every one emitted and handled. None needed the
structurally-deferred escape hatch, which also means the 60 rows whose structural status said
`DEFERRED_RUNTIME_IMPLEMENTATION` were emittable after all.

**The 54 self-loops.** `emitted_by = primary_consumer_role_id` on 54 of the 347 is a registry
property, not a loop. The question that matters is whether *consuming* re-applies the producer's
action, and it is answered by counting the business rows each consume call adds — tasks, runs, step
runs and further outbox rows. **Zero, on all 347.** Correlation, causation, dedupe, trace and retry
budget are read off the outbox row that was actually written, never off the registry.

---

## 4. The injected defects: nineteen exemptions down to nine gaps

```
node scripts/phase_d/build_injected_defect_result.mjs

catalogue                              75
executed with a discriminating result  66      (was 56)
NOT_RUN with a named blocker            9      (was 17)
executed but NOT_DISCRIMINATED          0      (was 2)
FAILED TO REFUSE                        0
attempt rows left behind                0
named in the disposition register       9 of 9
```

**Ten cases closed, and in eight of them the recorded blocker was simply wrong about its own
reason.** That makes 31 wrong blockers this estate has now found.

| case | the blocker said | what was measured |
|---|---|---|
| PD-CONC-001 | "a second claimant cannot exist" | two management-endpoint statements run on **two distinct backends** whose transactions overlap — pids 1719034 and 1719035, both live 00:48:42→00:48:46 UTC. And its other half, "a committed outbox row sends for real within 60s", is also wrong: neither `fn_kernel_outbox_deliver` nor `fn_kernel_event_consume` contains `net.*`, `http` or any send. Outbox delivery is an in-database projection. |
| PD-OUTBOX-004 | "no consumer runs under the hold" | `fn_kernel_event_consume` runs in the caller's own transaction. Consumed the same row twice: 0 outbox rows added either time. |
| PD-TRACE-001/002 | "doing it raw would test the kernel" | `fn_phase_d_object_write`'s own refusal, `pd_object_kernel_owned`, **is** the control — a Phase D refusal on a Phase D call. |
| PD-TRACE-005 | "Phase D has no path that requests it" | the absence of the path is the answer; the door refuses with `pd_object_unbound`. |
| PD-STATE-003/004 | "the subject is frozen" | the frozen registry **refusing** is the discriminating result. Two different guards answer the two injections — `a10_phase_b_owner_guard` and `z90_phase_b_freeze` — which is the control. The owner guard refuses even with `app.phase_b_change_reason` set, so an unowned successor is unreachable by construction, not by policy. |
| PD-PROV-002 | "not representable" | it was not **built**. `fn_phase_d_gate_evaluate` carried zero exception handlers. N06 built the distinction. |
| PD-PROV-004 | "the subject is outside the database" | that is a description of a test, and the test now exists. |
| PD-AUTH-002 / PD-PRIV-004 | "both fixtures held zero documents" | true when written; the probe was improved and the reason was never re-read. |

### PD-CONC-001 — a real race, with a control

```
node scripts/phase_d/run_concurrency_probes.mjs

race      A claimed 1 (outbox 327764)   B claimed 0
control   C alone claimed 1 (outbox 327764)
residue   0 business rows; 1 maintenance receipt (audit evidence)
```

Two concurrent backends raced the estate's own claimer, `fn_phase_c_outbox_claim`, over a temporary
committed canary. A claimed it and held the lock; B, on a different backend, claimed 0 — `for update
skip locked` passed over the locked row. **The control is the point:** a third session claiming alone
afterwards took the same row, so B's zero was caused by A's lock and not by an empty queue. The
canary was removed through the audited maintenance door and the relation is back at its watermark.

The first run of this probe failed usefully: it created the canary *before* waiting for a clear
window, the 1-minute cron claimed it, `fn_kernel_event_consume` refused it fail-closed ("carries no
workflow_run_id: it was produced as a command, not as a record of a run") and the worker
dead-lettered it after one attempt. That is direct runtime evidence of the retry/dead-letter branch,
and it is why the canary is now created inside the window.

### PD-PROV-004 — a real architectural finding, not a clean sheet

`scripts/checks/no_edge_function_calls_a_provider_directly.test.mjs` walks `supabase/functions`,
counts only provider hosts inside a `fetch()` call — a host in a comment or in an alert body a human
reads is not a call — and classifies each as INFERENCE or METADATA.

**Two edge functions perform paid inference through a direct provider client instead of through the
gateway:** `designer` (api.openai.com image generations) and `resend_inbound` (openrouter.ai chat
completions, whose own comment says it was not migrated because the gateway does not proxy image
payloads). Both are gated, so neither spends under the hold. The architectural control — all
inference through one door — was enforced by nothing until this check. Two more reach a provider for
metadata only. All five are registered with kind and reason; a sixth, or a METADATA entry that starts
doing inference, turns it red. Proved by negative control: a temporary function posting to
`openrouter.ai/api/v1/chat/completions` made it fail; removing it made it pass.

### The nine that remain are gaps, not exemptions

Every one is classified **G — REAL_PRODUCT_GAP** under the taxonomy the brief specified, and the
table now refuses to hold a `REAL_PRODUCT_GAP` that does not name the missing control:

| case | the control that does not exist |
|---|---|
| PD-AUTH-005, PD-LEGAL-005 | a door that opens a task with a caller-supplied accountable owner and is not itself a kernel-internal primitive. **Both refusals exist and were observed**; what is missing is a legitimate caller. |
| PD-FIN-004 | a registered write route for `phase_c_refund_decision` — `kernel_write_authority` holds zero rows for it, so the table holds zero rows and the append-only trigger has nothing to refuse. **The second half must not be built:** the subject would be a founder refund decision, and a fixture may never forge one. |
| PD-LEGAL-004 | a predicate that judges a legal or tax artefact stale. No routine compares `effective_date` or `updated_at` against `now()`. |
| PD-PRIV-002 | a business object for a drawing revision carrying its redaction-approval state. |
| PD-PRIV-005 | a rendering path and a scanner over the produced bytes. |
| PD-QUOTE-001 | two committed quotes and a testable supplier edit path. `public.quotes` has RLS enabled with **zero policies**, so both suppliers see nothing and a control differing in one respect behaves identically. |
| PD-QUOTE-004 | a publication state on the comparison. BR-019 and GATE-018 both evaluate ownership, never publication. |
| PD-QUOTE-005 | a normalisation path writing a projection alongside the immutable revision. BR-018 reads the caller's own claim about itself. |

**Classification E — a local ephemeral database — could not be attempted.** Docker Desktop on this
machine fails to start: stale unix-socket entries under `AppData\Local` in two separate directories
that Windows cannot delete. Two of them were renamed away and it got one stage further each time
before failing on the next. It would not have changed any of the nine — a database this harness
builds itself cannot answer whether the *estate* has a control, only whether a copy of it does.

---

### N11 — the ownership ledger still named the file N01 replaced, for the fourth time

`scripts/checks/application_source_of_truth.test.mjs` went red on the branch with one finding:
`public.kernel_routine_ownership` recorded `fn_unsafe_match_eligibility_guard`'s canonical file as
K05 while manifest order said N01. Nothing about the classification changed — QUOTESDONE_APPLICATION
under R4 before and after — only the file. D56, F28 and K09 carry titles one word from this one.

The ledger is deliberately **not** regenerated from the manifest: a ledger derived from the thing it
audits audits nothing, so the gate is right to be red until a human moves the row. Four occurrences
is an argument for a smaller diff at the point of replacement, not for deleting the check.

## 5. PCCR-004 — disclosed, not approved, not applied

`sha256(pg_get_functiondef('public.fn_kernel_cancel(jsonb)'))` measured this session:
`fc59489affbbc6654de56a7aa3012abeb339be4c8ae92a8282662e71d076f8ff` — **identical to the frozen
baseline digest** in `phase_c_frozen_subject`, captured 2026-08-18. The routine is running its frozen
body. `frozen_subjects_drifted` 0 of 25; `amendments_awaiting_founder_approval` 0 of 5;
`approved_by` and `approved_at` untouched.

The complete amendment table is in
[`PCCR_004_AMENDMENT_TABLE.md`](PCCR_004_AMENDMENT_TABLE.md), unchanged by this session.

**Recommendation: `PCCR-004_DEFER_OR_REJECT`.** Cancellation measures **30 of 30 reaching
`cancelled`** with the currently approved frozen service. Exactly one behaviour needs the amendment
— cancelling one run of a multi-run founder command while leaving its siblings' derived work intact
— and no production path does that today. Phase D does not depend on it.

---

## 6. Re-measured after every fix

| | |
|---|---|
| frozen steps producing their declared effect | **257 of 257** |
| reached through the canonical path | **257 of 257** · reached only by a direct complete **0** |
| step-contract cases | **1,799 of 1,799** passed, 0 failed — six of the seven kinds at `live_step_run` (the real handler), `malformed_output` at the frozen kernel door |
| happy closure · failure · cancellation · replay | **30 of 30** each · replay duplicate effects **0** |
| effective handoffs | 159 |
| events reconciled and runtime-proven | **347 of 347** `OBSERVED_SUCCESS` |
| injected defects | **66 of 75** discriminating · 0 accepted · 0 NOT_DISCRIMINATED · 9 gaps, each naming its missing control |
| migrations classified | **235 of 235** · down script required and missing **0** |

### The one thing the branch matrix does *not* prove, said plainly

`fail edge exercised 257 of 257` is reached with the handler **held** on all 257 —
`pd_handler_held_for_branch_probe`. That arm proves the workflow graph's fail edge behaves as the
frozen model declares; it does **not** prove the handler refuses its own invalid evidence. That is a
different instrument and it exists: the 1,799-case suite invokes the real handler with real invalid
evidence and reads a stable code —

```
missing_input        pd_input_schema_invalid    the real handler, a declared input key removed
invalid_state        pd_step_state_invalid      the real handler, a step run that does not exist
failed_rule_or_gate  pd_rule_refused            the real handler, a load-bearing evidence key removed
wrong_actor          k3_actor_unresolved        the kernel — actor resolution is the kernel's job
malformed_output     k3_output_empty            the frozen kernel door
duplicate            REPLAYED                   a second dispatch, one effect
positive             EXECUTED                   one effect on the ledger
```

Both instruments are legitimate and they measure different subjects. Conflating them would have been
the mistake.

---

## 7. Residue, holds and cost

```
inquiries 0 · quotes 0 · customers 0 · transactions 0 · inquiry_matches 0
phase_d_object_record 0 · phase_d_dispatch 0 · phase_d_effect_ledger 0 · phase_d_external_attempt 0
fn_phase_d_fixture_residue() 0 rows · net.http_request_queue 0
leads 20,465 (baseline) · phase_c_event_outbox 33 (baseline) · delivery_attempt 31 (baseline)

llm_attempt 69, unchanged · ai_usage 14, unchanged · llm_calls 78, unchanged
ai_cost_log 3,507 rows, unchanged · cost today AED 0.00 · paid inference USD 0.00
OpenRouter HTTP requests 0 · live email 0 · SMS/WhatsApp 0 · social 0
payment 0 · refund 0 · Apify 0 · production Dropbox writes 0 · fallback provider key 0

23 of 206 cron jobs active, unchanged · outcome_evaluate_daily INACTIVE
company_stand_down intact
```

**Audit evidence, reported separately as required.** `public.kernel_maintenance_write` gained **3**
receipts, all from the concurrency canary cleanups, each naming its `audit_run_id` and its reason.
They are immutable audit records of a deliberate maintenance write, not business activity, and no
business relation moved. `public.phase_d_concurrency_probe_result` holds 1 row, labelled in the
table's own COMMENT as audit evidence.

---

## 8. What was not done, and why

* **The independent Phase D audit was not run** — the brief forbids it in this session.
* **Phase E was not begun. Automation was not reactivated. `outcome_evaluate_daily` remains inactive.**
* **The knowledge-pack scorecard was not run** — `scripts/kb/pack_scorecard.mjs` requires
  `--packs=<extracted packs dir>`, which is not in this repository and was not supplied. Nothing is
  claimed about the packs either way.
* **The founder's supplied catalogue was not edited.**
  `QuotesDone_…/registries/PHASE_D_INJECTED_DEFECT_CATALOG.csv` is his specification;
  `expected_machine_result` stays exactly as delivered even where it is obsolete. What changed is the
  RESULT recorded beside it.
* **PHASE_D_STEP_BRANCH_COVERAGE.csv is a record of one drive, not a byte-stable artefact** — its
  `actual_effect_reference` column carries real row ids the scenario factory mints fresh each time.
  It is not one of the nine `build_all` deliverables the reproduction check compares. Unchanged from
  the 23 Aug hand-over; repeated because a reader of a diff will see it move.
