# QuotesDone Phase D — builder closure

**PHASE_D_NOT_READY**

| | |
|---|---|
| session | 2026-08-18, 14:00 → 15:00 UTC (database clock) |
| project | `htdblwldjkcgjvmqkbeh` — the one project |
| branch | `feat/phase-d-d1-d3-handler-registry-and-rules` |
| commits | `fb86840` (D1+D3), `195cfb4` (D0) |
| pull request | [#446](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/446) |
| paid inference | **USD 0.00** — `llm_attempt` 0 rows, `ai_cost_log` 0 rows since the Phase D start instant |
| live external effects | **0** — see the zero-cost section, which names what the 4 notification rows in the window actually are |

Phase E was not begun. No frozen Phase A, Phase B or Phase C object was edited.

---

## Why this ends NOT_READY

Phase D's Definition of Done requires, among other things: 257/257 handlers evidenced with seven
test cases each, 30/30 deterministic workflow closures, 56/56 business objects reconciled, 54/54
rules and 32/32 gates enforced, all effective handoffs, 347/347 events classified, 100% of the 75
injected defects refused, and fifteen committed deliverables.

**Three of those are met or partly met. The rest are not started.** Declaring readiness on that
basis would be the exact defect this phase exists to remove, so the verdict is NOT_READY and the
remainder is itemised below rather than summarised away.

---

## Precondition — checked before any write

The mandatory precondition was satisfied and was verified against the **database**, not only
against the repository:

| check | result |
|---|---|
| independent Phase C acceptance | `PHASE_C_FINAL_ACCEPTANCE_PASS`, `PHASE_D_TEST_HARNESS_READY` |
| founder approval | `PCA-2026-08-18-001`, approved 2026-08-18 11:45 UTC |
| checksummed | 3 phase fingerprints + 5 repository sha256 in `phase_c_founder_approval` |
| tagged | `phase-c-founder-approved-2026-08-18` |
| frozen | 25 subjects in `phase_c_frozen_subject`; `fn_phase_c_freeze_drift()` 0 red |
| Phase A drift | **0** |
| Phase B drift | **0** |

---

## What was measured first, and it changed the design

**Every one of the 257 Phase C step bindings named a retired routine.**
`phase_c_step_binding.canonical_runtime_handler` is
`public.fn_phase_c_step_advance(bigint,text,text,jsonb)` for all 257 rows. `kernel_k13` retired
that routine; it raises, and `kernel_retired_path` records `fn_kernel_step_complete` as the
replacement. 137 of the 257 were additionally `DEFERRED_RUNTIME_IMPLEMENTATION` — nothing produced
the step's business output at all.

**`fn_phase_c_rule_check` had a real predicate for 2 of the 54 business rules.** The other 52
ended `ok := true` with a reason string claiming *"registered and enforced through the canonical
boundary"*. The frozen `fn_kernel_step_complete` is honest about the same hole in its own comments;
Phase D is where it gets closed.

**All 32 gates share one generic predicate.** `fn_phase_c_gate_evaluate` checks that an evidence
object exists and carries `evidence_ref` and `actor_role_id`, and that the actor resolves. It never
reads the gate's own declared `required_evidence`, so the 32 gates are behaviourally one gate.
*This is recorded and is not yet fixed.*

**`fn_phase_c_output_validate` ignores its contract argument.** It requires `status` and `output`
and checks truncation markers; `p_contract` appears only in the reason string. Per-step output
contracts did not exist before D1.

---

## What landed, and how each was verified

### D0 — reconciliation (partial)

`PHASE_D_CURRENT_CODE_HANDLER_CROSSWALK.csv`, **257 rows × 40 columns**, built by
`scripts/phase_d/build_d0_crosswalk.mjs` from the live registries, never from the package. The
script exits 1 rather than writing fewer than 257 rows, so a partial export cannot be mistaken for
a complete one.

| | |
|---|---|
| Phase C bindings naming a DISABLED path | **257 of 257** |
| `IMPLEMENT` (nothing produced the output) | 137 |
| `WRAP_TO_CANONICAL` | 120 |
| capability-dependent steps | 21, each carrying the matched token as evidence |
| steps opening a handoff | 159 |
| closure steps | 30 |

**The two closure counts are both right and mean different things.** `step_type = 'closure'` is
**29**, and the handler classes below follow `step_type`, so there are 29 `CLOSURE_HANDLER`
bindings. `is_closure_step` is **30**, and the crosswalk follows that. The extra one is W22-S07,
recorded in `phase_b_package_erratum` #3: W22 was the only workflow of the 30 with no
`step_type='closure'` step, so GATE-008 had no step to attach to. The erratum sets
`is_closure_step` on the step that is already final and already points at `WORKFLOW_COMPLETE`,
without changing the step, its owner, its output, or the 257 total.

One package/live disagreement is **recorded, not reconciled away**: the packaged handoff matrix
carries 161 rows and `phase_b_handoff` carries 159. The founder-approved effective baseline is the
live one.

### D0 — the two authentication cases the founder named

Both were `OUTSTANDING` in `phase_d_preflight_requirement` because the Phase C closure audit was
read-only and declined to mint a session. Its own note is the reason they were owed: *"reading a
branch is not executing it."* Both are now **executed against production**:

```
PASS  D0-AUTH-001  management@quotesdone.com          expected 2xx, got 200
      {"ok":true,"user":"management@quotesdone.com"}
PASS  D0-AUTH-002  zz-phase-d-canary@example.invalid  expected 403, got 403
      {"error":"forbidden"}
```

The founder session was minted with admin `generate_link`, which returns a link and sends no mail,
then verified for a real bearer. **No password was read, set or handled** and the founder's account
was not modified. The non-founder session used a canary auth identity under this repository's
existing fixture convention — ZZ-prefixed, at `example.invalid` — created, used for one request,
and deleted in the same run. Its removal was **proved by read-back**, not assumed from the delete
status: `DELETE 200`, then `GET 404`. No customer, supplier, inquiry or other business row was
created.

*What this does not claim:* two identity branches of one edge function, exercised with one
read-only classified action. It says nothing about per-action authorization inside the Command
Center.

### D1 — handler registry, typed contracts, one executor

- `phase_d_handler_binding` — **257 rows**, `step_id` as primary key, so ambiguous binding is
  structurally impossible rather than promised.
- `phase_d_handler_schema` — **514 typed contracts**, two per step.
- Eight family handlers matching the eight `step_type` values, which partition all 257:
  execution 58 · review 47 · decision 35 · analysis 31 · closure 29 · handoff 25 · intake 24 ·
  measurement 8.
- `fn_phase_d_handler_execute(jsonb)` — the one executor.

**Nothing is hand-typed.** Input keys are the semicolon clauses of the frozen `required_inputs`,
slugged by one fixed rule. Output keys are the kernel envelope plus the evidence obligations of the
step's family. Every schema carries the sha256 of the frozen prose it derives from, so a Phase B
text change is detectable instead of leaving the contract quietly describing a step that no longer
says that. A registry whose expected values were typed by whoever wrote the migration agrees only
with that person.

The executor **calls** the frozen `fn_kernel_step_complete`. It opens no step run, creates no task
or handoff, moves no run state and emits no event — those belong to the kernel, and a handler that
wrote them would be the parallel engine the spec forbids.

**Verified by execution, in an aborted transaction on production:**

```
W01 run 5151, step run 5195
  handler produced typed output -> schema validated -> kernel accepted
  ok=true outcome=pass step_state=completed run_state=waiting_handoff
  successor=cross_owner next=W01-S02  handoffs=1 events=1
  output_hash=de2c90585add (over the actual output, not a constant)
  rules: 15 in scope, 13 evaluated, 2 out of scope, 0 outstanding for this step
  gates: 10 in scope
rolled back by raise
```

### D3 — 34 of 54 rules stop being prose

`phase_d_rule_enforcement` names, for all 54, **how** each is enforced and **when** it applies.

| enforcement kind | count | status |
|---|---|---|
| PREDICATE — decided from the call context | 15 | ENFORCED |
| KERNEL_ENFORCED — the frozen kernel raises | 9 | ENFORCED |
| TRIGGER_ENFORCED — refused at write time | 5 | ENFORCED |
| SCHEMA_ENFORCED — the output schema requires the key | 3 | ENFORCED |
| CONTEXT_REQUIRED — absent fact is a refusal | 1 | ENFORCED |
| EXECUTOR_ENFORCED — capability fails closed | 1 | ENFORCED |
| **PENDING_OBJECT_MAP** | **20** | **OUTSTANDING** |

The board **resolves every named enforcement point in the live catalogue** — a disposition in prose
with no mechanism is the failure mode this is built against. An unregistered rule is now
**refused**, which is the exact inversion of the routine it replaces.

The 20 outstanding rules report `enforced = false` to every caller and are ratcheted in
`kernel-boards.json` with their ids and an instruction to **delete the entry at 0, not lower it and
leave it**. They are: BR-011, 012, 013, 014, 015, 017, 018, 019, 020, 025, 026, 029, 032, 033, 034,
035, 036, 039, 041, 049.

---

## Defects found in my own work before it shipped

| defect | why it mattered |
|---|---|
| **Scope treated as applicability** | BR-002 refused an intake step for a creator/reviewer collision that cannot exist. Only 28 of 257 steps name a reviewer, and `fn_kernel_reviewer_independent` returns false for a NULL one. **Caught by execution, not by review.** |
| **BR-043 fired on every step** | Demanding an authority reference for a policy exception nobody proposed is a condition that cannot *not* fire. |
| **Review handler returned `approved`** | It would have made all 28 review steps a rubber stamp. The verdict is the caller's; an absent one fails the schema. |
| **Measurement denominator defaulted** | `least(100, NULL)` in another costume. Nothing defaults now, and a zero denominator raises. |
| **My board named a retired routine** | `fn_kernel_retired_path_state` finds callers by scanning bodies, and `pg_get_functiondef` returns comments as well as code. Writing the name — first in a string literal, then again in the comment explaining the first fix — made the board count as an active caller of the path it was checking nobody called. `0 → 1 of 2`, twice. It now resolves retired paths from `kernel_retired_path` and the name appears nowhere in the body. |
| **A row added without its artefact** | The three migrations were applied to production but not listed in `scripts/sql/MANIFEST.txt`, which is what the canonical routine engine compares the live estate against. The suite went 2 failures → 4. Fixed by registering the files and re-emitting the CSV from the engine. |
| **Three constraints read as uncommitted DDL while fully declared** | The engine derives an auto-generated constraint name only when `check (` or `references` sits on the *same source line* as its column, and three of mine were wrapped for readability. The instrument is not wrong — a wrapped clause is genuinely harder to attribute — so each is now named explicitly with the identity Postgres itself generated, rather than the check being taught to accept a shape it cannot attribute. |
| **The committed schema mirror was behind** | `supabase/schema/full_schema.sql` said 550 tables; production holds 553. Regenerated with `export_from_either_source_is_identical.mjs --write`. |

---

## Zero cost and zero external effect

| | |
|---|---|
| OpenRouter HTTP requests | **0** |
| other paid AI requests | **0** |
| `llm_attempt` rows since Phase D start | **0** |
| `ai_cost_log` rows since Phase D start | **0** |
| paid inference cost | **USD 0.00** |
| paid-provider gate | `allowed=false`, 8 of 8 routes held to 2126-08-15 |
| live email / SMS / WhatsApp / social / payment / refund | **0** |
| `phase_c_refund_decision` rows | 0 |
| persistent demo customers or suppliers created | **0** |

**The 4 notification rows in the window, named precisely rather than waved past:** ids 1944–1947,
all `to_email = management@quotesdone.com` — the founder's own admin address — produced by the
pre-existing read-only monitoring crons that remain active under the selective hold
(`founder_brief` 04:30, `health_alert` 08:00 and 14:30, `smoke_alert` 08:00). All four have
`sent_at = NULL` and `attempts = 0`: **none was delivered**, and none originated from Phase D work.

**Nothing was left behind.** `phase_c_workflow_run` rows matching the probe namespace: **0**.
`auth.users` matching the canary: **0**. Every write probe ended in `raise exception`.

---

## Two pre-existing suite failures, measured but deliberately not "fixed"

Both were red **before** any Phase D work and both live in
`scripts/checks/v3_runtime_behaviour.test.mjs`. Neither is in Phase D's scope. They are recorded
here with what I actually measured, because retyping either literal would be a rubber stamp.

**1. `every packaged department resolves to a live runtime department` — expected 24, got 33.**

Measured on production: `org_department_alias` holds **34 rows**, **33 distinct
`packaged_department` names**, resolving onto the **10 active departments**, and — the part that
matters — **`dangling = 0`**. Every alias points at an active department, which is the invariant
the test's own name describes and it holds.

The `24` is a count typed at V3 delivery time. The alias table has since grown as packaged
department names were merged into the ten live ones, so the number moved for a legitimate reason.
**Changing 24 to 33 would make the check agree with whatever is currently there**, which is the
same defect as the rule scorer this phase just removed. The honest fix is to assert that the set
of packaged names the delivery shipped is still fully covered, measured against a committed
delivery artefact rather than an integer — that artefact was not located in this session, so the
check is left red and the reason is recorded here.

**2. `a decided agent action writes a decision trace naming those records` — `traces=1 ids=<NULL>`.**

A trace exists but carries no record ids. Not investigated; out of Phase D scope and unchanged by
this work.

**3. One `fn_os_portals_gates()` gate reads `not_met` while its own evidence describes a pass.**

Noticed during the end-of-session sweep, not caused by this work, and not in Phase D scope.
21 of 22 gates are `met`. The exception is *"Monitoring and alerts configured"*, whose recorded
evidence is:

> 23 active cron jobs; `watch_failed_runs_hourly` is scheduled and last succeeded inside 3 hours;
> 0 cron run(s) failed in the last 24 hours

Every clause of that evidence describes a healthy monitoring estate, and the verdict is still
`not_met`. That is the "instrument reporting on the wrong subject" shape: either the verdict
predicate is reading something the evidence string does not name, or the evidence is assembled
from a different query than the verdict. **Recorded, not touched** — deciding which of the two it
is needs a look at the routine, and a gate that flips to `met` without that is a gate nobody
checked.

## Estate state at close

| check | result |
|---|---|
| Phase A baseline drift | **0** |
| Phase B baseline drift | **0** |
| `fn_phase_c_freeze_drift()` | **0 red** |
| `fn_phase_c_invariants()` | **0 red** |
| `fn_phase_d_handler_state()` | **6/6 green** |
| `fn_phase_d_rule_state()` | 3/4 — the fourth red **by disclosure** |
| `kernel_boards_are_green.test.mjs` | **7/7 pass** |
| kernel boards red | 8, all ratcheted with an owner and a reason |
| `canonical_routines.test.mjs` | **11 passed, 0 findings** |
| `application_source_of_truth.test.mjs` | **7 gates, 0 findings** |
| schema mirror vs live export | **byte-identical**, 67354 lines |
| `fn_os_portals_gates()` | 21 of 22 met — the exception is item 3 above, pre-existing |
| full suite | **302 tests, 300 pass, 2 fail** — the same two that were red before Phase D began |

**Phase D added zero test failures.** The suite ended exactly where it started.

---

## What is NOT done — the itemised remainder

This is the whole of the outstanding Phase D scope. Nothing below was started unless stated.

| wave | scope | state |
|---|---|---|
| **D2** | 56 business objects: canonical table, read/write service, ownership/RLS, versioning, mutation guard, retention, safe/raw representation, compensation | **not started.** Naive name matching resolves only 8 of 56 to a table — the estate's 553 tables do not share the registry's vocabulary, so this needs real mapping. **This is the blocking dependency for the 20 outstanding rules.** |
| **D3 (rest)** | 32 gates each need a real predicate reading their own `required_evidence`; today all 32 share one generic check | **not started** |
| **D4** | 159 effective handoffs: packet schema, acceptance, SLA, rejection, return owner | **not started** (the kernel already creates and validates handoff runs; the per-handoff contract does not exist) |
| **D5** | frontend → API → service → database call graph; storage MIME/magic-byte/quarantine; RLS proofs | **not started** |
| **D6** | external effect adapters, all mock/disabled | **not started** (effects are held, but the durable adapter contract is not built) |
| **D7** | finance/legal/privacy contracts for W08, W10, W15, W16, W17, W27, W28 | **not started** |
| **D8** | per-handler idempotency, lock, retry class, compensation, cancellation tests | **partial** — the kernel supplies idempotency and locking and this was exercised once; no per-handler test matrix |
| **D9** | capability boundary | **partial** — 21 steps classified, typed request and fail-closed behaviour implemented and enforced in the executor; no mock fixture library |
| **D11** | 257 × 7 = 1,799 per-step tests; 30 × 4 workflow tests; the 75-row injected defect catalogue | **not started.** One end-to-end execution proof exists (W01-S01). |
| **D12** | 347 events reconciled with real producer/consumer/outbox/trace | **not started** |
| **D13** | 30/30 deterministic workflow closure | **not started.** One workflow was driven one step. |
| **D14** | 15 required deliverables | **4 of 15** |

**Written:** `PHASE_D_CURRENT_CODE_HANDLER_CROSSWALK.csv`, `PHASE_D_ZERO_COST_EVIDENCE.md`,
`PHASE_D_PRODUCTION_DEPLOYMENT_LEDGER.md`, and this file.

**Still owed:** `PHASE_D_HANDLER_IMPLEMENTATION_RESULT.csv`,
`PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv`, `PHASE_D_BUSINESS_OBJECT_RESULT.csv`,
`PHASE_D_RULE_GATE_RESULT.csv`, `PHASE_D_HANDOFF_EVENT_RESULT.csv`,
`PHASE_D_FRONTEND_API_CALL_GRAPH.csv`, `PHASE_D_STORAGE_RLS_SECURITY_RESULT.md`,
`PHASE_D_FINANCIAL_PRIVACY_RESULT.md`, `PHASE_D_IDEMPOTENCY_CONCURRENCY_RESULT.md`,
`PHASE_D_EXTERNAL_EFFECTS_RESULT.md`, `PHASE_D_INJECTED_DEFECT_RESULT.csv`.

---

## Recommended next increment

**D2, and specifically the object→table map**, because it is the single dependency holding 20 of
the 54 business rules in `OUTSTANDING` — including BR-020, *reveal only after payment is
reconciled*, which is the highest-value unenforced rule in the estate. Once each object resolves to
a canonical table with a read/write service, those 20 rules become decidable predicates and the
rule board can go green honestly rather than by ratchet.

---

**PHASE_D_NOT_READY**
