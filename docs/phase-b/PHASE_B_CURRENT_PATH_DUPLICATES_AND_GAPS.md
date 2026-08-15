# Phase B — duplicate, conflicting and unconnected current paths

Measured 15 Aug 2026 against `htdblwldjkcgjvmqkbeh`. Every number below came from a query or a
script in this repository; the command that produced each verdict is in the
`evidence_command` column of `PHASE_B_CURRENT_TO_TARGET_WORKFLOW_CROSSWALK.csv`.

Reproduce the whole measurement with:

```bash
node scripts/phase_b/inventory_estate.mjs > docs/phase-b/_inventory.json && node scripts/phase_b/edge_callers.mjs > docs/phase-b/_edge_callers.json && node scripts/phase_b/classify_entry_points.mjs > docs/phase-b/_entry_points.json && node scripts/phase_b/build_crosswalk.mjs
```

## What was inventoried

719 current execution paths: 19 runtime workflow definitions, 205 cron jobs, 202 edge
functions, 175 database triggers, 93 state tables, 24 frontend routes, and one canonical
workflow with no current implementation at all.

| classification | count | what it means here |
| --- | --- | --- |
| `CANONICAL_KEEP` | 175 | all database triggers: structural guards, enabled, keep as they are |
| `CANONICAL_PARTIAL` | 401 | implements part of a canonical workflow |
| `PHASE_C_WIRING_GAP` | 121 | the structure exists; nothing connects it |
| `OUT_OF_SCOPE` | 21 | unrelated to the 30 business workflows |
| `CONFLICTING_PATH` | 1 | currently failing |
| `DUPLICATE_PATH` | 0 | see the note below — this is a finding, not a clean bill |
| `DEAD_CODE` | 0 | see the note below |
| `UNOWNED` | 0 | see the note below |

### Why `DUPLICATE_PATH`, `DEAD_CODE` and `UNOWNED` are zero

Not because the estate is clean. Because a single artefact gets one classification, and for
every artefact a more specific verdict applied first:

- **`DEAD_CODE` is zero because deactivation is not death.** Nineteen cron jobs are inactive.
  Eighteen of them had run before — `site_autodeploy` 21,563 times, `auto_deploy` 10,782 — and
  every one of the eighteen stopped on the same date, **2026-08-02**. That is a deliberate
  switch-off, and calling it dead code would invite Phase C to delete working machinery. They
  are `CANONICAL_PARTIAL` with `DEACTIVATED; N prior runs, last 2026-08-02` in their notes. The
  nineteenth, `supplier_exception_sweep_daily`, has never run at all and is a wiring gap.

- **`UNOWNED` is zero because it would have been the answer for almost everything.** No cron job
  and no edge function in this estate carries an accountable canonical role: they execute under
  `pg_cron` and the service role. That is true of 407 artefacts, and marking all 407 `UNOWNED`
  would have buried the more actionable verdict — whether the path is connected at all. It is
  recorded instead in the `current_owner_or_actor` column of every such row, which reads
  `pg_cron (no accountable role attached)` or `service role (no accountable role attached)`.
  **Binding these to accountable roles is Phase C work and it is the single largest gap in the
  estate.**

- **`DUPLICATE_PATH` is zero at artefact level, but the duplication is real and is recorded as
  a conflation instead.** See the next section.

## The 12 runtime workflows that have never executed

`public.workflow` holds 19 workflow definitions with 184 ordered steps between them. Twelve have
zero rows in `workflow_run`:

| runtime workflow | steps | gated steps | employees assigned | runs |
| --- | --- | --- | --- | --- |
| `rfq_handling` | 18 | 18 | 20 | **0** |
| `campaign_publishing` | 14 | 14 | 9 | 0 |
| `invoice_approval` | 11 | 11 | 19 | 0 |
| `supplier_suspension` | 11 | 11 | 0 | 0 |
| `complaint` | 10 | 10 | 0 | 0 |
| `refund` | 10 | 10 | 0 | 0 |
| `change_deployment` | 9 | 9 | 6 | 0 |
| `payment` | 8 | 8 | 0 | 0 |
| `lead_to_customer` | 8 | 3 | 5 | 0 |
| `incident_response` | 7 | 2 | 6 | 0 |
| `contract_review` | 6 | 3 | 4 | 0 |
| `budget_cycle` | 5 | 3 | 3 | 0 |

`rfq_handling` is the marketplace. Eighteen steps, every one of them gated, twenty employees
assigned to it, and it has never run once. Nothing about it fails, because nothing calls it —
which is why no watcher has ever reported it.

The seven that have executed: `employee_task` (232 runs), `metric_lifecycle` (30),
`strategic_review` (19), `customer_registration` (15), `improvement_lifecycle` (15),
`knowledge_lifecycle` (11), `supplier_onboarding` (1).

## Conflation: one runtime definition, many canonical workflows

For each runtime workflow, the actor roles on its steps were resolved to canonical roles and
matched against the canonical workflows those roles are accountable in.

**Stated precisely, because the number invites over-reading:** this counts the canonical
workflows whose steps are owned by roles appearing in the runtime definition. A role that owns
steps in several canonical workflows inflates it. It is an *upper bound on the span*, not proof
of it — but a definition drawing on twelve is not alignable to one.

| runtime workflow | canonical workflows its actor roles own steps in | runs |
| --- | --- | --- |
| `rfq_handling` | 12 — W04, W05, W06, W07, W08, W11, W12, W13, W14, W15, W18, W19 | 0 |
| `refund` | 10 — W01, W02, W16, W17, W18, W19, W22, W24, W27, W29 | 0 |
| `customer_registration` | 9 | 15 |
| `supplier_suspension` | 9 | 0 |
| `complaint` | 9 | 0 |
| `invoice_approval` | 8 | 0 |
| `campaign_publishing` | 8 | 0 |
| `payment` | 8 | 0 |
| `knowledge_lifecycle` | 1 — W26 | 11 |

`knowledge_lifecycle` is the one runtime workflow that maps cleanly to a single canonical
workflow, and it is also one of the seven that actually run.

### `supplier_onboarding` — the separation holds, but nothing holds it

Its nine steps span W09 onboarding and W10 verification, which is the one place the canonical
model demands independence: W10's reviewer must not be W09's owner. Measured step by step, the
separation is intact today — `supplier_onboarding_specialist` owns steps 1 and 6,
`supplier_verification` owns 2, 3 and 5, `compliance_and_privacy_officer` owns 4.

But it is intact by convention, not by construction: both roles live inside one definition with
nothing preventing a future edit from moving step 5 to the onboarding owner. Splitting it into
W09 and W10 is what makes the separation structural.

## 74 of 184 runtime steps are owned by a name nobody models

`public.workflow_step.actor_role` mixes three vocabularies: canonical role ids (`ceo`,
`payments_and_billing_manager`), human-readable titles (`Customer Support Specialist`,
`Trust & Safety Manager`, `Legal Counsel`), and two generic placeholders (`owner`, `Director`).

Before this session, 70 of 184 resolved exactly, 40 through an existing alias, and **74
resolved to nothing at all**. Twenty-four distinct titles account for 72 of the 74.

Phase B added `title` aliases for all 24. Nine were exact matches on `org_role.display_name`;
the other fifteen were assigned from the display name with the basis recorded on each line of
`scripts/sql/phase_b_02_identity_aliases.sql`. The two remaining rows are `owner` (15 steps) and
`Director` (1 step), both in `employee_task` — these are genuinely per-run assignees, not roles,
and giving them an alias would be inventing an employee.

Measured after deployment: **unresolved runtime step owners went from 74 to 16**, and the 16 are
exactly the `owner` and `Director` placeholder rows.

```sql
select count(*) from public.workflow_step ws
 where public.fn_phase_b_resolve_role(ws.actor_role) is null;   -- 16 of 184, was 74
```

**This changed no organization.** `org_role_alias` carries no Phase A frozen digest and no
`z90_phase_a_freeze` trigger. `fn_phase_a_baseline_drift()` returns 0 rows after the change.

## 64 edge functions with no caller and no external entry

Of 202 edge functions, 87 have no caller anywhere in the repository, the database or cron —
measured by searching for the four invocation forms this estate actually uses
(`functions/v1/<slug>`, `.invoke('<slug>')`, `callEdge('<slug>')`, `helper('<slug>', {…})`),
not by substring.

Of those 87, 23 serve an external entry surface read from their own source — 9 provider
webhooks, 10 public HTML pages, 1 OAuth callback — and are reachable from outside this codebase.
The remaining **64 have neither an internal caller nor an external entry surface.**

Among them: `artifact_review`, `claim_lookup`, `action_worker`, `agent_brain`, `match`,
`quote_quality`, `inquiry_intake`, `supplier_onboard`, `stripe_checkout`, `send_outbox`.

## 36 state tables that have never received a row

Thirty-six of the 93 tables carrying a workflow state column hold zero rows. A state machine
with no instances has never been exercised, and its transitions have never been tested by use.

## The single failing path

`index_slowdown_watch_daily` — last run 2026-08-15 04:15 UTC, status `failed`. It is a W29
reliability watcher, so a failing watcher is a blind spot rather than an outage. Classified
`CONFLICTING_PATH`.

## W21 — a canonical workflow with no current implementation

Strategic partnership development has no cron job, no edge function, no runtime workflow
definition and no frontend route. It is the only one of the 30 with zero current coverage.

## What Phase C inherits

1. Bind 407 cron jobs and edge functions to accountable canonical roles. Nothing executes under
   an accountable identity today.
2. Connect or retire 64 edge functions and 8 never-run cron jobs.
3. Give the 12 never-executed runtime workflows a real trigger, starting with `rfq_handling`.
4. Split the conflated runtime definitions along canonical boundaries, `supplier_onboarding`
   first because it carries an independence requirement.
5. Decide reactivation for the 18 cron jobs switched off on 2026-08-02.
6. Fix `index_slowdown_watch_daily`.
7. Build W21.
