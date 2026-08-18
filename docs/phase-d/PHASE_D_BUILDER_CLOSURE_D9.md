# QuotesDone Phase D — builder closure, session 4 (D9)

**PHASE_D_NOT_READY**

| | |
|---|---|
| session | 2026-08-18 19:12 → 2026-08-19 UTC (database clock) |
| project | `htdblwldjkcgjvmqkbeh` — the one project |
| branch | `feat/phase-d-d9-the-handoff-is-159-contracts` |
| baseline | `38bcc17` — `main` == `origin/main`, working tree clean of tracked changes, PR [#448](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/448) merged |
| paid inference | **USD 0.00** — 0 OpenRouter requests, 0 `llm_attempt` rows, 0 `ai_cost_log` rows |
| live external effects | **0** — nothing sent, published, charged or refunded |
| active cron, start → end | **23 → 23** |

Phase E was not begun. No frozen Phase A, Phase B or Phase C object was edited. No Phase D audit was
run. Business automation was not reactivated.

---

## The one number that moved

| | before | after |
|---|---|---|
| workflows reaching deterministic closure | **1 of 30** (W04) | **14 of 30** |
| workflows driven at all | 8 of 30 | **30 of 30** |
| handoffs accepted through a contract | 0 | **92** |
| business effects produced in one batch | 7 | **136** |
| effective handoff contracts | 0 of 159 | **159 of 159** |

The fourteen that close: **W02, W04, W08, W10, W11, W18, W19, W21, W22, W24, W25, W27, W29, W30.**

Every one of the other sixteen stops at a named step with a machine refusal code, recorded verbatim
in `PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv`. None is described as "partial" without saying where
and why.

---

## 0. Precheck

| check | result |
|---|---|
| branch at start | `main`, HEAD `38bcc17`, identical to `origin/main` |
| Phase D PRs merged before this session | #446 (D0/D1/D3), #447 (D2/D4/D5), #448 (D6/D7/D8) |
| working tree | 12 untracked session artefacts from earlier sessions, none staged |
| Phase A baseline drift | **0** |
| Phase B baseline drift | **0** |
| `fn_phase_c_freeze_drift()` | **0 red**, 25 of 25 frozen subjects intact |
| active cron jobs | 23 |
| effective handoffs | 159 (PBCR-001 denominator, not reopened) |
| production ahead of main | **no** — every routine deployed here is committed on the branch and merges through the PR |

---

## 1. The handoff was 159 contracts pretending to be one

`fn_phase_c_handoff_packet_valid(handoff_id, packet)` reads its `handoff_id` argument **only** to
confirm the handoff exists, then checks a fixed five-key list for every one of the 159. The frozen
`required_packet`, `receiving_acceptance_criteria`, `rejection_condition`, `return_owner_role_id`,
`closure_condition` and `sla_policy_id` were never read. Behaviourally the 159 handoffs were one
handoff — the same shape as the 32 gates sharing one predicate, found in D5.

**Measured before building:** 159 handoffs, 795 declared packet clauses, **163 distinct keys** —
four boilerplate clauses shared by all 159, and exactly one clause unique to each. Every handoff
really does ask for something of its own and nothing was reading it.

`public.phase_d_handoff_contract`, **159 rows**, derived — never hand-typed. Packet keys are the
semicolon clauses of the frozen prose through `fn_phase_d_slug`, the identical rule D1 used for the
514 handler contracts. Every row carries the sha256 of the prose it came from, so a Phase B text
change is detectable rather than leaving a contract quietly describing a handoff that no longer
says that.

| board check | result |
|---|---|
| effective handoffs contracted | **159 / 159** |
| distinct distinguishing keys | **159** |
| contracts whose packet is only boilerplate | **0** |
| contracts drifted from the frozen packet | **0** |
| contracts with no parsed SLA target | **0** |
| contracts where accountability does not move | **0** |

### Proved by execution, in an aborted transaction, on production

The board went green over an **empty population** on three of its checks, which cannot tell a dead
guard from an idle system. Each was made to fire:

```
open handoff H-W01-01-02 on run 7328 (receiver strategy_director)
  generic five-key packet          refused   pd_handoff_packet_incomplete   naming the missing item
  wrong receiver (the sender)      refused   pd_handoff_wrong_receiver
  complete packet, right receiver  ACCEPTED  to_step=W01-S02  step_run=6898  task=8930
                                             open tasks on W01-S02 = 1
                                             accountability chief_of_staff -> strategy_director
                                             run_state waiting_handoff -> active
  replay of the same acceptance    replay=true   open tasks on W01-S02 = 1   <- not 2
  reject with no missing item      refused   pd_handoff_rejection_unspecific
  reject by the sender             refused   pd_handoff_wrong_receiver
  reject, specific                 ok        workflow_advanced=false
                                             step runs 1 -> 1, run_state unchanged
                                             accountability returned to chief_of_staff
  accept after reject              replay=true, outcome=rejected — no second decision
  cancel                           run cancelled, open handoffs 1 -> 0
```

**The kernel still moves the state.** `fn_phase_d_handoff_accept` validates the contract and hands
the state move to the frozen `fn_kernel_handoff_accept`. It opens no step run, creates no task and
moves no run state itself.

### The kernel has no rejection door — disclosed, not worked around

`fn_phase_d_handoff_reject` originally called `fn_phase_c_handoff_decide`. The kernel board caught it
in the same session: **`kernel_primitives_called_from_outside_the_kernel` went 0 → 1 of 9.** That
routine is registered in `kernel_write_authority` with the words *"called only by
fn_kernel_handoff_accept"*.

The uncomfortable part, stated plainly: the frozen kernel has `fn_kernel_handoff_accept` and **no
corresponding reject**. Phase C is frozen, so Phase D may not add one, and reaching past the
boundary is what went red. So the Phase D rejection no longer touches `phase_c_handoff_run`. It
records a durable, specific refusal, returns accountability to the frozen contract's return owner,
proves the workflow did not advance, and returns `kernel_handoff_still_open: true`. A new board row
counts those. **It is expected to be non-zero, it is owned, and closing it needs a Phase C change
request — not a Phase D increment.**

---

## 2. The fixture factory, and four defects it found by running

Six of the eight workflows driven in D8 stopped for want of a parent. `customers`, `inquiries`,
`quotes`, `transactions`, `inquiry_matches`, `quote_comparisons` and `refunds` all held **zero rows**
since the 16 August purge.

`fn_phase_d_fixture_scenario` builds the lineage **through `fn_phase_d_object_write`** — the same
canonical object service the handlers use — in the foreign-key order measured from `pg_constraint`,
never by direct insert. 24 declared stages; **23 create**.

| guard | mechanism |
|---|---|
| explicit test context | `set local app.phase_d_test_context = 'on'` required, per transaction |
| execution context | must be `test` |
| untrusted caller | `anon` and `authenticated` refused, and both revoked from the routine |
| no external effect | `public.notifications` counted **before and after every stage**; the whole scenario aborts on any delta |
| no paid capability | the factory calls one routine and it is the object writer |
| deterministic ids | `md5(label:stage)::uuid` — the same label gives the same ids |
| cleanup | designed for an aborted transaction; `fn_phase_d_fixture_residue()` measures survivors **after** the fact, because a ledger written inside the transaction rolls back with the rows it describes |

**The one stage that does not create is reported, not faked:** `inquiry_answer` needs a
`group_id` into `public.inquiry_workstream_group`, which holds **0 rows**. It returns
`BLOCKED_NO_REFERENCE_DATA`. Creating a workstream group would be a fixture inventing business
reference data one layer down.

### Defect 1 — an object that could not reach its own state

`supplier_account` declares `approval_status` as its state column and `public.leads` carries
`CHECK (approval_status <> 'approved' OR verified = true)`. The write map had no `verified` column,
so the object's own `approved` state was **unreachable through its canonical writer** — and BR-015
requires approved AND verified, so no canonical path could ever satisfy it. Proved by execution:
`new row for relation "leads" violates check constraint leads_approved_implies_verified`.

### Defect 2 — five canonical object writes queue an outbound message

Stage `inquiry` tripped the notification assertion on its first run. Measured with a detector that
reads **trigger function bodies** rather than write maps, the canonical Phase D object services reach
**eight notification-writing triggers across four relations**:

| relation | trigger | reached by object |
|---|---|---|
| `public.inquiries` | `trg_inquiry_received_a` | `inquiry` |
| `public.inquiries` | `customer_abandon_ban` | `inquiry` |
| `public.inquiry_matches` | `notify_matched_supplier` | `supplier_assignment` |
| `public.quotes` | `trg_new_quote_sms` | `quotation` |
| `public.transactions` | `trg_reveal_receipt_a` | `payment_transaction`, `reveal_transaction` |
| `public.transactions` | `trg_notify_refund` | `payment_transaction`, `reveal_transaction` |

Not one of those rows comes from a Phase D write map, so the D7 board check
`phase_d_write_maps_into_the_outbound_notification_table` is green **and always would have been**.
Its name says Phase D does not write the outbound table; what it measures is that no Phase D write
map targets it. That is the instrument-on-the-wrong-subject shape again.

**What keeps the session at zero:** the fixture identities carry **no email and no phone**. Every one
of those triggers is conditional on a contact detail existing. That is the honest statement — the
lineage is quiet because it has no address, not because the paths are closed. 569 of the 20,465 real
supplier rows likewise have no email, so the shape is an ordinary business state. The per-stage
count, not the choice of fixture, is what enforces the zero, and it is asserted on every stage of
every scenario.

**Not done:** no trigger was disabled, altered or dropped. They are live product behaviour, the
outbound senders are held, and removing a notification path to make a Phase D number green would be
changing behaviour to pass a check.

### Defect 3 — the inquiry writer covered two of the six fields its own scorer reads

The first repair added `rfq_ready` to the `inquiry` write map. It did nothing: `trg_rfq_complete` is
a BEFORE trigger that computes `NEW.rfq_ready := fn_rfq_score(NEW)->>'ready'`, so the column is
derived and a caller's value is overwritten. **Mapping it was mapping a column that cannot be
written**, which is worse than not mapping it — the board would have gone green on a repair that
changes nothing.

What `fn_rfq_score` actually reads, out of 100 with 70 to pass: category 20 (mapped), emirate 10,
scope_detail 25 (mapped), scope_type 15, budget 15, supporting_detail 15 — **the canonical writer
could reach 45**. So no Phase D path could produce a quote-ready inquiry, therefore none could
produce a supplier assignment (`trg_gate_incomplete_match` returns NULL — *silently*, by its own
comment), therefore W12 and everything downstream of a dispatch could not be driven.

And the generic score is not the whole bar. The second attempt measured **score 100, ready false**:
`fn_rfq_required_check` found unanswered required keys in `category_specs`. A number that looks like
the verdict and is not the verdict — only reading both told them apart.

### Defect 4 — a harness that seeds the row the step is supposed to create

W09, W12, W14 and W16 collided with their own output on a unique constraint because the factory had
already produced `supplier_capability`, `supplier_assignment`, `quotation` and `payment_transaction`.
**GATE-015 read as a business refusal and was in fact the test seeding its own subject.** The factory
now takes `for_workflow` and skips any stage whose object that workflow writes, read from
`phase_d_step_effect` rather than listed by hand.

Measured honestly: with the exclusion on, closure went **14 → 3**, because removing the seed also
removes parents the workflow's own first-step rules read. The exclusion is therefore **available and
not used by default**, and the four collisions remain open with their mechanism recorded. Reporting
3 as though it were progress, or hiding the exclusion because it made the number worse, would both
have been the wrong call.

---

## 3. Three defects in the driver, each found by running it

**A generated fixture beat the real reference.** With the whole lineage built, W05–W08 still stopped
on their first step: `BR-013: no inquiry_id named`. The inquiry existed and the driver had it —
but `parent_refs` reached only the effect payload, never the rule and gate context. What the rules
read was `fn_phase_d_fixture_context`, which invents a typed value for every declared key, so BR-013
was handed the string `ZZ DEMO — inquiry_id` and correctly found nothing. **A harness that generates
the identifier the rule under test must resolve is answering its own question**, and here it was
answering in the negative — 250 steps unreachable behind a refusal that was about the harness.

**The owner of a customer-scoped object is a customer.** `inquiries.customer_id` points at
`owner_ref`, and the driver's `owner_ref` was a freshly generated key, so a foreign key received an
identifier for a customer that does not exist. The scope is already declared in
`phase_d_business_object_binding.ownership_scope` — CUSTOMER on 9 objects, SUPPLIER on 10,
COMPANY on 24 — so it is read rather than decided.

**A run that could not see what it just created.** `parent_refs` is computed once, before the drive.
A workflow that creates an object at step 1 and has a rule read it at step 4 was asking about
something it had itself written. The driver now folds each produced effect's result key back into
the context under the name that object contributes, read from `phase_d_fixture_stage.contributes_ref`
— the same mapping the factory uses, so the harness and the run cannot drift into two vocabularies
for one object.

**And one more, in the frozen registry's own derivations.** W11-S01 refused with
`pd_output_schema_invalid`. It is the **one step of 257** where the two derivations disagree: the
output contract follows `step_type` ('measurement') while D7d's lexicon classified the effect as
`CAPABILITY_REQUEST` from the required_action text. The driver was supplying measurement keys keyed
on the effect type, so this step could never satisfy its own contract. **The output contract is the
authority on the output**, and no other step changes behaviour.

---

## 4. A reviewer for a step the registry leaves to runtime

45 of the 47 review steps name no independent reviewer; the reviewer is a runtime fact. W05-S06
refused because the single reviewer offered for the run was `inquiry_quality_analyst` — which is the
reviewer the frozen registry names on a *different* step of W05, and is that step's own owner.
BR-002 was right.

The driver now takes a **candidate list from the caller** and, only where the frozen step names
nobody, takes the first candidate the **frozen kernel's own** `fn_kernel_reviewer_independent`
accepts against that step's owner. Where the registry does name a reviewer, that one is used and no
choice is made. The candidates are the 14 roles the frozen registry already names as independent
reviewers somewhere in the 257 steps. The verdict remains the caller's, and both
`fn_kernel_review_decide` and `fn_phase_d_effect_produce` re-check independence afterwards. This
cannot become `fn_pick_reviewer` returning a department head.

---

## 5. Two repository defects found while committing

**`scripts/sql/MANIFEST.txt` had 21 corrupt lines.** Eighteen were shell hook output
(`[INFO] Recording command outcome: echo`) written straight into the manifest, and three were
PowerShell-quoted paths — one naming a file that does not exist. A `scripts/sql` file the manifest
does not list is a MANIFEST GAP and its live routines are production→repository drift. Cleaned, with
every remaining line verified to resolve to a real file. *An interim clean removed three
single-quoted entries whose files DO exist; caught by re-reading the removals and restored.*

**Re-applying an earlier file silently reverted two later routines.** Fixing a constraint name in
`phase_d_d9c` re-applied that file's older `fn_phase_d_fixture_scenario` and
`fn_phase_d_fixture_state`, discarding four subsequent increments. Nothing failed and
`apply_sql.mjs` printed success both times — the read-back covers the file it was given, not the
increments after it. Only `canonical_routines.test.mjs` caught it, as
`repository -> production drift: 2`. All eleven files were re-applied in order and drift returned
to 0 in both directions.

---

## 6. Zero cost and zero external effect

| | |
|---|---|
| OpenRouter HTTP requests | **0** |
| other paid inference requests | **0** |
| `llm_attempt` rows this session | **0** |
| `ai_cost_log` rows this session | **0** |
| paid inference cost | **USD 0.00** |
| live email / SMS / WhatsApp / social / payment / refund | **0** |
| `public.notifications` rows written this session | **0** |
| Apify runs | **0** |
| production Dropbox writes | **0** |
| fallback provider key | **0** |
| active cron jobs, start → end | **23 → 23** |

**Nothing was left behind.** After 30 workflow drives and dozens of scenario builds, read back from
the database: `customers` 0, `inquiries` 0, `transactions` 0, `quotes` 0, `refunds` 0,
`inquiry_matches` 0, `phase_d_effect_ledger` 0, `phase_d_handoff_acceptance` 0,
`fn_phase_d_fixture_residue()` **0**, `leads` 20,465 (unchanged). Every probe ended in
`raise exception`.

---

## 7. Estate state at close

| check | result |
|---|---|
| Phase A baseline drift | **0** |
| Phase B baseline drift | **0** |
| `fn_phase_c_freeze_drift()` | **0 red** |
| `fn_phase_d_handoff_state()` | **10/10 green + 1 disclosure row** |
| `fn_phase_d_fixture_state()` | **10/10 green + 1 informational row** |
| `kernel_boards_are_green.test.mjs` | **7/7 pass** — 30 boards, 367 checks, 8 red, every one owned and pre-existing |
| `canonical_routines.test.mjs` | **11 passed, 0 findings** — 0 drift in both directions, 0 manifest gaps |
| schema mirror vs live export | regenerated — the mirror said 560 tables, production holds 563 |

**No new red board.** The two this session's own work introduced were both fixed here rather than
adjusted to agree with what shipped.

---

## 8. What is NOT done — the itemised remainder

| brief section | scope | state |
|---|---|---|
| **§0** | rollback classification for every deployed Phase D migration | **DONE** — see `PHASE_D_PRODUCTION_DEPLOYMENT_LEDGER.md` |
| **§1** | recalculate 257 handler effect + application-connection statuses from code and callers | **NOT DONE.** The effect dimension exists from D7 (224/21/12); the *application connection* dimension — NO_RUNTIME_CALLER / API_CONNECTED / FRONTEND_CONNECTED / FULL_APPLICATION_PATH_CONNECTED — is not measured. |
| **§2** | reconcile the 12 `EXTERNAL_ADAPTER_READY_DISABLED` rows against the 14-field durable contract | **NOT DONE.** They remain typed mock intents; the durable adapter contract is not built, so on the brief's own rule they should read `EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT`. |
| **§3** | prove the 30 generic-store objects are real objects | **PARTIAL.** All 56 bind and 23 of 24 lineage stages write through the canonical service; the per-object classification table (AUTHORITATIVE / TEMPORARY / PLACEHOLDER) is not written. |
| **§4** | 159 handoff contracts | **DONE — 159/159**, with acceptance, rejection, cancellation and replay proved by execution. One disclosure: no kernel rejection door. |
| **§5** | zero-persistence fixture factory | **DONE** — 24 stages, 23 create, 0 residue, 0 external effects, guards proved by execution. |
| **§6** | W05–W08 complete | **PARTIAL — W08 closes; W05, W06, W07 stop at a named step.** Failure/block evidence exists for all three; cancellation and replay evidence is per-handoff, not per-workflow. |
| **§7** | W09–W17 complete | **PARTIAL — W10, W11 close; 7 stop at a named step.** |
| **§8** | frontend / API / RLS / storage call graph and security probes | **NOT STARTED.** |
| **§9** | durable external-effect adapters in mock mode | **NOT STARTED.** |
| **§10** | 347 events reconciled | **NOT STARTED.** |
| **§11** | 1,799 per-step cases; 75 injected defects | **NOT STARTED.** The driver and the fixture factory are the harness for both, and both now work. |
| **§12** | all 30 workflows close | **14 of 30.** All 30 driven, all 30 stops named. |
| **§13** | 15 deliverables | **8 of 15** |

**Written this session:** `PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv` (30 rows, produced by driving
every workflow, not by reading a registry) and this file.

**Still owed:** `PHASE_D_HANDOFF_EVENT_RESULT.csv`, `PHASE_D_FRONTEND_API_CALL_GRAPH.csv`,
`PHASE_D_STORAGE_RLS_SECURITY_RESULT.md`, `PHASE_D_FINANCIAL_PRIVACY_RESULT.md`,
`PHASE_D_IDEMPOTENCY_CONCURRENCY_RESULT.md`, `PHASE_D_EXTERNAL_EFFECTS_RESULT.md`,
`PHASE_D_INJECTED_DEFECT_RESULT.csv`.

---

## 9. The sixteen remaining stops, so the next session does not rediscover them

| workflow | stops at | code | what it needs |
|---|---|---|---|
| W01 | W01-S03 | — | `department_objective_status_check` — the `department_mandate` write map's state vocabulary does not match the target's CHECK |
| W03, W20 | S01 | `pd_gate_refused` | GATE-021 requires `reviewer_role_id` in its evidence; the frozen step names none — same shape as GATE-026 on W26 |
| W05 | W05-S02 | `pd_rule_refused` | BR-013 — the inquiry the run created is not yet quote-ready at S02; readiness is produced later in W05 |
| W06 | W06-S02 | `pd_rule_refused` | BR-014 — `route_state` is being fed a record id, not a state |
| W07 | W07-S04 | `pd_gate_refused` | GATE-012 — the document the run created is not in a usable state |
| W09, W14, W16 | S03 / S01 / S01 | — | unique-constraint collision with the fixture; `for_workflow` exists and costs other closures, see §2 |
| W12 | W12-S01 | `pd_gate_refused` | GATE-015 duplicate dispatch — same cause |
| W13, W23, W28 | S02 / S06 / S04 | `pd_rule_refused` | BR-002 — no candidate in the frozen registry's reviewer set is independent of that step's owner |
| W15 | W15-S02 | `pd_rule_refused` | BR-019 — the comparison belongs to a different customer than the caller |
| W17 | W17-S01 | `pd_gate_refused` | GATE-020 — no recorded founder decision. **A fixture must not create one.** Every refund needs the founder, and forging that artefact is the one thing this harness may never do. |
| W26 | W26-S01 | `pd_gate_refused` | GATE-026 requires `reviewer_role_id` |

---

**PHASE_D_NOT_READY**
