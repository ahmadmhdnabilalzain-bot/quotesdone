# QuotesDone Phase D — builder closure, session 3 (D7 + D8)

**PHASE_D_NOT_READY**

| | |
|---|---|
| session | 2026-08-18, 17:49 → 20:0x UTC (database clock) |
| project | `htdblwldjkcgjvmqkbeh` — the one project |
| branch | `feat/phase-d-d7-every-handler-produces-an-effect` |
| commit | `d813e2c` |
| pull request | [#448](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/448) |
| baseline in | `e896ef5` (main == origin/main, working tree clean of tracked changes) |
| paid inference | **USD 0.00** — 0 OpenRouter requests, 0 `llm_attempt` rows, 0 `ai_cost_log` rows |
| live external effects | **0** — nothing sent, published, charged or refunded |

Phase E was not begun. No frozen Phase A, Phase B or Phase C object was edited. Business automation
was not reactivated: 23 cron jobs active at the start of the session, 23 at the end.

---

## 0. Source and deployment precheck

| check | result |
|---|---|
| branch at start | `main`, HEAD `e896ef5`, identical to `origin/main` |
| Phase D PRs merged before this session | #446 (D0/D1/D3), #447 (D2/D4/D5) |
| repository → production drift | schema export **byte-identical**, 68,879 lines, 0 project refs embedded |
| production → repository drift | 0 — every routine this session deployed was read back and matched the file |
| working tree | 11 untracked Phase C/D session artefacts from earlier sessions, none staged |
| Phase A baseline drift | **0** |
| Phase B baseline drift | **0** |
| `fn_phase_c_freeze_drift()` | **0 red**, 25 of 25 frozen subjects intact |
| production ahead of main | **no** — production-direct deploys land on the branch in the same session and merge through the PR |

`scripts/checks/sql_files_match_live.test.mjs` no longer exists; the file is
`sql_files_match_live.RETIRED.mjs`. `export_from_either_source_is_identical.mjs` is the live
equivalent and was run.

---

## 1. The handoff denominator, reconciled — §2 of the brief

The brief required this before any handoff work, and set a hard stop if the difference is not
founder-approved. **It is approved, and the stop does not apply.**

| | |
|---|---|
| source Phase B package handoffs | **161** (`frozen_reference/PHASE_B_HANDOFF_REGISTRY_SOURCE_PACKAGE.csv`, 161 distinct ids) |
| live effective handoffs | **159** (`public.phase_b_handoff`) |
| exact difference | **`H-W14-04-05`** and **`H-W14-05-06`** — both in W14, both absent from live |

| field | value |
|---|---|
| workflow | W14 — Quotation Submission and Evaluation |
| source package definition | two handoffs bridging W14-S04 → W14-S05 → W14-S06 |
| live effective definition | deleted; W14-S04 → W14-S05 → W14-S06 is now a single-owner sequence |
| reason | W14-S05's accountability moved from the `relevant_category_overlay` placeholder to the canonical role `quote_evaluation`, which already owns the other eight W14 steps. **Both ends of both handoffs became the same role**, and a handoff from a role to itself is not a handoff. |
| change-request ID | **PBCR-001**, founder reference `PHASE_B_CR_W14_S05_ACCOUNTABILITY` |
| founder-approval status | **APPROVED** — `phase_b_change_request.founder_approved_by` records the founder (management@doratajewelries.com), brief of 2026-08-17, quoted verbatim; `founder_approved_at` 2026-08-17 00:06 UTC |
| affected steps and roles | W14-S05 only. GAINS: `quote_evaluation`. LOSES: `relevant_category_overlay`, which was accountable on exactly one step of 257 and becomes a required technical contributor. No canonical role created, renamed, retired or re-departmented. |
| effect on the baseline | `org_phase_baseline` where phase = 'B' records `counts.handoffs = 159` and `cross_department_handoffs = 45`; `fn_phase_b_baseline_drift()` returns **0 rows** against those numbers |

**Unexplained handoff differences: 0. Phase B drift: 0. The effective denominator is 159 and it is
founder-approved.**

One artefact is stale and is recorded rather than edited:
`docs/phase-b/PHASE_B_FOUNDER_APPROVED_BASELINE.md` still says 161 handoffs with a
`handoff_registry` digest over 161 rows. It is the **pre-amendment** document — the original
2026-08-15 architecture approval — and PBCR-001 was applied on 2026-08-17. The database note on the
baseline row states the amendment in full. Correcting the document is a paperwork task, not a
Phase B change, and it is listed in the remainder below rather than done quietly here.

---

## 2. Correct Phase D status semantics — §1 of the brief

The brief was right that `NEW_DETERMINISTIC_HANDLER` on 236 of 257 bindings was overstating.
`implementation_depth` now answers a different question beside it, and the final status vocabulary
is unchanged.

**`public.phase_d_step_effect`, 257 rows.** Every field the brief names, per step: expected effect
type, effect object, effect service, actual caller, result reference, trace reference, completion
condition — plus the expected state transition and how the object was anchored.

| expected effect type | steps |
|---|---:|
| DOMAIN_MUTATION | 67 |
| VERSIONED_ARTIFACT | 58 |
| KERNEL_ONLY_TRANSITION | 51 |
| REVIEW_VERDICT | 41 |
| CAPABILITY_REQUEST | 21 |
| EXTERNAL_EFFECT_INTENT | 12 |
| MEASUREMENT_RECORD | 7 |
| **total** | **257** |

| implementation_depth | steps |
|---|---:|
| BUSINESS_EFFECT_CONNECTED | 224 |
| CAPABILITY_BOUNDARY_READY | 21 |
| EXTERNAL_ADAPTER_READY_DISABLED | 12 |

| required | result |
|---|---|
| steps with no expected effect type | **0** |
| steps falsely called implemented while schema-only | **0** — `SCHEMA_ONLY` and `VALIDATION_ONLY` are in the vocabulary and no step carries either, because every step's effect path now exists and is called |
| steps with no persistent or kernel-verifiable effect | **0** by declaration; **257** by *execution*, and that is the honest gap — see §6 |

**Nothing was forced.** A closure step's declared effect is the run reaching a frozen terminal state
(`KERNEL_ONLY_TRANSITION`, kernel-verifiable, no invented row). A measurement step's effect is a
number with a real denominator. A capability step's effect is a refusal. Inventing a domain row for
any of the three is exactly what the brief warned against.

### How each object was anchored, and why that column exists

`business_object_writes` was **empty on all 257 bindings** since D1 — and empty in the packaged
`PHASE_D_STEP_HANDLER_IMPLEMENTATION_MATRIX.csv` too, which carries the column with 0 of 257 rows
populated. Nothing anywhere said which object a step writes, so it is derived, and the derivation is
recorded per row rather than trusted.

| anchoring rule | steps |
|---|---:|
| WORKFLOW_PRIMARY_OBJECT | 74 |
| NO_DOMAIN_OBJECT (kernel-only or capability) | 72 |
| SOLE_OBJECT_OF_WORKFLOW | 60 |
| MATCHED_STEP_TEXT (object_id appears as a phrase) | 33 |
| MATCHED_ALL_TOKENS (every word of the object_id appears) | 18 |

---

## 3. The 56 business objects, and the writers they now have

| | |
|---|---|
| objects reconciled | **56 / 56** |
| objects with no authoritative read service | **0** |
| mutable objects with no authoritative write/version service | **0** |
| objects with no owning workflow/role | **0** |
| append-only objects updateable/deletable | **0** — the D2 policy guard is attached and the board proves it |
| null/no-row write treated as success | **0** — every write path asserts the returned key and refuses `pd_object_write_produced_nothing` |

**30** objects live in the Phase D store through `fn_phase_d_object_write` (unchanged from D2).
**22** existing-table objects gained a **declared, validated column map**: every mapped column must
exist, and every column the target *requires* — NOT NULL, no default, **not an identity column** —
must be covered, checked against `information_schema` at apply time. A map that would fail at runtime
cannot deploy, and the validator proved that by refusing the first version of this file over a column
`public.department_objective` does not have.

**4 objects are refused by name.** `workflow_run`, `workflow_step_run` and `handoff_record` are
written by `fn_kernel_step_complete`; `review_record` is the one `governing_workflow_id = 'ALL'`
object a handler may write, and it does. Two creators for one object is the defect that deadlocked
16 of 30 workflows.

**Identity columns were the trap.** `information_schema` reports a `GENERATED ALWAYS` identity column
as NOT NULL with a null default, which reads as "you must supply this" and is the opposite of the
truth. Seven of the 22 targets have one. A naive required-set would have demanded a value Postgres
refuses.

---

## 4. Every handler is connected to a business effect

`fn_phase_d_effect_produce(jsonb)` is the one effect service. `fn_phase_d_handler_execute` calls it
**before** handing to the frozen kernel, so the output the kernel stores carries the effect
reference; both sit in one transaction, so a kernel refusal rolls the effect back with it.

- **Idempotency is a constraint, not a convention.** `UNIQUE (step_run_id, effect_type)` on
  `phase_d_effect_ledger`. A replayed handler reads the existing row back and produces no second
  effect, and what a duplicate-effect test asserts on is the **row count**, not the result payload.
- **Handlers performing direct workflow/task/outbox writes outside the kernel: 0.** The executor
  still opens no step run, creates no task or handoff, moves no run state and emits no event.
- Every step binding now names: service called, operation, object read, object written, expected
  state transition, and result reference.

`business_write_wired` is **257 / 257**, measured from the live executor body and the step's own
declared effect — not declared. The ratchet entry `handlers_not_writing_a_business_object` is
**deleted at 0**, which is what its own text instructed.

---

## 5. Proved by execution, in an aborted transaction, on production

`fn_phase_d_drive_workflow` opens the run through the kernel, lets the **kernel** choose each next
step, executes each through the real executor, and reports every refusal with its machine code.

### W04 — Customer registration and onboarding: **deterministic closure**

```
steps 7/7   effects 7   run_state completed   terminal true

W04-S01  INTAKE_HANDLER      DOMAIN_MUTATION         public.customers  id=…e62791803d8e  created
W04-S02  REVIEW_HANDLER      REVIEW_VERDICT          public.review_chain id=2595
W04-S03  EXECUTION_HANDLER   DOMAIN_MUTATION         public.customers  id=…e62791803d8e  moved
W04-S04  EXECUTION_HANDLER   DOMAIN_MUTATION         public.customers  id=…e62791803d8e  moved
W04-S05  DECISION_HANDLER    DOMAIN_MUTATION         public.customers  id=…e62791803d8e  moved
W04-S06  HANDOFF_HANDLER     KERNEL_ONLY_TRANSITION  step_run 6588
W04-S07  CLOSURE_HANDLER     KERNEL_ONLY_TRANSITION  step_run 6589

customers 0 -> 1     review_chain 1904 -> 1905     effect ledger 0 -> 7
everything rolled back by raise; 0 rows survive
```

**One account, created once and moved four times — not four accounts.** That distinction is the
finding, not the closure: an earlier iteration produced `customers 0 -> 4` and the ledger counted
all four as successful effects. It is recorded in §6.

The chain proved end to end: kernel opens the run → executor validates typed input → 16 rules
evaluated for scope and applicability → gates evaluated against their own declared evidence →
capability and provider boundaries checked → family handler produces typed output → output schema
validates it → **effect service writes the business object** → frozen kernel completes the step,
moves the run and chooses the successor → closure step reaches a frozen terminal state.

**1 of 30 workflows reaches deterministic closure.** The other 29 are not claimed.

### Idempotent replay, asserted on the row count and not on the payload

```
first  call   replay=true  effect_id=42
second call   replay=true  effect_id=42
same result_reference                          yes
ledger rows for this step run                  1     <- a second effect would be 2
business rows written by the second call       0
```

The second call returns the stored first result and produces nothing. **The assertion is the ledger
row count**, because a replay that returned a fresh success while quietly writing a second business
row is the duplicate-effect defect this exists to prevent, and the result payload cannot tell the
two apart. The guarantee is a `UNIQUE (step_run_id, effect_type)` constraint, not a convention, and
the board counts duplicates anyway — a check that trusts a constraint it never reads is a check
nobody ran.

---

### The other workflows, driven and measured rather than assumed

Seven more workflows were driven with the same fixture harness. **None of the seven stops on a
defect in the implementation**, and each stop is named precisely so the next session does not have
to rediscover it.

| workflow | steps | effects | stopped at | why |
|---|---|---|---|---|
| W01 | 1 of 8 | 1 | after S01, run `waiting_handoff` | the kernel opens no successor step run until the handoff is **accepted**; the driver does not call `fn_kernel_handoff_accept` |
| W02 | 1 of 9 | 1 | after S01, run `waiting_review` | same shape: the run waits on a review decision the driver does not record at the run level |
| W03 | 1 of 9 | 0 | W03-S01, `pd_gate_refused` | GATE-021 requires `reviewer_role_id`; the frozen step names none and the fixture generator correctly refuses to invent an identity |
| W05 | 1 of 9 | 0 | W05-S01, `pd_rule_refused` | BR-013: *"no inquiry_id named; readiness cannot be measured against nothing"* — a foreign key a fixture must not invent |
| W06 | 1 of 7 | 0 | W06-S01, `pd_rule_refused` | BR-013, same |
| W07 | 1 of 8 | 0 | W07-S01, `pd_rule_refused` | BR-013, same |
| W08 | 1 of 8 | 0 | W08-S01, `pd_gate_refused` | GATE-013: the safe package's approver and the actor resolve to one identity, because the fixture gave both the same string. **The gate is correct** — that is a creator/reviewer collision. |

**Two distinct classes of remaining work fall out of this, and they are different jobs:**

1. **W01 and W02 need the handoff acceptance path.** A run in `waiting_handoff` or
   `waiting_review` has no open step run, so the driver's loop ends and reports a partial drive
   rather than a failure. This is D8's handoff-contract scope — acceptance criteria, rejection
   reason, return owner — and it is the single change that would take several workflows much
   further. It is not a defect; it is the kernel correctly declining to advance a run whose handoff
   nobody has accepted.

2. **W03, W05–W08 need real parent data**, built inside the same aborted transaction, in the order
   reality produces it. `public.customers` and `public.transactions` both hold **0 rows** since the
   16 August purge, so every gate and rule that reads business data refuses for absence of a parent.
   Inventing one would either violate the constraint or, worse, pass by pointing at somebody's real
   row.

**1 of 30 workflows reaches deterministic closure. 8 of 30 have been driven at all.** Nothing is
claimed about the remaining 22.

---

## 6. Defects found in my own work, every one by execution or by its own board

| defect | detail |
|---|---|
| **A check that was wrong twice, the same way** | `effect_services_that_do_not_resolve` reported 257 of 257 in D7 and **still** 257 of 257 after D7b "fixed" it. `pg_get_function_identity_arguments` includes the parameter name; `oid::regprocedure` omits the schema whenever it is on `search_path`, and every routine here sets one. Both predicates were written from what the rendering was *assumed* to produce. The third attempt measured both renderings against the database first. |
| **The lexicon matched nouns, and one was the payment ladder** | `provider` in *"Apply only an allowed transaction-state transition using the provider event"* classified **W16-S04** — the subject of BR-020 and the most important domain write in the estate — as a mock external intent that writes nothing. `dispatch` did the same to W08-S06 and W12-S06; `charge` to W16-S01. 29 external intents became **12**, each read against its own frozen `required_action`. |
| **A gate that could not NOT fire** | GATE-006 refused **all 55** steps whose `success_workflow_state` equals the state the run is already in, because the frozen model holds **0** self-transitions among its 35. *No transition* is not *an undeclared transition*. Four positive controls now run at deploy time — and the first one caught its own author asserting `active -> completed` is undeclared when it is. |
| **A fixture that overwrote the identity under test** | GATE-002 declares `actor_role_id` as its evidence, so the fixture generator produced `ZZ DEMO — actor_role_id`; the executor merges caller context last, so that replaced the real accountable owner and BR-004 refused it as non-canonical. The harness was answering its own question. |
| **A fixture that named an undeclared state** | `ZZ DEMO — from_state` is a fine fixture for an opaque reference and nonsense for a value checked against a model. Keys whose value is a member of a declared set now take their value from that set. |
| **Two customer rows for one onboarding** | The driver's business key carried the step id, so W04-S03 inserted instead of moving W04-S01's row. Keys are now one per `(run, object)`. Had this shipped, the ledger would have counted both as successful effects. |
| **A constraint altered after the rows that need it** | The widened `object_resolution` vocabulary was added *below* the insert that used it, and refused its own insert. |

**Two pre-existing grants revoked.** `fn_phase_d_rule_check` and `fn_phase_d_gate_applies` were
executable by `anon`. Neither is SECURITY DEFINER so neither escalates privilege, but both read the
frozen registries and would answer an unauthenticated caller about the estate's rule and gate
structure. `revoke … from anon` is a silent no-op when the grant is held through PUBLIC, so PUBLIC
was the target and the intended roles were re-granted explicitly.

---

## 7. Zero cost and zero external effect

| | |
|---|---|
| OpenRouter HTTP requests | **0** |
| other paid inference requests | **0** |
| `llm_attempt` rows this session | **0** |
| `ai_cost_log` rows this session | **0** |
| paid inference cost | **USD 0.00** |
| live email / SMS / WhatsApp / social / payment / refund | **0** |
| Apify runs | **0** |
| production Dropbox writes | **0** |
| fallback provider key | **0** |
| active cron jobs, start → end | **23 → 23** |
| persistent business rows created | **0** — every probe ended in `raise exception` |

**`public.notifications` is not written by any Phase D path, and that is now a board check.** Three
outbound senders read that table — `email_cron_2min`, `sms_flush`, `wa_flush` — and all three are
currently inactive. *Currently* is not a guarantee: a row written with status `pending` becomes a
live send the moment one is re-enabled. So every notification effect is `EXTERNAL_EFFECT_INTENT`
recorded in the Phase D ledger with `provider_mode = 'mock'`, `provider_mode` has **no `'live'`
value** to set, and `phase_d_write_maps_into_the_outbound_notification_table` goes red if a later
increment maps anything onto it.

---

## 8. Estate state at close

| check | result |
|---|---|
| Phase A baseline drift | **0** |
| Phase B baseline drift | **0** |
| `fn_phase_c_freeze_drift()` | **0 red** |
| `fn_phase_d_handler_state()` | **6/6 green** — including `handlers_not_writing_a_business_object` at 0 |
| `fn_phase_d_object_state()` | **7/7 green** |
| `fn_phase_d_rule_state()` | **4/4 green** |
| `fn_phase_d_gate_state()` | **5/5 green** |
| `fn_phase_d_effect_state()` | **14 of 15** — the fifteenth is the new disclosure ratchet |
| `kernel_boards_are_green.test.mjs` | **7/7 pass** — 28 boards, 345 checks, 8 red, every one owned |
| schema mirror vs live export | **byte-identical**, 69,815 lines |
| `canonical_routines.test.mjs` | **11 passed, 0 findings** — 0 drift in both directions |
| `fn_os_portals_gates()` | **22 of 23 met** — the exception is *Monitoring and alerts configured*, red before this session and out of Phase D scope |

---

## 9. What is NOT done — the itemised remainder

| wave | scope | state |
|---|---|---|
| **D7 effect contracts** | 257 declared effects, seven types, eight depths | **DONE this session.** |
| **D7 object writers** | 22 validated write maps + the 30-object store | **DONE this session.** 4 kernel-owned objects refused by name. |
| **D8 execution proof** | handlers producing real effects through the real path | **PARTIAL — W04 closes, 7 of 7 steps, 7 effects.** 250 steps have the path and have not been driven. |
| **D8 handoff contracts** | 159 effective handoffs: packet schema, acceptance, SLA, rejection, return owner, accountability transfer | **not started.** The denominator is now reconciled and approved, which was the blocker. |
| **D9** | frontend → API → service → database call graph; storage MIME/magic-byte/quarantine; RLS proofs | **not started** |
| **D10** | external effect adapters (Resend, SMS/WhatsApp, social, Stripe, storage, Apify), all mock | **PARTIAL** — 12 steps classified `EXTERNAL_ADAPTER_READY_DISABLED` with a typed mock intent record; the durable per-provider adapter contract (attempt, retry, dead-letter, reconciliation) is not built |
| **D11** | 257 × 7 per-step cases; 30 × 4 workflow cases; the 75-row injected defect catalogue | **not started.** The driver exists and is the harness for all of it. |
| **D12** | 347 events reconciled with real producer/consumer/outbox/trace | **not started** |
| **D13** | 30/30 deterministic workflow closure | **1 of 30 closed, 8 of 30 driven.** W04 closes deterministically. W01/W02 stop on an unaccepted handoff; W03, W05–W08 stop for want of real parent data. Neither class is a defect and both are named in §5. |
| **D14** | 15 required deliverables | **7 of 15** |

**Written this session:** `PHASE_D_HANDLER_IMPLEMENTATION_RESULT.csv` (257 rows × 43 columns) and
this file.

**Still owed:** `PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv`, `PHASE_D_HANDOFF_EVENT_RESULT.csv`,
`PHASE_D_FRONTEND_API_CALL_GRAPH.csv`, `PHASE_D_STORAGE_RLS_SECURITY_RESULT.md`,
`PHASE_D_FINANCIAL_PRIVACY_RESULT.md`, `PHASE_D_IDEMPOTENCY_CONCURRENCY_RESULT.md`,
`PHASE_D_EXTERNAL_EFFECTS_RESULT.md`, `PHASE_D_INJECTED_DEFECT_RESULT.csv`.

---

## 10. Three measurements the next session should not have to rediscover

**45 of the 47 review steps name no independent reviewer in the frozen registry.** Only 2 do. The
reviewer is therefore a **runtime fact**, not a registry fact, for all but two review steps: the
kernel is right to refuse without one (`fn_kernel_reviewer_independent(owner, NULL)` is false), and
the caller must name it. The driver takes it from the caller and **never picks one** — a driver that
chose a reviewer would be `fn_pick_reviewer` returning the department head 182 times, one layer up.

**A step that names a reviewer needs a recorded verdict before it can complete.** The frozen kernel
refuses with `k3_reviewer_verdict_missing` and names the routine to call. The driver now records the
verdict through `fn_kernel_review_decide` on the open task, using the reviewer **Phase B declares** —
and `fn_kernel_review_decide` independently re-checks the offered reviewer against that same frozen
registry, so the driver cannot smuggle one past the freeze. The verdict itself is still the caller's.

**`public.customers` holds 0 rows and `public.transactions` holds 0 rows.** The marketplace funnel
was purged on 16 Aug 2026. Any gate that reads real business data — GATE-011 inquiry quote-ready,
GATE-014 supplier approved, GATE-017 quote fields, GATE-018 comparison ownership, GATE-019 reveal
permitted, GATE-020 refund decided — will refuse for absence of a parent, not for a defect. Those
steps need caller-supplied `parent_refs` built inside the same aborted transaction, in the order
reality produces them.

---

**PHASE_D_NOT_READY**
