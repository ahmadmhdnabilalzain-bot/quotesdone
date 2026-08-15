# Phase C — prompt for the next session

**The package is committed to this repository at `docs/phase-c/package/`. Nothing needs attaching.**
All 52 files were verified against `SHA256SUMS.txt` on 15 Aug 2026, and every count the package
declares was confirmed against its own registries: 30 workflow bindings · 257 step bindings ·
161 handoff bindings · 347 event bindings · 32 gate bindings · 54 rule bindings · 90 role
bindings · 86 overlay bindings · 26 authority classes · 35 command intents · 20 command-routing
acceptance cases · 13 command states · 24 command transitions · 11 task states · 22 task
transitions · 10 system actors · 11 trace policies · 11 JSON schemas. Two templates ship empty by
design — the runtime-component crosswalk and the executor accountability sheet are yours to fill.

Copy the block below into a new session. It is self-contained.

---

Load the `quotesdone-session` skill first. Then read, in this order, from
`docs/phase-c/package/`:

1. `START_HERE.md`
2. `PHASE_C_FROZEN_BASELINE_REFERENCE.json`
3. `PHASE_C_MASTER_SPEC.md`
4. `PHASE_C_FOUNDER_AUTONOMY_POLICY.md`
5. `PHASE_C_COMMAND_CENTER_ARCHITECTURE.md`
6. `PHASE_C_PRODUCTION_DIRECT_PROTOCOL.md`
7. `PHASE_C_ZERO_COST_TEST_PLAN.md`
8. `PHASE_C_INVARIANTS.md`
9. `CLAUDE_PHASE_C_MASTER_PROMPT.md`

Then the authority matrix, the runtime contract files, the binding templates and the 11 JSON
schemas. Then execute Phase C. Verify the package's checksums yourself rather than trusting
this line.

## Phase A and Phase B are founder-approved and frozen

Do not redesign departments, roles, category overlays, workflows, ownership, steps, handoffs,
rules, gates, states or founder boundaries.

Verify before you start and again before you finish:

```
select * from public.fn_phase_a_baseline_drift();          -- must be 0 rows
select * from public.fn_phase_b_baseline_drift();          -- must be 0 rows
select * from public.fn_phase_b_effective_errata();        -- all three resolved
select count(*) from public.fn_phase_a_organization_violations();  -- must be 0
```

Two statement-level guards refuse changes to the approved shape: `z90_phase_a_freeze` on
`org_departments` and `org_role`, and `z90_phase_b_freeze` on 11 `phase_b_*` tables. **The Phase B
guard compares a digest, not a count** — swapping two step owners is refused even though no row
count moves. If Phase C genuinely needs a frozen thing changed, write the formal change request
(`docs/phase-b/PHASE_B_CHANGE_REQUEST_TEMPLATE.md`, eleven required elements) and bring it to me.
Do not set `app.phase_b_change_reason` to get past the guard.

## The company is autonomous. I am not its task queue.

I give orders through the Command Center, observe status and outcomes, provide or limit funding,
and manually approve or reject specific refund cases. That is all.

- `chief_of_staff` is the founder-facing Command Center secretary. **Do not create a 91st role.**
  The UI may label it "Founder Command Secretary — Chief of Staff".
- Every safely routable founder command must create its command plan and immediate tasks assigned
  to the exact canonical departments and employees **in one transaction, before the API responds**.
- **No non-refund routine action may create a founder approval request.** `refund_decision` is the
  only routine manual approval class.
- Founder-reserved constitutional and commercial matters are `founder_initiated_only`: agents may
  research and recommend, they may not build me an approval queue.
- An agent may not escalate to me because it is unsure. It uses internal evidence, tools,
  specialist consultation, manager judgement, reviewer verdict, or it fails closed.

## Zero paid inference — absolute

```
NO_PAID_AI=true
OPENROUTER_DISABLED=true
AI_PROVIDER_MODE=mock
```

All 8 OpenRouter routes are held open-circuit until 2126. **Do not release the hold and do not ask
me to.** Do not call OpenRouter, Anthropic, OpenAI, Gemini or any other paid endpoint. Phase C must
finish with OpenRouter requests = 0 and paid inference cost USD 0.00.

Prove it from the network guard and the cost log, not from a caught query error. The last AI call
this project ever made was 2026-08-15 02:51:33 UTC; `ai_cost_log.occurred_at` is the column, and
`llm_route_health.open_until` is the hold.

## Production-direct protocol

- inspect production read-only first;
- reconcile all runtime components;
- build and test locally;
- commit code, migrations, rollback and evidence **before** production;
- rehearse the exact committed SQL in an aborted production transaction and prove the fingerprint
  is unchanged;
- deploy incrementally, database first where backward compatible;
- immediately re-run every Phase A, Phase B and Phase C invariant;
- roll back the affected component if any mandatory invariant fails.

## What this repository already is, so you do not rediscover it

Measured 15 Aug 2026 after Phase B closed. **Re-measure before believing any of it** — this
paragraph is orientation, not evidence.

- **One Supabase project: `htdblwldjkcgjvmqkbeh`.** Staging was deleted 15 Aug 2026. Do not
  recreate it, do not write a check that reads it.
- **Deploy with** `node scripts/apply_sql.mjs <file> --apply [--ddl]`. A bare invocation is a dry
  run. It reads the definition back out of the database afterwards; that read-back is what makes
  the exit code mean anything.
- **A multi-statement file is ONE implicit transaction.** That is what makes the aborted rehearsal
  work: send the exact committed bytes with a trailing `raise exception` that first reads the
  post-change counts, so the numbers come out and nothing commits. `scripts/phase_b/rehearse.mjs`
  is a working example, including the refusal to report success if the migration does not raise.
- **CI lints migrations** (`squawk`): `set lock_timeout` and `set statement_timeout` at the top,
  CHECK constraints `not valid` then `validate`, `bigint` not `int`.
- **`scripts/sql` is append-only.** To change something, add a new file.
- **A database-reading `*.test.mjs` must skip loudly when there is no management token.** CI has
  none. Copy the pattern at the top of `scripts/checks/phase_b_invariants.test.mjs`, and put the
  skip before the db module is imported.

### The baseline reference in the package is one commit behind

`PHASE_C_FROZEN_BASELINE_REFERENCE.json` reports `main@675c111`. That is the commit whose tree the
Phase B registry digests were computed from — it is **not** what the tag points at. The approved
Phase B commit is the tag:

```
git rev-list -n 1 phase-b-founder-approved-2026-08-15     ->  763e318
```

Both are recorded on the baseline row (`final_commit` and `counts->>'digests_computed_at_commit'`)
with a note saying which is which. Verify the tags yourself and do not assume the repository has
not advanced since.

### Phase B already did the component inventory — build on it, do not redo it

`public.phase_b_crosswalk` holds **719 classified rows**, each with the command that produced its
verdict, covering 19 runtime workflow definitions, 205 cron jobs, 202 edge functions, 175 triggers,
93 state tables and 24 frontend routes. The scripts that produced it still run:

```bash
node scripts/phase_b/inventory_estate.mjs > docs/phase-b/_inventory.json && node scripts/phase_b/edge_callers.mjs > docs/phase-b/_edge_callers.json && node scripts/phase_b/classify_entry_points.mjs > docs/phase-b/_entry_points.json && node scripts/phase_b/build_crosswalk.mjs
```

Phase C's classification vocabulary is **different and finer** than Phase B's — `WIRE_TO_CANONICAL`,
`NO_CALLER_UNCLASSIFIED`, `INACTIVE_HISTORICAL`, `REPAIR_BEFORE_REACTIVATION`,
`INTENTIONALLY_RETIRED`, `PHASE_D_CORRECTNESS_GAP` — so the crosswalk needs re-classifying, not
re-measuring.

The seven runtime gaps I accepted as Phase C work are in `public.phase_b_phase_c_wiring_gap`, each
with its evidence command. They are Phase C's inbox, not Phase B defects.

### Four things Phase B measured that will shape Phase C

1. **12 of 19 runtime workflow definitions have never executed once.** `rfq_handling` — the
   marketplace itself — has 18 steps, every one gated, 20 assigned employees and 0 runs.
2. **407 cron jobs and edge functions execute under `pg_cron` and the service role with no
   accountable canonical role.** This is the single largest gap, and Gate C1 is where it closes.
3. **64 edge functions have neither an internal caller nor an external entry surface.** 87 of 202
   have no caller in repo, database or cron; 23 of those serve a webhook, a public page or an
   OAuth callback, leaving 64.
4. **Inactive is not dead.** 19 cron jobs are switched off; 18 of them had run before — one 21,563
   times — and all 18 stopped on the same date, 2026-08-02. That is a deliberate deactivation.
   Phase C's own vocabulary has `INACTIVE_HISTORICAL` and `REPAIR_BEFORE_REACTIVATION` for exactly
   this. Do not reactivate any of them merely because you have now mapped it.

### Preflight findings I already measured against the Phase C package

These are real and will cost you time if you meet them cold. **All of them are package-side naming,
not organizational defects — none needs a Phase A or Phase B change request.**

- **90 of the 100 role tokens the package addresses already resolve** through
  `public.fn_phase_b_resolve_role()`, because Phase B loaded 45 `packaged_role_id` aliases and 24
  `title` aliases into `org_role_alias` (237 rows now). Use that function; do not write a second
  resolver.
- **`fpa_analyst` resolves to nothing.** The live role is `fpna_analyst` and Phase B's alias is
  `fp_a_analyst`; the Phase C package introduces a third spelling. One alias row fixes it.
- **All 10 department names in the package are unknown to the live organization.** The package uses
  long descriptive keys, Phase A uses short ones:

  | package | live `dept_key` |
  | --- | --- |
  | `finance_payments` | `finance` |
  | `people_company_operations` | `people_ops` |
  | `growth_revenue` | `growth` |
  | `data_intelligence_knowledge` | `data_intel` |
  | `assurance_security_reliability` | `assurance` |
  | `marketplace_supplier_network` | `marketplace` |
  | `legal_compliance_risk_trust` | `legal` |
  | `customer_experience_communications` | `customer_experience` |
  | `product_engineering_ai` | `product_eng` |
  | `category_overlay` | *not a department* — overlays live in `org_role` where `runtime_mode = 'knowledge_overlay'` |

  `public.org_department_alias(packaged_department, dept_key, …)` exists and holds 25 rows, none of
  them these. It carries no Phase A frozen digest and no freeze trigger, so adding rows is safe and
  changes nothing frozen — confirm that yourself before writing.
- **Seven `review_or_contributors` cells hold prose where a role id belongs** — "fraud_reviewer or
  supplier_verification_reviewer", "manager/reviewer per Phase A/B", "accountable_canonical_role",
  "category overlay opcat-004". Same shape as the EX-006 column shift Phase B found. Record them as
  package errata with evidence and a decided correction; do not edit the checksummed bytes.

### The autonomy invariant already has counter-evidence in production

`founder approval requests where action_class != refund_decision = 0` is a Phase C hard invariant.
Today:

- **10 executors carry `notifies_human = true` and all 10 are active. None is a refund.**
  `capability_review`, `collections_chase`, `escalate_founder`, `expense_log`, `forecast`,
  `health_report`, `money_verify`, `nudge`, `outreach_send`, `security_review`.
- `public.founder_release_approval` exists and holds 1 row — a founder approval for a *release*,
  which the founder autonomy policy explicitly lists as something that must **not** reach me.
- `public.procurement_approval_request` exists and holds 0 rows.

`notifies_human` is not the same field as "creates a founder approval request", and I do not want
that conflated. **Measure which of these actually reach the founder before you change any of
them**, and say plainly which ones you looked at and which you did not.

### What exists for the Command Center, and what does not

- The OS/Command Center surface exists: `src/app/[locale]/os/page.tsx`, the `os_api` edge function,
  and `fn_os_portals_gates()` reporting 23 of 23 gates met.
- `public.agent_command_log` exists with 31 rows. `public.decision_trace` exists with 28 rows,
  plus `v_decision_trace_incomplete`, `v_executions_without_decision_trace` and `v_approval_trace`.
- `public.org_tasks` holds 1,050 rows, 55 open. `agent_actions` has 53 pending.
- **There is no outbox table of any kind.** Section 3.7 requires business state and events to be
  written atomically through one; that is new construction, not reconciliation.

Use the existing Command Center. Do not build a competing executive console.

## How to run the session

- No check-ins and no step-by-step updates. Work until done, then reply once.
- Do not ask me technical questions. Decide, do it, and tell me what you decided. Escalate only
  money, destructive production changes, and things only I can know.
- Verify by execution in the same turn, never by "it typechecks" or "the table exists".
- **A correct table with zero callers is not an implementation.** Ask what actually calls a path
  and whether it has ever run. Phase B found five finished capabilities with no entry point; the
  same lens is the most productive one here.
- **Force every new guard to fire before believing it.** A constraint that has never refused
  anything is indistinguishable from no constraint, and a zero row count cannot tell a dead guard
  from a test whose injection never landed. `scripts/checks/phase_b_guards_reject_injected_defects.test.mjs`
  is the working pattern: 20 cases, each in a transaction that always rolls back, each asserting
  the injection actually hit a row.
- Never weaken a check or fabricate data to turn a gate green. If a fix makes a check harder
  because the old pass was false, say so.
- Commit and merge via PR, never straight to main.
- Run the end-of-session sweep in the skill before you report, including step 9.

## Do NOT work on

Phase D correctness · professional knowledge content or certification · final model selection or
routing · V3 certification questions and answer keys · professional-quality scoring · persistent
synthetic customers, suppliers, inquiries or payments · live refund execution · external messages
to real recipients · enabling any previously disabled automation merely because it is now mapped ·
launch-readiness claims.

Produce the 20 deliverables the master prompt lists, under `docs/phase-c/`.

End with exactly `PHASE_C_READY_FOR_FOUNDER_APPROVAL` or `PHASE_C_NOT_READY`.
