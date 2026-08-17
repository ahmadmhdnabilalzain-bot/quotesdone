# Phase C — final independent re-acceptance audit

**Verdict: `PHASE_C_FINAL_ACCEPTANCE_FAIL`**

**Session:** 17 Aug 2026, 17:13–19:0x UTC. Independent, read-only, against production
`htdblwldjkcgjvmqkbeh`. The auditor did not implement the corrections under audit.
**Commit audited:** `8617bc9` (merge of PR #431, `fix/phase-c-final-five-root-causes`).
**Mode:** `NO_PAID_AI=true OPENROUTER_DISABLED=true AI_PROVIDER_MODE=mock`.
**Nothing was repaired. Phase D was not begun.** Every write in this audit ran inside a
transaction that ends in `raise exception`, except the two founder commands submitted through the
real Command Center (382, 386), both of which were cancelled through the same interface.

---

## THE VERDICT IN ONE PARAGRAPH

Four of the five root causes reproduce as fixed under independent measurement, and the load-bearing
Phase C behaviour holds: cancellation reaches the kernel and propagates completely, all twelve
active existing-workflow signal sources are executable through the canonical door, execution and
trace are written as one fact, trace 3730 is truthfully classified, 55/55 injected defects are
refused on stable contracts, and paid inference is USD 0.00 with zero OpenRouter requests. The
audit fails on **root cause 1's own subject**: the correction registered two new runtime components
on production and did not update the committed artefact the estate's own invariant check compares
against, so the repository and production now disagree about what the runtime is — and a second,
superseded source-of-truth check was left live, answering the same question with 436 findings while
the new one answers 0.

---

## FAILED GATES

### FAIL-1 — a correction registered production rows the repository does not record

| | |
|---|---|
| **Gate** | B (routine source of truth) / I (no unexplained discrepancy) |
| **File** | `scripts/sql/rc4_execution_and_trace_are_atomic.sql:50` |
| **Artefact** | `docs/phase-c/PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv` |
| **Check that fails** | `scripts/checks/phase_c_invariants.test.mjs` → exit 1 |
| **Introduced by** | the PR under audit (#431) |

`rc4_execution_and_trace_are_atomic.sql` inserts two rows into `public.phase_c_component`:

```
dbfn:fn_kernel_trigger_submit(jsonb)
dbfn:fn_kernel_signal_submit(jsonb)
```

Both are correct and necessary — `fn_kernel_system_execution_begin` refuses an unregistered
component, and root cause 4 exists precisely because those two doors were writing traces naming
component ids that did not exist. But `docs/phase-c/PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv` was
not touched by the PR (`git log 1fddbbd..HEAD -- <csv>` is empty). It still holds 1799 rows;
production holds 1801.

Measured:

```
FAIL  PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv (1799) matches public.phase_c_component (1801)
      — db-only dbfn:fn_kernel_signal_submit(jsonb); db-only dbfn:fn_kernel_trigger_submit(jsonb)
1 check(s) failed        (exit 1)
```

**Smallest responsible defect:** the migration that registers a component does not also extend the
crosswalk artefact the invariant check reads, and nothing forces the two to move together.

CI cannot see it: `phase_c_invariants.test.mjs` skips loudly without a management token, and CI has
none. The failure is only visible from a token-holding session — which is what this audit is.

### FAIL-2 — two committed source-of-truth checks, two answers, no stated winner

| | |
|---|---|
| **Gate** | B (exactly one canonical answer; no commit-time tie resolution) |
| **Files** | `scripts/checks/canonical_routine_manifest.mjs` (new) vs `scripts/checks/canonical_routines.test.mjs` (predecessor) |
| **Introduced by** | not the PR — but root cause 1 retired only *one* of the two predecessors |

Root cause 1 retired `sql_files_match_live.test.mjs` (renamed `.RETIRED.mjs`, refuses to run, names
its replacement). It left `scripts/checks/canonical_routines.test.mjs` — written 16 Aug for the same
defect, opening with *"THE MANIFEST IS THE SOURCE OF TRUTH, AND THIS IS THE CHECK THAT MAKES THAT
MEAN SOMETHING"* — live and unannotated. Run today against the same production:

| | `canonical_routine_manifest.mjs` | `canonical_routines.test.mjs` |
|---|---|---|
| sources read | 4 tiers (migrations_history, migrations, db-functions, scripts/sql) | `scripts/sql` only |
| countable findings | **0**, exit 0 | **436**, exit 1 |
| uncommitted DDL | 0 | 15 |

The new check is the correct one and this audit reproduced its result independently (below). The
older one is narrower by construction and its 436 are artefacts of that narrowness — spot-verified:
`phase_c_historical_repair.active_effect_now` is committed at
`scripts/sql/kernel_k23_historical_exception_register.sql:54` (a multi-column `add column`, the
matcher defect the new check fixed), and `kernel_signal_inbox` with its inline primary key is
created at `scripts/sql/kernel_k16_signal_service.sql:73`.

**Smallest responsible defect:** the retirement was applied to one predecessor and not the other, so
the repository now contains two checks that both claim to be the source of truth and disagree by 436.
`npm test` runs both (`run.mjs` walks every `*.test.mjs` in the repository), so a token-holding run of
the suite is red.

---

## PRE-EXISTING FAILURES FOUND, NOT INTRODUCED BY THIS CORRECTION

Reported because Section I forbids an unexplained discrepancy. Neither was caused by PR #431, and
neither was repaired here.

**P-1 — a stale value-shape assertion, the same family root cause 5 fixed for messages.**
`scripts/checks/phase_c_founder_chain.test.mjs:123` counts the canonical event with
`dedupe_value = 'founder_command:' || cmd`. Since the kernel cutover (16 Aug 2026 21:08 UTC)
`fn_kernel_workflow_start` writes `kernel:started:<workflow>:founder_command:<id>:1`. Measured: 6 of
the 12 command-bearing outbox rows carry the old shape, 6 the new; the check reads **0** for an event
this audit watched being emitted exactly once. Root cause 5 removed prose coupling from the guard
suite; this is the same coupling to a *value* shape, in a different file.

**P-2 — `scripts/checks/phase_c_command_acceptance.test.mjs` passes 17/20.** CC-020
(`CMD-W01 / tasks_created`) fails: *primary owner `strategy_director` not among task owners
`[chief_of_staff]`*. Phase B ownership is frozen and its drift is 0, so this predates the PR.

---

## A. BASELINES AND CURRENT DEPLOYMENT — PASS

| subject | required | measured |
|---|---|---|
| branch | `main` | `main` |
| working tree | clean before audit artefacts | 0 modified tracked files (38 untracked session artefacts, pre-existing) |
| local vs `origin/main` | equal | `8617bc9` both, 0 ahead / 0 behind |
| the five-root-cause PR | merged | `8617bc9`, merge of PR #431 |
| Phase A drift | 0 rows | **0 rows** |
| Phase B drift (effective) | 0 rows | **0 rows** |
| departments | 10 | **10** |
| canonical roles | 90 | **90** |
| category overlays | 86 | **86** |
| workflows | 30 | **30** |
| workflow steps | 257 | **257** |
| edge functions carrying repo code | all | **202 / 202 LIVE** |

**The baseline was not regenerated to produce this.** `org_phase_baseline.recorded_at` is
2026-08-16 08:08:37 UTC for Phase A and 2026-08-17 00:08:20 UTC for Phase B — both *before* the five
correction commits (17 Aug 20:17–21:00 Dubai / 16:17–17:00 UTC). Phase B's baseline carries the
PBCR-001 amendment (W14-S05 accountability, handoffs 161→159), which is a founder-approved change
request, not a repair of drift; `fn_phase_a_baseline_drift` compares registry SHA-256 digests, not
only counts.

**Boundary:** "production contains the same deployed commit" was measured for the two production
surfaces the PR touches — database routines (0 drift, below) and edge functions (202/202 parity).
PR #431 changed no frontend file, so the Vercel build was not re-measured; that is stated, not
assumed.

---

## B. ROUTINE SOURCE OF TRUTH — PASS on the routine gates, with FAIL-2 above

Reproduced independently with a parser written for this audit, not by re-running the builder's check.

| required | measured |
|---|---|
| application repository → production missing | **0** |
| application production → repository missing | **0** |
| drifted application routines | **0** |
| conflicting current definitions | **0** |
| ambiguous routine winners | **0** |
| uncommitted application DDL | **0** |
| manifest gaps | **0** |

Every one of the **1003 APPLICATION rows** in `CANONICAL_ROUTINE_MANIFEST.csv` was re-derived from
scratch: the declared `source_sha256` was recomputed from the named canonical file, the declared
`deployed_sha256` matched against a live `prosrc`, and the routine confirmed present in `public`.
Disagreements: 0 in every column.

`fn_ws_operations` / `fn_ws_company` — the pair root cause 1 names — verified byte-for-byte, not
token-for-token:

| routine | file | body sha (first 16) | live sha (first 16) |
|---|---|---|---|
| `fn_ws_operations` | `operations_company_remaining_lists.sql` | `3d0dcf4f2fa3ad42` | `3d0dcf4f2fa3ad42` |
| `fn_ws_operations` | `operations_assistance_company_reports.sql` | `a3f416c24b0a37fe` | (does not match) |
| `fn_ws_company` | `operations_company_remaining_lists.sql` | `351522eb4ed65186` | `351522eb4ed65186` |
| `fn_ws_company` | `operations_assistance_company_reports.sql` | `75c7f50cd3bcbc18` | (does not match) |

The conflict was real (different bodies), the winner is the later MANIFEST line (1275 vs 1274), and
both losing definitions are named in `scripts/sql/SUPERSEDED.txt` with the reason.

**Dollar-tag parsing.** 58 routines in the repository are defined with a digit-bearing dollar tag
(`$k34$`, `$w14$` …). Absent from the manifest CSV: **0**. Bodies the parser could not extract: **0**.
Live in `public`: **58 of 58**. The kernel routines are all present (57 `fn_kernel_*` rows in the CSV).

**Selection uses no commit timestamp.** The sequence is migration version, then filename, then line
position in `scripts/sql/MANIFEST.txt`. Two files can only collide on an identical key, and that is
itself a failure.

**Forced counterexample.** In a throwaway tree, two files at one migration version both defining
`public.fn_zz_probe` with a `$k34$` body:

```
CONFLICTING current definitions (two files at one sequence key): 1
   fn_zz_probe  seq 2|00000020990101000000  …_alpha.sql  …_beta.sql  distinct bodies 2
AMBIGUOUS routine winners: 1
countable findings 2  -> exit 1        EXIT=1
```

A manifest gap in either direction was forced the same way and reported the same way.

**CI.** `.github/workflows/project-parity.yml` has `on: pull_request` as well as `push`, `schedule`
and `workflow_dispatch`, and runs `canonical_routine_manifest.mjs --all` unconditionally.

**Stated boundary:** the manifest's SHA-256 columns are over a token normalisation, so pure
whitespace differences between file and production are deliberately not findings. Byte identity was
confirmed separately for the two `fn_ws_*` routines.

---

## C. CANCELLATION THROUGH THE REAL COMMAND CENTER — PASS

`fn_founder_command_control` delegates to `fn_kernel_cancel` for both `cancel` and `supersede`, and
verifies the founder identity twice on purpose.

**Live run, through the deployed path.** A real founder session was minted from the management token
(api-keys → `generate_link` → `verify`) and every call went to the deployed `os_api` with
`apikey: anon` + `Authorization: Bearer <founder access token>` — the exact request
`src/lib/osClient.ts` sends from the Cancel button at `OsxShell.tsx:1488`.

Command **382** (`Draft one short internal note … do not use any paid AI provider`):

| subject | before Cancel | after Cancel |
|---|---|---|
| founder command 382 | `tasks_created` | `cancelled` |
| workflow run 727 (W20) | `active` | `cancelled` |
| step run 654 (W20-S01) | `active` | `cancelled` |
| task 1818 | `queued` | `cancelled` |
| outbox 1102 (`EV-W20-STARTED`) | `pending` | `superseded`, `delivered_at` NULL |
| traces 6380 / 6381 / 6383 / 6384 | all `open` | all `sealed` |

**Replay.** A second Cancel returned `ok:true` with every `closed` counter at 0. Digest of the whole
subtree before and after: `fd4e56d9e71b5c8c13154177e0f2f13b` → unchanged.

**The worker cannot deliver a cancelled subject.** Forced through the audited maintenance door in an
aborted transaction: outbox 1102 was put back to `pending` and the real
`fn_kernel_outbox_deliver(3,'final-acceptance-probe')` was run. Result:

```
status=superseded  delivered_at=NULL
last_error=DELIVERY REFUSED …: founder command 382 is cancelled; workflow run 727 is cancelled;
           step run 654 is cancelled; task 1818 is cancelled
           (fn_kernel_outbox_refuse_cancelled_subject)
```

A direct forced transition into `delivered` produced the same refusal. Both transactions aborted;
the row is `superseded`, `attempts` 0.

**Normalised columns, not a JSON search.** `z05_outbox_refuse_cancelled_subject` and
`fn_kernel_cancel` join on `command_id`, `workflow_run_id`, `step_run_id`, `task_id`; the row also
carries `correlation_id` (`cmd:382`) and `causation_id` (`command:382`). No payload search is
involved. (Column naming note: the command column is `command_id`, not `founder_command_id`, and the
step column is `step_run_id`, not `workflow_step_run_id` — same substance, different spelling from
the brief.)

**Re-measured over all cancelled commands (9):**

| required | measured |
|---|---|
| cancelled commands with an active workflow run | **0** |
| cancelled commands with an active step run | **0** |
| cancelled commands with an active operational task | **0** |
| cancelled commands with a pending handoff | **0** |
| cancelled commands with a deliverable pending event | **0** |
| cancelled commands with an unsealed required trace | **0** |
| sealed trace with `sealed_at` null (whole estate) | **0** |

**Command 338 / run 538 / step run 531** are `cancelled` / `cancelled` / `cancelled`. The repair
evidence is preserved and truthful: `phase_c_workflow_run.closure_evidence` for 538 states in full
that the original cancellation went through `fn_founder_command_control`, which did not call
`fn_kernel_cancel`, and that the command's own history is unchanged. The step run's
`failure_reason` carries the same sentence.

---

## D. EXISTING-WORKFLOW SIGNALS — PASS

Inventory reproduced from `public.phase_c_source_cutover` where `source_class` = `B
EXISTING_WORKFLOW_SIGNAL`: **14 rows, 12 ACTIVE, 2 DISABLED** (`cron:141`, `cron:264`, both
`ADAPTER_ASSIGNED_SOURCE_STAYS_DISABLED`). Builder's "12 active sources" reproduces.

### The twelve active sources

Every row below carries `target_kernel_adapter = fn_kernel_signal_submit`,
`trace_policy = TRACE-SYSTEM-EXECUTION`, `idempotency_rule =
signal: <source_type>:<source_id>:<signal_type>:<workflow_run_id>`, and
`allowed workflow states = any non-terminal state of the named run`.

| # | source id | component | signal type | src state | type state | workflow | accountable role | measured acceptance | verdict |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `dbtrigger:public.inquiry_matches:notify_matched_supplier` | db trigger | `followup.due` | ACTIVE | active | W12 | `supplier_matching_dispatch_operator` | attached, trace 6419 | CUT_OVER, executable |
| 2 | `dbtrigger:public.notifications:trg_invite_status_on_send` | db trigger | `provider.callback` | ACTIVE | active | W09 | `supplier_onboarding_specialist` | attached, trace 6420 | CUT_OVER, executable |
| 3 | `dbtrigger:public.quote_items:quote_items_roll` | db trigger | `supplier.quote_revision` | ACTIVE | active | W14 | `quote_evaluation` | attached, trace 6425 | CUT_OVER, executable |
| 4 | `dbtrigger:public.supplier_dues:trg_due_paid` | db trigger | `provider.callback` | ACTIVE | active | W16 | `payments_and_billing_manager` | attached, trace 6426 | CUT_OVER, executable |
| 5 | `dbtrigger:public.transactions:trg_refund_resolved` | db trigger | `provider.callback` | ACTIVE | active | W17 | `trust_and_safety_manager` | attached, trace 6427 | CUT_OVER, executable |
| 6 | `edge:customer_documents` | edge function | `document.arrived_for_run` | ACTIVE | active | W07 | `document_intelligence_manager` | attached, trace 6428 | CUT_OVER via table trigger |
| 7 | `edge:messages_api` | edge function | `clarification.response` | ACTIVE | active | W18 | `customer_success_director` | reached `fn_kernel_step_complete`; refused only for a probe payload with no `output` | CUT_OVER, executable |
| 8 | `edge:stripe_confirm` | edge function | `provider.callback` | ACTIVE | active | W16 | `payments_and_billing_manager` | attached, trace 6430 | CUT_OVER via table trigger |
| 9 | `edge:sup_dob` | edge function | `document.arrived_for_run` | ACTIVE | active | W10 | `supplier_verification` | attached, trace 6431 | CUT_OVER via table trigger |
| 10 | `edge:supplier_ack` | edge function | `supplier.acknowledgement` | ACTIVE | active | (any) | `quote_evaluation` | attached, trace 6432 | CUT_OVER via table trigger |
| 11 | `edge:supplier_portal` | edge function | `supplier.quote_revision` | ACTIVE | active | W14 | `quote_evaluation` | attached, trace 6437 | CUT_OVER via table trigger |
| 12 | `ui:/[locale]/me` | frontend route | `clarification.response` | ACTIVE | active | W18 | `customer_success_director` | same door as #7 | covered by the edge function it calls |

Expected effect is the signal type's declared disposition: `ATTACH_ONLY` for eleven,
`COMPLETE_STEP` for `clarification.response`.

### The two groups of signal types, named

**Active (6).** `document.arrived_for_run` was already active; the five activated on 17 Aug under
root cause 3 are `clarification.response`, `followup.due`, `provider.callback`,
`supplier.acknowledgement`, `supplier.quote_revision`. This reconciles the builder's "five signal
types activated" with a live count of six.

**Intentionally inactive (5).** `deadline.due`, `retry.due`, `review.verdict`,
`run.cancellation_requested`, `sla.breach`. Each carries its own `activation_reason` — e.g.
cancellation already has exactly two doors, and a review verdict is recorded through
`fn_kernel_review_decide`.

### The four cases, driven through the canonical door

Every active handler was exercised in aborted transactions through `fn_kernel_signal_submit` and,
separately, through `fn_kernel_source_emit` under each of the twelve source keys.

| required | measured |
|---|---|
| valid state accepted | **6 / 6** |
| invalid state (terminal run) refused | **6 / 6** |
| missing workflow refused | **6 / 6** (plus 6/6 for "names no run at all") |
| duplicate replay creating work | **0** — the second submit returns the first decision, inbox delta 1, task delta 0, step-run delta 0 |
| active source targeting an inactive signal type | **0** |
| active signal type without a working handler | **0** |
| active source falsely marked CUT_OVER | **0** |
| cutover verdict resting only on source-text caller detection | **0** |

The last line matters and is the reason this section was driven rather than read. None of the five
`CUTOVER_COMPLETE` triggers contains the string `fn_kernel_signal_submit`; they call
`fn_kernel_source_emit(<source key>, …)`, which resolves the class from
`phase_c_source_cutover` and dispatches. A grep-based verdict would have called all five *not* cut
over. Driving the door proved they are.

`clarification.response` (`COMPLETE_STEP`) was proved separately with a contract-valid output: it
completed step `W20-S01`, created the handoff `H-W20-01-02`, and the replay returned the first
decision. `supplier.quote_revision` was proved on a real W14 run created for the probe.

---

## E. SYSTEM EXECUTION AND TRACE ATOMICITY — PASS

| required | measured |
|---|---|
| TRACE-SYSTEM-EXECUTION trace without an execution subject | **0** |
| system execution without a trace | **0** |
| terminal system execution with an open/incomplete trace | **0** |
| sealed trace with `sealed_at` null | **0** |
| traces on the policy / execution rows | **587 / 587** |
| failed or idempotent insert leaving an orphan trace | **0** |
| active orphan traces | **0** |
| unlabelled reconstructed execution evidence | **0** |

The contract: `..._begin` writes an OPEN trace (execution in flight, no execution row yet);
`..._close` seals the trace and inserts the execution row in the same transaction.
`fn_kernel_system_execution_pair_guard` enforces exactly that — a SEALED trace with no execution row
raises, naming trace 3730 as the shape it exists to prevent.

**Forced cases, all aborted:**

| case | result |
|---|---|
| 1 begin then finish | trace +1, execution +1, sealed-without-execution 0, open 0 |
| 2 failed execution | trace +1, execution +1, sealed-without-execution 0, open 0 |
| 3 duplicate idempotency key (begin twice, finish both) | trace +2, execution +2, no orphan |
| 3b close the same trace twice | trace +1, execution +1 — the second close returns without a second execution |
| 4 subject insert failure (unregistered `system_actor`) | FK `phase_c_system_execution_system_actor_fkey` raises at close; the whole transaction fails, so trace and execution roll back together — no orphan |
| 5 finish failure (`result='failed'` with no failure text) | refused, 23514, `fn_kernel_system_execution_close` |
| 5b finish failure (unknown result value) | refused, 23514, `…close: result banana is not one of succeeded, failed, refused, no_op` |
| 6 unregistered component at begin | refused, 23503, before anything is written |

Note on case 3: `idempotency_key` is accepted in the input but not used to de-duplicate an
execution — two begins produce two executions. That is consistent with an execution record being a
record of what ran, and it leaves no orphan; it is recorded here as an observation, not a finding.

### Trace 3730

| question | answer |
|---|---|
| original creator | `fn_kernel_trigger_submit(jsonb)`, 2026-08-17 05:05:00.033303 UTC, sealed at the same instant, parent trace 3726, resulting run 352 |
| was the trace row edited | **no** — `update` refused: *"sealed trace evidence is append-only; write a superseding row instead of editing it"* (`fn_phase_c_trace_append_only`); `delete` refused by FK from `kernel_trigger_inbox` |
| the execution row | reconstructed by `scripts/sql/rc4_execution_and_trace_are_atomic.sql`, `recorded_at` 2026-08-17 16:39:30 |
| labelled as a reconstruction | **yes**, in three independent places: `technical_scope` opens *"RECONSTRUCTED 17 Aug 2026 … This row was NOT written when the execution ran"*; `correlation_id = reconstructed:trace:3730`; `causation_id = reconstructed:trigger_inbox:46` |
| represented as contemporaneous | **no** — `started_at`/`finished_at` carry the original instant, `recorded_at` carries the repair instant, and the register says *"the difference between those two columns is the whole of the honesty here"* |
| repair/supersession immutable | **yes** — `update` and `delete` on `phase_c_historical_repair` both refused (`fn_phase_c_historical_repair_append_only`); `update` on the reconstructed execution row refused (`fn_phase_c_system_execution_append_only`) |

Repair 83 first classified 3730 as a historical exception. **Repair 85 corrects it** — 3730 was
created *after* the kernel cutover (2026-08-16 23:18:23), so it was a live kernel-era defect that
was repaired, not a preserved historical record. Both rows survive; the correction is a new row
citing `corrects_repair_id: 83`, which is what an append-only register is for.

**Final disposition: truthful.**

**Boundary on "active orphan traces = 0".** `fn_kernel_trace_integrity` reports non-zero on five of
its 32 lines. All five were examined:

- `orphan_traces_task 7 of 803` — traces 490, 491, 492, 534, 536, 537, 827. Every one is
  pre-cutover (16 Aug 10:29–18:37) and carries two `phase_c_historical_repair` rows
  (`HISTORICAL_ORPHAN_TRACE` + `S2-RETROFIT-ORPHAN-INVALID`) with `active_effect_now = false`.
- `trace_state_disagrees_with_subject_workflow_run 4 of 15` (runs 91, 92, 93, 96) and
  `…_handoff_run 1 of 7` (handoff 48) — all pre-cutover, all sealed; a sealed trace cannot follow
  its subject, which is the append-only rule working.
- `traces_with_unmapped_subject_kind 1 of 803` — a pre-cutover `subject_kind = 'command'` spelling.
- `system_execution_components_with_no_trace 589 of 635` — **deliberately red**, and the check says
  so in its own comment: it must stay red until scheduled, webhook, queue, storage and
  provider-adapter execution write traces. Turning it green by narrowing scope is the defect it
  exists to prevent.

Of the 22 open traces in the estate, 7 are post-cutover and every one belongs to a live
non-terminal subject (`active` / `queued` / `tasks_created`). None was created after the five fixes.

---

## F. GUARD CONTRACTS — PASS on the 55, with a stated qualification on the "20"

```
55/55 injected defects refused
row counts before/after every aborted injection: 10 tables, all unchanged
probe components persisted: 0
```

**Independently classified, not read from the file's own summary line.** All 55 expectations were
parsed out of `CASES`, `VALUE_CASES` and `SEQ_CASES` and typed:

| | count |
|---|---|
| refusals asserting a `[SQLSTATE, stable identity]` pair | **31** |
| assertions on the guard's own structured return value (`false\|…`, `true`, `tasks_created\|…`) | **24** |
| assertions resting only on human-readable exception prose | **0** |
| stale assertions (a case failing because wording moved) | **0** — all 55 pass |
| refused operations with partial effects | **0** — every probe aborts, and ten table counts are asserted as a delta |

**Wording changed, contract survived.** Inside an aborted transaction the guard
`fn_phase_c_task_state_guard` was replaced with a body raising the same `23514` and an entirely
different sentence, then the same defect was injected:

```
BASELINE : 23514: phase_c_task: owner a_person_nobody_models does not resolve to an active canonical role
           CONTEXT: PL/pgSQL function fn_phase_c_task_state_guard() line 10
           pair ["23514","fn_phase_c_task_state_guard"] matches: true

REWORDED : 23514: ZZZ AUDIT REWORDING: an entirely different sentence.
           CONTEXT: PL/pgSQL function fn_phase_c_task_state_guard() line 1
           pair ["23514","fn_phase_c_task_state_guard"] STILL matches: true
```

The production body was re-read afterwards and is unchanged.

### Qualification on "20 positive controls"

The closure document records *"positive cases accepted 20/20 (Phase B suite, both directions)"*.
The suite was run — **20/20 guards fired, row counts unchanged** — but its population is not 20
positive controls:

- **18 negative injections** and **2 positive controls** (`invalid state transition`,
  `frozen architecture changed WITH a change request`).
- Of its 20 expectations: **5** assert a stable identity (a constraint name, `not-null`,
  `duplicate key value`), **8** assert a token the harness itself raises (`DETECTED …`,
  `REFUSED …`, `HATCH OPENED as designed`), and **7 rest only on the guard's own human wording** —
  `/does not resolve to an active canonical role/`, `/store the canonical role_id/`,
  `/category overlay cannot be accountable in W12/`, `/may own an analysis step only/`,
  `/says sender ceo but step .* is owned by/`, `/PHASE B IS FROZEN/`. **No SQLSTATE is asserted
  anywhere in that file.**

So "prose-only assertions = 0" is true of the 55-case Phase C suite root cause 5 repaired, and false
of the 20-case Phase B suite the same table counts. Recorded as an observation: all 20 pass today,
nothing is stale, and Phase B is frozen — but the contract there is still a sentence.

---

## G. LOAD-BEARING PHASE C REGRESSION

### G.1 Founder authentication — PASS (7/7), against the deployed `os_api`

| case | result |
|---|---|
| no headers at all | **401** |
| anon key only, no bearer | **401** `{"error":"unauthorized","hint":"sign in — the Command Center requires a bearer token"}` |
| invalid bearer | **401** `{"error":"unauthorized"}` |
| non-founder JWT (`acceptance-nonfounder@example.invalid`) | **403** `{"error":"forbidden"}` |
| enabled founder JWT (`management@quotesdone.com`) | **200**, `ok:true` |
| build-mode founder identity | `active = false` |
| `fn_os_open_access()` | `false` |

### G.2 One founder command, one business effect — PASS

Command **386**, submitted and observed across a real 1-minute worker delivery:

| | at submit | after delivery |
|---|---|---|
| workflow runs | 1 | **1** |
| tasks | 1 | **1** |
| open tasks | 1 | 1 |
| outbox rows | 1 | **1** |
| delivered | 0 | 1 |
| traces | 4 | **4** |

One event (`EV-W20-STARTED`, producer `kernel:workflow_start`, `correlation_id cmd:386`,
`causation_id command:386`). Delivery created no run, no task, no trace and no further event — no
self-emission. The founder thread returns the plan, the founder's verbatim words, the task with its
owner (`marketing_director`), manager (`chief_revenue_officer`), department (`growth`), acceptance
and closure criteria, and the traces. Command 386 was cancelled through the Command Center at the
end of the audit so the estate carries no work this audit created.

### G.3 Autonomous new-work source — PASS

Driven through the real adapter `dbtrigger:public.agent_actions:trg_page_high_agent_action`
(class A, `system.incident_opened`) via `fn_kernel_source_emit`, never by calling workflow start:

```
run_delta=1  task_delta=1  command_delta=0
run_owner=it_operations_engineer   run_command_id=NULL   task_owner=it_operations_engineer
duplicate delivery created: {"run":0,"task":0,"event":0,"step_run":0,"inbox_row":0}
```

Founder absent (`command_delta = 0`, `command_id` NULL), Chief of Staff absent, one workflow, one
initial task, duplicate delivery inert.

### G.4 Workflow closure — PASS

| required | measured |
|---|---|
| W14-S05 owner | **`quote_evaluation`**, `actor_kind = canonical_role` |
| overlay owns a task anywhere | **0** |
| overlay owns a step in Phase B | **0** |
| overlay still contributes | yes — W14 `contributors = {category overlays, broad domain specialists, document_intelligence_manager}` |
| false terminal steps | **0 of 30 workflows** |
| workflows with no executable closure path | **0 of 30** |
| closure with an open mandatory blocker | refused (Phase B suite: *completed workflow with an open blocker*, *closure with a mandatory step incomplete*) |

**W14 driven end to end** in one aborted transaction — start, nine steps, two handoffs accepted with
complete packets, the independent review at W14-S08 by `rfq_success`:

```
W14 CLOSURE: final_state=completed iterations=10
W14-S01->waiting_handoff | W14-S02->waiting_handoff | W14-S03..S08->active | W14-S09->completed
```

A representative workflow already carries explicit closure on production: run 236 (W06) closed at
step W06-S07 with all seven hard gates evaluated and recorded in `closure_evidence`.

### G.5 Kernel-only business writes — PASS, on the full matrix

The repository's `kernel_write_guard_both_directions.test.mjs` passes 7/7, but it exercises **one**
of the eight protected tables. The full matrix was run for this audit — every table carrying
`fn_kernel_write_guard` × four untrusted identities:

```
protected tables: 8   (kernel_signal_inbox, kernel_trigger_inbox, phase_c_event_outbox,
                       phase_c_handoff_run, phase_c_refund_decision, phase_c_task,
                       phase_c_workflow_run, phase_c_workflow_step_run)
cases: 32   denied: 32   ACCEPTED: 0
```

`anon` and `authenticated` are stopped at the grant (42501 permission denied); `service_role` is
stopped by the guard; `service_role` with a forged `kernel.maintenance_reason` GUC is stopped too —
the door needs the table owner as well as a reason. Canonical kernel writes are accepted
(`run=742 step_runs=1 tasks=1`), and the audited maintenance door works and records itself.

### G.6 Legacy retirement — PASS

| check | value |
|---|---|
| old cron jobs invoking the old runtime | 0 of 0 |
| direct grants permitting kernel bypass | 0 of 8 |
| active callers of disabled paths | 0 of 2 |
| paths with no recorded disposition | 0 of 0 |
| kernel primitives called from outside the kernel | 0 of 3 |
| retired paths executable by an ordinary role | 0 of 8 |
| retired paths with a recorded final state | 8 of 8 (`COMPATIBILITY_WRAPPER_TO_KERNEL` 2, `DISABLED` 2, `KERNEL_INTERNAL_PRIMITIVE` 3, `READ_ONLY_HISTORICAL` 1) |
| compatibility wrappers not calling the kernel | 0 of 2 |

### G.7 Refund-only founder approval — PASS, forced rather than inferred

The state function reports `refund_decisions_that_are_mutable: 0 of 0` — an empty population, which
scores as satisfied whether or not the guard exists. Every claim was therefore forced:

| forced case | result |
|---|---|
| UPDATE a founder refund decision | **refused** 23514 *"the decision is append-only; supersede it, do not edit it"* |
| DELETE a founder refund decision | **refused** 23514 *"a founder refund decision cannot be deleted"* |
| executor = reconciler | **refused** 23514 *"the executor and the reconciler are the same role"* |
| decided by a non-founder | **refused** 28000 *"not the founder: payments_and_billing_manager is not an enabled founder identity"* |
| a non-refund founder approval request | **refused** 23514 *"commercial_model_change is not a founder-approval action class. The founder is not the company's approval queue; only a specific refund decision reaches him."* |

`founder_approval_request` holds 0 rows; `v_founder_inbox` exists and is refund-only; 0 of 46 org
tasks are newly routed to the founder for a non-refund reason. Execution against a non-approved
decision, and reconciliation before execution, are both refused by
`fn_phase_c_refund_decision_guard`. `refund_single_path.test.mjs` passes 4/4.

---

## H. ZERO-COST OBSERVATION WINDOW — PASS

**Four real scheduled `ai_health` executions were observed during this session** — cron job 102 at
17:07, 17:22, 17:37 and 17:52 UTC, all `succeeded`. Every one recorded:

```
skipped_due_to_zero_cost_mode: 8/8 routes held until 2126-08-15T02:51:36; key_present=true;
no request was made to any paid provider
note: "ai_health made NO request to any paid provider: …"
```

| required | measured |
|---|---|
| OpenRouter HTTP requests | **0** — the `fetch('https://openrouter.ai/api/v1/key')` branch is unreachable while the hold is on; the run reports from `fn_os_provider_state_cached` |
| other paid inference requests | **0** |
| `llm_attempt` rows this session | **0** (last row in the estate: 2026-08-15 02:51:33) |
| `ai_cost_log` rows today | **0**; cost today **AED 0.00 = USD 0.00** |
| `ai_usage` rows today | **0** |
| fallback provider key | **none** — `app_secrets` holds `openrouter_api_key` and `openrouter_min_usd` and no key matching openai / anthropic / gemini / groq / together / deepseek / mistral / fireworks / perplexity / xai / cohere / replicate / bedrock / azure |
| gate-read failure denies | the shared `paidProviderGate` is fail-closed: a throw, a null, a malformed shape and an explicit refusal all arrive as `allowed=false`; an `envHold` from `NO_PAID_AI`/`OPENROUTER_DISABLED` skips independently |
| empty/malformed route state denies | `fn_kernel_paid_provider_state()` — `gate_denies_a_registered_route` false, `gate_denies_an_unregistered_route` false, `gate_allows_the_deterministic_path` true, routes held 8 of 8, paid inference rows since the hold 0 |

`phase_c_invariants` independently reports: every provider route held open-circuit 8/8; zero paid
inference calls since Phase C began; paid inference cost AED 0.00 = USD 0.00.

**No V3 certification, knowledge-pack scorecard, professional agent-quality test or unrelated Row #3
check was run.**

---

## OBSERVATIONS — recorded, not findings

1. **The closure document reports "965 routine names, 965 canonical".** Run at that same commit
   (`7a23a0d`, in a clean worktree) the check reports **1013 / 1013**, identical to HEAD. The gate
   result (0 findings) reproduces; the figure in the prose is stale.
2. **`fn_kernel_outbox_deliver` returned `delivered: 1` for a row the guard refused.** In the
   aborted probe the worker's own counter said `delivered 1` while the row ended `superseded` with
   `delivered_at` NULL. No delivery happened and no check consumes that counter — its only callers
   are cron job 278 and the kernel SQL — but the counter reports the consumer's verdict, not the
   row's fate.
3. **The estate's own write-guard test covers 1 of 8 protected tables** (4 of the 32 denial cases).
   All 32 were run here and all 32 denied, so the system is not weaker than claimed; the instrument
   is narrower than the claim.
4. **`system_execution_components_with_no_trace 589 of 635` is red on purpose** and says so in its
   own comment. It is Phase D scope and must not be turned green by narrowing.
5. **Column naming.** The brief asks for `founder_command_id` and `workflow_step_run_id`; the
   normalised columns are `command_id` and `step_run_id`. Same substance.

---

## WHAT PASS WOULD REQUIRE

Nothing here was repaired. For completeness, the two failed gates are:

1. `docs/phase-c/PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv` does not record the two components
   `rc4_execution_and_trace_are_atomic.sql` registered on production, and
   `scripts/checks/phase_c_invariants.test.mjs` fails on the difference.
2. `scripts/checks/canonical_routines.test.mjs` is a superseded source-of-truth check left live; it
   exits 1 with 436 findings on the question `canonical_routine_manifest.mjs` answers with 0, and
   nothing in the repository states which is authoritative.

**PHASE_C_FINAL_ACCEPTANCE_FAIL**
