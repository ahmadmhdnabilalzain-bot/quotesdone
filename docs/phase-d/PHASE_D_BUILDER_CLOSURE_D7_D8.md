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
was not reactivated: 24 cron jobs active at the start of the session, 24 at the end.

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

```
W04 — Customer registration and onboarding

W04-S01  INTAKE_HANDLER     DOMAIN_MUTATION   public.customers:id=8da8bdfa-…    effect 3
W04-S02  REVIEW_HANDLER     REVIEW_VERDICT    public.review_chain:id=2588       effect 4
W04-S03  EXECUTION_HANDLER  DOMAIN_MUTATION   refused: pd_object_no_state_change

customers 0 -> 1     review_chain 1904 -> 1905     effect ledger 0 -> 2
everything rolled back by raise; 0 rows survive
```

Three handlers produced a business effect through the real canonical path. That is the thing this
increment exists to make possible, and it is now measured rather than described.

`pd_object_no_state_change` at S03 is **my own guard firing correctly**: the fixture payload for the
verification step is identical to the intake step's, so the UPSERT found the row and moved no
column. A write that changes nothing is not a state transition. A real S03 moves
`email_verified`/`phone_verified`; the fixture generator does not yet vary state per step, and that
is fixture work, not a defect in the step.

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
| active cron jobs, start → end | **24 → 24** |
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
| schema mirror vs live export | **byte-identical**, 69,703 lines |

---

## 9. What is NOT done — the itemised remainder

| wave | scope | state |
|---|---|---|
| **D7 effect contracts** | 257 declared effects, seven types, eight depths | **DONE this session.** |
| **D7 object writers** | 22 validated write maps + the 30-object store | **DONE this session.** 4 kernel-owned objects refused by name. |
| **D8 execution proof** | handlers producing real effects through the real path | **PARTIAL — 3 steps of W04 proved by execution.** 254 steps have the path and have not been driven. |
| **D8 handoff contracts** | 159 effective handoffs: packet schema, acceptance, SLA, rejection, return owner, accountability transfer | **not started.** The denominator is now reconciled and approved, which was the blocker. |
| **D9** | frontend → API → service → database call graph; storage MIME/magic-byte/quarantine; RLS proofs | **not started** |
| **D10** | external effect adapters (Resend, SMS/WhatsApp, social, Stripe, storage, Apify), all mock | **PARTIAL** — 12 steps classified `EXTERNAL_ADAPTER_READY_DISABLED` with a typed mock intent record; the durable per-provider adapter contract (attempt, retry, dead-letter, reconciliation) is not built |
| **D11** | 257 × 7 per-step cases; 30 × 4 workflow cases; the 75-row injected defect catalogue | **not started.** The driver exists and is the harness for all of it. |
| **D12** | 347 events reconciled with real producer/consumer/outbox/trace | **not started** |
| **D13** | 30/30 deterministic workflow closure | **not started.** W04 reached step 3 of 7. |
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

**A step that names a reviewer needs a recorded verdict before it can complete.** W04-S04 refused
with `k3_reviewer_verdict_missing` from the frozen kernel: *"no approved, independent verdict from
that role exists on task 8409. Record it with `fn_kernel_review_decide` first."* Driving any workflow
past such a step requires calling `fn_kernel_review_decide` in the same transaction. The driver does
not yet do this, and it is the next thing that unblocks W04 → closure.

**`public.customers` holds 0 rows and `public.transactions` holds 0 rows.** The marketplace funnel
was purged on 16 Aug 2026. Any gate that reads real business data — GATE-011 inquiry quote-ready,
GATE-014 supplier approved, GATE-017 quote fields, GATE-018 comparison ownership, GATE-019 reveal
permitted, GATE-020 refund decided — will refuse for absence of a parent, not for a defect. Those
steps need caller-supplied `parent_refs` built inside the same aborted transaction, in the order
reality produces them.

---

**PHASE_D_NOT_READY**
