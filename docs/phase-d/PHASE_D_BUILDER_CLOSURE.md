# QuotesDone Phase D — builder closure

**PHASE_D_NOT_READY**

## What that verdict rests on — every figure below re-measured 2026-08-20

The body of this document reads as a series of DONEs. Most of them are now true. The verdict is
still NOT_READY, and this section is what reconciles the two: it names what is built and measured,
and then what is open. It does not decide the verdict — no independent acceptance has been re-run
since this file was written, so NOT_READY stands until one is.

**Built, and measured on production today.** 257/257 handler bindings and 514 typed contracts;
`fn_phase_d_handler_state()` **7/7 green**, with `handlers_not_writing_a_business_object = 0`.
All **54 of 54** business rules carry a live enforcement mechanism — `fn_phase_d_rule_state()`
**4/4 green**, `rules_with_outstanding_enforcement = 0`. 56/56 business objects bound, 32/32 gates
predicated. **159** handoff contracts, each carrying a packet, acceptance criteria, an SLA target, a
rejection code and a return owner. **1,799** per-step cases recorded, **0** failing. **347** events
reconciled. **75** injected defects driven. All **15** required deliverables tracked by git under
`docs/phase-d/`. Phase A drift 0, Phase B drift 0, `fn_phase_c_freeze_drift()` 0 red,
`fn_phase_c_invariants()` 0 red.

**Open, and measured on production today.**

- **`steps_with_no_effect_ever_produced = 257`** — the single red on `fn_phase_d_effect_state()`,
  whose other eleven pass/fail checks are green.

  **CORRECTED 2026-08-20 by E5, and E5's own numbers CORRECTED THE SAME DAY by E7.** This bullet
  said "the effect ledger is empty because no committed business arrival has ever driven a step",
  which is true of a minority of the 257. E5 replaced that with a 21 / 51 / 185 split — and got two
  of the three wrong, by classifying each step from the object its effect row **declares** rather
  than the branch `fn_phase_d_effect_produce` **executes**. All 41 `REVIEW_VERDICT` steps call
  `fn_phase_d_object_write` with a hardcoded `'review_record'`, which binds to `public.review_chain`,
  an `EXISTING_TABLE` — so E5 counted 41 steps that write a real table as needing no table at all.

  `fn_phase_d_effect_reachability()` now derives the class from the branch, and the board carries
  five rows beside the red:

  | steps | what the effect actually writes | who can lift it |
  |---:|---|---|
  | **21** | nothing — `CAPABILITY_REQUEST` **raises** `pd_capability_unavailable` in production. The declared effect *is* the refusal; a ledger row needs `execution_context=test`, which is not a result. | the founder, by lifting the provider hold |
  | **70** | one row in `phase_d_effect_ledger` and nothing else anywhere — `KERNEL_ONLY_TRANSITION` 51, `EXTERNAL_EFFECT_INTENT` 12 (mock only), `MEASUREMENT_RECORD` 7 | Phase E |
  | **74** | `phase_d_object_record`, through a `v_obj_*` view — Phase D's own store | Phase E |
  | **78** | a **real existing table the zero-residue rule does not name**: `review_chain` (41), `refunds`, `company_goals`, `opportunity`, `os_incidents`, `legal_reviews`, `documents`, `quote_comparisons`, `supplier_capabilities`, `leads`, `stripe_events`, `inquiry_matches`, `department_objective`, `content_drafts`, `reveal_invoices`, `org_tasks` | Phase E, and a decision about writing rows into tables the company uses |
  | **14** | one of the five tables the zero-residue rule names — `quotes` 5, `inquiries` 4, `customers` 4, `transactions` 1 | the founder, by lifting the zero-residue rule |

  So **144** steps (70 + 74) write nothing outside Phase D's own two tables, **not** the 185 E5
  claimed; **92** write an existing table, not 51; and only **14** touch the five tables the
  zero-residue rule actually names. The 144 are held by neither hold — they are held by the fixture
  rule: the only driver, `fn_phase_d_drive_workflow`, opens every run with
  `source_ref = 'zz-phase-d-…'` and `trigger_ctx.fixture = true`, and `fn_phase_d_fixture_residue()`
  must return 0.

  The recording path itself works, and that was measured rather than argued. Producing the declared
  effect for step runs **255** (W06-S06) and **256** (W06-S07) — both real, committed, `completed`
  `KERNEL_ONLY_TRANSITION` runs — inside an aborted transaction wrote, per
  `pg_stat_xact_user_tables`, **`public.phase_d_effect_ledger ins=2 upd=0 del=0` and nothing else**,
  with `fn_phase_d_fixture_residue()` returning 0 rows and `provider_mode = none`. **The rows were
  not kept.** Backfilling a ledger for two step runs that completed before the recording path was
  built would be a row added to make a count look better, and `produced_by` would name a role that
  did not produce it.

  The estate does hold **0 inquiries, 0 quotes, 0 transactions and 0 customers** (`select count(*)`
  on each, 2026-08-20) since the 16 Aug funnel purge, and `phase_d_handoff_acceptance` and
  `phase_d_external_attempt` are both **0 rows**. Everything below is evidenced by driven fixtures,
  never by a real arrival.
- **14 of 30 workflows do not close.** Driving all 30 in `execution_context` `production`,
  **16** reach `DETERMINISTIC_CLOSURE` and **14** stop at `pd_capability_unavailable`: the capability
  boundary at `fn_phase_d_handler_execute` section 3 refuses the **21** steps whose
  `capability_dependency` is `REASONING` while the founder's hold on paid inference stands.
  16 of 30 with that reason is the honest figure. 30 of 30 is reachable only in test mode and is not
  a result.
- **Only 40 of the 54 rules have a predicate that can actually refuse.** From
  `select * from public.fn_phase_d_rule_can_refuse()`: **40** produce `ENFORCED_FAIL` on at least one
  of the three probe contexts; **11** are `DELEGATED_TO_KERNEL_GUARD` — the kernel decides and this
  predicate cannot invoke it (BR-006…010, 045…047, 050…052); **2** are constant while the provider
  hold stands (BR-053, BR-054); and **1**, BR-028, is enforced at the executor's capability boundary
  rather than in the predicate. "54/54 enforced" is a statement about mechanism, not about refusal.
- **38 of the 75 injected defects are `NOT_RUN`**, each with a named blocker; **35** were
  `REFUSED_AS_REQUIRED` and **2** ran without discriminating. The Definition of Done asks for 100%
  refused.
- **333 of the 347 events have never been observed emitting**, and **60** are still
  `DEFERRED_RUNTIME_IMPLEMENTATION`. Producer resolves for 286 of 347.
- ~~**56 SECURITY DEFINER routines in `public` remain anon-executable**~~ — **CLOSED 2026-08-20 by
  E4.** Measured before: 56 anon-executable and 59 authenticated-executable of 791. Measured after:
  **0 anon-executable and 2 authenticated-executable**, and the two are named — `fn_customer_documents`
  and `fn_customer_document_refs`, the only routines any caller invokes with a client JWT
  (`asUser.rpc` at `customer_documents/index.ts:125`, `:148`, `:167`, `:197`), the second of which is
  also evaluated inside the `documents_customer_select` RLS policy as the querying role. The other 57
  were revoked from `public, anon, authenticated` after a per-function review: all 279 remaining
  `.rpc(` call sites in the repository use the service-role client, no SECURITY INVOKER routine a
  client role can reach calls any of them, and no view in `public` compiles one in. Verified as the
  roles themselves on production — `anon` and `authenticated` receive `insufficient_privilege`,
  `service_role` still executes. `scripts/checks/anon_cannot_execute_security_definer.test.mjs` is no
  longer a ratchet at 56; it is a floor of zero with the authenticated set pinned by name.

- **NEW, and Phase D's own: 30 SECURITY DEFINER views handed back what their base table withheld.**
  `d2:722` revokes `public.phase_d_object_record` from `public, anon, authenticated` — *"The store is
  written only through the service"* — and `d2:474` grants SELECT on each of the thirty `v_obj_*`
  views **over that same store** to `service_role, authenticated`. A view without
  `security_invoker = true` reads as its owner, so any signed-in JWT could `GET
  /rest/v1/v_obj_financial_close` and 29 more, past an RLS policy set that is deny-all. It also
  defeated `d43`, which had revoked the *function* door to the same data for exactly that reason.
  Nothing had leaked because the store holds 0 rows — the D35 finding word for word. **E8 revoked all
  thirty**, plus `phase_d_business_object_binding` and `fn_phase_d_object_state()`, each an explicit
  `authenticated` grant with zero callers in `supabase/functions`, `src`, `scripts` or any routine
  body. Measured after: **anon can SELECT 2 of 574 relations in `public` (both public site content)
  and 0 views; authenticated 0 views.** Probed as the roles: `authenticated` denied,
  `service_role` still reads all 30.

- **The kernel dispatch reached every W01 step and executed none of them — measured, and three of six
  are now closed.** Driving W01 in `execution_context = 'production'` inside an aborted transaction,
  all six dispatched steps returned `INPUTS_UNRESOLVED`. Six key names, splitting in two:
  `founder_instruction` and `founder_mandate` (S01–S03) **are** named by the resolver and read
  `public.founder_command`; they are unresolved only because `fn_phase_d_drive_workflow` opens a run
  with no founder command behind it, and a real command through `os_api` resolves them. The other
  four — `external_and_internal_evidence`, `current_cash_budget_and_commitments`, `budget_envelope`,
  `resource_envelope` — were named **nowhere**, and the resolver's `else` branch said so: *"NO TABLE
  IN THIS ESTATE HOLDS THESE."*

  That sentence is wrong. `department_budget` holds 10 rows of `monthly_aed`/`spent_aed`/
  `degrade_at_pct`/`halt_at_pct`; `org_agents` 90 active over 10 active departments; `gl_journal` 73
  posted entries; `company_event` 1,452 in 30 days, `company_index` 60 in 90, `decision_trace` 114 in
  30. **E9** gives each of the four a branch reading those rows, refuses on an empty source rather
  than passing an empty object, and declines by name the two things no relation holds — a cash
  POSITION (`cash_position_available: false`) and an external signal (`external_available: false`).

  After E9, re-driven: **W01-S04, S05 and S06 resolve their inputs** and are `REFUSED` by a named
  rule or gate — `BR-003 requires [founder_authority_ref]`, `GATE-006 (Valid workflow transition)
  requires [to_state]`. That is the contract evaluating and saying no for a stated reason, which is
  what these steps could not reach before. S01–S03 remain honestly unresolved. Residue 0, business
  tables 0/0/0/0, `phase_c_workflow_run` unchanged at 18.

- **OPEN, and it has no database-level fix: `public` is DEFAULT-OPEN for function EXECUTE.** Measured
  by execution 2026-08-20, each step in its own transaction, as `postgres` — the role every migration
  runs as: a new **table** and a new **view** come back `postgres | service_role` with anon SELECT
  false, and a new **function** comes back `=X/postgres | postgres=X/postgres | service_role=X/postgres`
  with **anon EXECUTE true**. The leading `=X/postgres` is PostgreSQL's built-in `GRANT EXECUTE TO
  PUBLIC`; tables and views have no equivalent. `pg_default_acl` for `postgres` on functions in
  `public` holds no PUBLIC entry, so
  `alter default privileges … revoke execute on functions from public` has nothing to revoke and is a
  **no-op** — tried twice, the stored ACL byte-identical afterwards, and a function created in the
  next transaction still anon-executable. A migration claiming that as a fix was **withdrawn rather
  than committed**. What holds the floor at zero is the rule "revoke in the same migration that
  creates it" plus `scripts/checks/anon_cannot_execute_security_definer.test.mjs`, which now runs in
  the one CI job that holds the credential. A new SECURITY DEFINER routine without its revoke fails
  there and nowhere else.

| | |
|---|---|
| session | 2026-08-18, 14:00 → 15:20 UTC (database clock) |
| project | `htdblwldjkcgjvmqkbeh` — the one project |
| branch | `feat/phase-d-d1-d3-handler-registry-and-rules` |
| commits | `fb86840` D1+D3 · `195cfb4` D0 · `a8bda15` closure · `ef1a9db` manifest · `fc347b6` schema mirror + deliverables 13/14 · `713210a` sweep · `0262b25` refusal paths · `8874b7b` graph · `aabaaa1` deliverable 5 |
| pull request | [#446](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/446) |
| paid inference | **USD 0.00** — `llm_attempt` 0 rows, `ai_cost_log` 0 rows since the Phase D start instant |
| live external effects | **0** — see the zero-cost section, which names what the 4 notification rows in the window actually are |

Phase E was not begun. No frozen Phase A, Phase B or Phase C object was edited.

---

## Session 2 — D2, D4, D5 (2026-08-18, 15:20 → 16:15 UTC)

> **THE WAVE LETTERS IN THIS TABLE ARE THE SESSION'S OWN, NOT THE MASTER WORKLIST'S, and the two
> disagree.** This table calls business rules **D4** and gates **D5**; the remainder table further
> down calls handoffs **D4** and the call graph **D5**, and gates **D3 (rest)**. Same document, same
> names, two numbering schemes — noticed on 2026-08-20 and corrected here by saying so rather than
> by renumbering, because both labels are quoted in commit messages and in
> `PHASE_D_REMEDIATION_PLAN.md`. Read against the master worklist the mapping is:
> session-2 **D4** (business rules) → worklist **D3 (rules half)**; session-2 **D5** (gates) →
> worklist **D3 (rest)**. Worklist **D4** and **D5** are handoffs and the call graph, and neither
> was in session 2.

Resumed from `bc20365` after a clean precheck: main == origin, 0 drift both ways, schema mirror
byte-identical, working tree clean.

| wave | before | after |
|---|---|---|
| **D2** business objects | 0 of 56 mapped | **56/56 bound** — 26 to an existing relation, 30 to a new policy-guarded store with a canonical view each. Board 7/7. |
| **D4** business rules | 34 of 54 enforced | **54/54 enforced**, 0 outstanding. Ratchet entry **deleted**, not lowered. Board 4/4. |
| **D5** gates | 0 of 32 with their own predicate | **32/32 contracted and predicated**. 29 BLOCK on empty evidence; the 3 that pass are database-measured and need none. Board 5/5. |
| deliverables | 6 of 15 | **15 of 15** — all fifteen are tracked by git under docs/phase-d/ as of 2026-08-20; the 6 was true when written and was never revisited |

### Three measurements that decided the D2 design

- **There is no `suppliers` table.** The supplier account is `public.leads` (20,465 rows) carrying
  `claimed`, `approval_status`, `verification_status`, `accepted_terms_*`. Binding to a table
  called "suppliers" would have bound to nothing.
- **`public.transactions` is empty** and carries `revealed_at`/`fee_status`/`reveal_fee`/
  `payment_ref`. BR-020 is decided there, and only a fixture can prove it.
- **536 tables have RLS enabled with zero policies** — deny-all, not configured protection. The map
  and the CSV record the *policy count*, never the flag.

Thirty of the 56 objects have no table anywhere. MISSING means build it, so they get one canonical
store with a per-object view — the 21 declared record policies collapse to 6 enforcement families,
and thirty near-identical tables would have meant thirty copies of one trigger.

### BR-020, the rule the brief singled out

`public.transactions` has **no check constraints at all**, so `fee_status` is unconstrained text and
this estate had never declared what a payment state is. `phase_d_payment_state` now declares six
rungs as data. Driven up the ladder on a fixture, in an aborted transaction:

```
checkout_created    rung=1  permitted=false
payment_initiated   rung=2  permitted=false
provider_success    rung=3  permitted=false
payment_confirmed   rung=4  permitted=false
payment_reconciled  rung=5  permitted=false   <- no payment_ref, no reveal_fee
reveal_authorized   rung=6  permitted=false   <- same
reconciled + ref + fee      permitted=true
fee_status='paid'   rung=0  permitted=false   <- unknown REFUSES, no nearest-rung fallback
```

The six states the brief said not to equate are not equated. No CHECK was added to `transactions`:
a live writer using an off-ladder value would then fail at runtime, and Phase D repairs
implementation to the frozen design rather than changing behaviour to make a check green.

### The rule evaluator gained a third answer

Phase C's routine had two — true and false — and returned **true** when it had no predicate. The
state is now explicit: `ENFORCED_PASS`, `ENFORCED_FAIL`, `NOT_APPLICABLE`, `NOT_IMPLEMENTED`, the
last carrying `ok = false`. The executor blocks a hard rule on failure **and** on not-implemented.
Asked with an empty context, **30 rules return `ENFORCED_FAIL`** — they need evidence rather than
assuming it.

### Gates: additive, not a stricter kernel

`fn_phase_c_gate_evaluate` is called by the frozen kernel for every step in the estate and its
callers pass a fixed five-key object. Making it strict would refuse every step completion in the
system — not a stricter gate, an outage. So `fn_phase_d_gate_evaluate` is a new strict path the
Phase D executor calls **before** the kernel, with the kernel's generic check behind it. Every row
of the deliverable says so rather than implying estate-wide coverage.

### The handler status was overstating, and now says so

The brief warned against marking handlers implemented because bindings and schemas exist. 236 of
257 read `NEW_DETERMINISTIC_HANDLER`, which is true about the **output** and overstates the
**business effect**: at the time of writing, not one handler called a business-object service.
`business_write_wired` is MEASURED from the live executor body, and the board carried
`handlers_not_writing_a_business_object = 257`, ratcheted with an owner and an instruction to
delete the entry at 0.

**Re-measured 2026-08-20: that count is now `0` and the check is green** —
`fn_phase_d_handler_state()` is **7/7**. `fn_phase_d_effect_state()` classifies all 257 as
`BUSINESS_EFFECT_CONNECTED=224 · CAPABILITY_BOUNDARY_READY=21 · EXTERNAL_ADAPTER_READY_DISABLED=12`.
The gap moved rather than closed: **`steps_with_no_effect_ever_produced` is still 257**, because a
wired write is not a produced effect until a committed business arrival drives it, and none has.

### Defects found in my own work this session, every one by execution

| defect | detail |
|---|---|
| `%L` inside a `RAISE` | Only `format()` supports it; six messages printed a stray `L` after the value. |
| `transactions.id` is UUID, not bigint | Predicates cast the *argument* and threw on every call. The estate mixes key types — `inquiries` uuid, `leads` bigint, `inquiry_matches` one of each — so identifiers are now text and the column is cast. |
| Two OUT params shadowed columns | `state_key` and `reason`. Postgres refused both as ambiguous rather than silently choosing. |
| BR-011 collapsed to a tautology | An OR'd condition that read as if it were doing something it was not. |
| Scope treated as applicability — **again** | GATE-004 blocked an intake step for a reviewer the frozen step never names. Identical shape to BR-002 last session. |
| Ratchet expressed in the wrong direction | A check reading "0 of 257 wired" needs a number that must *grow*, which inverts the ratchet's meaning. Counted as the gap instead, so it falls. |

---

## Why this ends NOT_READY

Phase D's Definition of Done requires, among other things: 257/257 handlers evidenced with seven
test cases each, 30/30 deterministic workflow closures, 56/56 business objects reconciled, 54/54
rules and 32/32 gates enforced, all effective handoffs, 347/347 events classified, 100% of the 75
injected defects refused, and fifteen committed deliverables.

**Written on 2026-08-18 this read "three of those are met or partly met, the rest are not started."
Re-measured 2026-08-20 that is no longer true** — the itemised table near the end of this file
carries what each wave actually measures now. What remains true is the reason for the verdict:
several of those clauses are met by *mechanism* and not yet by *effect*. 100% of the 75 injected
defects are not refused (35 are), 30/30 deterministic closure is not reached (16 is, under the
capability hold), and not one step has ever produced an effect from a committed business arrival.
Declaring readiness on that basis would be the exact defect this phase exists to remove, so the
verdict is NOT_READY and the remainder is itemised below rather than summarised away.

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

**And the refusal paths, also by execution** (aborted transaction, step run 5544). A handler that
only ever succeeds is not evidence that anything is enforced, so each was driven until it refused:

| case | refused by | machine result |
|---|---|---|
| missing input — 1 of 3 declared keys sent | `fn_phase_d_schema_validate` | `pd_input_schema_invalid`, naming the missing key |
| wrong actor — `cfo` on a `chief_of_staff` step | the **frozen kernel** | `k3_not_the_accountable_owner`, "holds no active delegation" |
| founder-gated step with no authority reference | **BR-003** | `pd_rule_refused` — `br003_founder_boundary_unevidenced` |
| step run that does not exist | the executor | `pd_step_state_invalid` |

Note the second row: the executor did not re-implement the ownership check, it let the frozen
`fn_kernel_step_complete` refuse. That is the boundary working as designed.

**Idempotent replay, also by execution.** The same call twice under one key:

```
first  call  replay=false
second call  replay=true
same output_hash   yes        same step_run   yes
handoff runs on the workflow run:  1     <- not 2
```

The second call returns the **stored first result** rather than recomputing, and the effect count
is the number that matters: one handoff run, not two. A replay that returned a fresh success while
quietly creating a second handoff is the duplicate-effect defect D8 exists to prevent, and the
denominator here is the actual row count, not the result payload.

### D3 — 54 of 54 rules stop being prose

`phase_d_rule_enforcement` names, for all 54, **how** each is enforced and **when** it applies.
**Re-measured 2026-08-20** — the table below replaces the 2026-08-18 split, which read
PREDICATE 15 · KERNEL_ENFORCED 9 · PENDING_OBJECT_MAP **20 OUTSTANDING**:

| enforcement kind | count | status |
|---|---|---|
| PREDICATE — decided from the call context | 36 | ENFORCED |
| KERNEL_ENFORCED — the frozen kernel raises | 8 | ENFORCED |
| TRIGGER_ENFORCED — refused at write time | 5 | ENFORCED |
| SCHEMA_ENFORCED — the output schema requires the key | 3 | ENFORCED |
| CONTEXT_REQUIRED — absent fact is a refusal | 1 | ENFORCED |
| EXECUTOR_ENFORCED — capability fails closed | 1 | ENFORCED |
| **PENDING_OBJECT_MAP** | **0** | — |

The board **resolves every named enforcement point in the live catalogue** — a disposition in prose
with no mechanism is the failure mode this is built against. An unregistered rule is now
**refused**, which is the exact inversion of the routine it replaces. `fn_phase_d_rule_state()` is
**4/4 green** and `rules_with_outstanding_enforcement = 0`; the ratchet entry naming the 20 rules
(BR-011, 012, 013, 014, 015, 017, 018, 019, 020, 025, 026, 029, 032, 033, 034, 035, 036, 039, 041,
049) reached 0 and was **deleted, not lowered**.

**A mechanism is not a refusal, and the two must not be read as one number.**
`select * from public.fn_phase_d_rule_can_refuse()` probes every rule with three contexts —
empty, full, and authority-withheld — and reports where an `ENFORCED_FAIL` is actually reachable:

| | |
|---|---|
| rules with a real predicate that can refuse | **40** |
| `DELEGATED_TO_KERNEL_GUARD` — the kernel decides, this predicate cannot invoke it | **11** |
| constant while the founder's provider hold stands (BR-053, BR-054) | **2** |
| enforced at the executor's capability boundary, not in the predicate (BR-028) | **1** |

The 11 delegated are BR-006…010, BR-045…047 and BR-050…052. Their refusal is real but lives in the
frozen kernel, so this instrument cannot witness it — which is stated here rather than counted as a
pass.

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
| `fn_phase_d_handler_state()` | **7/7 green** — re-measured 2026-08-20; was 6/6 with the seventh red |
| `fn_phase_d_rule_state()` | **4/4 green** — re-measured 2026-08-20; was 3/4, the fourth red by disclosure |
| `fn_phase_d_effect_state()` | **11 of its 12 pass/fail checks green** (plus 3 informational rows), measured 2026-08-20; the red is `steps_with_no_effect_ever_produced = 257` |
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

This is the whole of the Phase D scope outside D0–D3. The left-hand columns are the original
targets and are unchanged; **every state cell was re-measured on 2026-08-20** and seven of them no
longer read "not started". A cell saying BUILT means the mechanism exists and was measured — it does
not mean the wave's Definition of Done clause is met, and where it is not the cell says so.

| wave | scope | state |
|---|---|---|
| **D2** | 56 business objects | **DONE this session — 56/56 bound, board 7/7.** Remaining: no handler yet writes an object (counted on the handler board). Naive name matching resolves only 8 of 56 to a table — the estate's 553 tables do not share the registry's vocabulary, so this needs real mapping. **That mapping was the blocking dependency for the 20 outstanding rules; re-measured 2026-08-20 it is done and outstanding rules are 0.** |
| **D3 (rest)** | 32 gate predicates | **DONE this session — 32/32, board 5/5.** Strict on the Phase D path; the kernel path is unchanged and that is stated. |
| **D4** | 159 effective handoffs: packet schema, acceptance, SLA, rejection, return owner | **BUILT — re-measured 2026-08-20.** `phase_d_handoff_contract` holds **159 rows**, and all 159 carry every one of the five: a non-empty `packet_keys`, `acceptance_criteria`, an `sla_target` interval, a `rejection_code` with its `return_owner_role_id`. **Not yet exercised:** `phase_d_handoff_acceptance` holds **0 rows** — no acceptance has been decided, because no committed arrival has driven one. |
| **D5** | frontend → API → service → database call graph; storage MIME/magic-byte/quarantine; RLS proofs | **BUILT — re-measured 2026-08-20.** `PHASE_D_FRONTEND_API_CALL_GRAPH.csv` (regenerated 2026-08-20T01:02:00Z) resolves **77 of 77 distinct (component, edge_function) pairs across 39 files and 39 edge functions, from 153 raw call sites**, one row per pair attributed to the file whose own source names the endpoint. Storage and RLS are in `PHASE_D_STORAGE_RLS_SECURITY_RESULT.md`. |
| **D6** | external effect adapters, all mock/disabled | **PARTIAL — re-measured 2026-08-20.** `phase_d_external_message_contract` holds **4 rows** — reveal to customer and to supplier, over email and WhatsApp — and `phase_d_external_adapter_field` holds **14 rows, all `PRESENT`**. `phase_d_external_attempt` holds **0 rows**: nothing has ever been attempted, so the adapter's disabled behaviour is declared and not yet witnessed. Four contracts is the reveal path only, not every external effect in the estate. |
| **D7** | finance/legal/privacy contracts for W08, W10, W15, W16, W17, W27, W28 | **PARTIAL — re-measured 2026-08-20.** `PHASE_D_FINANCIAL_PRIVACY_RESULT.md` now covers: the 6-rung payment ladder with only rungs 5 and 6 authorising a reveal, proved by injection; the founder-only refund trigger against 2 active founder identities, proved by injection, with 0 refunds approved by Phase D; ownership scope on **56/56** objects; and 0 outbound requests from a 30-workflow drive. It also records **3 of 5 FINANCE and 2 of 5 PRIVACY defects executed** — the other five are `NOT_RUN` with named blockers — and one finding it declines to fix: GATE-020 guards "Execute approved financial action" but accepts *any* decision, including a rejection. Separation of duties is declared on `phase_c_refund_decision` and enforced by no Phase D path. |
| **D8** | per-handler idempotency, lock, retry class, compensation, cancellation tests | **partial** — the kernel supplies idempotency and locking and this was exercised once; no per-handler test matrix |
| **D9** | capability boundary | **partial** — 21 steps classified, typed request and fail-closed behaviour implemented and enforced in the executor; no mock fixture library |
| **D11** | 257 × 7 = 1,799 per-step tests; 30 × 4 workflow tests; the 75-row injected defect catalogue | **PARTIAL — re-measured 2026-08-20.** `phase_d_step_case_result` holds **1,799 rows** — 257 steps × 7 case kinds — with **1,799 passed, 0 failed**. `PHASE_D_INJECTED_DEFECT_RESULT.csv` (regenerated 2026-08-20T01:02:06Z) carries all **75** catalogued defects: **35 REFUSED_AS_REQUIRED, 38 NOT_RUN** each with a named blocker, **2 NOT_DISCRIMINATED**. The Definition of Done asks for 100% refused, so **40 of 75 are not yet evidence of anything**. |
| **D12** | 347 events reconciled with real producer/consumer/outbox/trace | **PARTIAL — re-measured 2026-08-20.** `phase_d_event_reconciliation` holds **347 rows**, all carrying an outbox relation and a trace. Producer resolves for **286**, consumer for **346**; structurally **287 CONNECTED, 60 DEFERRED_RUNTIME_IMPLEMENTATION**. At runtime **333 of 347 have NEVER been observed** and only **14** were seen in the outbox — reconciled on paper, not in flight. |
| **D13** | 30/30 deterministic workflow closure | **16 of 30 — re-measured 2026-08-20**, and the reason is not a defect. `PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv` (regenerated 2026-08-20T01:01:54Z) drives all 30 through the executor and the kernel in aborted transactions, in `execution_context` **`production`**. **16 reach `DETERMINISTIC_CLOSURE`; 14 stop at `pd_capability_unavailable`** — the capability boundary at `fn_phase_d_handler_execute` section 3 refuses the **21** steps whose `capability_dependency` is `REASONING` while the founder's hold on paid inference stands. All 30 leave **0 open handoffs, 0 notifications and 0 outbound HTTP requests**. **16 of 30 with that reason is the honest figure; 30 of 30 is reachable only in test mode and must not be quoted as the result.** |
| **D14** | 15 required deliverables | **15 of 15** tracked (measured 2026-08-20 with git ls-files; the 5 was the state at D14 and is kept in the left column) |

**Written:** `PHASE_D_CURRENT_CODE_HANDLER_CROSSWALK.csv`, `PHASE_D_RULE_GATE_RESULT.csv`,
`PHASE_D_ZERO_COST_EVIDENCE.md`, `PHASE_D_PRODUCTION_DEPLOYMENT_LEDGER.md`, and this file.

**Still owed — re-measured 2026-08-20 with `git ls-files docs/phase-d/`: nothing.** The ten files
this section listed as owed — `PHASE_D_HANDLER_IMPLEMENTATION_RESULT.csv`,
`PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv`, `PHASE_D_BUSINESS_OBJECT_RESULT.csv`,
`PHASE_D_HANDOFF_EVENT_RESULT.csv`, `PHASE_D_FRONTEND_API_CALL_GRAPH.csv`,
`PHASE_D_STORAGE_RLS_SECURITY_RESULT.md`, `PHASE_D_FINANCIAL_PRIVACY_RESULT.md`,
`PHASE_D_IDEMPOTENCY_CONCURRENCY_RESULT.md`, `PHASE_D_EXTERNAL_EFFECTS_RESULT.md` and
`PHASE_D_INJECTED_DEFECT_RESULT.csv` — are all tracked by git under `docs/phase-d/`. That a
deliverable exists says nothing about whether what it reports is complete; the rows above say that.

---

## Recommended next increment

*Written 2026-08-18: "D2, and specifically the object→table map", because it held 20 of the 54
business rules in `OUTSTANDING`. **Re-measured 2026-08-20 that work is done** — every object
resolves, and `rules_with_outstanding_enforcement` is 0.*

**The next increment is an effect produced by a committed arrival.** Everything Phase D has proved
was proved in a transaction that was then aborted, against an estate holding 0 inquiries, 0 quotes,
0 transactions and 0 customers. That is why `steps_with_no_effect_ever_produced` is still 257, why
`phase_d_handoff_acceptance` and `phase_d_external_attempt` are both empty, and why 333 of 347
events have never been observed. No amount of further registry work moves any of those numbers.

The second item is the capability hold: 14 of 30 workflows cannot close and 21 steps cannot run
while paid inference is held. That is a founder decision, not an engineering gap, and it caps
D13 at 16 of 30 until he lifts it.

---

**PHASE_D_NOT_READY**
