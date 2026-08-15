# QuotesDone — Phase B final business workflow architecture

**Status:** deployed to `htdblwldjkcgjvmqkbeh` on 15 Aug 2026 and verified by execution.
**Depends on:** the founder-approved Phase A organization, tag `phase-a-founder-approved-2026-08-15`, unchanged.

Phase A answered *who exists and who owns outcomes*. Phase B answers *how the company works from
start to finish*, and puts that answer in the database as structure a future change must get past
rather than as a document a future change can ignore.

## What is now live

30 canonical workflows · 257 steps, each with exactly one accountable owner · 161 handoff
contracts, 47 of them crossing a department · 56 business objects · 54 business rules · 32 gates ·
50 exception patterns · 34 SLA policies · 347 events · 14 workflow states with 35 declared
transitions · 11 step states with 19 · 10 founder boundaries · and a 719-row crosswalk recording
what the estate does today against each of them.

All 90 canonical roles appear in at least one accountable, contributor or review responsibility.
All 10 departments appear. All 86 category overlays keep exactly the scope Phase A approved.

## The four things that make this structure rather than documentation

**One accountable owner, and it must be a real employee.** `step_id` is the primary key, so a
step cannot appear twice; `accountable_role_id` is `NOT NULL`, so it cannot appear unowned; and
`fn_phase_b_owner_guard` refuses an owner that does not resolve to an *active canonical* role.
74 of the estate's 184 current runtime steps would fail that guard today — they name a title
nobody models. That is measured, not estimated, and it is the largest single item Phase C
inherits.

**Independent review means a different person, not a different spelling.**
`phase_b_step_creator_not_reviewer` compares canonical role ids, and every token is resolved
through `org_role_alias` before it is stored. `risk_and_governance_manager` reviewing
`risk_governance_manager` is one identity here, and it is refused. This estate has shipped that
exact defect before.

**A handoff is a contract with two named parties.** Every column of
`phase_b_handoff` is `NOT NULL` — packet, acceptance criteria, rejection condition, return owner,
closure condition, SLA — so an incomplete contract cannot be stored. `fn_phase_b_handoff_guard`
additionally refuses one whose named sender or receiver is not the accountable owner of the step
it joins. Sending a message is not a handoff, and neither is naming the wrong people.

**Closure is refused while anything mandatory is open.** `fn_phase_b_closure_blockers` returns a
reason per open blocker, unaccepted handoff and incomplete mandatory step. It is pure over its
arguments, so it is testable today; Phase C supplies the run's real state.

Eighteen injected-defect cases prove each of these fires rather than merely exists. They run
inside transactions that always end in `rollback`, and the suite asserts the row counts are
unchanged afterwards.

## The category overlay boundary

All 86 overlays remain on-demand. They may contribute to inquiry qualification (W05), category
routing (W06), document interpretation (W07), supplier capability verification (W10) and
quotation technical evaluation (W14).

Exactly one step in the whole registry is *accountable* to an overlay: `W14-S05 Validate
technical completeness`, an `analysis` step. `fn_phase_b_owner_guard` allows that and nothing
wider — an overlay accountable in W12 dispatch, W15 reveal, W16 payment, W17 refund or W24
release is refused by name, as is an overlay owning a `decision` step even inside its own scope.

## Founder boundaries

Ten boundaries, each mapped to the workflows in its scope: equity and ownership · commercial
pricing model · the AED 1,000,000 revenue objective · country and marketplace model · company
identity and permanent policy · spending above authority · binding legal commitments · senior
human and equity compensation · consequential autonomy activation · permanent material risk
acceptance.

Each is reachable only through a founder-gated step somewhere in its scope; zero boundaries have
no gate. Several boundaries are constraints rather than approval events — *"departments operate
within approved policy"* — and demanding a gated step in every scoped workflow would have been a
check measuring something other than what it names.

## Phase A was not touched

`org_workflow_ownership` turned out to be **inside** the frozen Phase A digest, so the package
had to agree with it rather than the reverse. All 30 workflows' accountable owners and
independent reviewers were compared after alias resolution: **0 conflicts**. No Phase A change
request is required, and none was written.

The identity work Phase B did was additive: 69 rows in `org_role_alias` teaching the estate that
`payments_billing_manager` and `Trust & Safety Manager` name employees it already has.
`org_role_alias` carries no Phase A frozen digest and no `z90_phase_a_freeze` trigger. Nothing
was created, renamed, merged, moved or retired. `fn_phase_a_baseline_drift()` returns 0 rows.

## What Phase B deliberately did not do

No workflow was activated. No cron job, provider route, edge function or autonomous executor was
created, enabled or rewired. No customer, supplier, inquiry, payment or notification was created.
No email, SMS or WhatsApp was sent. No OpenRouter request and no other paid inference call was
made; all 8 routes remain held open-circuit, and Phase B's cost was USD 0.00.

Runtime connection is Phase C, and the crosswalk is what Phase C starts from.

## The honest state of the estate underneath

The registry describes how the company should work. It does not claim the company works that way
today, and the crosswalk is explicit about the difference:

- 12 of 19 runtime workflow definitions have **never executed once**. `rfq_handling` — the
  marketplace itself — has 18 gated steps, 20 employees assigned and 0 runs.
- 407 cron jobs and edge functions execute under `pg_cron` and the service role, with **no
  accountable canonical role attached to any of them**.
- 64 edge functions have neither an internal caller nor an external entry surface.
- 36 state tables have never received a row.
- W21 (strategic partnership development) has no current implementation at all.

Full detail, with the command that measured each verdict, is in
`PHASE_B_CURRENT_PATH_DUPLICATES_AND_GAPS.md` and
`PHASE_B_CURRENT_TO_TARGET_WORKFLOW_CROSSWALK.csv`.

## Deliverables

| # | file |
| --- | --- |
| 1 | `docs/phase-b/PHASE_B_FINAL_WORKFLOW_ARCHITECTURE.md` (this file) |
| 2 | `docs/phase-b/PHASE_B_WORKFLOW_REGISTRY.csv` |
| 3 | `docs/phase-b/PHASE_B_WORKFLOW_STEP_REGISTRY.csv` |
| 4 | `docs/phase-b/PHASE_B_WORKFLOW_STATE_MODEL.csv` |
| 5 | `docs/phase-b/PHASE_B_WORKFLOW_TRANSITIONS.csv` |
| 6 | `docs/phase-b/PHASE_B_HANDOFF_REGISTRY.csv` |
| 7 | `docs/phase-b/PHASE_B_BUSINESS_OBJECT_REGISTRY.csv` |
| 8 | `docs/phase-b/PHASE_B_BUSINESS_RULE_REGISTRY.csv` |
| 9 | `docs/phase-b/PHASE_B_GATE_REGISTRY.csv` |
| 10 | `docs/phase-b/PHASE_B_EXCEPTION_ESCALATION_MATRIX.csv` |
| 11 | `docs/phase-b/PHASE_B_SLA_POLICY.csv` |
| 12 | `docs/phase-b/PHASE_B_CURRENT_TO_TARGET_WORKFLOW_CROSSWALK.csv` |
| 13 | `docs/phase-b/PHASE_B_CURRENT_PATH_DUPLICATES_AND_GAPS.md` |
| 14 | `docs/phase-b/PHASE_B_INVARIANT_RESULTS.md` |
| 15 | `docs/phase-b/PHASE_B_PRODUCTION_DEPLOYMENT_EVIDENCE.md` |
| 16 | `scripts/sql/phase_b_workflow_closure_rollback.sql` |

Also produced: `PHASE_B_EVENT_REGISTRY.csv` (347 events) and
`PHASE_B_FOUNDER_BOUNDARY_MAPPING.csv` (10 boundaries), both read back from production.

Registries 2–11 are **selected from the deployed tables**, not re-serialised from the package, so
what is written here is what is live.

## Unresolved founder-level decisions

None. Nothing in the workflow analysis required a decision only the founder can make, and no
Phase A change request was raised.

## What Phase C should do first

1. Bind cron jobs and edge functions to accountable canonical roles.
2. Connect or retire the 64 uncalled edge functions and 8 never-run cron jobs.
3. Give the 12 never-executed runtime workflows a real trigger, `rfq_handling` first.
4. Split the conflated runtime definitions along canonical boundaries, `supplier_onboarding`
   first because it carries an independence requirement that currently holds by convention.
5. Decide reactivation for the 18 cron jobs switched off on 2026-08-02.
6. Fix `index_slowdown_watch_daily`, the one currently failing path.
7. Build W21.
